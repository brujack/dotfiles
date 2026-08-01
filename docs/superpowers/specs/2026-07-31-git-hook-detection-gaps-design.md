# pre-push Self-Coverage — Design

**Date:** 2026-07-31
**Status:** Approved, pending plan
**Scope note:** This spec originally covered two items. Gap 2 (the `core.hooksPath`
detector) was **split out** after two rounds of multi-lens review found the real
defect was neither thing the backlog described — see "Gap 2, and why it left this
spec" below. Both review rounds are preserved verbatim at the bottom; they are the
record of how that was established.

## Problem

`scripts/pre-push` does not test itself. Its trigger regex (`scripts/pre-push:24`) is
`'\.(sh|bats)$|^Makefile$|^tests/'`. Both `scripts/pre-push` and `scripts/commit-msg`
are extensionless, so a push whose only change is to one of those two hooks matches
nothing and skips `make test` entirely. The local gate is absent for exactly the files
that implement the local gate. CI backstops it, but only after the push has left the
machine. Found during dotfiles#191 bug-scan.

The window is narrower than it first looks: under this repo's TDD standard, any
behavioral change to either hook also touches `tests/scripts/pre_push.bats` or
`tests/scripts/commit_msg.bats`, which already match via `^tests/`. The gap bites on
comment-only, docs-only, or trivially-mechanical edits to the two hooks. Still a real
hole in a gate, and the fix is one alternation.

## Decision

**The regex adds `^scripts/`, not the two filenames.** Rejected naming
`scripts/(pre-push|commit-msg)` explicitly — a third extensionless script added later
would be silently uncovered again, which is the exact failure being fixed.
`git ls-files scripts/` is 19 files, all executable shell; 17 already match via
`\.sh$`, so this adds exactly the two hooks today and over-triggers on nothing.

## Design

`scripts/pre-push:24` becomes:

```bash
if git diff --name-only "${range}" | grep -qE '\.(sh|bats)$|^Makefile$|^scripts/|^tests/'; then
```

One alternation. No other change to the hook.

## Testing

`tests/scripts/pre_push.bats` gains:

- a diff containing only `scripts/pre-push` sets `needs_test=1` — the self-coverage
  case, and the only test here that fails against the current regex
- a diff containing only `scripts/commit-msg` sets `needs_test=1`
- a diff containing only `.gitignore` still exits 0 without running the suite —
  regression guard against over-triggering

## Risks

No meaningful failure mode. Worst case is running the suite on a push that did not
strictly need it; `scripts/` contains no generated or high-churn files. This item was
reviewed clean by all three lenses across both rounds, with the regex behavior
verified against `git ls-files` rather than asserted.

## Acceptance

- `make test` passes; test count increases by 3.
- `make lint` exits 0.
- Bash coverage unaffected — `scripts/pre-push` is not instrumented (nothing under
  `scripts/` is; that absence is the separate "coverage include-list" backlog row).
- An edit to `scripts/pre-push` alone triggers `make test` on push. **Verified by a
  scratch commit touching only that file, pushed to a throwaway branch** — not by the
  push of this change, which also touches `tests/**` and would therefore run the suite
  under the old regex regardless. The first draft of this criterion claimed exactly
  that and could not have failed; see memory
  `does-the-fix-make-its-own-verification-vacuous`.

## Gap 2, and why it left this spec

The original second item was: `_git_hooks_hookspath_offenders`'s `|| continue` treats
a git config scope it could not read as unset. Two rounds of review established that
both the backlog's framing and this spec's replacement framing were aimed at the wrong
shape, and that a third, real defect sits underneath both.

1. **Draft one — "an unreadable scope hides an active pin."** False. Git skips a
   config scope it cannot read and carries on without applying it. A `chmod 000`
   config containing `hooksPath = /tmp/PINNED` leaves `rev-parse --git-path hooks` at
   `.git/hooks` and `git status` at rc 0. The pin is inert.
