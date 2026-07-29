# Doctor check: no repo pins `core.hooksPath`

Date: 2026-07-29
Repo: dotfiles
Status: Spec

## Problem

On 2026-07-29 the git-hooks sweep's first real run (PR #189) found four repos —
`ai-config`, `dotfiles`, `etch-cli`, `math` — carrying an absolute macOS
`core.hooksPath` in their per-clone `.git/config`. On the Mac the path resolved and
hooks ran. On the Linux workstation that path cannot exist, so **git ran no hooks at
all** there: no ggshield secret scan, no Conventional Commits check, no `_dod_gate`,
no SDLC branch guard — silently, on every commit and push, for months.

Nothing surfaced it at the time. `setup_env.sh -t update` succeeded. CI was green. The
hook files were present and executable. `make install-hooks` reported success in every
repo. Each of those signals answers a different question than the one that matters:
_does git actually find a hook here._

That is no longer the full picture, and the difference shapes this design. PR #189's
sweep — the mechanism that found this — resolves each repo's hooks directory through
`rev-parse --git-path hooks`, which honours `core.hooksPath`. On the Linux box the
pinned macOS path fails `[[ -d ]]`, so `_git_hooks_dir` returns 1,
`_git_hooks_check_complete` returns 2, and the sweep now emits
`"<repo>: no hooks directory (install-hooks cannot fix this)"` on every `-t update`
(`lib/git_hooks.sh:361`). All four affected repos are mandated and carry
`install-hooks:` targets, so **the broken-on-Linux case is already detected today**.

What remains undetected is narrower, and is what this change is actually for: a pin that
*resolves* — the Mac case, where hooks run and every signal reads green while the value
silently propagates to machines where it cannot resolve; `--global` and `--system`
scope, which nothing reads at all; repos with no `install-hooks:` target, which the
sweep never discovers; and the absence of any exit code that moves when a pin is
found.

The delivery vector is confirmed from history: the pre-#182 `synch_git-repos.sh` ran
`rsync -ar --delete ~/git-repos <host>:~/` with no exclusion, mirroring `.git/config`
— and the machine-specific absolute paths inside it — onto hosts where they are
meaningless. PR #182 closed that vector with `--exclude=personal`, but residue
survives on any machine mirrored before it.

A scan of `~/git-repos/personal/` on the Mac Studio on 2026-07-29, before this spec
was written, found **zero** repos still pinning `core.hooksPath` — the residue there
has already been cleaned. This check is therefore not a cleanup mechanism. It is
recurrence detection, and coverage for the six other machines in the fleet whose
state has not been inspected.

### Why a check and not a fix

Every observed value pointed at the default location git would have used anyway. The
setting was redundant wherever it appeared. That makes _any_ value an anomaly
regardless of how it got there, which in turn means a check catches recurrence from
sources the closed rsync vector never covered — a stray `git config` in a script, a
restored backup, a future sync tool.

## Decisions

Decisions 1–6 were revised after the Multi-Lens Review (recorded at the bottom of this
file); the "Revised" column states what changed and why. The pre-review reasoning is
kept rather than overwritten, because two of the three reversals turn on facts that were
true when first written and are no longer.

