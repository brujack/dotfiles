#!/usr/bin/env bash
# One-shot python3 HTTP listener for real-curl header tests. Launched with fd 3
# closed and output redirected: an orphan holding bats' fd 3 or output pipe
# hangs the suite instead of failing it (measured: `timeout 15 bats` rc 124).
# handle_request() serves one request or returns after srv.timeout, so the
# process ends even if teardown never runs.
start_http_listener() {
  local _dir="$1" _i
  HTTP_LISTENER_HEADERS="${_dir}/headers"
  local _ready="${_dir}/port"
  python3 -I - "${_ready}" "${HTTP_LISTENER_HEADERS}" "${HTTP_LISTENER_DEADLINE:-10}" \
    3>&- >"${_dir}/listener.log" 2>&1 <<'PY' &
import http.server, os, sys
# 3>&- closes bats' fd 3 only. A caller (a git hook, for one) can hand down
# other pipes, so close every inherited fd above stderr before binding.
for _fd in [int(n) for n in os.listdir("/dev/fd")]:
    if _fd > 2:
        try:
            os.close(_fd)
        except OSError:
            pass
ready, out, deadline = sys.argv[1], sys.argv[2], float(sys.argv[3])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(out, "a") as f:
            f.write(str(self.headers))
        body = b'{"tag_name": "v9.9.9"}'
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
srv.timeout = deadline
with open(ready + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
os.replace(ready + ".tmp", ready)
srv.handle_request()
PY
  HTTP_LISTENER_PID=$!
  for _i in $(seq 100); do
    [[ -s "${_ready}" ]] && break
    kill -0 "${HTTP_LISTENER_PID}" 2>/dev/null || break
    sleep 0.05
  done
  if [[ ! -s "${_ready}" ]]; then
    cat "${_dir}/listener.log" >&2
    return 1
  fi
  # shellcheck disable=SC2034 # HTTP_LISTENER_URL is read by the sourcing test
  HTTP_LISTENER_URL="http://127.0.0.1:$(<"${_ready}")"
}

stop_http_listener() {
  [[ -n "${HTTP_LISTENER_PID:-}" ]] || return 0
  # Cleanup site: the listener usually exited already, so both may fail.
  kill "${HTTP_LISTENER_PID}" 2>/dev/null || :
  wait "${HTTP_LISTENER_PID}" 2>/dev/null || :
  HTTP_LISTENER_PID=""
  return 0
}
