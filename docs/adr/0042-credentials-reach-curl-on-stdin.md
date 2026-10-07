# ADR-0042: GitHub credentials reach curl on stdin, and credential-carrying seams are allowlisted

**Date:** 2026-10-07
**Status:** Accepted

## Context

Two call sites passed a GitHub bearer token to curl as `-H "Authorization: Bearer ${TOKEN}"`:
`_doctor_check_github_mcp` (`GITHUB_PAT`, which runs on every `-t doctor`) and `_fetch_github_latest`
(`GITHUB_TOKEN`, used by `-t check-versions`). curl's argv is readable by every uid through `ps` and
`/proc/<pid>/cmdline` for as long as the call runs. On `claude` and `workstation`, `/proc` is
mounted without `hidepid` and the `github-runner` service shares the host PID namespace, so a CI
job could read the operator's token from argv.

Three alternatives were considered:

- **`curl -K -` with a `header = "..."` config line on stdin.** This is the form
  `scripts/cadence-notify.sh` uses. curl's config values are quoted, so the token would need
  `\` and `"` escaping.
- **`curl -H @-`, which reads raw header lines from stdin.** No quoting is needed. A line break
  still injects a second header, and there is no escape for one, so a token containing `\n` or
  `\r` has to be refused.
- **A curl wrapper on `PATH` for tests.** This needs no production seam, but it cannot drive the
  production call sites against a real listener.

Making the URL overridable for tests (`_GITHUB_API`) introduced a second hazard. A background
security review of the first version found that any value of the variable redirected the real
token to that host, so a stray `export` would leak it. A Phase 3 review then found two more
problems with the loopback form: it honoured `http_proxy`, which sent the token to the proxy in
cleartext, and `[0-9]` follows the locale, so non-ASCII digits matched.

## Decision

1. A GitHub credential never appears in a command's argv. `_github_auth_header` prints
   `Authorization: Bearer <token>` for `curl -H @-`. It refuses a token containing `\n` or `\r`
   (rc 1, a message on stderr, nothing on stdout) instead of escaping it.
2. Callers capture the header and its status before invoking curl. They never write
   `_github_auth_header "$t" | curl`, because a pipe cannot stop curl: the request would go out
   unauthenticated and exit 0. A refused token stops the call. There is no unauthenticated
   fallback.
3. A test seam that can redirect a credential is allowlisted, not free-form. `_github_api_base`
   honours `_GITHUB_API` only when it is exactly `https://api.github.com` or matches
   `^http://127\.0\.0\.1:[0123456789]{1,5}$`. Any other value writes one stderr line and falls back
   to the default. Both curl calls pass `--noproxy 127.0.0.1`.
4. `run_check_versions` checks `GITHUB_TOKEN` once. On refusal it skips only the seven checks
   that send the token, reports them as `not checked`, and returns 2. That rc takes precedence
   over rc 1 ("a pin is outdated").

## Consequences

- The token's only exposure in transit is curl's stdin pipe, which is same-uid. It is no longer
  visible to other accounts. On the runner hosts this is hygiene, not containment:
  `github-runner` is in the host `docker` group and can read `config/local.sh` directly. That is
  tracked as a P1 in terraform_ansible's backlog.
- Any new code that hands a credential to an external tool should follow the same shape: stdin
  over argv, refusal over escaping where the format has no escape, and capture before the pipe.
- A real-curl test needs a listener. `tests/helpers/http_listener.bash` is the sanctioned one. It
  uses `socketserver.TCPServer` because `http.server.HTTPServer` calls `socket.getfqdn()`, which
  blocks on macOS mDNS. It closes inherited fds and carries a deadline, so it cannot hang the
  suite.
- `check-versions` has a third exit code. Callers that test only for 0 or 1 need to handle 2.

## Related

- Spec: [docs/superpowers/specs/2026-10-07-github-token-off-argv-design.md](../superpowers/specs/2026-10-07-github-token-off-argv-design.md)
- Plan: [docs/superpowers/plans/2026-10-07-github-token-off-argv.md](../superpowers/plans/2026-10-07-github-token-off-argv.md)
- PR #320 (`326ae7ef`)
- [ADR-0039](0039-apt-keys-are-scoped-and-pinned.md): the same principle of pinned, scoped trust, applied to apt keys
