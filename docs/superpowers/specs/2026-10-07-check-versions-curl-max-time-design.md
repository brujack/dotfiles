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
2. **Point `_check_cv_homebrew_install` at the installer's own history:**
   `Homebrew/install/commits?path=install.sh&per_page=1`. The pin guards `install.sh`, not
   the repo, so the reference is the newest commit that touched that file. Over the 90 days
   to 2026-10-07 the repo took 74 commits and 9 touched `install.sh` (latest `09c62fc5…`,
   2026-10-01), so a repo-tip reference would report OUTDATED for unrelated churn about 8
   times in 9. The response is a one-element list whose object starts with `"sha"`, so the
   existing `grep '"sha"' | head -1 | cut -d'"' -f4` parse is unchanged (measured: returns
   `09c62fc5…`). The path query follows the default branch, so a future rename cannot
   break it the way `commits/master` broke.
3. **Make homebrew-install report-only.** On OUTDATED it no longer calls
   `_prompt_version_update`, even under `--update`. Instead the OUTDATED line is followed by
   `https://github.com/Homebrew/install/compare/<pin>...<latest>`, so reviewing the
   installer diff is one click. The pin is executed by `lib/macos.sh:82` and both bootstrap
   scripts, and `_update_version_pin` is a bare `sed` with no diff shown; fixing the check
   would otherwise make a one-keystroke, unreviewed bump of that pin reachable for the first
   time. Bumping stays a manual edit.
4. **Add `--max-time 10`** to `_check_cv_homebrew_install`'s and `_check_one_cargo_version`'s
   curl, matching `_fetch_github_latest`'s value and spelling.

No new constant, helper or seam. `HOMEBREW_INSTALL_SHA` is not bumped: the first fixed run
reports it OUTDATED (pin `5e78e698…`, 2026-06-21; installer last changed `09c62fc5…`), and
bumping it means reviewing the installer diff, a separate decision.

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
  `MOCK_CALLS_FILE` line carries both `commits?path=install.sh` and `--max-time 10`
  (`grep -- '--max-time 10' | grep -qF 'commits?path=install.sh'`), so the flag is tied to
  that call and the case fails if the function stops calling curl.
- **homebrew-install, report-only:** with `UPDATE_VERSIONS=1` and a differing SHA, a
  recorder stub for `_prompt_version_update` is never called, and the output contains
  `https://github.com/Homebrew/install/compare/<pin>...<latest>`. A positive control in the
  same test asserts the OUTDATED line was printed, so the not-called assertion cannot pass
  because the function printed nothing.
- **cargo, bound:** one case in `tests/setup_env/check_versions_cargo.bats`, whose `setup()`
  points `_CRATES_API` at a sentinel host, asserting a single line carries both the sentinel
  crate URL and `--max-time 10`.
- **oh-my-zsh removal:** delete `run_check_versions checks oh-my-zsh tag` (`workflows.bats`
  ~`:1541`) and `_check_cv_oh_my_zsh emits WARN…` (~`:1555`). In the call-recording test
  (~`:3066-3080`) **keep** the `_check_cv_oh_my_zsh` recorder stub and flip its assertion
  from `-eq 1` to `-eq 0`, alongside the existing `-eq 1` for `_check_cv_homebrew_install`
  as the positive control: without the stub a reinstated call fails only with "command not
  found" on stderr and the count stays 0 regardless. The WARN-count literal at ~`:3115`
  goes from 17 to 16. The no-op `_check_cv_oh_my_zsh` stubs in `check_versions_cargo.bats`
  (`:46`, `:67`, `:96`) are removed.
- Existing tests that override `curl()` as a function ignore argv and are unaffected.

A real-curl silent-listener test is not added: the timeout behaviour is curl's and is
measured above, and each case would cost the full 10 s bound in suite time.

### Docs

`CLAUDE.md` `check-versions` bullet: drop `_check_cv_oh_my_zsh` from the list of checks that
still run without the token, and say homebrew-install is report-only under `--update`.

### Out of scope

- The four cheat.sh curls in `-t update` (`lib/workflows.sh:435`, `:445`, `:1156`, `:1166`).
  Backlog row already committed with the first version of this spec.
- Authenticating the homebrew call through `_github_api_base` / `_github_auth_header`. The
  call stays on the unauthenticated 60/h limit; a 403 reads as `could not fetch latest SHA`.
