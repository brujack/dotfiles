# Retrospective — 2026-06 (dotfiles)

**Period:** 2026-05-17 to 2026-06-01
**Repo(s):** dotfiles
**PRs merged:** 31 (PRs #85–#115)

---

## PRs Merged This Period

| # | Date | Title |
|---|---------|-------|
| #85 | 2026-05-19 | feat(windows): AI-native dev environment setup |
| #86 | 2026-05-19 | fix(powershell): fix choco prefix-match bug; clean early-learning patterns |
| #87 | 2026-05-19 | ci: remove bash-coverage from auto-merge gate |
| #88 | 2026-05-19 | ci: add bash and PowerShell coverage badges |
| #89 | 2026-05-22 | refactor(linux): remove RHEL, CentOS, and Fedora support |
| #90 | 2026-05-22 | refactor(linux): drop Ubuntu 18.04/20.04/22.04 support |
| #91 | 2026-05-23 | feat(changelog): add git-cliff config and make target |
| #92 | 2026-05-25 | fix(brewfile): tag mas as HAS_PRINTING to suppress Linux brew-drift false positive |
| #93 | 2026-05-27 | fix(whats-new-anthropic): truncate current content before diff to match 20KB state window |
| #94 | 2026-05-27 | test(coverage): add brewfile helper function tests |
| #95 | 2026-05-28 | test(coverage): add run_update optional-tools installed-path tests |
| #96 | 2026-05-28 | test(coverage): add run_update claude/npm/pip section tests |
| #97 | 2026-05-28 | test(coverage): add install_terraform_skill tests |
| #98 | 2026-05-28 | test(coverage): add setup_env.sh prereq bypass tests for -t doctor and -t check-versions |
| #99 | 2026-05-28 | refactor: remove powerlevel10k support |
| #100 | 2026-05-28 | test(setup_env): cover preamble bash-version and brew error paths |
| #101 | 2026-05-28 | test(developer): cover update_rust branches and clone_personal_repos |
| #102 | 2026-05-28 | test(helpers): cover setup_dotfile_symlinks and credential dirs |
| #103 | 2026-05-28 | test(workflows): cover run_update single-flag isolation |
| #104 | 2026-05-28 | test(workflows): cover setup_claude_plugins branches and run_setup_user chain |
| #105 | 2026-05-29 | test(update_summary): cover npm, tpm/tfenv/zsh-autosuggestions, default case |
| #106 | 2026-05-29 | test(workflows): coverage for _check_one_version and run_check_versions |
| #107 | 2026-05-30 | test(coverage): raise update_summary.sh coverage from 82% to 97% |
| #108 | 2026-05-30 | test(coverage): raise helpers.sh coverage from 83% to ≥90% |
| #109 | 2026-05-30 | test: per-file coverage gaps — helpers.sh and workflows.sh |
| #110 | 2026-05-31 | test(macos): cover xcodebuild-fail, no-brew error paths |
| #111 | 2026-05-31 | fix(macos.bats): export -f install_homebrew stub for subshell visibility |
| #112 | 2026-05-31 | test(helpers): cover doctor/process_args error paths |
| #113 | 2026-05-31 | test(helpers): cover OMZ-installed and Cursor-not-installed paths |
| #114 | 2026-05-31 | test(workflows): cover run_update pip block |
| #115 | 2026-05-31 | test(workflows): cover _check_one_version and _run_cv_check arg behavior, 720 tests |

---

## Recurring Patterns and Gotchas

**`readonly` variable crash on re-source.** `zshrc.d` modules set `readonly` vars that blow up
when the shell re-sources the file. Fixed by guarding with `[[ -v VAR ]]` before declaring.
Gotcha worth watching in any zsh module that pins a constant.

**`export -f` required for BATS subshell stubs.** When a test calls a function that spawns a
subprocess (e.g. `install_homebrew` inside `install_macos_packages`), any stub defined in the
test's setup must be exported with `export -f stubname` or the subprocess sees the real binary.
PR #111 fixed a whole test file that was silently not exercising the stub. Added to conventions.

**Prereq bypass tests can't assert `status -eq 0`.** Tests for `-t doctor`/`-t check-versions`
that bypass the brew-check guard (`--brew-install` terminates at `exit 0`) must assert absence
of the error string rather than a clean exit code. The exit code of these entry points varies
with mock environment; asserting it causes flaky failures in CI. Documented in CLAUDE.md.

**`_DOCTOR_FAIL` vs `_DOCTOR_FAILED` confusion.** `_DOCTOR_FAIL` is a counter incremented by
`doctor_fail`; `_DOCTOR_FAILED` is a 0/1 flag. Using `-ge N` on `_DOCTOR_FAILED` always fails
for N > 1. Documented in CLAUDE.md doctor test conventions section.

**`log_warn` does not increment `_DOCTOR_WARN`.** Only `doctor_warn` does. Tests that exercise
a branch using `log_warn` must not assert `_DOCTOR_WARN > 0`. Documented alongside the above.

**Coverage ceilings exist and must be respected.** Some lines (the direct-execution dispatch
block, multi-line array literals, heredoc body lines, `funcname() {` declarations) are
structurally untraceable by the PS4 xtrace approach. Chasing 100% on these files is
counterproductive; per-file ceilings are now documented in CLAUDE.md to avoid wasted effort.

**`whats-new-anthropic` 20KB state window.** The script was appending to the state file instead
of truncating before diff, causing the state to grow past the 20KB context limit. Fixed by
truncating before writing (#93).

---

## Test Health

| Metric | Period Start (≈2026-05-17) | Period End (2026-06-01) |
|--------|--------------------------|------------------------|
| BATS test count | ~614 | 720 (+106) |
| Overall bash coverage | ~85% | 90% |
| `update_summary.sh` coverage | 82% | 97% |
| `helpers.sh` coverage | 83% | ≥90% |
| `workflows.sh` coverage | ~85% | ≥90% (estimated) |
| PowerShell coverage | 95.54% | 95.54% (unchanged) |

**No flaky tests observed** this period. The primary risk of false stability is the
`export -f` pattern — tests that don't export stubs pass trivially while the real binary runs
silently. Mitigation: explicitly verify stubs are called via `MOCK_CALLS_FILE` assertions.

---

## What Went Well

- **Coverage sprint landed.** Went from 85% to 90% bash coverage in two weeks, hitting the
  target floor. The spec/plan/PR pipeline (superpowers docs → focused PRs) worked well for
  keeping coverage work organized.

- **CLAUDE.md kept pace with discoveries.** Every new gotcha (doctor conventions, `export -f`,
  prereq bypass assertion pattern, coverage ceilings, `load_setup_env` OS side effect) was
  documented the same day it was found. The file is genuinely useful to consult.

- **Structural cleanup shipped without drama.** Removing RHEL/CentOS/Fedora (#89), old Ubuntu
  LTS (#90), and powerlevel10k (#99) trimmed significant dead code with no regressions. The
  CI gate caught nothing unexpected.

- **Auto-merge is reliable.** The three-job CI gate (test, lint-macos, secret-scan) + auto-merge
  continues to work well. Moving bash-coverage off the gate (#87) was the right call — it's
  advisory-only and shouldn't block delivery.

- **Weekly digest automation runs on schedule.** `whats-new-claude-code.sh` and
  `whats-new-anthropic.sh` produced digests on 2026-05-29 and 2026-06-01 without intervention.

---

## What to Improve

- **Coverage PRs were too granular.** May 28 had 8 PRs merged in a single day, each covering
  one small function group. This inflates PR numbers and makes the git log noisy. Future coverage
  sprints should batch by module (one PR per lib file, e.g. all of `helpers.sh` gaps in one PR).

- **Revert on zshrc fix signals premature merge.** `685d23f revert(zshrc): restore RUBY_VER...`
  followed `662565c fix(zshrc): fix RUBY_VER...` the same day. The fix wasn't tested on a live
  shell before merge. For zshrc changes, test in an interactive shell (`zsh -i -c 'exit'`) before
  pushing.

- **Bash coverage floor not enforced in CI.** Coverage is still advisory-only because
  the PS4 xtrace measurement is macOS-only. A per-commit regression check (even just tracking
  test count as a proxy) would catch drops early without requiring full coverage infra in CI.

- **No retrospective last period for May 1–17 gap.** The last retro covered through May 17 and
  was written on May 17 itself, but a 15-day gap existed between that date and the April retro's
  cutoff. Consider writing retros on the 1st of each month with a fixed lookback to avoid drift.

---

## Action Items for Next Period

- [ ] Batch future coverage PRs by lib file (one PR per module, not per function group)
- [ ] Add `zsh -i -c 'exit'` smoke-test step to zshrc change workflow (document in CLAUDE.md)
- [ ] Investigate lightweight test-count regression check for CI (fail if BATS count drops)
- [ ] Document `export -f` stub pattern in CLAUDE.md testing section (mock pattern table)
- [ ] Evaluate git-cliff changelog (#91) output quality after a full release cycle
- [ ] Monthly retro target: write on the 1st with lookback to prior month's 1st
