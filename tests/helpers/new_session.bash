#!/usr/bin/env bash
# Shared helper: run a script as the leader of its own session. Source it from a
# bats file; it defines a function and has no top-level side effects.

# _in_new_session <script> -- runs `bash <script>` as the leader of its own
# process group, so `kill -SIG 0` cannot reach bats, with INT and TERM at their
# default action (a child spawned from a non-interactive shell can inherit
# them ignored). Prints the exit as a shell reports it: 128+N for a signal.
# The child's stderr is dropped: bash reports a killed job there
# ("Terminated ..."), and it would otherwise land in $output.
# python3 rather than setsid, which macOS does not ship.
_in_new_session() {
  python3 - "$1" <<'PY'
import signal, subprocess, sys
def reset():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
p = subprocess.run(["bash", sys.argv[1]], stdin=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, start_new_session=True,
                   preexec_fn=reset)
print(128 - p.returncode if p.returncode < 0 else p.returncode)
PY
}
