# 2026-10 Retrospective — dotfiles

Period: 2026-10-01 → 2026-10-31
Previous: [2026-09-retrospective.md](./2026-09-retrospective.md)

---

## PRs Merged This Period

| # | Title | Merged |
|---|-------|--------|
| #385 | fix(update): strip GIT_* and require .git in the git-pull sections | Oct 27 |
| #386 | fix(update): report SKIP, not OK, for sections that did nothing | Oct 27 |
| #387 | fix(update): never lose or soften a row in the update summary | Oct 27 |
| #388 | fix(update): warn on unfetchable apt sources and kept-back packages | Oct 28 |
| #389 | fix(update): stop git-repos syncing nothing without a word | Oct 28 |
| #390 | fix(update): stop failed snapshots reading as no changes | Oct 28 |
| #391 | fix(update): print the summary with %s, never %b | Oct 28 |
| #392 | fix(update): cut every tool-sourced detail line to printable ASCII | Oct 28 |
| #393 | fix(update): stop failed apt, snap, claude and npm snapshots reading clean | Oct 28 |
| #394 | fix(update): name what brew and mas left outdated; stop swallowing brew trust | Oct 28 |
| #395 | fix(apt): treat a held package as installed in every apt guard | Oct 29 |
| #396 | fix(release-bin): stage to .new and rename over the target | Oct 29 |
| #397 | fix(fetch): keep every redirect-following download on https | Oct 29 |
| #398 | fix(ruby-install): verify the release tarball before building it as root | Oct 29 |
| #399 | refactor(ruby): stop building ruby-install on Linux | Oct 29 |
| #400 | fix(apt): reinstall a package dpkg marks reinstall-required | Oct 29 |
| #401 | fix(doctor): bound dev-tool probes with the gtimeout fallback | Oct 29 |
| #402 | fix(rust): run rustup and cargo from HOME, not the caller's cwd | Oct 29 |
| #403 | fix(hashicorp): report a failed signer parser instead of no hint | Oct 29 |
| #404 | docs(requirements): correct the sync-requirements-ci.sh header | Oct 29 |
| #405 | fix(vagrant): run provision apt non-interactively | Oct 30 |
| #406 | test(requirements): assert all five renderings pairwise distinct | Oct 30 |
| #407 | fix(tfenv): gate the repo URL seam and end clone options | Oct 30 |
| #408 | fix(pre-commit): triage ggshield scan exit codes | Oct 30 |
| #410 | perf(lint-scope): grep-prefilter the make -C partition scan | Oct 31 |
| #411 | ci(test-macos): shard across three macOS runners | Oct 31 |
| #412 | feat(pre-push): load the shared push-content gate (PR2) | Oct 31 |
| #413 | fix(pre-push): re-sync wiring block from ai-config#345 | Oct 31 |
| #414 | ci(test): shard traced Linux suite as the single Linux gate | Nov 1 |

**29 PRs merged; 50 commits in git history (shallow clone; older fix(update) commits not
locally present).** The single largest work wave was the 10-PR `fix(update)` burst on Oct
27–28 closing the September truthfulness spec.

---

## Patterns and Gotchas

### September carry-forward: update truthfulness closed in a 10-PR burst

