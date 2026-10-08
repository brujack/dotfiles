# Fix and bound the non-release check-versions calls

- **Date:** 2026-10-07
- **Backlog row:** `_check_cv_oh_my_zsh` / `_check_cv_homebrew_install` call api.github.com with no `--max-time` (P2 — bugs and security)

## Problem

`-t check-versions` makes three kinds of network call beyond the GitHub-release checks.
The backlog row says two are unbounded. Measurement found that both of those two have also
never returned a usable answer, which is the larger defect.

| call site               | function                     | endpoint                                         | calls per run                 | bound           | works?       |
| ----------------------- | ---------------------------- | ------------------------------------------------ | ----------------------------- | --------------- | ------------ |
| `lib/workflows.sh:1273` | `_fetch_github_latest`       | api.github.com releases (via `_github_api_base`) | 7                             | `--max-time 10` | yes          |
| `lib/workflows.sh:1378` | `_check_cv_oh_my_zsh`        | `ohmyzsh/ohmyzsh/releases/latest`                | 1                             | **none**        | **no — 404** |
| `lib/workflows.sh:1399` | `_check_cv_homebrew_install` | `Homebrew/install/commits/master`                | 1                             | **none**        | **no — 422** |
| `lib/workflows.sh:1434` | `_check_one_cargo_version`   | crates.io (`_CRATES_API`)                        | 8 (one per `CARGO_TOOLS` pin) | **none**        | yes          |

### The two GitHub checks never worked

Measured 2026-10-07 from `claude`, unauthenticated, as the functions call them:

```
ohmyzsh/ohmyzsh/releases/latest    404  {"message": "Not Found"}
ohmyzsh/ohmyzsh/tags?per_page=3    []
Homebrew/install/commits/master    422  {"message": "No commit found for SHA: master"}
Homebrew/install                   default_branch: "main"
Homebrew/install/commits/HEAD      200  sha 8ab1549dfa1189fd4d818a2116592d8f0ee06d8c
```

- **oh-my-zsh** has no releases and no tags. `OH_MY_ZSH_VER` is `"master"`, a branch name
  consumed by `git clone --branch` (`lib/helpers.sh:1317`); `lib/constants.sh` itself says
  "no tagged releases; master is the distribution branch". There is no version to compare,
  so `_check_cv_oh_my_zsh` WARNs on every run and no endpoint fix can make it meaningful.
- **homebrew-install**: Homebrew/install's default branch is `main`, so `/commits/master`
  returns 422 and the check WARNs on every run. `HOMEBREW_INSTALL_SHA` pins the installer
  script `lib/macos.sh:82` downloads and runs, so drift on a security-relevant pin is
  currently never reported. The pin (`5e78e698…`) is behind `HEAD` (`8ab1549d…`).

Population: one unauthenticated request per endpoint from one machine. The claims drawn are
about GitHub's responses for these repos, which do not vary by client.

### The unbounded calls hang on a stalled connection

curl has no default total timeout. Measured 2026-10-07 on `claude` (curl 8.22.0) against a
loopback listener that accepts the TCP connection and never replies:

```
curl -fsSL <url>                 rc=124 elapsed=12s   (killed by an outer `timeout 12`)
curl -fsSL --max-time 3 <url>    rc=28  elapsed=3s
```

### Is 10 s enough for crates.io

Measured 2026-10-07 on `claude`, all 8 `CARGO_TOOLS` crates:

| crate               | body   | normal link | `--limit-rate 20k` |
| ------------------- | ------ | ----------- | ------------------ |
| cargo-audit         | 94 KB  | 0.34 s      | 4.7 s              |
| cargo-deny          | 213 KB | 0.25 s      | 10.4 s             |
| cargo-insta         | 171 KB | 0.23 s      | 8.4 s              |
| cargo-machete       | 26 KB  | 0.18 s      | 0.17 s             |
| cargo-mutants       | 113 KB | 0.23 s      | 5.7 s              |
| cargo-semver-checks | 148 KB | 0.23 s      | 7.3 s              |
| cargo-tarpaulin     | 232 KB | 0.19 s      | 11.3 s             |
| cargo-zigbuild      | 193 KB | 0.24 s      | 9.4 s              |

On a normal link the bound has 30x headroom. On a ~160 kbit/s link two crates exceed it and
WARN; that is accepted (see Failure path).

## Design

1. **Delete `_check_cv_oh_my_zsh`** and its call in `run_check_versions`. Rewrite the
   `OH_MY_ZSH_VER` comment in `lib/constants.sh` so it no longer names a check-versions
   consumer or update command. `OH_MY_ZSH_VER` itself stays: `git clone --branch` still reads it.
2. **Fix `_check_cv_homebrew_install`'s endpoint** to `Homebrew/install/commits/HEAD`.
   `HEAD` resolves to the default branch, so a future rename cannot break it again. The
   `grep '"sha"' | head -1` parse is unchanged: the commit's own `sha` is the first key.
3. **Add `--max-time 10`** to `_check_cv_homebrew_install`'s and `_check_one_cargo_version`'s
   curl, matching `_fetch_github_latest`'s value and spelling.

No new constant, helper or seam. `HOMEBREW_INSTALL_SHA` is not bumped: the first fixed run
reports it OUTDATED, and bumping it means reviewing the installer-script diff, a separate
decision.

Worst case on a fully stalled network: 7 + 1 + 8 calls at 10 s each, at most 160 s.

### Failure path

Unchanged branches. On timeout curl exits 28.

- If no body byte arrived, stdout is empty and the existing fetch WARN fires
  (`could not fetch latest SHA` / `could not fetch latest version`).