| #   | Decision | Rationale, and what the review changed |
| --- | -------- | -------------------------------------- |
| 1 | Detection is reported from **both** surfaces: the `-t update` git-hooks sweep and `-t doctor`. | Originally `doctor` only. `run_doctor` has exactly one call site — `setup_env.sh:69`, human-invoked; it appears in no workflow, no `run_update` path, and no CI job (`grep -rn run_doctor lib/ setup_env.sh scripts/`; `grep -rn doctor .github/workflows/`). A check reachable only by typing `-t doctor` fires only where someone already went looking, which is the runbook posture `USER.md` explicitly rejects for exactly this class of fleet drift. `-t update` is what actually runs unattended on all seven machines and already owns a `git-hooks` section. `doctor` is kept as the on-demand surface. |
| 2 | One detector function, called from both surfaces — no parallel machinery. | The review's "minimal" alternative was to drop the per-repo arm entirely and rely on the sweep's existing rc=2 gap plus a new global/system read. Rejected: that detects only values that *fail to resolve*, so the Mac case — a pin that resolves, hooks run, everything looks green — stays invisible, which is precisely the blindness that let this run for months (see Decision 4). What is dropped instead is the duplication: the detector is written once and both surfaces call it. |
| 3 | Scan every git repo under `PERSONAL_GITREPOS`, plus `--global` and `--system` scope. `PERSONAL_GITREPOS` only — not the other `~/git-repos/*` trees. | Gating on a Makefile `install-hooks:` target (i.e. reusing `_git_hooks_discover`) would leave the identical silent kill undetected in any repo without that target. The defect is a git-config anomaly, not a hooks-install anomaly. Global/system scope included because a pin there disables hooks in *every* repo on the box. `~/git-repos/{fortis,fullscript,cybernetiq,…}` are per-employer trees from elsewhere, last touched 2022–23, with none of this tooling installed and no hook mandate; failing on an archived repo is noise. There is no `~/git-repos/work/`. |
| 4 | Severity is split by mandate: a pin in a `HOOK_EXPECTED_REPOS` repo, or at `--global`/`--system`, is a **failure**. A pin in any other repo is a **warning**. | Originally: any non-empty value anywhere is a hard failure with no override. The severity floor is right — failing only when the path is *broken* would have been a clean PASS on the Mac for months, firing on one machine of seven, after the damage. The scope was not: 8 of the 17 git repos under `personal/` (`ai`, `homepage`, `kubernetes`, `python-learning`, `pfsense_config`, `truenas-config`, both `docker_container_*`) carry no hook mandate, and husky sets `core.hooksPath` as its *normal* install step. Under the original rule the first tooling-managed repo landing there turns `doctor` permanently red with no suppression path — and because `run_doctor` collapses to a single boolean, that also destroys the exit-code signal for the symlink, credential, tool, and version checks. `HOOK_EXPECTED_REPOS` is already the repo's declared answer to "where do hooks matter", so it is the allowlist; no second list is introduced. |
| 5 | Read each scope explicitly (`--local`, `--global`, `--system`), never bare `--get`. | Bare `--get` returns the *effective* value after system→global→local precedence. A single global pin would then fire once per repo plus once globally — the same anomaly reported 18 times, each with the wrong remedy attached. Scoped reads report each anomaly once, at its true scope, with the correct `git config [--global] --unset` line. |
| 6 | Detection lives in `lib/git_hooks.sh`; `lib/helpers.sh` holds a thin `_doctor_check_hooks_path` that formats and delegates. | Putting the whole check in `helpers.sh` would copy the `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip into a second file. That idiom drifting across hand-copies is a documented failure class in this fleet — `ai-config/.claude/scripts/git_env.py` exists because five hand-rolled copies had already drifted to two different variable sets. `run_doctor`'s call list stays uniform with the other `_doctor_check_*` entries. |
| 7 | Aggregate PASS, per-offender FAIL/WARN. | One PASS line per repo would emit 17 lines on this machine (20 subdirectories under `personal/`, 17 of them git repos, counted 2026-07-29). Unlike the symlink check, knowing *which* repo was clean carries no diagnostic value. |
| 8 | The sweep's existing `make install-hooks` invocation gets the `env -u` strip. | Raised by the risk lens and independently confirmed here: `lib/git_hooks.sh:326` runs `run_cmd make -s -C "${_dir}" install-hooks` with no strip, so a leaked `GIT_DIR` redirects the install. This is a live hole today for `ai-config` and `math`, both of which resolve their hooks dir via `--git-path hooks`. Fixing it at the sweep's invocation covers every repo regardless of Makefile shape — one strip instead of one per Makefile across nine repos. |

## Design

### `_git_hooks_hookspath_offenders` (lib/git_hooks.sh)

Contract: prints zero or more tab-separated `scope<TAB>name<TAB>value` lines on stdout,
one per anomaly; prints nothing when clean; returns 0 in both cases. An empty result
means "checked, clean" — callers count lines, they do not interpret the exit code as a
verdict. `scope` is one of `system`, `global`, `repo`, `repo-unmandated`; the last
distinction is what lets each caller pick failure vs warning severity without
re-deriving the mandate list.

Three arms:

```bash
# system and global — no repo context, so no GIT_DIR strip needed
git config --system --get core.hooksPath
git config --global --get core.hooksPath