2. **Draft two — "the residual is unknown operator intent."** True but near-worthless,
   and the advisory reframe routed it into a WARN lane measured at 3292 standing
   `brew-drift` warnings across 3916 runs, while `doctor_warn` cannot move
   `_DOCTOR_FAILED` and `_DOCTOR_WARN` persists to no file — failing both reads-it
   questions.
3. **The actual defect.** `git config --<scope> --get` defaults to `--no-includes`;
   effective hook resolution traverses includes. An `[include]` that sets
   `core.hooksPath` reads as **rc 1 with empty stderr** — byte-identical to
   clean-unset — while `rev-parse --git-path hooks` returns the pin and `git status`
   stays rc 0. A readable, well-formed, fully effective machine-wide hook redirect
   renders as `[PASS] <scope>: unset`. This is live in shipped code since dotfiles#194.
   It is not hypothetical for this fleet: `.gitconfig_linux:30` and
   `.gitconfig_mac_gitlab:38` both carry `[includeIf "gitdir:~/git-repos/gitlab/"]`.
   The scope-level remedy is also wrong for that shape — `git config --global --unset
   core.hooksPath` against an include-borne pin returns rc 5 and the pin survives.

Carried forward to the successor spec, so they are not rediscovered: read with
`--includes --show-origin` and key the remedy on the origin file, not the scope; the
WARN-lane saturation constrains any channel choice; the sweep does **not** fail loudly
when every git call returns 128 (`_git_hooks_discover`'s `|| continue` skips all
repos, all counters stay 0, sweep returns rc 0 and `run_update` renders `[OK]
git-hooks`); and both consumer strings at `workflows.sh:210`/`:562` hardcode "gaps or
a pinned core.hooksPath". Full reproduction in
`ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md`.

## Related

- dotfiles#191 — bug-scan that found this gap
- dotfiles#194 — added the hooksPath detector; introduced the include blind spot
- `ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md` — running dossier

## Multi-Lens Review

Reviewed at commit: `125f878` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Item 2's motivating scenario is benign, and the states it actually detects
are already loud. Measured (and independently reproduced in the main session): git
_skips_ a config scope it cannot read and carries on without applying it — so a
`chmod 000` config containing `hooksPath = /tmp/PINNED` yields `rev-parse --git-path
hooks` = `.git/hooks` (pin inert) and `git status` rc 0. The two states where a bad
config genuinely hurts (directory-as-config, malformed config) return rc 128 from
every git call, so `_git_hooks_discover` skips all 9 repos and the sweep visibly
reports 0 checked. Of three states: one harmless, one caught by rc alone, and only
directory-as-gitconfig requires the stderr-keying. Decision 1 rejects rc-only because
it "does not close the stated gap" — but the stated gap, measured, is the inert one.
Simpler paths: close Gap 2 as measured-benign and ship Item 1 alone, or rc-only
fail-closed on rc > 1 (~3 lines, no protocol change, no fleet-wide false-positive
risk). Also: the Item 1 acceptance bullet is vacuous — the push of this change
touches five files that already match the old regex, so the suite runs either way.
Reads-it test: Item 2 passes both questions (doctor verdict genuinely changes;
`_update_warn` gives it a durable channel). It fails on proportionality, not plumbing.
Assumption: that git's _clean_ path emits nothing on stderr across every git version
in this fleet, not just macOS git 2.55 where the table was probed. Settle by running
`git --version; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git config
--global --get core.hooksPath 2>&1 1>/dev/null | wc -c` on each non-macOS box;
non-zero anywhere refutes stderr-keying outright.
Disposition: Addressed (user, 2026-07-31) — premise refutation accepted. Item 2 kept but reframed: the Problem section now states the measured inert-pin result and narrows the claim to unknown operator intent, and Decision 2 flips from doctor_fail to doctor_warn. The vacuous Item 1 acceptance bullet is replaced with a scratch-commit verification. The 'drop Item 2 entirely' option was offered and declined; it is recorded in Risks as a legitimate fallback if implementation proves invasive. Assumption not yet settled — the per-machine stderr probe is now a pre-implementation acceptance item.

### Ergonomics

