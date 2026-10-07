#!/usr/bin/env bash
# One-shot python3 HTTP listener for real-curl header tests. Launched with fd 3
# closed and output redirected: an orphan holding bats' fd 3 or output pipe
# hangs the suite instead of failing it (measured: `timeout 15 bats` rc 124).
# handle_request() serves one request or returns after srv.timeout, so the
# process ends even if teardown never runs.
# shellcheck disable=SC2034 # HTTP_LISTENER_URL/PID are the interface read by sourcing tests
start_http_listener() {
  local _dir="$1" _i
  HTTP_LISTENER_HEADERS="${_dir}/headers"
  local _ready="${_dir}/port"
  python3 -I - "${_ready}" "${HTTP_LISTENER_HEADERS}" "${HTTP_LISTENER_DEADLINE:-10}" \
    3>&- >"${_dir}/listener.log" 2>&1 <<'PY' &
import http.server, os, sys
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
    sleep 0.05
  done
  [[ -s "${_ready}" ]] || return 1
  HTTP_LISTENER_URL="http://127.0.0.1:$(<"${_ready}")"
}

stop_http_listener() {
  [[ -n "${HTTP_LISTENER_PID:-}" ]] || return 0
  kill "${HTTP_LISTENER_PID}" 2>/dev/null
  wait "${HTTP_LISTENER_PID}" 2>/dev/null
  HTTP_LISTENER_PID=""
  return 0
}