# per repo, for each "${PERSONAL_GITREPOS}"/*/ where "${_dir}.git" is a directory
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  git -C "${_dir}" config --local --get core.hooksPath
```

`-d "${_dir}.git"` (not `-e`) for the same reason `_git_hooks_discover` uses it: a
worktree or submodule `.git` is a *file*, its config is the parent's, and testing `-e`
would both double-report the parent's value and let `git -C` walk up into an ancestor
repo. This guard is load-bearing, not defensive — `personal/` on every machine checked
contains three worktree parent directories (`ai-config-worktrees`,
`brucejacksonconsulting-site-worktrees`, `dotfiles-worktrees`) that are plain
directories, not repos. Without the guard the check emits three `fatal: --local can only
be used inside a git repository` lines to stderr on every run, on every machine. Those
three are exactly the 20-subdirectory / 17-repo gap counted in Decision 7.

The `env -u` strip is required because git exports `GIT_DIR` into the pre-push hook
environment when pushing from a worktree, and this repo's pre-push hook runs `make
test`, which sources this file — an inherited `GIT_DIR` overrides `-C` entirely and
would silently read one repo's config 17 times.

`git config --get` exits 1 when the key is unset; that is the normal clean path and must
not be treated as an error.

### Surface 1 — the `-t update` sweep (lib/git_hooks.sh)

`install_git_hooks_all_repos` calls the detector once per run and folds the result into
the counters it already maintains, alongside `_gaps` and `_unknown`. Offender lines
reach `log_warn` and `~/.dotfiles-update.log` like the sweep's other findings, and the
`git-hooks` section of the printed summary reports the count.

This is the surface that matters for the fleet: `-t update` runs unattended on all seven
machines, `-t doctor` does not.

Note the interaction with `_UPDATE_SECTION_ORDER` documented in `CLAUDE.md`: the
`git-hooks` section is already registered, so no array edit is needed here — but
`_update_record_end` still has no `git-hooks)` case arm, which is a known open backlog
item. Until that lands, offender counts reach the log but not the summary table. This
change does not fix that and does not depend on it.

### Surface 2 — `_doctor_check_hooks_path` (lib/helpers.sh)

Added to `run_doctor`'s call list after `_doctor_check_cred_dirs`. Prints the section
header, calls the detector once, and maps its output onto `doctor_pass` / `doctor_warn`
/ `doctor_fail` per Decision 4.

Clean:

```
Git hooksPath:
  [PASS] system/global: unset
  [PASS] 17 personal repos: none pinned
```

Dirty:

```
Git hooksPath:
  [FAIL] global: pinned to /Users/bruce/.githooks — remedy: git config --global --unset core.hooksPath
  [PASS] 17 personal repos: none pinned
```

```
Git hooksPath:
  [PASS] system/global: unset
  [FAIL] etch-cli: pinned to /Users/.../etch-cli/.git/hooks — remedy: git -C <repo> config --unset core.hooksPath
  [WARN] homepage: pinned to .husky/_ (not a hook-mandated repo — expected if husky-managed)
