# ADR-0016: Auto-Install Git Hooks Across Personal Repos

**Date:** 2026-07-28
**Status:** Accepted

## Context

`repo-structure.md` requires every personal repo to carry the same three git hooks
(`pre-commit`, `pre-push`, `commit-msg`), each installed via `make install-hooks`. Nothing
made that actually happen: the target has to be run by hand, per repo, after every clone
and after every hook-script edit. Measured on the Mac Studio 2026-07-28, `state-ledger` was
running with a stale `pre-push` for 11 days before anyone noticed — the gap is not
theoretical.

`dotfiles` has no canonical list of the other nine personal repos; it special-cases
`ai-config` at `lib/workflows.sh:96` and knows nothing else. A weekly, unattended sweep
(`-t update`) plus a bootstrap-time sweep (`-t setup_user`) closes the drift window, but
four design decisions in that sweep are easy to get wrong in ways that look correct on
first read, and easy to re-litigate without the measurements behind them. This ADR records
those four decisions and the evidence for each.

## Decision

### 1. Discover repos, don't hardcode a list

The sweep walks `${PERSONAL_GITREPOS}/*/` and filters rather than reading a maintained
repo list:

```bash
[[ -d "${_dir}.git" ]] || continue
git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
[[ -f "${_dir}Makefile" ]] || continue
grep -q '^install-hooks:' "${_dir}Makefile" || continue
```

Both `-d .git` and `rev-parse --git-dir` run, in that order, because **neither test
subsumes the other**:

- `-d .git` alone accepts any directory that merely contains something named `.git` — a
  partial clone or an interrupted `git clone` passes it despite not being a working repo.
- `rev-parse --git-dir` alone **succeeds inside a linked worktree**, whose `.git` is a file
  (a `gitdir:` pointer), not a directory — it would re-admit exactly the throwaway
  worktrees the first test exists to exclude. `ai-config-hook-integrity` is a live worktree
  sitting directly under `~/git-repos/personal/`, and its Makefile does carry an
  `install-hooks:` target, so this is not a hypothetical collision.

The `rev-parse` filter is defense against a measured hazard, not decoration: an
`install-hooks` recipe built as `HOOKS_DIR := $(shell git rev-parse --git-path hooks)`
expands to the empty string when run outside a real repo, producing the path
`/pre-commit`. As root on Linux that writes hooks into `/`. macOS fails safe only because
`/` is read-only there — Linux does not have that accident of protection. Confirmed on
`ai-config` 2026-07-28.

**Rejected alternative:** a maintained repo list in `dotfiles/config/`. Rejected for
installation because it drifts the moment a new repo appears — the whole failure mode this
sweep exists to close. A short list is still used, but only for reporting gaps (decision 2
below), a narrower and lower-stakes use than deciding what gets installed.

### 2. Gate correctness on the installed hooks directory, not `make`'s exit code

`make install-hooks` exiting 0 means the target ran, not that the repo now has correct
hooks. The two diverge in both directions, measured across the six repos that carry the
target on 2026-07-28:

| Repo                          | `pre-commit` | `pre-push` | `commit-msg` |
| ----------------------------- | ------------ | ---------- | ------------ |
| `state-ledger`                | ok           | **absent** | **absent**   |
| `brucejacksonconsulting-site` | **absent**   | ok         | ok           |

`state-ledger` has no `scripts/pre-commit` at all — its `pre-commit` hook comes from
`ledger init`, not from `make install-hooks`, and the sweep's assertion must **pass** on
it: checking `scripts/` instead of the installed `.git/hooks/` directory would report a
false gap there every week, forever, which is the exact tune-out failure the reporting
design exists to prevent. `brucejacksonconsulting-site` has `scripts/pre-commit` but no
hook actually installed — the opposite shape, and the assertion must **fail** on it. A
source-based check inverts both verdicts.

The fix: after each `make`, assert the mandated set `{pre-commit, pre-push, commit-msg}`
exists and is executable in the repo's `.git/hooks/` (or worktree-equivalent) directory —
never in `scripts/`. A repo whose target ran cleanly but left the directory incomplete
counts as a gap, not an OK.

### 3. Digest hook-directory contents, never metadata

"Updated" must mean the hooks actually changed, not that `make` ran. `installed: 6` every
week regardless of whether all six were already current or all six were 11 days stale is
the exact unactionable line this reporting exists to replace.

Measured by running `make install-hooks` twice in `ai-config`:

```
content-hash (shasum -a 256):   IDENTICAL across runs
stat metadata (%N %m %z):       DIFFERS
```

Four of six repos install with `cp` (which rewrites the destination file, and therefore its
mtime, unconditionally on every run); the other two use `ln -sf` (unlink + recreate, giving
a fresh inode every run). A `stat`-based digest — the natural first read of "digest of the
directory" — would report every `cp` repo as updated on every single run, on an otherwise
untouched box. The digest must be a content hash with symlinks resolved, taken immediately
before and after the `make` call, and compared.

This has a coupling worth recording rather than rediscovering later: **the digest's
informativeness is inversely tied to the symlink-normalization backlog item.** A
symlink-installed hook's content tracks its source continuously — the moment the source is
pulled, the installed hook is already current, with no `make` call involved — so a
symlink-style repo reports checked-not-updated on every run by construction, correctly. If
the backlog item lands and all six repos normalize to `ln -sf`, the updated count goes
permanently to zero — not because nothing is being maintained, but because nothing can
drift anymore. Whoever picks that item up should delete the digest at that point rather
than debug a count stuck at zero.

### 4. Return-code handling is asymmetric by call site, not a repo-wide convention

The sweep is called from two places, and the usual `|| return 1` propagation shorthand is
wrong at one of them:

