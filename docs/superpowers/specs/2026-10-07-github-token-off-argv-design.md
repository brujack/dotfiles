# GitHub tokens off curl's argv

## Problem

Two call sites hand a GitHub credential to curl as a command-line argument:

| site                                                           | variable       | reached by                                     |
| -------------------------------------------------------------- | -------------- | ---------------------------------------------- |
| `lib/workflows.sh` `_fetch_github_latest`                      | `GITHUB_TOKEN` | `-t check-versions`, once per pinned tool      |
| `lib/helpers.sh` `_doctor_check_github_mcp` (live-token check) | `GITHUB_PAT`   | `-t doctor`, on every machine with the PAT set |

Both build `-H "Authorization: Bearer ${TOKEN}"`. curl's argv is world-readable through
`ps` and `/proc/<pid>/cmdline` for the life of the call, so any local process can read the
token. Verified 2026-10-07 over tracked files in `lib/`, `scripts/` and `setup_env.sh`:
`git grep` for any `*TOKEN*`/`*PAT*`/`*PASSWORD*`/`*SECRET*`/`*_KEY*` variable on a line
carrying `curl`, `wget`, `-u`, `-H`, `token=` or a `user@` URL returns these two lines and
nothing else. Not covered: `tests/`, `powershell/`, and credentials passed through a
differently named variable.
`scripts/cadence-notify.sh` already sends its ntfy credential on stdin via `curl -K -`.

The backlog row named only the first site. The second is the same defect.

## Design

### Helper

`_github_curl_auth_config <token>` in `lib/helpers.sh`:

- Refuses a token containing `\n` or `\r`: one line on stderr naming the reason, rc 1, no
  stdout. curl's config format is line-oriented, so a line break in a quoted value ends it
  and the rest is parsed as further directives (`shell.md`, credentials entry). Refusal,
  not escaping, because the format has no escape for a line break.
- Otherwise escapes `\` as `\\` and `"` as `\"`, in that order, and prints exactly one line:
  `header = "Authorization: Bearer <escaped token>"`. rc 0.
- An empty token is the caller's concern; both callers already branch on it.

### `_fetch_github_latest`

- Token unset or empty: unchanged. curl runs with no `-K` and no auth header.
- Token set: the helper's output is piped into `curl -sf -K - <url>`.
- Helper refuses: print nothing on stdout and return without calling curl. The caller's
  existing `[WARN] <tool> could not fetch latest version` then fires. It must not fall back
  to an unauthenticated request: a silently-unauthenticated run hides a broken credential.

### `_doctor_check_github_mcp`

- Helper refuses: `doctor_fail "GITHUB_PAT" "contains a newline — fix config/local.sh"`
  and skip the live check and the expiry check (return).
- Otherwise the live check pipes the helper's output into
  `curl --max-time 5 --silent --fail -K - https://api.github.com/user`. The rc
  classification (22 fail, 28/6 warn, other warn, 0 pass) is unchanged.

### Test mock

`tests/mocks/curl` does not read stdin. Add `MOCK_CURL_STDIN_FILE`: when set and the argv
contains `-K -`, the mock copies its stdin to that file. Unset, behaviour is unchanged.

### Testing

- The token string never appears in `MOCK_CALLS_FILE` at either site.
- The config the mock received on stdin is exactly the expected `header = ...` line.
- No token: no `-K` in argv and no stdin captured.
- `\n` and `\r` tokens are refused at both sites, curl is not invoked, and each site
  produces its documented outcome.