```

Independent arms, so a global pin and a per-repo pin are reported separately with their
own remedies, and the repo-arm PASS still prints when only the global arm fails.

### The `env -u` strip on the sweep's `make` invocation

`lib/git_hooks.sh:326` currently reads:

```bash
run_cmd make -s -C "${_dir}" install-hooks
```

Verified in this repo:

```
$ git rev-parse --git-path hooks
.git/hooks
$ GIT_DIR=/Users/bruce/git-repos/personal/ai-config/.git git rev-parse --git-path hooks
/Users/bruce/git-repos/personal/ai-config/.git/hooks
```

A leaked `GIT_DIR` does not merely redirect within a repo — it sends the target repo's
hooks into *another repo's* hooks directory. `ai-config` and `math` both resolve via
`--git-path hooks` and are exposed today. Strip at the invocation:

```bash
run_cmd env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  make -s -C "${_dir}" install-hooks
```

One change covers all nine repos regardless of their Makefile shape, which is why this
is preferred over adding a strip to each Makefile.

### dotfiles `Makefile` install-hooks

Current target writes to a literal path:

```make
install-hooks: ledger-symlink
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
```

Under a set `core.hooksPath` this installs into a directory git ignores and prints
success — the "reports success while git reads elsewhere" shape that let the original
bug survive. It also fails outright in a worktree, where `.git` is a file.

```make
HOOKS_DIR := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                       git rev-parse --git-path hooks 2>/dev/null)

install-hooks: ledger-symlink
	@[ -n "$(HOOKS_DIR)" ] || { printf "install-hooks: cannot resolve hooks dir (not a git repo?)\n" >&2; exit 1; }
	@mkdir -p "$(HOOKS_DIR)"
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" "$(HOOKS_DIR)/pre-commit"
	ln -sf "$(shell pwd)/scripts/pre-push" "$(HOOKS_DIR)/pre-push"
	ln -sf "$(shell pwd)/scripts/commit-msg" "$(HOOKS_DIR)/commit-msg"
