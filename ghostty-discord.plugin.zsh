# Activate only in local Ghostty shells. No command arguments are published.
[[ "$TERM_PROGRAM" == ghostty ]] || return 0
[[ -n "${_GHOSTTY_DISCORD_LOADED:-}" ]] && return 0
typeset -g _GHOSTTY_DISCORD_LOADED=1
autoload -Uz add-zsh-hook

_ghostty_discord_event() {
    command "${GHOSTTY_DISCORD_BIN:-$HOME/.local/bin/ghostty-discord}" event --pid "$$" --cwd "$PWD" --command "$1" >/dev/null 2>&1
    return 0
}
_ghostty_discord_preexec() {
    local -a words
    words=( ${(z)1} )
    local executable="${words[1]:-}"
    # Discard assignments and common wrappers without retaining their values.
    while [[ "$executable" == *=* || "$executable" == (command|exec|noglob|sudo|env) ]]; do
        words[1]=()
        executable="${words[1]:-}"
        [[ -z "$executable" ]] && break
    done
    [[ "$executable" == -* ]] && executable='command'
    _ghostty_discord_event "${(Q)executable}"
}
_ghostty_discord_precmd() { _ghostty_discord_event ''; }
_ghostty_discord_exit() {
    command "${GHOSTTY_DISCORD_BIN:-$HOME/.local/bin/ghostty-discord}" leave --pid "$$" >/dev/null 2>&1
}
add-zsh-hook preexec _ghostty_discord_preexec
add-zsh-hook precmd _ghostty_discord_precmd
add-zsh-hook zshexit _ghostty_discord_exit