Finding: (1) The Item 1 acceptance criterion cannot fail — 5 of 6 files this change
touches already match the current regex, so the operator ticks the box having
confirmed nothing. Replace with a scratch commit touching only `scripts/pre-push` on
a throwaway branch. (2) The `unknown` doctor line is the only FAIL in this check with
no remedy; every sibling FAIL renders its fix inline, and the plausible action here
needs `sudo` — exactly where a half-remedy costs most. (3) The Risks section models a
future-git false positive but not a present-machine unfixable one: a machine whose
system scope is legitimately unreadable stays permanently red, and since doctor's
exit is human-read only (`setup_env.sh:69`, consumed by nothing automated), the cost
is an operator who learns to stop reading the summary. (4) Factual: `git ls-files
scripts/` is 19, not 18; 17 match via `.sh$`, not 16. Exactly two files newly
covered, so the conclusion holds.
Assumption: that on all seven machines an unreadable-scope result is a state the
operator can actually remediate. Most plausibly false on the three work Macs, where
`/etc/gitconfig` may be MDM-owned and rewritten. Settle by running `git config
--system --get core.hooksPath; echo "rc=$?"` (stderr NOT suppressed) and the
`--global` equivalent on each of the seven before implementing; any machine printing
a `warning:` today is one this design turns permanently red.
Disposition: Addressed (user, 2026-07-31) — (1) vacuous acceptance bullet replaced with a scratch-commit verification on a throwaway branch; (2) the unknown line now carries an inspect-with remedy, new Decision 3; (3) the permanently-red concern is resolved at the root by Decision 2's flip to doctor_warn, so an unremediable scope costs a noisy line rather than a red gate; (4) counts corrected to 19 files / 17 matching. Assumption folded into the same pre-implementation seven-machine probe.

### Risk

Finding: Same refutation as Goal-Fit, reached independently — the detector, the
sweep's `make install-hooks`, and the git process that runs the hooks are the same
binary, same uid, same files, so "unreadable to the detector" is perfectly correlated
with "inert in practice." Decision 2 rejects `doctor_warn` on an assertion about git's
behavior the spec never probed, and the probe refutes it. The genuine residual is
narrower and advisory-grade: an unreadable scope means the _operator's stated intent_
is unknown, not that hooks are misrouted. Second finding: the Risks section's stated
mitigation has a hole it claims to close — the clean fixture is `GIT_CONFIG_GLOBAL=/dev/null`,
an _empty_ config, which cannot trigger any content-dependent warning, so a future git
that warns about content in a real `~/.gitconfig` leaves `make test` green on all seven
machines while all seven doctors go red. Fix: add a fixture using this repo's own
tracked `.gitconfig_mac`/`.gitconfig_linux`. Third: Item 1's acceptance bullet is
vacuous (concurs). Proportionality: Item 1 and Item 2 have opposite risk/benefit
profiles and should not share a merge decision. Minor: "the first line is the whole
diagnostic" is over-generalized (an `[include] path = <directory>` yields a
`warning:` line 1 and a `fatal:` line 2); the stdout/stderr separation mechanism is
unspecified and the obvious `2>&1` one-liner would fold warnings into the pinned
value; line-number drift — call sites are `workflows.sh:206`/`:558` (spec says
210/562) and `install_git_hooks_all_repos` starts at `git_hooks.sh:329` (spec says
378, the hooksPath loop terminator).
Assumption: that git's stderr stays empty on the clean path for a _real, populated_
gitconfig across future versions, not just the empty fixture the spec probed. Settle
by running `git config --system --get core.hooksPath 2>&1 >/dev/null | wc -c` and the
`--global` equivalent on all seven machines against their real config files, and
adding that assertion as a fixture rather than against `/dev/null`.
Disposition: Addressed (user, 2026-07-31) — refutation accepted, same reframing as Goal-Fit. The stated-mitigation hole is closed: a real-content clean fixture using this repo's own tracked .gitconfig_mac/.gitconfig_linux is added alongside the /dev/null one, and the spec now says explicitly that the real-content fixture is the load-bearing one. The stdout/stderr separation mechanism is named in the Design section. The 'first line is the whole diagnostic' claim is corrected to a deliberate truncation with the [include] counter-example. Line numbers corrected to workflows.sh:206/:558 and git_hooks.sh:329. Proportionality point partially accepted: Item 2 is kept, but its residual value is now stated plainly in Risks rather than overclaimed in Problem.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Main-session verification of the shared finding