- Bumping `HOMEBREW_INSTALL_SHA`.

## Requirements

- **R1.** `[PR1]` `_check_cv_oh_my_zsh` no longer exists in `lib/workflows.sh`, and `run_check_versions` does not call it.
- **R2.** `[PR1]` `OH_MY_ZSH_VER` remains in `lib/constants.sh`, and its comment names no check-versions consumer.
- **R3.** `[PR1]` `_check_cv_homebrew_install`'s curl requests `https://api.github.com/repos/Homebrew/install/commits?path=install.sh&per_page=1` with `--max-time 10`.
- **R4.** `[PR1]` `_check_one_cargo_version`'s curl passes `--max-time 10`.
- **R5.** `[PR1]` On OUTDATED, `_check_cv_homebrew_install` never calls `_prompt_version_update`, and prints `https://github.com/Homebrew/install/compare/<pin>...<latest>`.
- **R6.** `[PR1]` A `workflows.bats` case asserts one curl call line carrying both `commits?path=install.sh` and `--max-time 10`.
- **R7.** `[PR1]` A `workflows.bats` case with `UPDATE_VERSIONS=1` asserts the OUTDATED line and compare URL are printed and `_prompt_version_update` is not called.
- **R8.** `[PR1]` A `check_versions_cargo.bats` case asserts one curl call line carrying both the `_CRATES_API` crate URL and `--max-time 10`.
- **R9.** `[PR1]` The call-recording test keeps a `_check_cv_oh_my_zsh` recorder stub and asserts it is called 0 times, beside a 1-time assertion for `_check_cv_homebrew_install`.
- **R10.** `[PR1]` `CLAUDE.md`'s `check-versions` bullet does not name `_check_cv_oh_my_zsh` and states homebrew-install is report-only.
- **R11.** `[PR1]` The backlog row for this bug is removed from `docs/superpowers/README.md`.
- **V1.** Each of R6, R7, R8, R9 goes red under its mutation: R6 and R8 with `--max-time 10` removed, R6 also with the endpoint reverted to `commits/master`; R7 with the `_prompt_version_update` call restored; R9 with the `_check_cv_oh_my_zsh` call restored in `run_check_versions`.
- **V2.** `make test` exits 0 on the branch.
- **V3.** A real `./setup_env.sh -t check-versions` on `claude`, with GitHub rate-limit headroom, prints homebrew-install as OK or OUTDATED with a compare URL, not WARN, and prints no oh-my-zsh line.
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
Disposition: Addressed — operator, 2026-10-07: failure-path claim narrowed; slow-link WARN accepted.

### Risk

Finding: Minor. Put the cargo case in `check_versions_cargo.bats` (has the `_CRATES_API` sentinel); tie endpoint and flag to one grep. Confirmed the three sites are the complete unbounded set on the check-versions path.
Assumption: `--max-time` bounds DNS only where curl has `AsynchDNS`; confirmed on `claude` and the Studio, unchecked on `workstation` and CI.
Disposition: Addressed — operator, 2026-10-07: cargo case moved, one-grep form adopted; AsynchDNS gap accepted as documented.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `91fabd46` (all three lenses; rescoped body)

- **Goal-Fit.** Finding: `commits/HEAD` is the wrong reference; the pin guards `install.sh`, and most repo commits do not touch it, so OUTDATED would be near-permanent. Assumption checked by the orchestrator: 74 commits in 90 days, 9 touching `install.sh`. Disposition: Addressed — operator chose the `install.sh` path reference, 2026-10-07.
- **Ergonomics.** Finding: same reference problem; and fixing the check makes `--update`'s one-keystroke, no-diff bump of an executed installer pin reachable. Assumption: whether the operator bumps promptly; moot under the path reference. Disposition: Addressed — operator chose report-only plus compare URL, 2026-10-07.
- **Risk.** Finding: R7 as written was vacuous once the recorder stub was deleted; exact test edits unstated (`:1541`, `:3079`, `:3115` 17 to 16). Assumption: top-level `sha` precedes nested ones; measured true for both object and list responses, left as the existing parse. Revision made: recorder stub kept with `-eq 0` plus positive control, edits stated, mutation added to V1. Disposition:
