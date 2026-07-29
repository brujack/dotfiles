# Detect a pinned `core.hooksPath` at global/system scope; strip `GIT_DIR` from the hooks sweep

Date: 2026-07-29
Repo: dotfiles
Status: Spec

> This spec was scoped down substantially by two rounds of Multi-Lens Review (recorded at
> the bottom). The original proposal — a per-repo `core.hooksPath` scan across all 17 git
> repos under `PERSONAL_GITREPOS`, plus a `Makefile` rewrite — is **not** what this builds.
> Both were dropped for reasons the review established and the fleet evidence confirmed.
> The narrative below is the surviving design; the review section records what was cut and
> why, because two of the cuts turn on facts that were true when first written.

## Problem

On 2026-07-29 the git-hooks sweep's first real run (PR #189) found four repos —
`ai-config`, `dotfiles`, `etch-cli`, `math` — carrying an absolute macOS `core.hooksPath`
in their per-clone `.git/config`. On the Mac the path resolved and hooks ran. On the Linux
workstation that path cannot exist, so **git ran no hooks at all** there: no ggshield
secret scan, no Conventional Commits check, no `_dod_gate`, no SDLC branch guard —
silently, on every commit and push, for months.

Nothing surfaced it at the time. `setup_env.sh -t update` succeeded, CI was green, the
hook files were present and executable, and `make install-hooks` reported success in every
repo. Each of those answers a different question than the one that matters: *does git
actually find a hook here.*

### What is already covered, and what is not

