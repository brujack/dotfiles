#!/usr/bin/env bash
# Claude Code notification hook — fires on Stop and Notification events.
# Works in tmux on macOS (osascript) and Linux (notify-send).
# Rings terminal bell so tmux highlights the window regardless of platform.

read -r input
message=$(printf '%s' "${input}" | jq -r '.message // "Claude Code is waiting"')

# Ring terminal bell — tmux highlights the window
printf '\a'

# Include tmux context in the subtitle if available
if [[ -n "${TMUX}" ]]; then
  session=$(tmux display-message -t "${TMUX_PANE}" -p '#{session_name}' 2>/dev/null)
  window=$(tmux display-message -t "${TMUX_PANE}" -p '#{window_name}' 2>/dev/null)
  subtitle="${session}:${window}"
else
  subtitle="Claude Code"
fi

case "$(uname -s)" in
  Darwin)
    # osascript is always available on macOS; no extra install needed
    osascript - "${subtitle}" "${message}" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set sub to item 1 of argv
  set msg to item 2 of argv
  display notification msg with title "Claude Code" subtitle sub sound name "Ping"
end run
APPLESCRIPT
    ;;
  Linux)
    notify-send -u normal -a "Claude Code" "${subtitle}" "${message}" 2>/dev/null || true
    ;;
esac
