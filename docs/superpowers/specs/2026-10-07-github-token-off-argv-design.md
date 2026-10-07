# GitHub tokens off curl's argv

- **Approved:** 2026-10-07

## Problem

Two call sites hand a GitHub credential to curl as a command-line argument:

| site                                                           | variable       | reached by                                     |
| -------------------------------------------------------------- | -------------- | ---------------------------------------------- |
| `lib/workflows.sh` `_fetch_github_latest`                      | `GITHUB_TOKEN` | `-t check-versions`, once per pinned tool      |
| `lib/helpers.sh` `_doctor_check_github_mcp` (live-token check) | `GITHUB_PAT`   | `-t doctor`, on every machine with the PAT set |

Both build `-H "Authorization: Bearer ${TOKEN}"`. curl's argv is readable through `ps` and
`/proc/<pid>/cmdline` by **every uid** for the life of the call. A same-uid process could
already read the token from `/proc/<pid>/environ`, so the exposure this closes is cross-uid.
On `claude` and `workstation` that reader is concrete. Measured on `claude` 2026-10-07:
`/proc` is mounted without `hidepid`, and `github-runner` processes share the host PID
namespace (`pid:[4026531836]`, identical to the operator's shell). A CI job, which can run
PR-supplied code, can therefore read the operator's curl argv.

**This change is hygiene on those two hosts, not the fix for that reader.** `github-runner`
is in the `docker` group (`docker:x:983:bruce,github-runner` on `claude`, measured
2026-10-07, and `docker:x:984:bruce,github-runner` on `workstation`, measured over `ssh`
the same day), and the socket is `root:docker 660` on both. A job can therefore mount `/home/bruce` into a container and read
`config/local.sh` at any time, which outranks a 5-second argv window. That defect is tracked
as a P1 backlog row in `terraform_ansible`, which provisions the runners. Moving the token
off argv still closes the window for any cross-uid reader without docker or filesystem
access: system daemons, and any future unprivileged account.

`GITHUB_PAT` is exported by `config/local.sh`. `GITHUB_TOKEN` is set nowhere in the repo, so
the doctor site is the live leak and the check-versions site leaks only when the operator
exports the variable by hand.

Scope of the search, 2026-10-07, over tracked files in `lib/`, `scripts/` and `setup_env.sh`:
`git grep` for any `*TOKEN*`/`*PAT*`/`*PASSWORD*`/`*SECRET*`/`*_KEY*` variable on a line
carrying `curl`, `wget`, `-u`, `-H`, `token=` or a `user@` URL returns these two lines and
nothing else. Not covered: `tests/`, `powershell/`, and credentials passed through a
differently named variable.

The backlog row named only the first site. The second is the same defect.

## Design

### Helper

`_github_auth_header <token>` in `lib/helpers.sh`:

- Refuses a token containing `\n` or `\r`: one line on stderr naming the reason
  ("contains a line break"), rc 1, no stdout. Measured on curl 8.22: a `\n` in a header read
  through `-H @-` injects a second header, so refusal is required, not defensive.
- Otherwise prints exactly one line, `Authorization: Bearer <token>`, with no escaping. rc 0.
- An empty token is the caller's concern; both callers already branch on it.

curl receives it with `-H @-`, which reads header lines from stdin. This replaces the
first draft's `-K -` config, whose quoted-value format needed `\` and `"` escaping.
Measured on curl 8.22 / Linux against a python3 listener: a token `tok"x\y` arrives
verbatim through `-H @-`.

### Call shape: capture, then pipe

Both sites capture the helper's output and status before curl runs:

```bash
local _hdr
_hdr=$(_github_auth_header "${GITHUB_TOKEN}") || return 0   # site-specific outcome
printf '%s\n' "${_hdr}" | curl ... -H @- "${_url}"
```

A literal `_github_auth_header "$t" | curl -H @-` is forbidden. A pipe cannot stop the
downstream command: measured, `( exit 1 ) | curl -sf -K - <url>` sends an unauthenticated
request and returns rc 0, which is the fallback N2 prohibits.

### URL seam

`_GITHUB_API`, default `https://api.github.com`, read by both sites:
`${_GITHUB_API:-https://api.github.com}/repos/<repo>/releases/latest` and `.../user`.
It exists so a test can point real curl at a local listener and exercise each production
call site end to end. It lets an environment variable send the token to any host. That is
no new capability: whoever can set the environment can already put a `curl` of their own on
`PATH`. It gets a Test Seams entry in `CLAUDE.md`, matching `_CRATES_API`.

`_fetch_github_latest` gains `--max-time 10`, matching doctor's `--max-time 5` in kind, so a
listener (or a real network path) that accepts and never answers cannot hang the caller.

### `_fetch_github_latest` and `run_check_versions`

- Token unset or empty: no `-H @-`, no stdin, unauthenticated request. Unchanged.
- `run_check_versions` checks `GITHUB_TOKEN` once, before the `_run_cv_check` tools. On
  refusal it prints one `[WARN]` line naming `GITHUB_TOKEN` and the reason, skips only the
  `_run_cv_check` tools (the only ones that read the token), and still runs every other
  check: `CARGO_TOOLS` (crates.io), `_check_cv_oh_my_zsh` and `_check_cv_homebrew_install`.
  The header and summary print as usual, and each skipped tool is counted in a separate
  "not checked" figure in the summary line, so the summary cannot hide the skip. It then
  returns **2**, never 1. Return 1 keeps its
  documented meaning, "a pin is outdated" (`setup_env.sh:73` exits with this rc), and a
  refused token takes precedence over it. `CLAUDE.md`'s `check-versions` entry documents
  rc 2.
- `_fetch_github_latest` keeps its own capture-then-pipe guard for any other caller. On
  refusal it prints nothing on stdout and returns without invoking curl.

### `_doctor_check_github_mcp`

- Helper refuses: `doctor_fail "GITHUB_PAT" "contains a line break — fix config/local.sh"`,
  and return before the live and expiry checks.
- Otherwise the live check is
  `printf '%s\n' "${_hdr}" | curl --max-time 5 --silent --fail -H @- "${_GITHUB_API:-https://api.github.com}/user"`.
  The rc classification (22 fail, 28/6 warn, other warn, 0 pass) is unchanged.

### Test mock

`tests/mocks/curl` does not read stdin. Add `MOCK_CURL_STDIN_FILE`: when set and argv
contains `-H @-`, the mock copies its stdin to that file. Unset, behaviour is unchanged.

### Testing

Every absence assertion carries a positive control in the same test, proving curl ran:
the request URL is present in `MOCK_CALLS_FILE`. A refusal test's control is a sibling test
using the same harness with a valid token, which shows a recorded call.

- Each site, token set: the URL is in `MOCK_CALLS_FILE`, the token string is not, and the
  captured stdin equals `Authorization: Bearer <token>` exactly.
- Each site, no token: the URL is in `MOCK_CALLS_FILE`, and `-H @-` is not.
- `\n` and `\r` tokens: refused at both sites and in `run_check_versions`, with no curl
  call recorded, plus the site's documented outcome. `run_check_versions` prints the
  reason line exactly once.
- Real curl, per site: with the mocks directory stripped from `PATH`, `_GITHUB_API` points
  at a python3 listener. Each test asserts the listener received
  `Authorization: Bearer <token>`. This is `tdd.md` pitfall F: a mock that records stdin
  cannot show that real curl sends the header.
- The listener lives in one shared helper under `tests/helpers/`, never inlined per test,
  because an orphaned listener hangs the suite rather than failing it. Measured by the
  round 2 Risk lens: a backgrounded listener with no teardown made `timeout 15 bats`
  return 124. The helper:
  - binds port 0 and writes the port to a readiness file atomically (temp file, then `mv`);
    the test polls it with `-s`, bounded;
  - is launched with `3>&-` and its stdout and stderr redirected to a file, so it cannot
    hold bats' fd 3 or output pipe;
  - carries its own deadline (a server-side socket timeout and a request cap), so it exits
    even if never killed;
  - is killed by PID in `teardown()`, not in the test body.
- `run_check_versions` refusal test runs the real function, not a redefinition.
  `_run_cv_check` is a nested function redefined on every call, so it cannot be stubbed;
  the test stubs what it calls instead. `_check_one_version` is a recorder asserted at 0
  calls, and `_check_cv_oh_my_zsh`, `_check_cv_homebrew_install` and the `CARGO_TOOLS`
  check are recorders each asserted as called. The test asserts the "not checked" count
  is 7 and the rc is 2.
- The listener helper's teardown kills the python process's own PID, never a wrapping
  subshell or `timeout`.
- The existing test `_fetch_github_latest adds Authorization header when GITHUB_TOKEN is set`
  asserts the header is in argv, which is the defect. It is replaced, not kept.

## Out of scope

- `scripts/cadence-notify.sh`'s `-K -` copy. It is a standalone script that does not source
  `lib/`, and its `user =` credential needs config syntax.
- `_fetch_github_latest`'s pipeline discarding curl's exit status. An empty result already
  degrades to WARN.

## Requirements

- **R1.** `[PR1]` `_fetch_github_latest` with `GITHUB_TOKEN` set passes no argv element containing the token to curl.
- **R2.** `[PR1]` `_doctor_check_github_mcp` with `GITHUB_PAT` set passes no argv element containing the token to curl.
- **R3.** `[PR1]` Both sites send `Authorization: Bearer <token>` to curl on stdin via `-H @-`.
- **R4.** `[PR1]` `_github_auth_header` exits 1 with no stdout for a token containing `\n` or `\r`.
- **R5.** `[PR1]` Both sites capture `_github_auth_header`'s output and status before invoking curl; neither pipes the helper directly into curl.
- **R6.** `[PR1]` On a refused token `_fetch_github_latest` prints nothing and does not invoke curl.
- **R7.** `[PR1]` On a refused token `_doctor_check_github_mcp` records `doctor_fail` for `GITHUB_PAT` and does not invoke curl.
- **R8.** `[PR1]` With the token unset or empty, neither site passes `-H @-` to curl.
- **R9.** `[PR1]` One bats test per site drives real curl through the production function at a `_GITHUB_API` listener and asserts the received `Authorization` header.
- **R10.** `[PR1]` Both sites build their URL from `${_GITHUB_API:-https://api.github.com}`.
- **R11.** `[PR1]` `_fetch_github_latest` passes `--max-time 10` to curl.
- **R12.** `[PR1]` On a refused `GITHUB_TOKEN`, `run_check_versions` prints one reason line, skips only the `_run_cv_check` tools, runs the remaining checks, reports the skipped tools as a "not checked" count in the summary, and returns 2.
- **R13.** `[PR1]` `CLAUDE.md` Test Seams documents `_GITHUB_API` and `MOCK_CURL_STDIN_FILE`, and the `check-versions` entry documents rc 2.
- **R14.** `[PR1]` The real-curl listener is a shared `tests/helpers/` helper launched with `3>&-`, with a server-side deadline, and killed in `teardown()`.
- **V1.** `make test` exits 0 on the Linux box and in CI, including `test-macos`.
- **V2.** During `./setup_env.sh -t doctor` with the real `GITHUB_PAT`, a `ps -eo args` sampling loop catches at least one `curl ... api.github.com/user` argv (positive control) and no argv containing the token. Run it against the pre-change code too, where it must catch the token.
- **V3.** `-H @-` delivers the header on the Studio's curl, measured over `ssh` against a listener.
- **N1.** No change to `scripts/cadence-notify.sh`.
- **N2.** No unauthenticated fallback when a set token is refused.
- **N3.** No change to `_doctor_check_github_mcp`'s rc classification for curl exit codes.

## Multi-Lens Review

Reviewed at commit: `4448cbcb` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building, but the Problem section omits the concrete reader. Same-uid processes can already read `/proc/<pid>/environ`, so the real exposure is cross-uid: `github-runner` jobs on `claude`/`workstation`, which can run PR-supplied code. Measured by the author after the lens: `/proc` is mounted without `hidepid`, and `github-runner` processes share the host PID namespace (`pid:[4026531836]`). Second: `curl -H @-` reads the header line from stdin with no config-file quoting, which deletes R5 and its escape-order logic. Measured by the author on curl 8.22 / Linux against a python3 listener: `tok"x\y` arrives verbatim, and an embedded `\n` injects a second header (`X-Injected: 1` received), so R4 still applies. macOS curl unverified. Third: `GITHUB_PAT` is set in `config/local.sh` while `GITHUB_TOKEN` is set nowhere, so the doctor site is the live leak, and V2 samples only the dormant site.
Assumption: Runner processes share the host PID namespace. Measured: confirmed.
Disposition: Addressed — threat named (cross-uid runner reader, measured); `-H @-` replaces `-K -`, dropping escaping; V2 moved to `-t doctor` with a positive control.

### Ergonomics

Finding: R9 cannot reach either call site, because both hardcode `https://api.github.com/...` and no URL seam exists. A bare `helper | curl` against a listener tests curl, not the wiring. A seam needs a name, a default, a Test Seams entry, an ephemeral-port listener (port 0, readiness file) for `bats --jobs 24`, and `--max-time` on `_fetch_github_latest`. Second: the absence assertions (token not in argv, no `-K`, curl not invoked) pass if curl never ran; each needs a positive control in the same test. Third: "piped into curl" invites `helper | curl`, which runs curl unauthenticated on refusal and violates N2; the Design must state capture-then-pipe. Minor: under `-t check-versions` a refused token prints one reason line per tool, and each WARN blames the network; `doctor_fail` says "newline" for a `\r`.
Assumption: R9 can exercise the production call sites without a URL seam. Refuted by `grep -n 'api.github.com' lib/workflows.sh lib/helpers.sh`.
Disposition: Addressed — `_GITHUB_API` seam plus `--max-time 10`; port-0 listener with readiness file; positive control in every absence test; capture-then-pipe stated; one refusal line in `run_check_versions`; "line break" wording.

### Risk

Finding: Same R9 seam gap. Option (a), a hand-built pipe, is the same derivation run twice. Option (b), a `_GITHUB_API` seam, lets an env var direct the token to any host. That is no new capability over editing `PATH`, but it must be stated, and it needs `--max-time` on `_fetch_github_latest` so a silent listener cannot hang the suite. Measured: `( exit 1 ) | curl -sf -K - <url>` sends an unauthenticated request and returns rc 0, so capture-then-pipe is mandatory. V2's `ps` sampling loop passes when it sees nothing; it needs a positive control, such as seeing at least one `curl ... api.github.com` argv or catching the token in pre-change code. Not raised: stdin contention, xtrace (no regression), escaping order (verified correct with real curl).
Assumption: Same as Ergonomics. Refuted.
Disposition: Addressed — seam chosen and its scope stated; capture-then-pipe mandated (R5); V2 positive control and pre-change run.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `40ec644d`. All three lenses, fresh subagents, prior section framed as history.

Goal-Fit — Finding: the cited reader is dominated: `github-runner` is in the `docker` group on `claude` and `workstation`, so a job can read `config/local.sh` from disk at any time; this change is hygiene there. The seam, timeout and refusal path serve a site whose token is set nowhere. Lens ran `docker run --network none -v /home/bruce:/h:ro` to prove readability, outside its read-only brief; nothing was written. Assumption: no cross-uid reader worth defending lacks docker and filesystem access — open; the docker-group defect goes to `terraform_ansible`.
Disposition: Addressed — Problem section states hygiene and names the docker-group reader; both sites kept as cheap hygiene (operator chose scope (a)); P1 row filed in `terraform_ansible`.

Ergonomics — Finding: rc 1 on a refused token collides with "outdated" and skips token-free checks; listener harness can hang the suite; R12 test must run the real function. Assumption: a `ps` sampler catches a ~150 ms curl — measured by the author 10/10, confirmed.
Disposition: Addressed — rc 2, skip only `_run_cv_check` tools; shared listener helper (R14); real-function test with stubbed tool list.

Risk — Finding: no listener teardown; reproduced a hang (rc 124 under `timeout 15`). Same rc-1 collision. Verified `-H @-` header bytes identical to argv form for whitespace, `:`, `@`, `;`, empty token; no new argv or trace leak. Assumption: macOS curl handles `-H @-` like curl 8.22 — unmeasured (`ssh studio` hung); stays V3.
Disposition: Addressed — R14 (`3>&-`, server deadline, teardown kill, `-s` atomic readiness file); rc 2.

### Round 3 (scoped)

Reviewed at commit: `a16cb60e`. Risk lens only, scoped to the round 2 diff (`40ec644d..a16cb60e`).

Risk — Finding: on a refused token the summary line omits the 7 skipped tools from every count, so rc 2 is the only sign; count them. `_run_cv_check` is nested and cannot be stubbed; stub its callees. Teardown must kill python's own PID. Verified: skip-only is implementable; `--update` unaffected; nothing else consumes rc 2; `3>&-` plus redirect alone prevented an orphan hang on bats 1.13 / Linux (`timeout 30 bats --jobs 2` rc 0 in 1 s). Assumption: the same holds on bats 1.10 (ubuntu-latest) and the macOS runner — unmeasured; the teardown kill and server deadline are the backstop if not.
Disposition: Addressed — "not checked" count in summary (R12); callee stubs; teardown kills python's own PID. Operator: "addressed, approved".
