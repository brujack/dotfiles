# 2026-09 Retrospective — dotfiles

Period: 2026-09-01 → 2026-09-30
Previous: [2026-08-retrospective.md](./2026-08-retrospective.md)

---

## PRs Merged This Period

| # | Title |
|---|-------|
| #290 | feat(workflows): provision Claude plugins from ai-config settings.json |
| #291 | feat(test): run bats in parallel under a validated JOBS knob |
| #292 | revert: take ungated phrase_check off master |
| #293 | feat(claude-md): four-class re-sort with a manifest checker |
| #294 | docs(claude-md): relocate narratives to ai-config knowledge |
| #295 | fix(rust): update the toolchain on macOS too |
| #296 | fix(update): abort the run on Ctrl-C and SIGTERM |
| #297 | fix(deps): bump platformdirs to 4.12.2 |
| #298 | fix(setup): one failed Ubuntu step no longer aborts -t developer |
| #299 | fix(security): verify packages-microsoft-prod.deb before dpkg-i |
| #300 | test(verify-deb): cover extraction and key-import failure branches |
| #301 | fix(ci): hold a uv.lock change without pyproject.toml from auto-merge |
| #302 | fix(deps): bump urllib3 to 2.8.0 |
| #303 | fix(deps): bump gitpython, tornado and virtualenv |

**14 PRs merged; 50 commits total.** The commit count is inflated by the multi-stage CLAUDE.md four-class-resort spec work (12 intermediate spec commits).

---

## Patterns and Gotchas

### Recurring: signal handling gaps surfaced late
`#296` (SIGINT/SIGTERM abort in `run_update`) landed after two related entries already sat
in the backlog. The pattern is consistent: signal handling only becomes visible when someone
hits Ctrl-C during a long sudo or snap call. Worth keeping a mental note that any new section
wrapping a slow, signal-catching tool (brew, pip, snap) needs explicit SIGINT handling.

### Revert-and-reland cycle (#292 → #293)
`phrase_check.py` landed ungated (#292 reverted it) then re-landed gated behind `make test`
(#293). The issue was that the checker ran unconditionally in a pre-commit hook context
before any test seam was wired. The fix required a full 13-task plan and a manifest
(`docs/superpowers/plans/phrases.md`). This revert-reland pattern has appeared twice now
(the other was the CLAUDE.md blanket shellcheck suppressions); both times the root cause was
a missing test seam that was not caught by CI.

### Security verification in the packaging path
`#299` added signature verification for `packages-microsoft-prod.deb` before `sudo dpkg -i`.
The key finding during design: Microsoft rewrites that file in place on each release, so a
SHA256 pin cannot work — only a debsig/GPG verification against the vendored key does. The
corresponding test (`#300`) required a real signed fixture and GNU `ar`, which is absent on
macOS, forcing a skip-on-macOS path.

### Auto-merge gate tightened for lockfile-only changes
`#301` added a gate that holds any PR where `uv.lock` changed without `pyproject.toml`
changing too. Background: Renovate can produce lockfile-only PRs from transitive bumps that
should still be human-reviewed.

### `_install_ubuntu_brew_packages` tri-state now documented in CLAUDE.md
Several Ubuntu provisioning fixes (#273, #274, #280, #298 in aggregate) finally landed as
a stable documented tri-state: 0 clean, 1 hard, 2 partial. The docstring in CLAUDE.md was
updated to match.

---

## Test Health

- **Test count:** >840 (CI gate holds at 840; count grew with #300's deb-verification tests
  and #291's parallel harness work)
- **Parallel bats runs (#291):** JOBS now validated (must be numeric, 1–999); `HAVE_PARALLEL=`
  forces serial anywhere; `make test JOBS=6` overrides. Shaved measurable wall-clock off
  CI runs on the 24-vCPU runner.
- **One revert in the period (#292):** phrase_check ran ungated, causing pre-commit
  failures on machines where `docs/superpowers/plans/` didn't have a valid `phrases.md`.
  Landed correctly behind its test seam in #293.
- **Bash coverage:** still gated at 91%; no coverage regressions noted in CI for merged PRs.
  Raising the gate to 92% (August action item) deferred — still waiting on the cd-guard
  tests landing.
- **Flaky tests:** none reported this period. The cadence-notify isolation fix (#255, landed
  late August) held through September.

---

## August Action Items — Status

| Item | Status |
|------|--------|
| Implement `-t update` cd-guard spec (7 tasks) | **Not started.** Plan exists. Deferred. |
| Update-run truthfulness exit contract | **Partially done** — #296 closes the signal gap; broader truthfulness spec still open |
| Enable Renovate `pep621` | **Not done.** Still a gap. |
| Add CI retry for pinned downloads | **Not done.** |
| Investigate raising coverage gate to 92% | **Deferred** — waiting on cd-guard tests |
| Consolidate `_OVERRIDE_RUN_TMPDIR_ROOT` in seams table | **Done** — CLAUDE.md updated |

---

## What Went Well

- **Claude plugin provisioning (#290)** landed cleanly and integrated with the `run_update`
  `ai-config` section ordering: the plugin reconcile now reads the `settings.json` the same
  run just pulled. The design spec → plan → implementation cycle took ~3 weeks but the seam
  and test infrastructure were thorough.
- **Parallel bats (#291)** was a straightforward quality-of-life improvement with good test
  coverage of the JOBS validation path itself.
- **Security hardening (#299/#300)** demonstrated the right pattern: measure what you can't
  pin by hash, vendor the trust anchor, cover both branches in tests.
- **CLAUDE.md four-class resort (#293)** was complex (13 tasks, one revert) but the end
  state — four classes with a phrase-manifest checker enforcing anchors — is a sustainable
  improvement over the previous unchecked prose.
- The **ci.yml `timeout-minutes`** additions from August continued to hold; no hanging CI
  jobs reported in September.

---

## What to Improve

1. **cd-guards in `run_update` keep slipping.** The plan exists and was `High` priority in
   August. This item should be treated as a carry-forward blocker for raising the coverage
   gate.
2. **Python update path is still unautomated.** Renovate `pep621` would close this. The
   risk is low today (vulnerability alerts are on) but it's a known steady-state gap.
3. **Spec work is generating a lot of intermediate commits.** The CLAUDE.md resort produced
   12 spec-docs commits before any production code landed. Consider whether the spec review
   loop can be tightened (fewer round-trips, or batch the intermediate commits into one
   before merging to master).
4. **Revert-reland pattern.** Two occurrences in three months suggests the pre-commit hook
   test gate isn't catching ungated tools early enough. Worth adding a CI check that runs
   `phrase_check.py` (and equivalent gated tools) against a known-bad input to confirm the
   gate fires before merge.

---

## Action Items for October

| Priority | Item |
|----------|------|
| High | Land the cd-guard plan (`docs/superpowers/plans/2026-08-31-update-run-cd-guards.md`) — blocks 92% coverage raise |
| High | Close the `run_update` truthfulness spec (exit codes, WARN vs FAIL contract) |
| Medium | Enable Renovate `pep621` for Python dependency automation |
| Medium | Add CI gate that exercises `phrase_check.py` against a known-bad fixture |
| Low | Add CI retry for pinned downloads (shellcheck, uv) |
| Low | Raise bash coverage gate to 92% once cd-guard tests land |