The refutation Goal-Fit and Risk reached independently was re-run directly in the main
session rather than accepted on report, per the skill's note that same-model lens
agreement is not itself confirmation:

| fixture (config contains `hooksPath = /tmp/PINNED`) | `rev-parse --git-path hooks` | `git status` |
| --------------------------------------------------- | ---------------------------- | ------------ |
| readable (control)                                  | `/tmp/PINNED` — redirects    | rc 0         |
| `chmod 000`                                         | `.git/hooks` — pin inert     | rc 0         |
| directory-as-config                                 | rc 128                       | rc 128       |

Confirmed. This spec's Problem section for Gap 2 is false as written.

Also confirmed in the main session: `git ls-files scripts/` = 19 with exactly 2
non-`.sh` files (`ls -1` had hidden `scripts/.osx.sh`); call sites are
`workflows.sh:206`/`:558`; `install_git_hooks_all_repos` starts at `git_hooks.sh:329`;
and both scopes on this machine read rc 1 with silent stderr.

---

## Multi-Lens Review — Round 2

Reviewed at commit: `1bf5644` (the advisory-reframe revision). All three lenses
re-run, per the rule that a revision changing design substance carries its own new
defects. It did.

### Goal-Fit (round 2)

Finding: the `doctor_fail` → `doctor_warn` flip deleted the only thing that made Item
2 pass the reads-it test in round 1, and nothing re-ran the test. Verified in the main
session: `run_doctor` returns `[[ ${_DOCTOR_FAILED} -eq 0 ]]` (`helpers.sh:319`) and
`doctor_warn` (`helpers.sh:40`) touches only `_DOCTOR_WARN` — so no doctor verdict can
differ, by construction (Q1: no) — and `_DOCTOR_WARN` is printed in a summary line and
persisted nowhere (Q2: no). Two "no"s: by the spec's own test, the doctor consumer is
now decoration. The sweep consumer keeps one "yes" (`~/.dotfiles-update.log`), and
that channel is saturated. Also flags the consumer-string drift below.
Assumption: that the clean read emits nothing on stderr on the six non-probed
machines; the work Macs are the plausible counterexample.
Disposition: Addressed (user, 2026-07-31) — split accepted. The reads-it failure is real and is not patched in place: Item 2 leaves this spec entirely rather than being re-argued a third time. Item 1 ships on its own merits.

### Ergonomics (round 2)

Finding: (1) Decision 2 routes the signal into an already-saturated lane. Measured in
the main session on this box: **3292 of 3916** update runs carry a standing `[WARN]
brew-drift`. The argument Decision 2 makes against a permanent red line — that it
trains the operator to stop reading — has already completed in the yellow lane it
selects as the replacement, and no acknowledge/suppress mechanism is proposed. (2)
Decision 3's remedy is null: `git config --<scope> --list` against an unreadable
config re-prints the same denial and exits 128 (measured). It cannot show contents;
unreadable is the condition being reported. (3) The seven-machine probe is filed under
Acceptance, labelled pre-implementation, and has no decision rule — nothing branches
on its result, which is the same vacuous shape round 1 flagged on Item 1,
reintroduced elsewhere. Item 1 itself verified clean.
Assumption: that a `[WARN]` in the update summary is still a channel this operator
reads. Settle with the same `awk` count on the other six machines.
Disposition: Addressed (user, 2026-07-31) — all three points are moot for this spec once Item 2 splits out: no WARN routing, no Decision 3 remedy, no seven-machine probe remain in scope. The measured WARN-lane saturation (3292/3916) carries forward to the successor spec as a constraint on any channel it picks, and is recorded in the bug-hunt dossier so it is not rediscovered.

### Risk (round 2)

Finding: **the central premise still does not generalize, and the revision codified
the gap as a reasoned all-clear.** `git config --<scope> --get` defaults to
`--no-includes` (documented in `git-config(1)`); effective hook resolution traverses
includes. Reproduced in the main session:

