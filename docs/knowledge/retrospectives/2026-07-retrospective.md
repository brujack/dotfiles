# July 2026 Retrospective

**Period:** 2026-07-01 → 2026-07-31
**PRs merged:** 25 (#170–#194)
**Commits:** 50
**Test count:** 848 → 1099 (+251)
**Bash coverage:** 91% (CI-gated at 90%)

---

## PRs Merged

### CI / Coverage
| PR | Title |
|----|-------|
| #170 | ci: raise test count floor from 779 to 840 |

### Features
| PR | Title |
|----|-------|
| #172 | feat: add recreate-ruby entry point to setup_env.sh |
| #176 | feat: auto clone/pull state-ledger on setup/update runs |
| #178 | feat: implement sync-agent-guidance / check-agent-guidance targets |
| #182 | feat: replace rsync-only sync_git_repos.sh with git-native + legacy split |
| #185 | feat: scripts/ world-class pass — -h/--help sweep, modernize, delete dead coverage tool |
| #186 | feat: add -h/--help to run-bash-coverage.sh and .osx.sh |
| #188 | feat: add codex cask to Brewfile |
| #189 | feat(hooks): auto-install git hooks across personal repos |
| #192 | feat(deps): pin npm global packages, add jscpd |
| #194 | feat(git-hooks): detect global/system core.hooksPath pins |

### Bug Fixes
| PR | Title |
|----|-------|
| #171 | fix(ruby): system OpenSSL for gem HTTPS + Linux test hermeticity |
| #173 | fix(ruby): detect silent install failure in recreate_ruby |
| #174 | fix: run gem update after ruby recreate |
| #177 | fix: harden ensure_state_ledger against SSH hangs and corrupt clones |
| #179 | fix: brace $0/$1/$2/$3 in sync-agent-guidance.sh |
| #183 | fix: scripts/ cleanup — kill_zombie multi-PID bug, mkill/html2ascii modernize |
| #184 | fix: remove dangling tw alias for deleted tmux-workstation.sh |
| #190 | fix(hooks): strip GIT_DIR from the sweep's make invocation |
| #191 | fix(hooks): strip inherited git repo-location vars before make test |
| #193 | fix(deps): install json2yaml globally, and pin it |

### Tests
| PR | Title |
|----|-------|
| #187 | test: add BATS coverage for git hooks, fix pre-push [ ] and bash-tracer.sh eval |

### Chore / Config
| PR | Title |
|----|-------|
| #175 | chore: switch claude-code cask to claude-code@latest |
| #180 | chore: scope dotfiles enabledPlugins per ADR-0046 |
| #181 | chore: enable AI auto-detection in Warp agent input settings |

---

## Recurring Patterns and Gotchas

### git-hooks work required 6 PRs to settle
The auto-install git hooks feature (#189) spawned four follow-on PRs before the area stabilized: GIT_DIR strip from the sweep's make invocation (#190), full inherited git env strip before make test (#191), BATS coverage (#187), and finally a hooksPath global/system detector (#194). The root cause was that git exports `GIT_DIR` into hooks when a push originates from a worktree, and that env var leaks into subprocess `make test` calls — causing every BATS fixture to silently operate on the parent repo rather than the fixture. This was a non-obvious cross-cutting bug.

Two distinct fix PRs were needed: #190 stripped GIT_DIR only from the sweep's own `make` call, and #191 broadened the strip to cover `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, and `GIT_INDEX_FILE` in the pre-push hook's own test invocation. The spec review for #189 did not surface these interactions; a BATS test that runs under a git worktree would have caught both gaps in CI.

**Takeaway:** When a feature's behavior differs between a bare checkout and a worktree, write a test that explicitly simulates the worktree case before merging.

### Ruby recreate feature uncovered two immediate edge cases
Three consecutive PRs (#172, #173, #174) were needed: the initial feature, detection of silent rbenv install failure (which exits 0 even on failure), and running `gem update` post-recreate. This is the classic pattern where the feature lands, then two implicit requirements surface on first real use. The spec for #172 did not enumerate post-install validation steps.

**Takeaway:** For features that wrap an external tool's lifecycle (install → validate → post-install), enumerate all three stages in the spec before implementation.

### hooksPath detector has a known include-borne blind spot
PR #194 added detection of global/system `core.hooksPath` pins, but the detector uses `git config --<scope> --get` which defaults to `--no-includes`. An `[includeIf]` stanza that sets `core.hooksPath` registers as "unset" while `git rev-parse --git-path hooks` returns the actual redirected path. This is documented in `docs/superpowers/README.md` backlog. The `.gitconfig_linux` and `.gitconfig_mac_gitlab` files both use `[includeIf]`, making this gap live on real machines. Fix direction is `--includes --show-origin`.

**Takeaway:** When writing a git config reader, always verify behavior with `--includes` and test against a config file that uses `[include]`/`[includeIf]`.

### npm global pin version bumping path is not fully solved
The three npm pins added in #192 (`JSCPD_VER`, `FIRECRAWL_CLI_VER`, `EXA_MCP_SERVER_VER`) cannot be checked by `check-versions` because the existing checker targets GitHub Releases. `firecrawl-cli` has no GitHub releases; `exa-mcp-server`'s `--version` flag starts the MCP server instead of printing a version. The bump path for these tools is currently manual with no automation guard.

### June action items: 3 of 5 carried over unaddressed
- **Brewfile dedup lint** — not done, carries forward again
- **Ubuntu upgrade runbook** — not done, carries forward
- **Per-file coverage floors** — not done, carries forward
- **Default pyenv mock in test setup()** — DONE: `load_mocks` now exports `MOCK_PYENV_WHICH_STDOUT` by default per CLAUDE.md
- **Bump CI test count floor** — PARTIALLY DONE: #170 raised to 840, but real count hit 1099 by month end; floor needs another raise

---

## Test Health

| Date | Count | Notes |
|------|-------|-------|
| Jul 1 | 848 | Carried from June |
| Jul 4 | ~850 | Minor additions with ruby work |
| Jul 19 | ~900 | BATS coverage for pre-push / bash-tracer (#187) |
| Jul 28–31 | 1099 | git-hooks sweep tests (#187, #189–#191, #194) |

**+251 tests in July** — the largest single-month test count increase in repo history. The bulk came from the git-hooks BATS test suite added in #187 and the subsequent fix PRs that each added targeted regression tests.

**Coverage gate:** 91% bash coverage (PS4/xtrace method), CI gates at 90%, no regressions detected.

**Mock isolation resolved:** `load_mocks` now exports `MOCK_PYENV_WHICH_STDOUT` by default, so `run_update` tests no longer silently fall through to real `pip install`. This was a June carry-over item and is now fully fixed.

**CI test count floor:** Raised to 840 by #170 in early July, but the floor is already stale — actual count is 1099. The floor should be raised to ~1090 to provide meaningful regression protection.

**Known spec gap:** `pre-push-self-coverage` (the plan to make pre-push cover its own `.sh`/`.zsh` file scope) was "In Progress" at end of July. This carries into August.

---

## What Went Well

- **+251 tests in one month.** The git-hooks sweep drove an unprecented test growth; the repo hit 1099 tests and 91% bash coverage.
- **sync_git_repos.sh fully replaced.** The old rsync-only script was replaced with a git-native + legacy split that handles dirty repos, ahead/behind states, and SSH hangs correctly. A substantial architectural improvement that had been deferred for months.
- **Scripts directory comprehensively cleaned.** PRs #183–#186 swept all scripts/ files for dead code, modernized arg parsing, added `-h/--help`, and deleted the legacy coverage tool. First time this directory had a systematic pass.
- **State-ledger hardened.** #177 added SSH hang protection and corrupt-clone detection on top of June's integration. The ledger is now production-stable.
- **Spec-driven development maintained.** 10 specs were written before implementation across July's major features (7 `docs/superpowers/specs/` files created in July). The multi-lens review format caught the GIT_DIR scope issue before the hooksPath detector landed.
- **MOCK_PYENV_WHICH_STDOUT footgun eliminated.** A chronic source of slow/unreliable tests is now automatically handled by `load_mocks`.
- **sync-agent-guidance / check-agent-guidance** added — agent guidance drift is now detectable in CI with `make check-agent-guidance`.

---

## What to Improve

1. **CI test count floor is stale.** Floor is 840 but real count is 1099. Every new test added since July could be deleted without tripping CI. Raise the floor to 1090.

2. **Worktree behavior not tested in BATS.** The GIT_DIR leak (#190, #191) was not caught until post-merge because no BATS test simulates running hooks from a git worktree. A harness-level fixture for the worktree case would have caught both gaps before the feature PR landed.

3. **Brewfile dedup lint still missing.** Carries from June. Third time on this retro list — if it's not done in August it should be explicitly deprioritized.

4. **Ubuntu upgrade runbook still missing.** Carries from June. Low urgency now that 26.04 is stable, but the June wave of 15 fix PRs is still a warning.

5. **Per-file bash coverage floors not enforced.** Carries from June. The overall 90% gate masks regressions in individual files.

6. **hooksPath include-borne blind spot is a live bug.** The detector (#194) is already deployed and incorrect on machines using `[includeIf]`. This should be fixed before the next machine setup rather than left as a backlog note.

7. **npm pin version checker path incomplete.** Three npm globals (#192) have no automated version drift detection. A simple `npm outdated -g` check or npm-registry query mode for `check-versions` would cover these.

---

## Action Items for Next Period

- [ ] **Raise CI test count floor** — bump the `≥ 840` assertion in `.github/workflows/ci.yml` to `≥ 1090`
- [ ] **Fix hooksPath include-borne blind spot** — update `_git_hooks_hookspath_offenders` to use `--includes --show-origin`; add test with an `[includeIf]` fixture
- [ ] **Brewfile dedup lint** — add `scripts/check-brewfile-dedup.sh` and wire into `make lint` (third carry-over; escalate or close)
- [ ] **Worktree BATS fixture** — add a helper in `tests/helpers/` that sets up a git worktree environment so hook behavior under worktrees is covered
- [ ] **npm version bump path** — extend `check-versions` or add a separate `npm outdated -g` check for the three pinned npm globals
- [ ] **Complete pre-push-self-coverage** — the in-progress plan from July 31 (`.zsh` scope widening for pre-push)
- [ ] **Per-file coverage floors** — extend `scripts/run-bash-coverage.sh` to emit per-file percentages with optional floor checks (third carry-over)