- If the timeout hits mid-body, curl has already written a partial body. For homebrew the
  `grep '"sha"'` either finds the commit sha (first key, early in the body) or nothing and
  takes the fetch WARN. For cargo, `_json` is non-empty and the function prints its
  **parse**-failure WARN instead of the fetch WARN. That misattributes a network fault to
  parsing on a very slow link. Accepted: the run still continues and still WARNs, and the
  existing `2>/dev/null` already hides curl's error text for every check.

The DNS stage is covered only where curl is built with `AsynchDNS`: confirmed on `claude`
and the Studio, unchecked on `workstation` and CI.

### Testing

- **homebrew-install, endpoint + bound:** one case running `_check_cv_homebrew_install`
  against `tests/mocks/curl` (no `curl()` override) that asserts a single
  `MOCK_CALLS_FILE` line carries both `Homebrew/install/commits/HEAD` and `--max-time 10`
  (`grep -- '--max-time 10' | grep -q 'commits/HEAD'`), so the flag is tied to that call and
  the case fails if the function stops calling curl. RED before both edits.
- **cargo, bound:** one case in `tests/setup_env/check_versions_cargo.bats`, whose `setup()`
  points `_CRATES_API` at a sentinel host, asserting a single line carries both the sentinel
  crate URL and `--max-time 10`.
- **oh-my-zsh removal:** delete `_check_cv_oh_my_zsh`'s own tests and its stubs; the
  ordering/call-count test (`workflows.bats` ~`:3066-3080`) asserts `_check_cv_oh_my_zsh` is
  **not** called. The WARN-count comment at ~`:3104` and any count it guards are updated to
  the new total, re-derived from the code.
- Existing tests that override `curl()` as a function ignore argv and are unaffected.

A real-curl silent-listener test is not added: the timeout behaviour is curl's and is
measured above, and each case would cost the full 10 s bound in suite time.

### Docs

`CLAUDE.md` `check-versions` bullet: drop `_check_cv_oh_my_zsh` from the list of checks that
still run without the token.

### Out of scope

- The four cheat.sh curls in `-t update` (`lib/workflows.sh:435`, `:445`, `:1156`, `:1166`).
  Backlog row already committed with the first version of this spec.
- Authenticating the homebrew call through `_github_api_base` / `_github_auth_header`.
- Bumping `HOMEBREW_INSTALL_SHA`.

## Requirements

- **R1.** `[PR1]` `_check_cv_oh_my_zsh` no longer exists in `lib/workflows.sh`, and `run_check_versions` does not call it.
- **R2.** `[PR1]` `OH_MY_ZSH_VER` remains in `lib/constants.sh`, and its comment names no check-versions consumer.
- **R3.** `[PR1]` `_check_cv_homebrew_install`'s curl requests `https://api.github.com/repos/Homebrew/install/commits/HEAD` with `--max-time 10`.
- **R4.** `[PR1]` `_check_one_cargo_version`'s curl passes `--max-time 10`.
- **R5.** `[PR1]` A `workflows.bats` case asserts one curl call line carrying both `commits/HEAD` and `--max-time 10`.
- **R6.** `[PR1]` A `check_versions_cargo.bats` case asserts one curl call line carrying both the `_CRATES_API` crate URL and `--max-time 10`.
- **R7.** `[PR1]` A test asserts `run_check_versions` does not call `_check_cv_oh_my_zsh`.
- **R8.** `[PR1]` `CLAUDE.md`'s `check-versions` bullet does not name `_check_cv_oh_my_zsh`.
- **R9.** `[PR1]` The backlog row for this bug is removed from `docs/superpowers/README.md`.
- **V1.** R5 and R6 each fail with their `--max-time 10` removed; R5 also fails with the endpoint reverted to `commits/master`.
- **V2.** `make test` exits 0 on the branch.
- **V3.** A real `./setup_env.sh -t check-versions` on `claude` prints homebrew-install as OK or OUTDATED, not WARN, and prints no oh-my-zsh line.
- **N1.** No change to the output line, counter or exit code of any check other than oh-my-zsh and homebrew-install.
- **N2.** No new constant, helper function, or environment-variable seam.
- **N3.** No change to the cheat.sh curls, to how the homebrew call authenticates, or to `HOMEBREW_INSTALL_SHA`'s value.

## Multi-Lens Review

Reviewed at commit: `144a7ea7` (round 1, original timeouts-only spec)

### Goal-Fit

Finding: Worth building. Timeout claim narrowed needed: a mid-body timeout leaves a partial body, so cargo hits its parse WARN, not the fetch WARN. No requirement covered the cheat.sh backlog row (already committed in `144a7ea7`).
Assumption: 10 s is enough for these endpoints on a working network. Measured by the orchestrator: crates.io 0.17–0.34 s normal, 2 of 8 over 10 s at 20 KB/s. Checking it also found both GitHub endpoints return 404/422, which caused the rescope to the current body.
Disposition: Addressed — operator chose "Fix both + bound" (2026-10-07); spec rewritten.

### Ergonomics

Finding: Same partial-body misattribution for cargo. Endpoint and `--max-time 10` should be matched on one line, not two greps.
Assumption: every newly bounded response finishes within 10 s on a slow but working link. Measured: refuted at 20 KB/s for cargo-deny (10.4 s) and cargo-tarpaulin (11.3 s).
Disposition:

### Risk

Finding: Minor. Put the cargo case in `check_versions_cargo.bats` (has the `_CRATES_API` sentinel); tie endpoint and flag to one grep. Confirmed the three sites are the complete unbounded set on the check-versions path.
Assumption: `--max-time` bounds DNS only where curl has `AsynchDNS`; confirmed on `claude` and the Studio, unchecked on `workstation` and CI.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
