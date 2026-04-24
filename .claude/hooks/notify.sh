#!/usr/bin/env bash
# Claude Code notification hook — fires on Stop and Notification events.
#
# Local Warp sessions: rings terminal bell only (Warp plugin handles desktop
# notifications natively; no ntfy needed).
#
# SSH sessions (tmux on Linux workstation, remote Mac attach, iPad/iPhone SSH):
# rings terminal bell AND posts to self-hosted ntfy so the notification reaches
# you regardless of which device you're on.
#
# Required in config/local.sh on each machine:
#   export NTFY_TOPIC="your-private-topic-name"
#   export NTFY_URL="https://ntfy.conecrazy.ca"  # optional, this is the default

read -r input
message=$(printf '%s' "${input}" | jq -r '.message // "Claude Code is waiting"')

# Ring terminal bell — tmux highlights the window on all session types
printf '\a'

# Include tmux context in the subtitle if available
if [[ -n "${TMUX}" ]]; then
  session=$(tmux display-message -t "${TMUX_PANE}" -p '#{session_name}' 2>/dev/null)
  window=$(tmux display-message -t "${TMUX_PANE}" -p '#{window_name}' 2>/dev/null)
  subtitle="${session}:${window}"
else
  subtitle="Claude Code"
fi

# SSH sessions: post to ntfy so the notification reaches all subscribed devices
# (Mac, iPhone, iPad) regardless of where Claude Code is running.
# Local Warp sessions skip this — the warp@claude-code-warp plugin handles them.
if [[ -n "${SSH_CONNECTION}" && -n "${NTFY_TOPIC:-}" ]]; then
  ntfy_url="${NTFY_URL:-https://ntfy.conecrazy.ca}"
  host=$(hostname -s 2>/dev/null || printf "unknown")
  curl -s \
    -H "Title: Claude Code — ${host} ${subtitle}" \
    -H "Priority: high" \
    -H "Tags: robot" \
    -d "${message}" \
    "${ntfy_url}/${NTFY_TOPIC}" 2>/dev/null || true
  # Bell already sent above; skip local OS notification for SSH sessions
  exit 0
fi

# Local sessions: OS notification as a fallback for non-Warp environments
case "$(uname -s)" in
  Darwin)
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
