"""Black-box native executable tests against a fake Discord desktop server."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest

BINARY = str(Path(sys.argv.pop(1)).resolve())

class NativeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gd-', dir='/tmp')
        self.root = Path(self.temp.name)
        self.env = {**os.environ, 'GHOSTTY_DISCORD_HOME': str(self.root / 'data'), 'TMPDIR': str(self.root), 'XDG_RUNTIME_DIR': str(self.root)}
        self.daemon = None

    def tearDown(self):
        if self.daemon:
            self.daemon.terminate()
            self.daemon.wait(timeout=5)
        self.temp.cleanup()

    def cli(self, *args, check=True):
        return subprocess.run([BINARY, *args], env=self.env, capture_output=True, text=True, check=check)

    def wait(self, condition, seconds=20):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.1)
        self.fail('Timed out waiting for condition')

    def test_config_and_project_privacy(self):
        self.assertNotEqual(self.cli('configure', 'invalid', check=False).returncode, 0)
        self.cli('configure', '1559258860634771566')
        repo = self.root / 'secret-parent' / 'project'
        (repo / '.git').mkdir(parents=True)
        (repo / 'nested').mkdir()
        self.cli('event', '--pid', str(os.getpid()), '--cwd', str(repo / 'nested'), '--command', '/usr/bin/nvim')
        event = json.loads((self.root / 'data/sessions' / f'{os.getpid()}.json').read_text())
        self.assertEqual(event['project'], 'project')
        self.assertEqual(event['command'], 'nvim')
        self.assertNotIn('secret-parent', json.dumps(event))
        self.cli('leave', '--pid', str(os.getpid()))
        self.assertFalse(list((self.root / 'data/sessions').glob('*.json')))

    def test_rpc_reconnect_pause_clear_and_singleton(self):
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(self.root / 'discord-ipc-0'))
        server.listen(5)
        server.settimeout(1)
        activities, connections, errors = [], [], []
        stopping = threading.Event()
        def exact(sock, n):
            result = b''
            while len(result) < n:
                data = sock.recv(n-len(result))
                if not data:
                    raise EOFError()
                result += data
            return result
        def receive(sock):
            op, n = struct.unpack('<II', exact(sock, 8))
            return op, json.loads(exact(sock, n))
        def send(sock, op, payload):
            data = json.dumps(payload).encode()
            packet = struct.pack('<II', op, len(data)) + data
            for start in range(0, len(packet), 3):
                sock.sendall(packet[start:start+3])
        def mock():
            while not stopping.is_set():
                try:
                    sock, _ = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    return
                connections.append(True)
                sock.settimeout(5)
                try:
                    op, handshake = receive(sock)
                    self.assertEqual(op, 0)
                    self.assertEqual(handshake['client_id'], '1559258860634771566')
                    send(sock, 1, {'evt': 'READY'})
                    while not stopping.is_set():
                        op, request = receive(sock)
                        if op != 1:
                            continue
                        activities.append(request['args']['activity'])
                        send(sock, 3, {'ping': True})
                        self.assertEqual(receive(sock)[0], 4)
                        send(sock, 1, {'nonce': request['nonce'], 'data': {}})
                        if len(connections) == 1:
                            break  # Force daemon to discover a disconnect and reconnect.
                except (EOFError, OSError):
                    pass
                except BaseException as error:
                    errors.append(error)
                finally:
                    sock.close()
        worker = threading.Thread(target=mock, daemon=True)
        worker.start()
        try:
            self.cli('configure', '1559258860634771566')
            self.cli('event', '--pid', str(os.getpid()), '--cwd', str(self.root), '--command', 'nvim')
            self.daemon = subprocess.Popen([BINARY, 'daemon'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.wait(lambda: activities)
            self.assertEqual(activities[0]['state'], 'Using Neovim')
            self.assertEqual(self.cli('daemon').returncode, 0)
            self.cli('pause')
            self.wait(lambda: len(connections) >= 2 and activities[-1] is None)
            self.cli('resume')
            self.wait(lambda: activities[-1] is not None)
            self.cli('leave', '--pid', str(os.getpid()))
            self.wait(lambda: activities[-1] is None)
            self.assertFalse(errors, errors)
        finally:
            stopping.set()
            server.close()

if __name__ == '__main__':
    unittest.main()
