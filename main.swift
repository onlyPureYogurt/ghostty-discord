import Foundation
import Darwin

let version = "0.1.0"
let fm = FileManager.default
let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GHOSTTY_DISCORD_HOME"] ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ghostty-discord").path)
struct Failure: Error, CustomStringConvertible { let description: String; init(_ text: String) { description = text } }
func load(_ name: String) -> [String: Any] {
    guard let data = try? Data(contentsOf: root.appendingPathComponent(name)), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }; return value
}
func save(_ name: String, _ value: [String: Any]) throws {
    let url = root.appendingPathComponent(name)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
func run(_ executable: String, _ args: [String]) throws -> (Int32, String) {
    let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
    let output = Pipe(); task.standardOutput = output; task.standardError = FileHandle.nullDevice
    try task.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}
func project(_ cwd: String) -> String {
    // Walk ancestors rather than invoking git or requiring Xcode tools.
    var current = URL(fileURLWithPath: cwd).standardizedFileURL
    while current.path != "/" {
        if fm.fileExists(atPath: current.appendingPathComponent(".git").path) { return current.lastPathComponent }
        current.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? "Terminal" : URL(fileURLWithPath: cwd).lastPathComponent
}
func latest() -> [String: Any]? {
    let urls = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)) ?? []
    var events: [[String: Any]] = []
    for url in urls where url.pathExtension == "json" {
        let event = load("sessions/" + url.lastPathComponent)
        guard let pid = event["pid"] as? Int32, pid > 0, kill(pid, 0) == 0 || errno == EPERM else { try? fm.removeItem(at: url); continue }
        events.append(event)
    }
    return events.max { ($0["updated"] as? Double ?? 0) < ($1["updated"] as? Double ?? 0) }
}
let editors = ["nvim": "Neovim", "vim": "Vim", "vi": "Vi", "nano": "Nano", "emacs": "Emacs", "hx": "Helix"]
func activity(_ event: [String: Any], _ config: [String: Any], _ start: Int) -> [String: Any] {
    let command = event["command"] as? String ?? ""
    let state = editors[command].map { "Using " + $0 } ?? (command.isEmpty ? "Terminal idle" : "Running " + command)
    var result: [String: Any] = ["details": "Project: " + String((event["project"] as? String ?? "Terminal").prefix(100)), "state": String(state.prefix(128)), "timestamps": ["start": start], "instance": false]
    if let key = config["image_key"] as? String, !key.isEmpty { result["assets"] = ["large_image": key, "large_text": "Ghostty"] }
    return result
}
final class RPC {
    var fd: Int32 = -1
    init(_ clientID: String) throws {
        let env = ProcessInfo.processInfo.environment
        var prefixes: [String] = []
        for prefix in [env["XDG_RUNTIME_DIR"], env["TMPDIR"], env["TMP"], env["TEMP"], "/tmp"].compactMap({ $0 }) where !prefixes.contains(prefix) { prefixes.append(prefix) }
        for prefix in prefixes {
            for index in 0..<10 {
                let candidate = socket(AF_UNIX, SOCK_STREAM, 0)
                guard candidate >= 0 else { continue }
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(candidate, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var noSigPipe: Int32 = 1
                setsockopt(candidate, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
                let path = URL(fileURLWithPath: prefix).appendingPathComponent("discord-ipc-\(index)").path
                let bytes = Array(path.utf8CString)
                guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(candidate); continue }
                withUnsafeMutableBytes(of: &address.sun_path) { target in bytes.withUnsafeBytes { source in target.copyBytes(from: source) } }
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                let connected = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
                guard connected == 0 else { Darwin.close(candidate); continue }
                fd = candidate
                do {
                    try send(0, ["v": 1, "client_id": clientID])
                    guard try receive()["evt"] as? String == "READY" else { throw Failure("Discord handshake rejected") }
                    return
                } catch { close() }
            }
        }
        throw Failure("Discord desktop IPC unavailable; open Discord and check Application ID")
    }
    deinit { close() }
    func close() { if fd >= 0 { Darwin.close(fd); fd = -1 } }
    func write(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure("Discord socket write failed") }; offset += count
            }
        }
    }
    func frame(_ opcode: UInt32, _ data: Data) throws {
        var op = opcode.littleEndian; var length = UInt32(data.count).littleEndian
        var packet = Data(bytes: &op, count: 4); packet.append(Data(bytes: &length, count: 4)); packet.append(data); try write(packet)
    }
    func send(_ opcode: UInt32, _ value: [String: Any]) throws { try frame(opcode, JSONSerialization.data(withJSONObject: value)) }
    func exact(_ count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let size = recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if size < 0 && errno == EINTR { continue }
                guard size > 0 else { throw Failure("Discord disconnected or timed out") }; offset += size
            }
        }; return data
    }
    func receive() throws -> [String: Any] {
        while true {
            let header = [UInt8](try exact(8))
            func number(_ start: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[start + $1]) << (8 * $1) } }
            let op = number(0); let size = number(4)
            guard size <= 1_048_576 else { throw Failure("Invalid Discord frame length") }
            let data = try exact(Int(size))
            if op == 3 { try frame(4, data); continue }
            guard op == 1 else { throw Failure("Discord closed connection") }
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure("Invalid Discord response") }; return result
        }
    }
    func update(_ value: [String: Any]?) throws {
        let nonce = UUID().uuidString
        try send(1, ["cmd": "SET_ACTIVITY", "args": ["pid": getpid(), "activity": value as Any? ?? NSNull()], "nonce": nonce])
        for _ in 0..<100 {
            let reply = try receive()
            if reply["nonce"] as? String == nonce {
                if reply["evt"] as? String == "ERROR" { throw Failure("Discord rejected activity: \(reply["data"] ?? "unknown")") }; return
            }
        }; throw Failure("Too many unrelated Discord responses")
    }
}
func daemon() throws {
    try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lock = open(root.appendingPathComponent("daemon.lock").path, O_CREAT | O_RDWR, 0o600)
    guard lock >= 0 else { throw Failure("Cannot open daemon lock") }
    defer { Darwin.close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return }
    var rpc: RPC?; var connectedID = ""; var previous = Data(); var sent = Date.distantPast; var retry = Date.distantPast
    let started = Int(Date().timeIntervalSince1970)
    while true {
        let config = load("config.json"); let id = config["client_id"] as? String ?? ""
        let desired = (config["paused"] as? Bool != true) ? latest().map { activity($0, config, started) } : nil
        do {
            if rpc != nil && connectedID != id { try rpc?.update(nil); rpc = nil }
            guard !id.isEmpty else { throw Failure("Run ghostty-discord configure APPLICATION_ID") }
            if rpc == nil && Date() >= retry { rpc = try RPC(id); connectedID = id; previous = Data() }
            let encoded = try JSONSerialization.data(withJSONObject: desired as Any? ?? NSNull(), options: [.sortedKeys, .fragmentsAllowed])
            if rpc != nil && (encoded != previous || Date().timeIntervalSince(sent) >= 30) && Date().timeIntervalSince(sent) >= 5 {
                try rpc?.update(desired); previous = encoded; sent = Date()
                try save("status.json", ["connected": true, "activity": desired as Any? ?? NSNull(), "updated": Date().timeIntervalSince1970])
            }
        } catch {
            rpc = nil; retry = Date().addingTimeInterval(10)
            try? save("status.json", ["connected": false, "error": String(describing: error), "updated": Date().timeIntervalSince1970])
        }
        Thread.sleep(forTimeInterval: 1)
    }
}
func removeHook(_ path: URL) throws {
    guard fm.fileExists(atPath: path.path) else { return }
    let text = try String(contentsOf: path, encoding: .utf8)
    guard let begin = text.range(of: "# BEGIN ghostty-discord\n"), let end = text.range(of: "# END ghostty-discord", range: begin.upperBound..<text.endIndex) else { return }
    var finish = end.upperBound
    if finish < text.endIndex && text[finish] == "\n" { finish = text.index(after: finish) }
    var result = text; result.removeSubrange(begin.lowerBound..<finish)
    try result.write(to: path, atomically: true, encoding: .utf8)
}
func setup(_ id: String, _ zshPath: String?) throws {
    guard id.range(of: "^[0-9]{17,20}$", options: .regularExpression) != nil else { throw Failure("Application ID must contain 17–20 digits") }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    // Called with an absolute executable path by the distribution installer/Homebrew.
    guard fm.isExecutableFile(atPath: executable.path) else { throw Failure("Run setup using an absolute path to ghostty-discord") }
    try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let hook = root.appendingPathComponent("ghostty-discord.plugin.zsh")
    let bundledHook = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/ghostty-discord/ghostty-discord.plugin.zsh")
    if fm.fileExists(atPath: bundledHook.path) {
        try Data(contentsOf: bundledHook).write(to: hook, options: .atomic)
    }
    guard fm.fileExists(atPath: hook.path) else { throw Failure("Missing bundled zsh plugin") }
    var config = load("config.json"); config["client_id"] = id; try save("config.json", config)
    let home = fm.homeDirectoryForCurrentUser
    let zshrc = URL(fileURLWithPath: zshPath ?? ProcessInfo.processInfo.environment["ZDOTDIR"].map { $0 + "/.zshrc" } ?? home.appendingPathComponent(".zshrc").path)
    try fm.createDirectory(at: zshrc.deletingLastPathComponent(), withIntermediateDirectories: true)
    let text = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
    if fm.fileExists(atPath: zshrc.path) {
        try fm.copyItem(at: zshrc, to: URL(fileURLWithPath: zshrc.path + ".ghostty-discord-backup-" + UUID().uuidString))
        try removeHook(zshrc)
    }
    func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let existing = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? text
    let block = "\n# BEGIN ghostty-discord\nexport PATH=\(quote(executable.deletingLastPathComponent().path)):$PATH\nexport GHOSTTY_DISCORD_BIN=\(quote(executable.path))\nsource \(quote(root.appendingPathComponent("ghostty-discord.plugin.zsh").path))\n# END ghostty-discord\n"
    try (existing + block).write(to: zshrc, atomically: true, encoding: .utf8)
    try save("installation.json", ["zshrc": zshrc.path, "executable": executable.path])
    let agent = home.appendingPathComponent("Library/LaunchAgents/local.ghostty-discord.plist")
    try fm.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
    let plist: [String: Any] = ["Label": "local.ghostty-discord", "ProgramArguments": [executable.path, "daemon"], "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10, "StandardErrorPath": root.appendingPathComponent("daemon.log").path, "StandardOutPath": root.appendingPathComponent("daemon.log").path]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent, options: .atomic)
    _ = try run("/bin/launchctl", ["bootout", "gui/\(getuid())", agent.path])
    let (code, _) = try run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agent.path])
    guard code == 0 else { throw Failure("Files installed, but launchctl bootstrap failed. Try logging out and back in.") }
    print("Installed. Open a new Ghostty tab, then run ghostty-discord status.")
}
func uninstall() throws {
    let info = load("installation.json"); let home = fm.homeDirectoryForCurrentUser
    let agent = home.appendingPathComponent("Library/LaunchAgents/local.ghostty-discord.plist")
    _ = try run("/bin/launchctl", ["bootout", "gui/\(getuid())", agent.path])
    if let path = info["zshrc"] as? String { try removeHook(URL(fileURLWithPath: path)) }
    if fm.fileExists(atPath: agent.path) { try fm.removeItem(at: agent) }
    // Homebrew binaries belong to Homebrew; only remove the manual installation.
    let manual = home.appendingPathComponent(".local/bin/ghostty-discord")
    if info["executable"] as? String == manual.path, fm.fileExists(atPath: manual.path) { try fm.removeItem(at: manual) }
    if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
    print("Integration removed. Open a new shell. For Homebrew also run brew uninstall ghostty-discord.")
}
func main() throws {
    let args = Array(CommandLine.arguments.dropFirst()); let action = args.first ?? "help"
    func option(_ name: String) -> String? { guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }; return args[index + 1] }
    switch action {
    case "--version", "version": print(version)
    case "daemon": try daemon()
    case "event":
        guard let text = option("--pid"), let pid = Int32(text), pid > 0, let cwd = option("--cwd") else { throw Failure("event requires --pid and --cwd") }
        let command = String((option("--command") ?? "").split(separator: "/").last ?? "")
        try save("sessions/\(pid).json", ["pid": pid, "project": project(cwd), "command": String(command.prefix(80)), "updated": Date().timeIntervalSince1970])
    case "leave":
        guard let text = option("--pid"), let pid = Int32(text), pid > 0 else { throw Failure("leave requires --pid") }
        try? fm.removeItem(at: root.appendingPathComponent("sessions/\(pid).json"))
    case "configure":
        guard args.count > 1, args[1].range(of: "^[0-9]{17,20}$", options: .regularExpression) != nil else { throw Failure("Application ID must contain 17–20 digits") }
        var config = load("config.json"); config["client_id"] = args[1]; config["image_key"] = option("--image-key") ?? config["image_key"] ?? ""; try save("config.json", config); print("Discord application configured.")
    case "pause", "resume": var config = load("config.json"); config["paused"] = action == "pause"; try save("config.json", config); print(action + " requested")
    case "status":
        var status = load("status.json"); status["stale"] = Date().timeIntervalSince1970 - (status["updated"] as? Double ?? 0) > 45
        if status["connected"] == nil { status["connected"] = false; status["error"] = "Daemon has not started" }
        print(String(data: try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    case "setup": try setup(option("--client-id") ?? "1559258860634771566", option("--zshrc"))
    case "uninstall": try uninstall()
    default: print("Ghostty Discord \(version)\nCommands: setup, configure ID [--image-key KEY], status, pause, resume, uninstall, --version")
    }
}
do { try main() } catch { FileHandle.standardError.write(Data(("ghostty-discord: \(error)\n").utf8)); exit(1) }