The September action item "close the `run_update` truthfulness spec" landed as 10 rapid-fire
PRs (#385–#394) across two days. Each fixed a distinct reporting defect: lost summary rows,
silent no-ops, snapshot reads treating a failed section as clean, `%b` format-string injection
in `printf`, non-ASCII bytes from tool output, and git-pull sections leaking `GIT_DIR`.

The pattern that generated them: an operator ran `-t update` and noticed the summary
contradicted what the tools actually did. A single investigation uncovered a chain of
independent bugs, each requiring its own PR. The correct approach — one bug per PR, each
with its own test — was used and worked. The downside is that 10 PRs in two days is high
context-switching overhead for CI and reviewers.

**Takeaway:** when the update summary is the symptom, audit every section's snapshot logic
before opening the first PR, so all related fixes can land as a coordinated batch without
follow-on "oh, and also…" PRs.

### Security hardening: tarball verification and HTTPS enforcement

`#398` added SHA256 verification of the `ruby-install` release tarball before building as
root. `#397` enforced HTTPS for redirect-following downloads by adding `-L --proto-redir
-all,https` to every `curl` that follows redirects. Both were discovered during the
October robustness sweep rather than from incidents, which is the right trigger.

`#396` (atomic rename for pinned-release binaries: stage to `.new`, then `mv`) prevents a
partial download from corrupting the live binary. All three changes follow the same pattern
as September's `#299`/`#398` Microsoft deb verification: harden the install path before the
incident, not after.

### ggshield exit-code triage (#408, ADR-0052)

The pre-commit hook now distinguishes rc 3 (credential) from rc 4 (unreachable): rc 3 warns
and continues with `SECRET SCAN DID NOT RUN`; rc 4 blocks. Previously rc 3 also blocked,
causing false-positive failures when ggshield could not reach the server (e.g. airgapped dev
environment). The ADR documents the rationale; the test seam (`GGSHIELD_BIN`) drove all
three branches without touching `PATH`.

The earlier blanket `rc != 0 → block` design had been in place since the hook was introduced.
This is the first protocol-aware exit-code split in a hook in this repo.

### CI sharding: macOS and Linux both sharded by end of month

Two independent sharding efforts landed in the same week:

- **macOS** (#411): three runners, `bats-weights.tsv`-balanced, `scripts/ci-shard-gate.sh`
  enforces exact coverage; `test-macos` aggregation gate on ubuntu-latest fails unless all
  shards are `success` (ADR-0037, ADR-0053).
- **Linux** (#414): three traced legs; `test` aggregation gate on ubuntu-latest with
  `--with-traces` flags; gates at 91% bash coverage on the union trace (ADR-0054).

The Linux shard is the first CI change that makes bash coverage part of the merge gate
rather than a post-merge advisory. The traced design required a `COVERAGE_TRACE_DIR` step
env and a `scripts/ci-shard-gate.sh --with-traces` pairing step.

### Shallow-clone blind spot in retrospective tooling

This retrospective's git log could only reach 50 commits (shallow clone). PRs #385–#403
(merged Oct 27–29) were not visible in `git log` even though they are within the period.
The MCP PR listing was the authoritative source for those PRs.

**Action:** consider `git fetch --unshallow` or a deeper clone depth in the environment
that runs the retrospective task, or rely solely on the GitHub PR API for coverage data
going forward.

---

## Test Health

- **ggshield hook triage (#408):** three exit-code branches now tested; the seam-driven
  design means CI does not need a live ggshield server.
- **Requirements pairwise distinctness (#406):** `tests/setup_env/requirements_ci.bats` now
  asserts all 10 pairs of the five CI requirement files are pairwise distinct. Adds a guard
  against inadvertent harmonisation of the five groups.
- **macOS sharding (#411):** shard coverage check (`scripts/ci-shard-gate.sh`) enforces
  that every test file appears in exactly one shard's list. A missed file now fails the gate
  rather than silently not running.
- **Linux tracing (#414):** bash coverage is now a merge gate, not advisory. The 91% floor
  established in earlier work becomes an enforced CI threshold.
- **No flaky tests reported** this period. The Oct 30 backlog entry records a macOS
  dirty-tree `TERM` timing flake (observed but not yet filed as a PR).
- **Bash coverage gate:** still at 91%; the cd-guard tests (needed to raise to 92%)
  did not land this period — see action items.

---

## September Action Items — Status

| Item | Status |
|------|--------|
| Land the cd-guard plan | **Not started.** Deferred again. Blocks 92% raise. |
| Close `run_update` truthfulness spec | **Done** — 10-PR burst (#385–#394) closed it entirely |
| Enable Renovate `pep621` | **Not done.** Still a gap. |
| Add CI gate exercising `phrase_check.py` against bad fixture | **Not done.** |
| Add CI retry for pinned downloads | **Not done.** |
| Raise bash coverage gate to 92% | **Blocked** — cd-guard tests still unwritten |

---

## What Went Well

- **Update truthfulness (#385–#394):** Ten focused PRs closed a multi-month open item
  in two days. Each PR was clean and self-contained. The `fix(update)` pattern (one named
  defect per PR) made bisecting and rolling back individual fixes trivial.
- **Security sweep (#396–#398):** Atomic renames, HTTPS enforcement, and tarball
  verification all landed from a single investigation. No incident required.
- **CI sharding:** Both platforms sharded in one month, each with an aggregation gate and
  coverage enforcement. This is the most significant CI improvement since the parallel bats
  work in September.
- **Shared push-content gate (#412):** The ai-config ADR-0091 gate is now wired into the
  pre-push hook. The immediate fix (#413) after the wiring shows the sync-from-ai-config
  discipline working as intended.
- **ADR cadence:** ADR-0052 (ggshield exit codes) was written and merged alongside the
  implementation. ADRs landing with their PRs rather than after has been consistent since
  ADR-0037 in September.

---

## What to Improve

1. **cd-guard plan keeps slipping** — third month without landing. It is the blocker for
   raising the coverage gate to 92% and for accurate `run_update` exit codes on partial
   runs. Should be treated as the top-priority item until it's done.
2. **Update burst pattern is a debt signal** — 10 PRs in two days suggests the original
   update summary design had systematic gaps that accumulated. Consider writing an integration
   test that runs a full mocked `-t update` and asserts the summary against the mock outcomes
   after any update-section change.
3. **macOS dirty-tree `TERM` timing flake** — recorded in the backlog but not yet filed.
   Timing-sensitive tests are the hardest to fix later; should be investigated while the
   context is fresh.
4. **Python automation gap** — Renovate `pep621` would automate Python dependency bumps.
   Vulnerability alerts are on but nothing proposes fixes. Three months unresolved.
5. **Retrospective tooling needs a deeper clone** — the shallow clone (50 commits) missed
   27 commits from the period. The PR API bridged the gap but a deeper clone would allow
   per-file change analysis to be accurate.

---

## Action Items for November

| Priority | Item |
|----------|------|
| High | Land the cd-guard plan (blocks 92% coverage raise and `-t update` exit contract) |
| High | File and fix the macOS dirty-tree `TERM` timing flake (context still fresh) |
| Medium | Add integration test for `-t update` summary truthfulness (prevents update-burst recurrence) |
| Medium | Enable Renovate `pep621` for Python dependency automation |
| Low | Add CI retry for pinned downloads (shellcheck, uv) |
| Low | Raise bash coverage gate to 92% once cd-guard tests land |
| Low | Increase clone depth for retrospective environment (or use PR API exclusively) |
