# GitHub Tokens Off curl's argv Implementation Plan

spec: docs/superpowers/specs/2026-10-07-github-token-off-argv-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send the GitHub bearer token to curl on stdin (`-H @-`) at both call sites, so it never appears in curl's argv.

**Architecture:** A new `_github_auth_header` in `lib/helpers.sh` prints the header line or refuses a token containing a line break. `_doctor_check_github_mcp` and `_fetch_github_latest` capture that line first, then pipe it to `curl -H @-`, building the URL from `$(_github_api_base)`, an allowlisted seam. `run_check_versions` checks the token once and skips only the seven GitHub-release checks on refusal, returning 2. Tests use a recording curl mock (new `MOCK_CURL_STDIN_FILE`) plus one real-curl test per site against a shared python3 listener helper.

**Tech Stack:** bash, bats-core, curl, python3 (test listener only).

## Global Constraints

- Work in worktree `../dotfiles-ghtoken` on branch `fix/github-token-off-argv`, created from `origin/master`. Never commit in the main checkout.
- Capture, then pipe. `_hdr=$(_github_auth_header "$t") || <site outcome>` and only then `printf '%s\n' "${_hdr}" | curl ... -H @- ...`. `_github_auth_header "$t" | curl` is forbidden (N2): a pipe cannot stop curl, which then sends an unauthenticated request and exits 0.
- Never escape the token. `-H @-` takes the header line verbatim. Refuse `\n` and `\r`.
- Both sites build the URL from `$(_github_api_base)` (Task 5), which honours `_GITHUB_API` only when it is `https://api.github.com` or `http://127.0.0.1:<port>`; anything else warns and falls back to the default.
- `run_check_versions` returns 2 on a refused token, taking precedence over 1 ("a pin is outdated").
- No change to `scripts/cadence-notify.sh` (N1). No change to doctor's curl rc classification (22 fail; 28/6 warn; other warn; 0 pass) (N3).
- Every absence assertion has a positive control in the same test: the request URL appears in `MOCK_CALLS_FILE`.
- Strip mocks for real-curl tests with the repo idiom: `_clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"`.
- Base suite on this box: see `## Baseline`. `make test` is under the 600s Bash cap, so run it in the foreground with `timeout: 600000` and `< /dev/null`. Do not background it.

## Baseline

`make test` on `origin/master` at `70fc74bc` (spec-only commits over `039e909c`), on `claude`, 2026-10-07: rc 0, 143 s wall time, 2591 `ok` lines, 0 `not ok`. Well under the 600 s Bash cap.

## Session-level verification