PR #189 changed this. Its sweep resolves each repo's hooks directory through `rev-parse
--git-path hooks`, which honours `core.hooksPath`, so:

| Case | Covered today? |
| ---- | -------------- |
| Pin does not resolve | **Yes** — `_git_hooks_dir` returns 1, `_git_hooks_check_complete` returns 2, sweep emits `"<repo>: no hooks directory (install-hooks cannot fix this)"` (`lib/git_hooks.sh:361`) |
| Pin resolves, but mandated hooks are not there | **Yes** — `check_complete` reads *through* `--git-path hooks`, returns 1, reports the missing hooks by name |
| Mandated repo has no `install-hooks:` target | **Yes** — `_git_hooks_gap_repos` walks `HOOK_EXPECTED_REPOS` directly and emits a `:no-target` gap |
| Pin resolves and the mandated hooks are present | Not detected — and, per the propagation analysis below, has no failure mode |
| Pin at `--global` or `--system` scope | **No — nothing in this repo reads either scope** |

That table is why this spec is small. The per-repo case that started it is already
detected in every shape that can actually hurt.

### Why the per-repo scan was dropped

A per-repo pin that resolves, with the mandated hooks present, means hooks run correctly
on that machine. It is only dangerous if it can travel to a machine where it cannot
resolve. Every route was checked:

- **`sync_git_repos.sh` git-native mode** — `fetch`/`pull`/`push`. Git never transfers
  `.git/config`; it is per-clone by construction. Safe by design, not by configuration.
- **`legacy_rsync.sh:17,19`** — the workstation and laptop-1 pushes. Both carry
  `--exclude=personal` since PR #182. Closed.
- **`legacy_rsync.sh:21`** — the ratna push, which has no `--exclude` and does mirror
  `personal/*/.git/config`. Confirmed with the owner: ratna is an **archive-only** target,
  an older Intel Mac no longer used for development, never restored *into* a working
  checkout. Full-tree mirroring there is the intent, not an oversight — this line is
  correct as written and is deliberately not changed.

With no route back to a machine where a pin breaks, the residual per-repo case guards a
state with no failure mode. Scanning 17 repos for it — with a worktree guard, a `GIT_DIR`
strip, and a stderr-silence case — was ~80% of the original design's cost for that.

### Why global/system scope is worth reading

Unlike the per-repo case, a `--global` or `--system` pin needs no propagation: it disables
or redirects hooks in **every repo on that box**, immediately. Two shapes matter, and
#189 handles neither well:

1. **Global pin that does not resolve** — #189 reports all nine mandated repos as `"no
   hooks directory"`. Nine symptom lines, no cause, and the remedy each one implies
   (`make install-hooks`) cannot fix it. Reading the scope names the cause once, with the
   remedy that works.
2. **Global pin that resolves** — this is the dangerous one and #189 reports it green. The
   sweep runs `install-hooks` across nine mandated repos, each `ln -sf`-ing `pre-commit`,
   `pre-push`, and `commit-msg` into the same resolved directory. Each repo overwrites the
   previous; the last repo swept wins; every repo then runs one repo's hooks; and all nine
   pass `check_complete` because the files exist and are executable. The digest flips every
   run, producing permanent "updated" churn with no explanation.

## Decisions

| # | Decision | Rationale |
| - | -------- | --------- |
| 1 | Read `--global` and `--system` scope only. No per-repo scan. | Per the propagation analysis above: the per-repo residual has no failure mode, and every shape that does is already caught by #189. Global/system is the only scope nothing reads, and the only one whose blast radius is immediate rather than propagated. |
| 2 | Read each scope explicitly (`--global`, `--system`), never bare `--get`. | Bare `--get` returns the *effective* value after system→global→local precedence, so it cannot tell you which scope to unset. Scoped reads attach the correct `git config --global --unset` / `--system --unset` remedy. |
| 3 | A pin at either scope is a **failure**, not a warning. | The blast radius is every repo on the box, and the resolving case reads green everywhere else. There is no legitimate use: the fleet has no machine that wants hooks somewhere other than where `install-hooks` puts them. With the per-repo scan gone, the unmandated-repo/husky case that motivated a warn tier no longer arises, so no allowlist or suppression path is introduced. |
| 4 | Reported from **both** the `-t update` sweep and `-t doctor`. | `run_doctor` has exactly one call site — `setup_env.sh:69`, human-invoked; it appears in no `run_update` path and no CI job (`grep -rn run_doctor lib/ setup_env.sh scripts/`; `grep -rn doctor .github/workflows/`). A check reachable only by typing `-t doctor` fires only where someone already went looking, which is the runbook posture `USER.md` rejects for this class of fleet drift. `-t update` is what actually runs on all seven machines. `doctor` is kept as the on-demand surface. |
| 5 | The `git-hooks)` case arm in `_update_record_end` lands in this PR. | Without it the sweep surface is not a signal. `_update_record_end` has no `git-hooks)` arm, so it falls to `*)` → `_result="updated"` and then writes `OK` unconditionally (`lib/update_summary.sh:362-368`); gaps and unknowns are documented as never affecting the sweep's return code. The summary table would print `git-hooks — OK — updated` over its own findings — the same "reports success while git reads elsewhere" shape this change exists to catch. This is the existing backlog item "Surface git-hooks gap counts in the `-t update` summary block"; it stops being separable the moment the sweep becomes a reporting surface. |
| 6 | The sweep's `make install-hooks` invocation gets the `env -u` strip. | `lib/git_hooks.sh:327` runs `run_cmd make -s -C "${_dir}" install-hooks` with no strip. A leaked `GIT_DIR` does not merely redirect within a repo — it sends the target repo's hooks into *another repo's* hooks directory. Live today for `ai-config` and `math`, both of which resolve their hooks dir via `--git-path hooks`. Git exports `GIT_DIR` into the pre-push hook environment when pushing from a worktree, and this repo's pre-push hook runs `make test`. One strip at the invocation covers all nine repos regardless of Makefile shape. |
| 7 | The dotfiles `Makefile` `install-hooks` target is **not** changed. | The proposed change (`--git-path hooks` + `mkdir -p`) is actively harmful, verified against real git: `--git-path hooks` returns the pin verbatim, `mkdir -p` then creates it, `_git_hooks_dir`'s `[[ -d ]]` succeeds, and `check_complete` returns 0 instead of 2 — **deleting the #189 detection this spec's Problem section relies on.** Ordering makes it worse: `make` runs at line 327, `check_complete` at line 351, so the sweep would repair into the anomaly and then evaluate. Under a global pin it is the clobber engine described above. The target's real defects — literal `.git/hooks`, breaks in a worktree — are real but belong in their own change, gated on their own reasoning, not smuggled into a detection PR. |

## Design

### `_git_hooks_hookspath_offenders` (lib/git_hooks.sh)

Contract: prints zero, one, or two tab-separated `scope<TAB>value` lines on stdout, one
per pinned scope; prints nothing when both scopes are unset; returns 0 in every case. An
empty result means "checked, clean" — callers count lines and do not read the exit code as
a verdict.

```bash
git config --system --get core.hooksPath
git config --global --get core.hooksPath
```

No `env -u GIT_DIR …` strip is needed here: neither read takes repo context, so an
inherited `GIT_DIR` cannot redirect them. (The strip is still required at Decision 6's
`make` invocation, which does.)

`git config --get` exits 1 when the key is unset. That is the normal clean path and must
not be treated as an error — the function must not propagate it.

Placement in `lib/git_hooks.sh` rather than `lib/helpers.sh` is because both surfaces call
it and it is hooks-domain knowledge, not because of the `GIT_DIR` idiom argument that
justified placement in the earlier draft — with the per-repo arm gone, that argument no
longer applies.

### Surface 1 — the `-t update` sweep

`install_git_hooks_all_repos` calls the detector once per run. Offender lines reach
`log_warn` and `~/.dotfiles-update.log` alongside the sweep's other findings, and the
count is carried into the summary via Decision 5's case arm.

This is the surface that matters for the fleet: `-t update` runs on all seven machines,
`-t doctor` does not.

### Surface 2 — `_doctor_check_hooks_path` (lib/helpers.sh)

Added to `run_doctor`'s call list after `_doctor_check_cred_dirs`. Prints the section
header, calls the detector once, maps its output onto `doctor_pass` / `doctor_fail`.

```
Git hooksPath:
  [PASS] global: unset
  [PASS] system: unset
```

```
Git hooksPath:
  [FAIL] global: pinned to /Users/bruce/.githooks — remedy: git config --global --unset core.hooksPath
  [PASS] system: unset
```

Two independent lines, so each scope gets its own verdict and its own remedy, and one
failing does not suppress the other's PASS.

### Decision 5 — the `git-hooks)` case arm

`_update_record_end` gains a `git-hooks)` arm mirroring what the structurally analogous
`git-repos` and `legacy-rsync` sections already do for partial success: `_update_warn` plus
`_update_write_detail_from_err` when the sweep reports gaps, unknowns, or a hooksPath
offender with rc 0. The actionable line (`N checked, M updated, K gaps (names)`) reaches
the summary table a weekly reader scans, instead of only the log.

`"git-hooks"` is already present in `_UPDATE_SECTION_ORDER`, so no array edit is needed —
but per the coupling documented in `CLAUDE.md`, that pairing is checked, not assumed.

### Decision 6 — the `env -u` strip

Verified in this repo:

```
$ git rev-parse --git-path hooks
.git/hooks
$ GIT_DIR=/Users/bruce/git-repos/personal/ai-config/.git git rev-parse --git-path hooks
/Users/bruce/git-repos/personal/ai-config/.git/hooks
```

`lib/git_hooks.sh:327` becomes:

```bash
run_cmd env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  make -s -C "${_dir}" install-hooks
```

## Testing

The global and system arms use `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_SYSTEM` pointed at temp
files — real git, no mock, and no possibility of touching the developer's own
`~/.gitconfig`. `tests/setup_env/git_hooks.bats` already builds real repos with `git init
-q` under a `PERSONAL_GITREPOS` override, which covers the sweep and strip cases.

| Category | Case | Assertion |
| -------- | ---- | --------- |
| Happy | neither scope set | no offender lines; two `doctor_pass`; `_DOCTOR_FAILED` stays 0 |
| Boundary | global set, system unset | one offender line, one FAIL, one PASS; remedy names `--global` |
| Boundary | system set, global unset | one offender line, one FAIL, one PASS; remedy names `--system` |
| State | both set | two offender lines, two FAILs, distinct remedies; neither masks the other |
| Error | value points at a nonexistent directory | still FAIL, same as a resolvable value — Decision 3 |
| Error | `git config` exits 1 (key unset) | treated as clean, not propagated as failure |
| Idempotency | detector called twice in one shell | identical output both times |
| State | sweep run with a global pin set | offender count reaches the summary via the `git-hooks)` arm, and the section does **not** render as a bare `[OK] git-hooks updated` — this is the Decision 5 regression test |
| Isolation | `GIT_DIR` exported, sweep runs `make install-hooks` | make is invoked with the var stripped; hooks land in the target repo, not the leaked one |
| State | two repos, `--global` pin resolving to one shared directory | sweep does not let repo B's hooks land as repo A's; the condition is reported rather than silently "completed". This case has no coverage today and is the clobber shape that motivated Decision 7 |

Coverage: `lib/git_hooks.sh`, `lib/helpers.sh`, and `lib/update_summary.sh` are all
already in `scripts/run-bash-coverage.sh`'s `INCLUDE_FILES`, so the new lines are
measured. The 90% CI floor must still hold.

## Fleet evidence

| Machine | local pins | `--global` | `--system` | `/etc/gitconfig` | Date |
| ------- | ---------- | ---------- | ---------- | ---------------- | ---- |
| Mac Studio | none (17 repos) | unset | unset | — | 2026-07-29 |
| laptop | none | unset | unset | absent | 2026-07-29 |
| Linux workstation | none | unset | unset | absent | 2026-07-29 |
| 3× work Mac | not inspected | not inspected | not inspected | not inspected | — |
| Windows/WSL | not inspected | not inspected | not inspected | not inspected | — |

The Linux workstation row is the significant one: it is the machine where the missing
hooks actually bit, and it was rsync'd from the Studio before #182 closed that vector. It
is clean and has stayed clean — the strongest available evidence that no live writer is
still setting `core.hooksPath`. The three work Macs remain the only plausible home for an
MDM-managed `--system` pin, which is precisely the case Decision 1 keeps.

Note on provenance, unresolved: `ai-config` ADR-0055:72, written 2026-07-28, asserts the
setting was present in that repo (`git config --show-origin` → `file:.git/config`); the
2026-07-29 scan found zero. It was hand-removed, not never-present, and nothing has
identified what set it on the Mac Studio — which was the rsync *source*, not a
destination. The only `core.hooksPath` write found anywhere in `~/git-repos/personal`,
`~/.claude/plugins`, or state-ledger is `dotfiles/scripts/push-bash-coverage.sh:55`, a
transient `git -c` flag that never persists. The writer, if one exists, is not in the tree
that was searched.

## Out of scope

- **`math/Makefile`** — its `install-hooks` targets `$(git rev-parse --git-path hooks)`
  without a `mkdir -p` guard, so `ln -sf` fails hard when that directory does not exist.
  Own commit, branch + PR in `math`.
- **`ai-config/Makefile:25`** — the comment reads `core.hooksPath IS set locally in this
  repo, so the two agree here by coincidence, not by design`, recording the defect as a
  fact to honour rather than an anomaly to flag. A large part of why this survived, and now
  factually false. Docs-only: direct to master in `ai-config`.
- **The dotfiles `Makefile` `install-hooks` target** — its literal `.git/hooks` path and
  worktree breakage are real defects, deliberately deferred per Decision 7 rather than
  dropped. Any future change must not create the pinned directory, or it deletes the #189
  signal.
- **`--worktree` scope** (`extensions.worktreeConfig`) — not enabled anywhere in this
  fleet. A pin set there would not be seen.

## Related

- Verified lead 4 in `ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md` — evidence and
  original write-up
- PR #189 — the git-hooks sweep whose first real run found this
- PR #182 — closed the rsync delivery vector for the two working machines

## Multi-Lens Review

Two rounds. Round 1 reviewed commit `0a1636a`; every finding dispositioned Addressed,
which per the skill required a re-review, recorded as Round 2 against `b51b25a`. Round 2
produced substantive new findings on all three lenses — including two that reversed
Round 1's own resolutions — so the design was cut down again.

Every finding in both rounds was re-verified in this session with the command shown, not
accepted on the lens's word. Three lenses converging is not treated as confirmation; the
`grep`, the `git rev-parse`, and the temp-repo reproduction are.

### Round 1 — commit `0a1636a`

#### Goal-Fit

Finding: (a) The check is placed where it will not run on the machines it exists for —
`run_doctor` has one call site, `setup_env.sh:69`, human-invoked, absent from `run_update`
and CI. (b) "Nothing else surfaced it" is stale after PR #189, whose sweep already detects
the broken-on-Linux case via `_git_hooks_dir` → `check_complete` rc=2; the genuinely new
coverage is narrower than the Problem section claimed.

Assumption: That nothing in the toolchain *persists* `core.hooksPath`. Genuinely uncertain
— the spec explained the vector for destination machines but never what set it on the Mac
Studio, the rsync *source*; ADR-0055 asserted it present on 2026-07-28 and the scan found
zero on 2026-07-29, so it was hand-removed. Settled by scanning the Linux workstation and
WSL box before committing to FAIL semantics.

Disposition: **Addressed**, then superseded by Round 2. Surface widened to both (Decision
4, still current). The staleness point was folded into the Problem section and ultimately
drove the whole scope-down: Round 2 extended the same analysis to show the per-repo arm's
residual had no failure mode at all. The assumption was checked — laptop and Linux
workstation both clean at every scope, recorded in Fleet evidence.
Re-reviewed at commit: `b51b25a` (Round 2 below)

#### Ergonomics

Finding: (a) Same wrong-surface finding, reached independently, plus its consequence:
Decision 3 rejected `doctor_warn` because "nothing automated would notice" a warning —
but nothing automated noticed the failure either, at that trigger. (b) No escape hatch,
against a scope deliberately widened past the mandate; husky sets `core.hooksPath` as its
normal install, so the first tooling-managed repo under `personal/` would turn `doctor`
permanently red with no suppression path.

Assumption: That someone actually runs `-t doctor` on the six uninspected machines,
unprompted. Not observable from the repo — nothing schedules it.

Disposition: **Addressed**, then superseded by Round 2. The surface change stands. The
escape-hatch finding was first addressed with a mandate-scoped warn tier, then made moot:
dropping the per-repo scan entirely removes the unmandated-repo case that needed
suppressing, so no allowlist exists to maintain.
Re-reviewed at commit: `b51b25a` (Round 2 below)

#### Risk

Finding: (a) The `env -u` strip was applied to the read path and omitted from the write
path — the damaging direction. Verified: a leaked `GIT_DIR` sends this repo's hooks into
*another repo's* hooks directory. Escalation found while verifying: `lib/git_hooks.sh:327`
invokes `make install-hooks` unstripped, so `ai-config` and `math` are exposed today
regardless of this spec. (b) Decision 3's evidence base (nine mandated repos, per-clone)
did not cover the `--system`/`--global` scope it was being used to justify on six
uninspected machines, three employer-managed; and `run_doctor` collapses to a single
boolean, so one unclearable red destroys every other check's exit signal.

Assumption: That no machine carries a `--system`/`--global` pin the user cannot or should
not unset. Genuinely uncertain: six machines uninspected, three employer-managed.

Disposition: **Addressed.** (a) became Decision 6 — the strip moved to the sweep's `make`
invocation, covering all nine repos. (b) the evidence base was extended rather than argued
with: laptop and Linux workstation scanned clean at every scope, neither even has
`/etc/gitconfig`. The three work Macs remain uninspected and are recorded as such.
Re-reviewed at commit: `b51b25a` (Round 2 below)

### Round 2 — commit `b51b25a`

#### Goal-Fit

Finding: (a) The per-repo arm is ~80% of the design's cost for the thinnest slice of its
value, and one of its three justifications is factually wrong — `_git_hooks_gap_repos`
already walks `HOOK_EXPECTED_REPOS` and emits `:no-target` gaps, so "repos with no
`install-hooks:` target, which the sweep never discovers" holds only for *unmandated*
repos, which the warn tier made non-actionable anyway. Unique FAIL-tier coverage was one
case, not three: a mandated repo whose pin resolves. (b) The highest-value change in the
spec was not the stated feature: Decision 6's strip is a live defect fix with a
present-tense trigger, bundled inside a speculative feature's review surface.

Assumption: That a *resolving* pin can still reach a machine where it cannot resolve —
the sole load-bearing assumption under the per-repo arm. Evidence cut both ways:
`legacy_rsync.sh:21`'s ratna push has no `--exclude=personal` and does mirror
`personal/*/.git/config`. Settled by asking whether ratna is archive-only or a restore
source.

Disposition: **Addressed.** The assumption was settled directly by the owner: ratna is
archive-only, an older Intel Mac no longer used for development, never restored into a
working checkout — so `legacy_rsync.sh:21` is intentional full-tree backup, not a second
bug, and is deliberately unchanged. With git-native sync never carrying `.git/config` and
the other two rsync destinations excluded since #182, no propagation route remains. The
per-repo arm was **dropped entirely** (Decision 1), along with the warn tier and allowlist
it required. The `:no-target` correction is reflected in the coverage table. Decision 6
survives as one of the three things this PR does.

#### Ergonomics

Finding: (a) The surface Decision 4 elevated to primary prints green while an offender
exists. `_update_record_end` has no `git-hooks)` arm, so it falls to `*)` →
`_result="updated"` and writes `OK` unconditionally; gaps and unknowns never affect the
sweep's return code. The summary would show `git-hooks — OK — updated` while the finding
sat in a `log_warn` line upstream — the exact "reports success while git reads elsewhere"
shape named as the original root cause, reproduced inside the detector built to catch it.
The spec also contradicted itself in adjacent paragraphs on whether the count reaches the
summary. (b) The warn tier still had no suppression path — `HOOK_EXPECTED_REPOS` gated
fail-vs-warn, not report-vs-silent.

Assumption: That `-t update` cadence on the six uninspected machines is materially better
than `-t doctor` cadence. Nothing in the repo schedules either; `-t update` is hand-typed
too. Plausible on the Studio (entries on 8 distinct dates in 11 days), genuinely uncertain
for the box `USER.md` calls backup-of-last-resort.

Disposition: **Addressed.** (a) The `git-hooks)` case arm is now in scope for this PR
(Decision 5) rather than deferred, with a dedicated regression test asserting the section
does not render as a bare `[OK]`. The self-contradiction is gone — Step 7 should have
caught it and did not. (b) Moot: with the per-repo scan dropped, there is nothing left to
suppress. The cadence assumption is accepted unresolved — both surfaces are hand-typed, so
Decision 4 buys reach on whichever the operator actually runs rather than a guarantee, and
the WSL box's cadence is genuinely unknown.

#### Risk

Finding: (a) The `Makefile` change destroys the detection the spec credits as already
working, and converts the sweep into an amplifier for the anomaly it flags. Verified with a
real temp repo: `--git-path hooks` returns the pin verbatim, `mkdir -p` creates it,
`_git_hooks_dir`'s `[[ -d ]]` then succeeds, and `check_complete` returns 0 instead of 2.
Ordering compounds it — `make` at line 327, `check_complete` at line 351 — so the sweep
repairs into the anomaly, then evaluates. Under a resolving global pin, nine repos `ln -sf`
into one directory, each clobbering the last, all reporting complete. No test covered two
repos resolving to one directory. (b) Cost/benefit inverted: a three-arm detector, two
surfaces, twelve test cases, a `Makefile` rewrite, and a sweep change, against zero
observed offenders on three machines with the vector closed.

Assumption: That any recurrence will point at a directory unique to one repo rather than a
shared or global one — an n=4 evidence base, all per-repo, all pre-#182 residue, all since
hand-deleted, generalized into a design that `mkdir -p`s whatever it finds.

Disposition: **Addressed.** The `Makefile` write-path change was **dropped entirely**
(Decision 7), which removes both the deleted-detection defect and the clobber engine; the
target's real defects are recorded in Out of scope with an explicit constraint on any
future fix. (b) drove the same scope-down as the goal-fit finding. The shared-directory
assumption is now the *motivating* case for what remains rather than a blind spot: the
resolving-global-pin clobber shape is called out in the Problem section and has its own
test row.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