- `run_update()` — the rc is passed through to `_update_record_end "git-hooks"` and
  surfaces as a `[FAIL]` row in the update summary and a `_failure_stage` entry in the
  state-ledger record, the same treatment every other update section gets.
- `run_setup_user()` — the failure count is logged but the function **returns 0**, never
  propagating the sweep's rc. `setup_env.sh` dispatches `run_setup_user` through
  `_run_or_exit`, whose body is `[[ ${_ec} -eq 0 ]] || exit "${_ec}"`. Propagating a
  non-zero rc there would let a single broken Makefile in one unrelated repo `exit` the
  entire `-t setup` script before `run_setup_or_developer` and `run_developer_or_ansible`
  ever run — a hooks-hygiene sweep has no business holding that much power over a full
  machine bootstrap.

The asymmetry is deliberate, not an inconsistency to clean up later: `run_update` is a
maintenance pass where a `[FAIL]` row is the correct, proportionate signal, while
`run_setup_user` is on the critical path of getting a new machine usable at all.

## Consequences

**Easier:**

- Hook drift (stale `pre-push`, missing `commit-msg`) closes automatically on the existing
  weekly `-t update` cadence and on every `setup_user` run, with no manual `make
install-hooks` sweep required across repos.
- New repos need only add an `install-hooks:` Makefile target to be picked up — no edit to
  `dotfiles` itself.
- The gap report names specific repos and specific missing hooks (e.g. `state-ledger:
commit-msg`), rather than a bare count nobody can act on.

**Harder / accepted going forward:**

- The sweep executes every discovered repo's Makefile recipe unconditionally, every week,
  on every machine. All six existing targets were verified with `make -n` to be
  `cp`/`ln -sf`/`chmod` only — nothing that builds, fetches, or prompts — but `etch-config`
  and `terraform_ansible` are gaining `install-hooks` targets authored in a concurrent
  session and have not been read. The safety argument for "unconditional is free" needs
  re-verifying once those land.
- The expected-repos list (for gap reporting only) lives in `dotfiles/config/` but
  describes a property of the other nine repos, with nothing enforcing agreement between
  them — the same shape as `roleModels`, and the same failure mode one level up: a repo
  gains hooks, nobody updates the list, the gap goes silently unreported. Scoping the list
  to reporting only (never installation) bounds the blast radius of that drift.
- The content-digest mechanism has a built-in expiry: it is only informative while any
  repo installs hooks via `cp`. Normalizing all repos to `ln -sf` (a separate backlog item)
  retires this reporting path rather than complementing it.

### Accepted risk: discovery is not gated on the expected-repos list

Raised by `security-review` on this branch (2026-07-29) and **accepted by the repo owner**,
recorded here rather than left in a session transcript.

Installation selects on `.git` + `Makefile` + `^install-hooks:` alone. There is no
allowlist on the execute path — `HOOK_EXPECTED_REPOS` deliberately governs gap _reporting_
only, so any repo matching those three conditions has its Makefile recipe executed
unattended, weekly, on every machine.

**The load-bearing invariant is a directory convention:** `~/git-repos/personal/` holds
only repositories the owner controls. Third-party clones live elsewhere. Given that, the
scenario security-review first reached for — cloning someone else's project into that
directory to read it, and having its `install-hooks:` target run on the next `-t update` —
is not reachable, and the finding was overstated on that point. It is recorded here because
the invariant is a _convention_, enforced by habit rather than by the code: nothing in
`_git_hooks_discover` checks provenance, so the safety of the execute path rests entirely
on that habit holding.

What remains after the correction:

- **Compromise of any one of the owner's own repos, or of the GitHub account, yields code
  execution on every machine within a week**, unattended. This is the same class of exposure
  that already existed — `setup_env.sh` sources and runs code pulled from `dotfiles` and
  `ai-config` — widened from two repos to nine, and from owner-invoked to self-executing.
- **The sweep runs immediately after `sync_git_repos` in the same pass**, by design: hooks
  must install from freshly-pulled sources or the sweep installs the previous cycle's hooks
  and reports success. The security consequence of that correctness requirement is that
  upstream content is fetched and executed in one run, with no interval in which anything
  could inspect it. The `make -n` verification recorded above is a point-in-time check of
  current recipe content, not a control on future content — notably, `etch-config` and
  `terraform_ansible` are gaining targets authored elsewhere that nobody here has read.

Gating installation on `HOOK_EXPECTED_REPOS` would narrow both, at the cost of the zero-touch
property: a new repo would need a list edit before its hooks install. That trade was
considered and declined — the zero-touch property is the reason the discovery design was
chosen over a hardcoded list in the first place, and re-introducing a mandatory list edit on
the execute path would reinstate exactly the drift this ADR's first decision exists to avoid.

Revisit if the directory convention ever changes — i.e. if `~/git-repos/personal/` starts
holding repositories the owner does not control, the execute path needs an allowlist.

## Related

- `docs/superpowers/specs/2026-07-28-auto-install-git-hooks-design.md` — full design,
  including the Multi-Lens Review and External Review rounds that shaped these four
  decisions
- `docs/superpowers/plans/2026-07-28-auto-install-git-hooks.md` — implementation plan
- `lib/git_hooks.sh` — `install_git_hooks_all_repos()`, the sweep implementation
- `lib/update_summary.sh` — `_UPDATE_SECTION_ORDER`, `_update_record_start`/`_update_record_end`
- [ADR-0006](0006-shell-script-testability-conventions.md) — testability conventions the
  new `lib/git_hooks.sh` follows (sourcing guard, mock-based BATS tests)
- `~/.claude/standards/repo-structure.md` — the three-hook mandate this sweep enforces