- `make test` exits 0 on the branch, with the new test counts above zero (each task's `--count` gate).
- V1: CI green on all six jobs, including `test-macos` and `bash-coverage`. The orchestrator also runs `make bash-coverage` once after Task 6. It takes about 19 min in CI, so run it in the background and poll; it is not a per-task gate.
- V2 (operator machine, real `GITHUB_PAT`): run a `ps -eo args` sampler at 20 ms during `./setup_env.sh -t doctor`. On the branch it must match `curl .* api.github.com/user` at least once (positive control) and never match the token. On `origin/master` it must catch the token. The sampler prints only match counts, never argv.
- V3: on the Studio over `ssh`, `printf 'Authorization: Bearer x\n' | curl -s -H @- http://127.0.0.1:<port>/` against a header-logging listener delivers exactly `Bearer x`.

---

### Task 1: curl mock captures `-H @-` stdin

```yaml-task
id: 1
description: Add MOCK_CURL_STDIN_FILE to tests/mocks/curl so tests can read the header a caller sent on stdin.
role: executor
model: sonnet
tdd: required
requirements: [R3]
acceptance:
  - cmd: bats tests/setup_env/mocks_curl.bats
    exit_code: 0
  - cmd: '[ "$(bats --count -f "STDIN_FILE" tests/setup_env/mocks_curl.bats)" -ge 3 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/mocks/curl, tests/setup_env/mocks_curl.bats]
depends_on: []
```

**Interfaces:**

- Produces: when `MOCK_CURL_STDIN_FILE` is set **and** argv contains `-H` immediately followed by `@-`, the mock writes its stdin to that file before deciding its exit code, so capture also happens on simulated failures (`MOCK_CURL_EXIT=22`). It is unchanged otherwise. Every call is still recorded to `MOCK_CALLS_FILE`.

- [ ] Add `MOCK_CURL_STDIN_FILE` to the `unset` line in `mocks_curl.bats` `setup()`. Then write three failing tests whose names contain `STDIN_FILE`:
  1. Knob set, `printf 'Authorization: Bearer t1\n' | "${CURL_MOCK}" -sf -H @- http://x/a`: the file content equals `Authorization: Bearer t1`, and `http://x/a` is in `MOCK_CALLS_FILE`.
  2. Knob set, no `-H @-` (`printf 'junk\n' | "${CURL_MOCK}" -sf http://x/b`): the file does not exist, and `http://x/b` is in `MOCK_CALLS_FILE` (positive control).
  3. Knob set with `MOCK_CURL_EXIT=22` and `-H @-`: status 22, and the file still holds the line.
- [ ] Run `bats tests/setup_env/mocks_curl.bats` and confirm the three tests fail for the stated reason.
- [ ] In the mock's arg loop, add a branch before the short-option cluster check: `if [[ "$1" == "-H" && "${2:-}" == "@-" ]]; then stdin_hdr=1; shift 2; continue; fi` (initialise `stdin_hdr=0` above the loop). Directly after the loop: `if [[ -n "${MOCK_CURL_STDIN_FILE:-}" && ${stdin_hdr} -eq 1 ]]; then cat > "${MOCK_CURL_STDIN_FILE}"; fi`. Comment the deviation: real curl reads this stdin as header lines, and the mock records it so a test can assert what was sent off argv.
- [ ] Run the acceptance gates, then commit (`caveman:caveman-commit`).

### Task 2: `_github_auth_header`

```yaml-task
id: 2
description: Add _github_auth_header to lib/helpers.sh, printing the bearer header line or refusing a token with a line break.
role: executor
model: sonnet
tdd: required
requirements: [R4]
acceptance:
  - cmd: bats -f "_github_auth_header" tests/setup_env/unit.bats
    exit_code: 0
  - cmd: '[ "$(bats --count -f "_github_auth_header" tests/setup_env/unit.bats)" -ge 5 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats]
depends_on: []
```

**Interfaces:**

- Produces: `_github_auth_header <token>`. rc 0 prints exactly `Authorization: Bearer <token>\n` to stdout, token verbatim. rc 1 prints nothing to stdout and one line to stderr containing `line break`, for a token containing `\n` or `\r`.

- [ ] Add five failing tests in `unit.bats`, placed directly above `# ── _doctor_check_github_mcp`. `unit.bats` has no `bats_require_minimum_version`, so capture output with `$(...)` rather than `run --separate-stderr`.
  1. `tok123` → rc 0, stdout `Authorization: Bearer tok123`.
  2. `a"b\c` → rc 0, stdout `Authorization: Bearer a"b\c`, unescaped.
  3. `$'a\nX-Injected: 1'` → rc 1, empty stdout.
  4. `$'a\rb'` → rc 1, empty stdout.
  5. `$'a\nb'` → stderr contains `line break`.
- [ ] Run them and confirm they fail with `command not found`.
- [ ] Add the function in `lib/helpers.sh` immediately above `_doctor_check_github_mcp`:

```bash
# Prints the GitHub auth header for `curl -H @-`, so the token reaches curl on
# stdin instead of argv (argv is readable by every uid via /proc/<pid>/cmdline).
# A line break would inject a second header, and -H @- has no escape, so refuse.
_github_auth_header() {
  local _token="$1"
  case "${_token}" in
    *$'\n'* | *$'\r'*)
      printf "GitHub token contains a line break -- refusing to send it\n" >&2
      return 1
      ;;
  esac
  printf 'Authorization: Bearer %s\n' "${_token}"
}
```

- [ ] Run the gates, then commit.

### Task 3: shared real-curl listener helper

```yaml-task
id: 3
description: Add tests/helpers/http_listener.bash, a python3 listener that records request headers and cannot hang bats, plus its own tests.
role: executor
model: sonnet
tdd: required
requirements: [R14]
acceptance:
  - cmd: bats tests/helpers_http_listener.bats
    exit_code: 0
  - cmd: '[ "$(bats --count tests/helpers_http_listener.bats)" -ge 3 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/helpers/http_listener.bash, tests/helpers_http_listener.bats]
depends_on: []
```

**Interfaces:**

- Produces: `start_http_listener <dir>` sets `HTTP_LISTENER_URL` (`http://127.0.0.1:<port>`), `HTTP_LISTENER_PID` (python's own PID) and `HTTP_LISTENER_HEADERS` (`<dir>/headers`). It returns 1 if the port file is not ready within 5 s. The listener answers one GET with 200 and body `{"tag_name": "v9.9.9"}`, then exits. With no request it exits after `HTTP_LISTENER_DEADLINE` seconds (default 10).
- Produces: `stop_http_listener` kills `HTTP_LISTENER_PID` if it is still alive, and is safe to call twice. Callers invoke it from `teardown()`.

- [ ] Write `tests/helpers_http_listener.bats` (it sources `tests/helpers/common.bash` and the new helper, and its `teardown()` calls `stop_http_listener`) with three failing tests:
  1. Start, then run real `/usr/bin/env curl -sf -H 'X-Probe: p1' "${HTTP_LISTENER_URL}/x"` (no mocks are loaded in this file): stdout `{"tag_name": "v9.9.9"}`, and `HTTP_LISTENER_HEADERS` contains `X-Probe: p1`.
  2. With `HTTP_LISTENER_DEADLINE=1`, start and send nothing. Within 4 s (poll `kill -0`), the PID is gone.
  3. Start; on Linux (`[[ -d /proc/${HTTP_LISTENER_PID}/fd ]]`, else `skip`), `/proc/<pid>/fd/3` does not exist and `/proc/<pid>/fd/1` resolves to `<dir>/listener.log`. The positive control is that `/proc/<pid>/fd/0` exists.
- [ ] Run them and confirm they fail because the helper is missing.
- [ ] Write the helper:

```bash
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
```

- [ ] Verify `$!` is python's PID, not a subshell's: in test 3, `ps -o comm= -p "${HTTP_LISTENER_PID}"` contains `python`. Add that assertion to test 3.
- [ ] Run the gates, then commit.

### Task 4: doctor site

```yaml-task
id: 4
description: _doctor_check_github_mcp sends GITHUB_PAT via -H @- to ${_GITHUB_API}/user, failing on a refused token without calling curl.
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R5, R7, R8, R9, R10]
acceptance:
  - cmd: bats -f "_doctor_check_github_mcp" tests/setup_env/unit.bats
    exit_code: 0
  - cmd: '[ "$(bats --count -f "_doctor_check_github_mcp.*(argv|stdin|line break|real curl)" tests/setup_env/unit.bats)" -ge 4 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats]
depends_on: [1, 2, 3]
```

**Interfaces:**

- Consumes: `_github_auth_header` (Task 2), `MOCK_CURL_STDIN_FILE` (Task 1), `start_http_listener`/`stop_http_listener` (Task 3; source `${REPO_ROOT}/tests/helpers/http_listener.bash` in the test, and call `stop_http_listener` from `unit.bats`'s existing `teardown()`).

- [ ] Write four failing tests in the `_doctor_check_github_mcp` block, using the existing fixture shape (`mkdir -p "${HOME}/.claude"; printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"`, `unset GITHUB_PAT_EXPIRY`, reset `_DOCTOR_*`):
  1. **argv**: `GITHUB_PAT=argv-tok-77`, `MOCK_CURL_STDIN_FILE` set. `MOCK_CALLS_FILE` contains `api.github.com/user` (control) and `-H @-`, and does not contain `argv-tok-77`.
  2. **stdin**: same setup. The stdin file equals `Authorization: Bearer argv-tok-77`.
  3. **line break**: `GITHUB_PAT=$'a\nb'`. `_DOCTOR_FAIL` is 1, and `MOCK_CALLS_FILE` has no `curl` line. Its control is test 1, which uses the same harness and records a call.
  4. **real curl**: strip mocks from `PATH`, `start_http_listener "${BATS_TEST_TMPDIR}"`, `_GITHUB_API="${HTTP_LISTENER_URL}"`, `GITHUB_PAT=real-tok-55`. `_DOCTOR_FAIL` is 0, `_DOCTOR_PASS` is at least 1, and `HTTP_LISTENER_HEADERS` contains `Authorization: Bearer real-tok-55`.
- [ ] Name each test `_doctor_check_github_mcp <phrase>`, where the phrase contains its bold keyword (`argv`, `stdin`, `line break`, `real curl`); Task 4's count gate matches on them. The empty-token case of R8 is already covered by the existing `fails when GITHUB_PAT is unset` test, which returns before curl.
- [ ] Run them and confirm all four fail (the token is still in argv, and the URL ignores `_GITHUB_API`).
- [ ] In `_doctor_check_github_mcp`, after the `doctor_pass "GITHUB_PAT (set)"` line, replace the live-check curl:

```bash
  # Token goes to curl on stdin: argv is readable by every uid. Capture first so
  # a refused token returns before curl runs -- a pipe could not stop it.
  local _hdr
  if ! _hdr=$(_github_auth_header "${GITHUB_PAT}"); then
    doctor_fail "GITHUB_PAT" "contains a line break — fix config/local.sh"
    return
  fi

  local _curl_rc=0
  printf '%s\n' "${_hdr}" | curl --max-time 5 --silent --fail -H @- \
    "${_GITHUB_API:-https://api.github.com}/user" > /dev/null 2>&1 || _curl_rc=$?
```

Leave the rc branches below unchanged.

- [ ] Run the gates. The existing 22/28/6/7 tests must stay green, which covers N3. Then commit.

### Task 5: allowlist the `_GITHUB_API` seam

> Spliced in during Phase 2, 2026-10-07. A background security review of `cd8d08cf` flagged the unrestricted seam as a credential-exfiltration path: a stray `export _GITHUB_API=...` would send the real PAT to that host. Operator chose the allowlist. R10 is amended and R15 added in the spec's `## Amendments`.

```yaml-task
id: 5
description: Add _github_api_base, honouring _GITHUB_API only for https://api.github.com or http://127.0.0.1:<port>, and wire the doctor site to it.
role: executor
model: sonnet
tdd: required
requirements: [R10, R15]
acceptance:
  - cmd: bats -f "_github_api_base|_doctor_check_github_mcp" tests/setup_env/unit.bats
    exit_code: 0
  - cmd: '[ "$(bats --count -f "_github_api_base" tests/setup_env/unit.bats)" -ge 8 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats]
depends_on: [4]
```

**Interfaces:**

- Produces: `_github_api_base` prints one URL on stdout, rc 0. Unset, empty or exactly `https://api.github.com` prints `https://api.github.com`. A value matching `^http://127\.0\.0\.1:[0-9]+$` prints itself. Anything else prints `https://api.github.com` and writes one stderr line containing `ignoring`.

- [ ] Write failing tests named `_github_api_base <phrase>`:
  1. unset -> default; 2. exact default -> default; 3. `http://127.0.0.1:8080` -> itself.
  4-9. Each of `https://evil.example`, `https://api.github.com.evil`, `http://127.0.0.1.evil:1`, `http://127.0.0.1:`, `https://api.github.com/`, `http://127.0.0.1:80/x` prints the default, and stderr contains `ignoring`. Capture stderr with `2>&1 >/dev/null` into its own variable.
- [ ] Add `_doctor_check_github_mcp ignores an off-host _GITHUB_API`: `_GITHUB_API=https://evil.example`, mocked curl. `MOCK_CALLS_FILE` contains `api.github.com/user` and does not contain `evil.example`.
- [ ] Tighten `_doctor_check_github_mcp real curl delivers the header on stdin`. Capture its output (`_out="$(PATH=... _doctor_check_github_mcp 2>&1)"`) and assert it contains the live-check pass line. Read `doctor_pass` for the exact text, which `_doctor_check_github_mcp` passes as `GitHub PAT (live)`. Assert it contains no `FAIL`, and keep the header grep. The current `_DOCTOR_PASS -ge 1` is satisfied before curl runs (both Task 4 reviews).
- [ ] Run them and confirm RED.
- [ ] Add above `_github_auth_header` in `lib/helpers.sh`:

```bash
# Base URL for GitHub calls that carry a bearer token. _GITHUB_API lets a test
# aim real curl at a local listener; any other value could send the token
# off-host, so only the default or a 127.0.0.1 port is honoured.
_github_api_base() {
  local _default="https://api.github.com" _want="${_GITHUB_API:-}"
  if [[ -z "${_want}" || "${_want}" == "${_default}" ]]; then
    printf '%s\n' "${_default}"
  elif [[ "${_want}" =~ ^http://127\.0\.0\.1:[0-9]+$ ]]; then
    printf '%s\n' "${_want}"
  else
    printf "_GITHUB_API=%s is not api.github.com or 127.0.0.1 -- ignoring it\n" "${_want}" >&2
    printf '%s\n' "${_default}"
  fi
}
```

- [ ] In `_doctor_check_github_mcp` replace `"${_GITHUB_API:-https://api.github.com}/user"` with `"$(_github_api_base)/user"`.
- [ ] Run the gates, then commit.

### Task 6: check-versions site

```yaml-task
id: 6
description: _fetch_github_latest sends GITHUB_TOKEN via -H @- with --max-time 10 to ${_GITHUB_API}; run_check_versions refuses once, skips the 7 GitHub checks, returns 2.
role: executor
model: sonnet
tdd: required
requirements: [R1, R3, R5, R6, R8, R9, R10, R11, R12, R15]
acceptance:
  - cmd: bats -f "_fetch_github_latest|run_check_versions" tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: '[ "$(bats --count -f "(_fetch_github_latest|run_check_versions).*(argv|stdin|line break|real curl|not checked|max-time)" tests/setup_env/workflows.bats)" -ge 7 ]'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: [5]
```

**Interfaces:**

- Consumes: Tasks 1-3, as in Task 4. Call `stop_http_listener` from the existing `teardown()` at `workflows.bats:55`.

- [ ] Delete the test `_fetch_github_latest adds Authorization header when GITHUB_TOKEN is set`; it asserts the defect. Write failing tests:
  1. **argv**: `GITHUB_TOKEN=gt-argv-1`, `MOCK_CURL_STDOUT='  "tag_name": "v2.0.0",'`, `MOCK_CURL_STDIN_FILE` set. Output is `2.0.0`, and `MOCK_CALLS_FILE` has `releases/latest` (control) and `-H @-`, but not `gt-argv-1`.
  2. **stdin**: same setup. The stdin file equals `Authorization: Bearer gt-argv-1`.
  3. **no token, argv**: `GITHUB_TOKEN` unset. `MOCK_CALLS_FILE` has `releases/latest` and not `-H @-`.
  4. **max-time**: `MOCK_CALLS_FILE` contains `--max-time 10`.
  5. **line break**: `GITHUB_TOKEN=$'a\nb'`. Output is empty, and `MOCK_CALLS_FILE` has no `curl` line.
  6. **real curl**: strip mocks, listener, `_GITHUB_API="${HTTP_LISTENER_URL}"`, `GITHUB_TOKEN=gt-real-9`. Output is `9.9.9`, and the headers contain `Authorization: Bearer gt-real-9`. Also export `http_proxy=http://127.0.0.1:9` and `HTTP_PROXY` to the same dead port, so the test fails if `--noproxy 127.0.0.1` is dropped.
  7. **run_check_versions not checked**: run the real function with `GITHUB_TOKEN=$'a\nb'` and `CARGO_TOOLS=(foo@1.0.0)`, after defining recorder stubs that append their name to `${BATS_TEST_TMPDIR}/rec` and print `[OK]`: `_check_one_version`, `_check_cv_oh_my_zsh`, `_check_cv_homebrew_install` and `_check_one_cargo_version`. Status is 2, `rec` has 0 `_check_one_version` lines and one line for each of the other three, output contains `7 not checked`, and exactly one output line contains `GITHUB_TOKEN`.
  8. **run_check_versions control**: same stubs with `GITHUB_TOKEN=ok-tok`. Status is 0, `rec` has 7 `_check_one_version` lines, and the output does not contain `not checked`.
  9. **off-host**: `_GITHUB_API=https://evil.example`, `MOCK_CURL_STDOUT` as in test 1. `MOCK_CALLS_FILE` contains `api.github.com/repos/` and does not contain `evil.example`. Name it `_fetch_github_latest ignores an off-host _GITHUB_API`.
- [ ] Name tests 1-6 `_fetch_github_latest <phrase>` and tests 7-8 `run_check_versions <phrase>`, where the phrase contains the bold keyword (`argv`, `stdin`, `max-time`, `line break`, `real curl`, `not checked`; the control needs none). Task 6's count gate matches on them.
- [ ] Run them and confirm each fails for its stated reason.
- [ ] Rewrite `_fetch_github_latest`:

```bash
_fetch_github_latest() {
  local _repo="$1" _hdr=""
  # --noproxy: the 127.0.0.1 test form would otherwise send the bearer
  # token in cleartext to any http_proxy; harmless for the https default.
  local -a _curl_args=(-sf --max-time 10 --noproxy 127.0.0.1)
  # Token goes to curl on stdin (-H @-), not argv, which every uid can read.
  # Capture first: a refused token must stop here, not fall back unauthenticated.
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    _hdr=$(_github_auth_header "${GITHUB_TOKEN}") || return 1
    _curl_args+=(-H @-)
  fi
  { [[ -n "${_hdr}" ]] && printf '%s\n' "${_hdr}"; } \
    | curl "${_curl_args[@]}" \
      "$(_github_api_base)/repos/${_repo}/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
    | sed 's/^v//'
}
```

- [ ] In `run_check_versions`:
  - Add `_unchecked=0 _token_refused=0` to the `local` line.
  - After the header `printf`, add:

```bash
  if [[ -n ${GITHUB_TOKEN:-} ]] && ! _github_auth_header "${GITHUB_TOKEN}" >/dev/null 2>&1; then
    printf "  [WARN]     GITHUB_TOKEN contains a line break -- GitHub release checks not run; fix the variable\n"
    _token_refused=1
  fi
```

- Make the first statement of `_run_cv_check`: `if [[ ${_token_refused} -eq 1 ]]; then _unchecked=$(( _unchecked + 1 )); return 0; fi`.
- Replace the summary and return:

```bash
  printf "\n%d outdated, %d skipped, %d warnings, %d OK" \
    "${_outdated}" "${_skipped}" "${_warned}" "${_ok}"
  [[ ${_unchecked} -gt 0 ]] && printf ", %d not checked" "${_unchecked}"
  printf "\n"

  # A refused token outranks "outdated" (rc 1): the caller cannot act on a
  # version verdict that skipped seven of its inputs.
  [[ ${_token_refused} -eq 1 ]] && return 2
  [[ ${_outdated} -eq 0 ]]
```

- [ ] Run the gates, then commit.

### Task 7: documentation

```yaml-task
id: 7
description: Document _GITHUB_API, MOCK_CURL_STDIN_FILE, the listener helper and check-versions rc 2 in CLAUDE.md, and remove the backlog row (docs-only, no behaviour change, so tdd not-applicable).
role: executor
model: sonnet
tdd: not-applicable
requirements: [R13]
acceptance:
  - cmd: 'grep -q "_GITHUB_API" CLAUDE.md && grep -q "MOCK_CURL_STDIN_FILE" CLAUDE.md && grep -q "http_listener.bash" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "check-versions.*(exits|returns|rc) 2" CLAUDE.md'
    exit_code: 0
  - cmd: '! grep -q "_fetch_github_latest. passes .GITHUB_TOKEN. in curl argv" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [4, 6]
```

The suite reads no tracked `.md` outside `tests/` (`tests/scripts/docs_inert_premise.bats`), so this task's gates are scoped. The orchestrator ran `make test` after Task 6.

- [ ] In `CLAUDE.md` Entry Points, add to the `check-versions` bullet: "Exits 2 when `GITHUB_TOKEN` contains a line break: the seven GitHub-release checks are not run and the summary counts them as `not checked`; rc 2 takes precedence over the rc 1 'outdated' verdict."
- [ ] In `CLAUDE.md` Test Seams, after the `_CRATES_API` bullet, add:
  - `_GITHUB_API` (`lib/helpers.sh:_doctor_check_github_mcp`, `lib/workflows.sh:_fetch_github_latest`): the API base, default `https://api.github.com`. It exists so a test can point real curl at `tests/helpers/http_listener.bash`. Read through `_github_api_base`, which honours it only for `https://api.github.com` or `http://127.0.0.1:<port>`; any other value warns and is ignored, so a stray export cannot send the token off-host.
  - `MOCK_CURL_STDIN_FILE` (`tests/mocks/curl`): records the stdin of a call carrying `-H @-`, the route both GitHub sites use to keep the token off argv.
  - `tests/helpers/http_listener.bash`: the only sanctioned listener. It closes fd 3, redirects output, carries a deadline, and is stopped from `teardown()`. Inlining a listener risks hanging the suite.
- [ ] In `docs/superpowers/README.md` Backlog, delete the row beginning ``| `_fetch_github_latest` passes `GITHUB_TOKEN` in curl argv``.
- [ ] Run the gates, then commit.

## Non-goal check

Fresh reviewer, 2026-10-07: 3 CLEAR, 0 CONFLICT, 0 UNCLEAR.

- N1 CLEAR — "no task's `files_touched` includes `scripts/cadence-notify.sh`." No resolution needed.
- N2 CLEAR — "doctor: `doctor_fail` + `return`; `_fetch_github_latest`: `|| return 1` precedes curl; `run_check_versions`: skips the 7 release checks, returns 2." No resolution needed. The reviewer noted it could not confirm from the plan alone that `_check_cv_oh_my_zsh` and `_check_cv_homebrew_install` never used the token. Already settled: round 3 confirmed both call `api.github.com` without auth today and `GITHUB_TOKEN` is read only in `_fetch_github_latest`, so running them on refusal is not a fallback.
- N3 CLEAR — "Task 4 says 'Leave the rc branches below unchanged'; `_curl_rc` still takes curl's exit, curl being the last pipeline element." No resolution needed.
