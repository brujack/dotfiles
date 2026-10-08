# Bound every check-versions curl with `--max-time`

- **Date:** 2026-10-07
- **Backlog row:** `_check_cv_oh_my_zsh` / `_check_cv_homebrew_install` call api.github.com with no `--max-time` (P2 — bugs and security)

## Problem

`-t check-versions` makes three kinds of network call. One is bounded; two are not.

| call site               | function                     | endpoint                                         | calls per run                 | bound           |
| ----------------------- | ---------------------------- | ------------------------------------------------ | ----------------------------- | --------------- |
| `lib/workflows.sh:1273` | `_fetch_github_latest`       | api.github.com releases (via `_github_api_base`) | 7                             | `--max-time 10` |
| `lib/workflows.sh:1378` | `_check_cv_oh_my_zsh`        | api.github.com `ohmyzsh/ohmyzsh/releases/latest` | 1                             | **none**        |
| `lib/workflows.sh:1399` | `_check_cv_homebrew_install` | api.github.com `Homebrew/install/commits/master` | 1                             | **none**        |
| `lib/workflows.sh:1434` | `_check_one_cargo_version`   | crates.io (`_CRATES_API`)                        | 8 (one per `CARGO_TOOLS` pin) | **none**        |

The backlog row names the two GitHub calls. The crates.io call has the same defect in the
same run, so it is in scope (operator decision, 2026-10-07).

curl has no default total timeout. Measured 2026-10-07 on `claude` (curl 8.22.0) against a
local listener that accepts the TCP connection and never replies:

```
curl -fsSL <url>                 rc=124 elapsed=12s   (killed by an outer `timeout 12`; would hang)
curl -fsSL --max-time 3 <url>    rc=28  elapsed=3s
```

Population: one Linux machine, a loopback listener standing in for a stalled remote. The
claim drawn from it is only that curl without `--max-time` does not bound itself, which is
curl's documented behaviour and does not depend on platform or remote.

## Design

Add `--max-time 10` to the curl invocation at each of the three unbounded sites, matching
`_fetch_github_latest`'s value and spelling. No new constant, helper or seam.

Worst-case wall time for a fully stalled network goes from unbounded to 10 s per call: 7
GitHub-release calls already bounded, plus 2 + 8 newly bounded, for at most 170 s.

### Failure path

Unchanged. On timeout curl exits 28 with empty stdout. Each function's existing empty-result
branch fires:

- `_check_cv_oh_my_zsh`: `[WARN] oh-my-zsh could not fetch latest version`, `_warned += 1`
- `_check_cv_homebrew_install`: `[WARN] homebrew-install could not fetch latest SHA`, `_warned += 1`
- `_check_one_cargo_version`: `[WARN] <crate> could not fetch latest version`

The run continues to the next check. The existing `2>/dev/null` hides curl's "Operation timed
out", so the WARN does not distinguish a timeout from a 404 or DNS failure. That gap already
exists for `_fetch_github_latest` and is not widened here.

### Testing

Three new cases in `tests/setup_env/workflows.bats`, one per function, in the form of the
existing `_fetch_github_latest passes max-time 10` case (`:1487`): run the function against
`tests/mocks/curl` (no `curl()` function override) and assert `--max-time 10` appears in
`MOCK_CALLS_FILE`. Each is written and run RED before its edit.

Each case must also assert the mock was called at all (a non-empty `MOCK_CALLS_FILE` line for
that endpoint), so a function that stopped calling curl cannot pass by absence.

The existing tests that override `curl()` as a bash function ignore argv and are unaffected.

A real-curl silent-listener test is not added: the behaviour is curl's and is measured above,
each case would cost the full 10 s bound in suite time, and the two GitHub URLs are hardcoded,
so reaching them would need a new seam.

### Out of scope

- The four cheat.sh curls in the `-t update` path (`lib/workflows.sh:435`, `:445`, `:1156`,
  `:1166`) are also unbounded. Separate backlog row, added with this spec.
- Authenticating the two GitHub calls through `_github_api_base` / `_github_auth_header`.
  That changes the rate-limit and credential path, not the hang.

## Requirements

- **R1.** `[PR1]` `_check_cv_oh_my_zsh`'s curl invocation passes `--max-time 10`.
- **R2.** `[PR1]` `_check_cv_homebrew_install`'s curl invocation passes `--max-time 10`.
- **R3.** `[PR1]` `_check_one_cargo_version`'s curl invocation passes `--max-time 10`.
- **R4.** `[PR1]` `tests/setup_env/workflows.bats` has one case per function asserting both that the function called curl for its endpoint and that the call carried `--max-time 10`.
- **R5.** `[PR1]` The backlog row for this bug is removed from `docs/superpowers/README.md`.
- **V1.** Each new test fails with its `--max-time 10` removed and passes with it present.
- **V2.** `make test` exits 0 on the branch.
- **N1.** No change to any check-versions output line, counter, or exit code.
- **N2.** No new constant, helper function, or environment-variable seam.
- **N3.** No change to the cheat.sh curls or to how the GitHub calls authenticate.