- Escaping: a token containing `"` and `\` round-trips.
- One test runs **real** curl, with the mocks directory stripped from `PATH`, against a
  local `python3` HTTP listener that records request headers. It asserts the captured
  request carries `Authorization: Bearer <token>`. This is `tdd.md` pitfall F: a mock that
  records stdin cannot show that real curl honours the config.
- The existing test `_fetch_github_latest adds Authorization header when GITHUB_TOKEN is set`
  asserts the header is in argv, which is the defect. It is replaced, not kept.

## Out of scope

- `scripts/cadence-notify.sh`'s inline copy of the same technique. It is a standalone script
  that does not source `lib/`.
- `_fetch_github_latest`'s pipeline discarding curl's exit status. An empty result already
  degrades to WARN.

## Requirements

- **R1.** `[PR1]` `_fetch_github_latest` with `GITHUB_TOKEN` set passes no argv element containing the token to curl.
- **R2.** `[PR1]` `_doctor_check_github_mcp` with `GITHUB_PAT` set passes no argv element containing the token to curl.
- **R3.** `[PR1]` Both sites send `header = "Authorization: Bearer <token>"` to curl on stdin via `-K -`.
- **R4.** `[PR1]` `_github_curl_auth_config` exits 1 with no stdout for a token containing `\n` or `\r`.
- **R5.** `[PR1]` `_github_curl_auth_config` escapes `\` to `\\` and `"` to `\"`.
- **R6.** `[PR1]` On a refused token `_fetch_github_latest` prints nothing and does not invoke curl.
- **R7.** `[PR1]` On a refused token `_doctor_check_github_mcp` records `doctor_fail` for `GITHUB_PAT` and does not invoke curl.
- **R8.** `[PR1]` With the token unset or empty, neither site passes `-K` to curl.
- **R9.** `[PR1]` One bats test drives real curl against a local listener and asserts the received `Authorization` header.
- **V1.** `make test` exits 0 on the Linux box and in CI, including `test-macos`.
- **V2.** With a real `GITHUB_TOKEN`, `./setup_env.sh -t check-versions` still resolves latest versions, and a concurrent `ps -eo args` sampling loop shows no argv containing the token.
- **N1.** No change to `scripts/cadence-notify.sh`.
- **N2.** No unauthenticated fallback when a set token is refused.
- **N3.** No change to `_doctor_check_github_mcp`'s rc classification for curl exit codes.

## Multi-Lens Review

Reviewed at commit: `4448cbcb` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building, but the Problem section omits the concrete reader. Same-uid processes can already read `/proc/<pid>/environ`, so the real exposure is cross-uid: `github-runner` jobs on `claude`/`workstation`, which can run PR-supplied code. Measured by the author after the lens: `/proc` is mounted without `hidepid`, and `github-runner` processes share the host PID namespace (`pid:[4026531836]`). Second: `curl -H @-` reads the header line from stdin with no config-file quoting, which deletes R5 and its escape-order logic. Measured by the author on curl 8.22 / Linux against a python3 listener: `tok"x\y` arrives verbatim, and an embedded `\n` injects a second header (`X-Injected: 1` received), so R4 still applies. macOS curl unverified. Third: `GITHUB_PAT` is set in `config/local.sh` while `GITHUB_TOKEN` is set nowhere, so the doctor site is the live leak, and V2 samples only the dormant site.
Assumption: Runner processes share the host PID namespace. Measured: confirmed.
Disposition:

### Ergonomics

Finding: R9 cannot reach either call site, because both hardcode `https://api.github.com/...` and no URL seam exists. A bare `helper | curl` against a listener tests curl, not the wiring. A seam needs a name, a default, a Test Seams entry, an ephemeral-port listener (port 0, readiness file) for `bats --jobs 24`, and `--max-time` on `_fetch_github_latest`. Second: the absence assertions (token not in argv, no `-K`, curl not invoked) pass if curl never ran; each needs a positive control in the same test. Third: "piped into curl" invites `helper | curl`, which runs curl unauthenticated on refusal and violates N2; the Design must state capture-then-pipe. Minor: under `-t check-versions` a refused token prints one reason line per tool, and each WARN blames the network; `doctor_fail` says "newline" for a `\r`.
Assumption: R9 can exercise the production call sites without a URL seam. Refuted by `grep -n 'api.github.com' lib/workflows.sh lib/helpers.sh`.
Disposition:

### Risk

Finding: Same R9 seam gap. Option (a), a hand-built pipe, is the same derivation run twice. Option (b), a `_GITHUB_API` seam, lets an env var direct the token to any host. That is no new capability over editing `PATH`, but it must be stated, and it needs `--max-time` on `_fetch_github_latest` so a silent listener cannot hang the suite. Measured: `( exit 1 ) | curl -sf -K - <url>` sends an unauthenticated request and returns rc 0, so capture-then-pipe is mandatory. V2's `ps` sampling loop passes when it sees nothing; it needs a positive control, such as seeing at least one `curl ... api.github.com` argv or catching the token in pre-change code. Not raised: stdin contention, xtrace (no regression), escaping order (verified correct with real curl).
Assumption: Same as Ergonomics. Refuted.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