```

The `env -u` inside `$(shell ...)` is not redundant with Decision 8's strip: that one
covers the sweep's invocation, this one covers a human running `make install-hooks`
directly from a worktree. Without it, this change would *remove* the accidental immunity
the literal `.git/hooks` path currently has.

POSIX `[ ]`, not `[[ ]]`: this `Makefile` sets no `SHELL`, so recipes run under
`/bin/sh`. `ai-config`'s `Makefile` sets `SHELL := /bin/bash` on line 1 and can use
`[[ ]]`; copying its recipe verbatim would break here. Adding `SHELL := /bin/bash` to
this file would change the interpreter for every other recipe in it — out of scope.

`--git-path hooks` is the only primitive that honours `core.hooksPath` *and* resolves
correctly from a worktree. It returns a path relative to the repo root in the common
case, which is correct here because `make` runs at the repo root; the `ln` sources are
absolute via `$(shell pwd)`. `mkdir -p` covers the hard-fail shape `math`'s target has
today.

## Testing

`tests/setup_env/git_hooks.bats` already builds real repos with `git init -q` under a
`PERSONAL_GITREPOS` override, so the repo arm needs no new harness. The global and
system arms use `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_SYSTEM` pointed at temp files — real
git, no mock, and no possibility of touching the developer's own `~/.gitconfig`.

| Category | Case | Assertion |
| -------- | ---- | --------- |
| Happy | no scope sets the key | no offender lines; two `doctor_pass`; `_DOCTOR_FAILED` stays 0 |
| Boundary | zero repos under `PERSONAL_GITREPOS` | clean, `0 personal repos`, no crash on the empty glob |
| Boundary | exactly one repo, pinned | one offender line — a one-element fixture cannot see separator bugs, so the multi-offender case below is the load-bearing one |
| State | two mandated repos pinned + global pinned | three offender lines, three failures, each naming its own scope and remedy |
| State | unmandated repo pinned | `doctor_warn`, not `doctor_fail`; `_DOCTOR_FAILED` stays 0 |
| State | mandated + unmandated both pinned | one fail and one warn; the warn does not suppress or mask the fail |
| Error | value points at a nonexistent directory | still reported at the same severity as a resolvable value — Decision 4 |
| Error | worktree parent dir (no `.git` at all) | skipped silently; **stderr must be empty** — this is the real-world `*-worktrees/` case |
| Error | worktree checkout (`.git` is a file) | skipped; parent repo reported once, not twice |
| Isolation | `GIT_DIR` exported into the environment | offenders read per-repo, not 17 reads of the leaked repo |
| Isolation | `GIT_DIR` exported, sweep runs `make install-hooks` | make is invoked with the var stripped; hooks land in the target repo, not the leaked one |
| Idempotency | detector called twice in one shell | identical output both times |

`Makefile` change verification: `make install-hooks` in a temp clone with
`core.hooksPath` set to a temp directory must install into *that* directory, not into
`.git/hooks`. A test that only checks "three hooks exist somewhere" passes against both
the old and new target and proves nothing.

Coverage: `lib/git_hooks.sh` and `lib/helpers.sh` are both already in
`scripts/run-bash-coverage.sh`'s `INCLUDE_FILES`, so the new lines are measured. The 90%
CI floor must still hold.

## Fleet evidence

| Machine | local pins | `--global` | `--system` | `/etc/gitconfig` | Date |
| ------- | ---------- | ---------- | ---------- | ---------------- | ---- |
| Mac Studio | none (17 repos) | unset | unset | — | 2026-07-29 |
| laptop | none | unset | unset | absent | 2026-07-29 |
| Linux workstation | none | unset | unset | absent | 2026-07-29 |
| 3× work Mac | not inspected | not inspected | not inspected | not inspected | — |
| Windows/WSL | not inspected | not inspected | not inspected | not inspected | — |

The Linux workstation row is the significant one: it is the machine where the missing
hooks actually bit, and it was rsync'd from the Studio before #182 closed that vector.
It is clean and has stayed clean, which is the strongest available evidence that no live
writer is still setting `core.hooksPath`. Not proof — three work Macs and the WSL box
remain uninspected, and the work Macs are the only plausible home for an MDM-managed
`--system` pin.

## Out of scope for this PR

Both are the same defect class in other repos, and each gets its own commit under its
own repo's gates in the same session:

- **`math/Makefile`** — its `install-hooks` targets `$(git rev-parse --git-path hooks)`
  correctly but without a `mkdir -p` guard, so `ln -sf` fails hard when that directory
  does not exist. Code change: branch + PR in `math`.
- **`ai-config/Makefile:25`** — the comment reads `core.hooksPath IS set locally in this
  repo, so the two agree here by coincidence, not by design`, recording the defect as a
  fact to honour rather than an anomaly to flag. That framing is a large part of why
  this survived, and it is now also factually false. Docs-only: direct to master in
  `ai-config`.

Also deliberately excluded: `--worktree` scope (`extensions.worktreeConfig`), not
enabled anywhere in this fleet; and the missing `git-hooks)` case arm in
`_update_record_end`, which is an existing backlog item this change neither fixes nor
depends on.

## Related

- Verified lead 4 in `ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md` — evidence
  and original write-up
- PR #189 — the git-hooks sweep whose first real run found this
- PR #182 — closed the rsync delivery vector

## Multi-Lens Review

Reviewed at commit: `0a1636a` (Step 7 self-review commit, before Step 8 dispatch)

Every finding below was re-verified in this session with the command shown, not accepted
on the lens's word. The three lenses converging on "wrong surface" is not treated as
confirmation — the confirmation is the `grep` and the `git rev-parse` output.

### Goal-Fit

Finding: Two points.

(a) **The check is placed where it will not run on the machines it exists for.**
`run_doctor` has exactly one call site — `setup_env.sh:69`, behind `-t doctor`, human
invoked. It is not in `run_update`, not in `setup`, not in CI. Verified:

```
$ grep -rn run_doctor lib/ setup_env.sh scripts/
lib/helpers.sh:277:run_doctor() {
setup_env.sh:69:[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
$ grep -rn doctor .github/workflows/     # (no output)
```

So the mechanism fires only when a human on that box already went looking — the runbook
posture `USER.md`'s own fleet note rejects. `-t update` is what runs unattended on all
seven machines, and it already owns a `git-hooks` section in `_UPDATE_SECTION_ORDER`.

(b) **"Nothing else surfaced it" is stale after PR #189, which narrows what this buys.**
`_git_hooks_dir` resolves through `rev-parse --git-path hooks`, which honours
`core.hooksPath`. On the Linux box a pinned macOS path fails `[[ -d ]]`, so
`_git_hooks_dir` returns 1, `_git_hooks_check_complete` returns 2, and the sweep already
emits `"<repo>: no hooks directory (install-hooks cannot fix this)"` on every `-t update`
(`lib/git_hooks.sh:361`). All four affected repos are mandated and carry `install-hooks:`
targets, so the exact production silent-kill is already detected today. The genuinely new
coverage is narrower than the Problem section claims: values that *resolve* (the Mac
case), `--global`/`--system` scope, repos with no `install-hooks:` target, and a non-zero
exit code. That residual is real — Decision 3's argument against "only fail when broken"
still holds — but it is reachable more cheaply than a three-arm detector plus nine test
cases: add the global/system read, and escalate the sweep's existing rc=2 gap, which
today is `log_warn`-only and deliberately never affects the return code.

Assumption: That nothing in the toolchain *persists* `core.hooksPath` — the claim
Decision 3's no-allowlist hard FAIL rests on entirely. Genuinely uncertain because the
spec explains the delivery vector for *destination* machines (pre-#182 rsync) but never
explains what set it on the Mac Studio, which was the rsync **source**. `ai-config`
ADR-0055:72, written 2026-07-28, asserts the setting was present (`git config
--show-origin` → `file:.git/config`); the scan one day later found zero, meaning it was
hand-removed, not never-present. An unidentified writer may still be live. Settles it:
run `for d in ~/git-repos/personal/*/; do printf '%s ' "$d"; git -C "$d" config --local
--get core.hooksPath; done` on the Linux workstation and the WSL box **before**
committing to FAIL semantics. Reappearance on a machine not rsync'd since #182 means the
writer exists and `doctor` goes permanently red there.

Disposition: **Addressed.** (a) surface — the detector is now reported from the `-t update` sweep as well as `doctor` (Decisions 1 and 2, new "Surface 1" section). (b) staleness — the Problem section now states that #189 already detects the broken-on-Linux case and names the narrower residual this change covers. The review's cheaper variant (drop the per-repo arm, rely on the sweep's rc=2 gap plus a global/system read) was **not** taken: it detects only values that fail to resolve, leaving the Mac case invisible. What was dropped instead is the duplication — one detector, two callers.
Re-reviewed at commit: 

### Ergonomics

Finding: Two points.

(a) **Same wrong-surface finding, reached independently, plus its consequence for
Decision 3.** Decision 3 rejects `doctor_warn` because "nothing automated would ever
notice" a warning. Nothing automated notices the *failure* either, at this trigger. The
exit-code choice buys nothing where it is attached while carrying its full accepted cost.
This machine's own update log corroborates: `grep -c doctor ~/.dotfiles-update.log` → `0`.
The Windows/WSL box `USER.md` names as the emergency-only machine — where stale hooks
matter most, because you would be on it under time pressure — is the box least likely to
have anyone type `-t doctor` on it.

(b) **No escape hatch, against a scope deliberately widened past the mandate.** Decision 1
covers all 17 git repos under `personal/`; 8 of them (`ai`, `homepage`, `kubernetes`,
`python-learning`, `pfsense_config`, `truenas-config`, both `docker_container_*`) have no
hook mandate and no `install-hooks:` target. All read empty today, so there is no live
friction — but husky sets `core.hooksPath` as its *normal* install step, so the first
tooling-managed repo that lands there turns `doctor` permanently red with no `git config`
you are willing to run and no suppression path. Every other gate in this fleet has one
(`Perf: skip`, `Bug Scan: skip`, `Maintainability: skip(...)`). Cheap now, annoying to
retrofit after a week of red.

Assumption: That someone actually runs `./setup_env.sh -t doctor` on the six uninspected
machines, on some cadence, unprompted. If false, the check detects nothing it was built to
detect regardless of how correct its internals are. Not observable from this repo —
nothing schedules it. Settles it: ask directly — on the WSL box and the three work Macs,
when was `-t doctor` last run, and what makes you run it? Corroborating check on those
boxes: `grep -c doctor ~/.dotfiles-update.log` or `history | grep 'setup_env.*doctor'`.

Disposition: **Addressed.** (a) same surface change as above; `-t update` is now the primary surface and `doctor` the on-demand one. (b) escape hatch — severity is now split by mandate (Decision 4): a pin in a `HOOK_EXPECTED_REPOS` repo or at `--global`/`--system` fails; a pin anywhere else warns. `HOOK_EXPECTED_REPOS` is reused as the allowlist rather than introducing a second list. The husky case the lens named lands in the warning bucket by construction.
Re-reviewed at commit: 

### Risk

Finding: Two points.

(a) **The `Makefile` change introduces the exact failure mode the literal path was immune
to.** The spec argues at length that an inherited `GIT_DIR` must be stripped on the read
path, then specifies the write path as a bare `HOOKS_DIR := $(shell git rev-parse
--git-path hooks)` with no strip. Verified in this repo:

```
$ git rev-parse --git-path hooks
.git/hooks
$ GIT_DIR=/Users/bruce/git-repos/personal/ai-config/.git git rev-parse --git-path hooks
/Users/bruce/git-repos/personal/ai-config/.git/hooks
```

A leaked `GIT_DIR` does not merely redirect within a repo — it sends this repo's hooks
into *another repo's* hooks directory. The current literal `.git/hooks` target is immune
(plain relative path); the proposed fix would end that immunity. Also `:=` is immediate
expansion, so the `rev-parse` fires on every `make` invocation, not just `install-hooks`.

Escalation found while verifying: `lib/git_hooks.sh:326` invokes `run_cmd make -s -C
"${_dir}" install-hooks` with **no `env -u` strip**, so the sweep already carries this
hole today for `ai-config` and `math` — both resolve via `--git-path hooks`. The proposed
change would add `dotfiles` to the exposed set rather than being its origin. That
relocates the correct fix to the sweep's `make` invocation, where one strip covers every
repo regardless of Makefile shape. Note also that `_git_hooks_dir` already encapsulates
this guard plus relative→absolute resolution: Decision 5 forbids hand-copying the idiom
into a second *file*, and the design then hand-copies a degraded version into a second
*language*.

(b) **Decision 3's evidence base does not cover the scope it justifies, and there is no
override.** "No such case exists across the nine mandated repos" is per-clone evidence;
Decision 1 extends hard FAIL to `--system` and `--global`, scopes never surveyed on six of
seven machines — three of which are work Macs where MDM-managed git config is plausible
and would be unfixable by the user. `run_doctor` collapses to a single boolean
(`[[ ${_DOCTOR_FAILED} -eq 0 ]]`), so one permanently-red unclearable check destroys the
exit-code signal for the symlink, credential-directory, tool, and version checks on that
machine.

Assumption: That no machine in the fleet carries a `core.hooksPath` at `--system` or
`--global` scope that the user cannot or should not unset. Genuinely uncertain: six of
seven machines uninspected, three employer-managed. Settles it, per machine:
`git config --system --get core.hooksPath; git config --global --get core.hooksPath;
ls -l /etc/gitconfig` — a non-empty system value on a root-owned MDM-managed
`/etc/gitconfig` refutes it and forces an allowlist or scope narrowing before this ships.

Disposition: **Addressed.** (a) the strip moves to the sweep's `make` invocation (new Decision 8), covering all nine repos rather than one Makefile at a time; the dotfiles `Makefile` change is retained but now carries `env -u` inside its `$(shell ...)` so it does not remove the immunity the literal path had. (b) the evidence base was extended rather than argued with: the laptop and the Linux workstation were both scanned on 2026-07-29 and are clean at every scope, with no `/etc/gitconfig` present on either — recorded in the new "Fleet evidence" table. The three work Macs remain uninspected and are the only plausible MDM case; Decision 4's warn-tier plus the mandate-scoped fail keeps a surprise there from reddening `doctor` permanently.
Re-reviewed at commit: 

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