| fixture                             | detector's `--get` form   | `rev-parse --git-path hooks` | `git status` |
| ----------------------------------- | ------------------------- | ---------------------------- | ------------ |
| `[include]` sets `core.hooksPath`   | **rc 1, 0 bytes stderr**  | `/tmp/PINNED_VIA_INCLUDE`    | rc 0         |

`rc 1 + silent stderr` is byte-identical to clean-unset, which this spec's own
protocol table assigns to "prints nothing; scope is clean." So a readable,
well-formed, **fully effective** machine-wide hook redirect renders as `[PASS] global:
unset` — before this change and after it. That is the hazard the revised Problem
section deleted as "false": the shape was wrong (it is not unreadability), the hazard
is real. Not hypothetical for this fleet — `.gitconfig_linux:30` and
`.gitconfig_mac_gitlab:38` both carry `[includeIf "gitdir:~/git-repos/gitlab/"]`, so
include-based config is this fleet's established style. Fix is in the same function:
read with `--includes --show-origin`. That also exposes a second defect — measured,
`git config --global --unset core.hooksPath` against an include-borne pin returns
**rc 5 and the pin survives**, so the existing remedy string is wrong; a remedy must
name the origin file, not the scope.

Secondary: the spec's "visibly broken, not quietly passing" claim is false for the
sweep. Verified — `_git_hooks_discover`'s `git -C … rev-parse --git-dir || continue`
skips every repo when all git calls return 128, leaving all counters at 0, so the
sweep returns rc 0 and `run_update` renders `[OK] git-hooks`. It quietly passes.
Also: the rc-1-plus-stderr branch is never tested against the state it exists for —
the only such fixture is directory-as-config, which the spec itself classifies as the
loud state. `GIT_CONFIG_GLOBAL=/nonexistent-dir/config` is root-safe and reaches the
real branch.
Assumption: that no machine in the fleet currently resolves `core.hooksPath` through
an include chain. Settle per machine with `git config --global --includes
--show-origin --get core.hooksPath` compared against the non-`--includes` form.
Disposition: Addressed (user, 2026-07-31) — this is the finding that decided the split. The include blind spot is a live false-negative in shipped code, not a defect in this spec's proposal, so it earns its own spec rather than a third revision of a section already on its second premise. Reproduction recorded in ai-config/docs/knowledge/dotfiles-bug-hunt-leads.md; backlog row opened. The 'visibly broken' correction and the rc-1 fixture gap carry forward with it.

### Main-session verification of round 2

Re-run directly rather than accepted on report:

- Include-borne pin: detector's form rc 1 / 0 bytes stderr; `rev-parse --git-path
  hooks` = `/tmp/PINNED_VIA_INCLUDE`; `git status` rc 0. **Pin active and invisible.**
- `--includes --show-origin` finds it and names the origin file. rc 0.
- `git config --global --unset core.hooksPath` on that pin: **rc 5, pin survives.**
- `git config --global --list` on an unreadable config: rc 128, re-prints the denial.
- `awk` over `~/.dotfiles-update.log`: 3916 runs, 3292 `[WARN] brew-drift`.
- `run_doctor` = `[[ ${_DOCTOR_FAILED} -eq 0 ]]`; `_DOCTOR_WARN` written to no file.
- `.gitconfig_linux:30`, `.gitconfig_mac_gitlab:38` carry `[includeIf …]`.
- `workflows.sh:210` and `:562` both render "gaps or a pinned core.hooksPath", which
  is false under `unknown`.
- Real-content clean fixtures (`.gitconfig_mac`, `.gitconfig_linux`): 0 bytes stderr.

**Consequence: this spec's Gap 2 is aimed at the wrong shape in both drafts.** Draft
one claimed unreadable scopes hide pins (false — inert). Draft two claimed the
residual is unknown operator intent (true but near-worthless, and routed to a
saturated channel). The actual defect, live in shipped code since dotfiles#194, is
that the detector reads without `--includes` and therefore cannot see an effective
include-borne pin at all.
