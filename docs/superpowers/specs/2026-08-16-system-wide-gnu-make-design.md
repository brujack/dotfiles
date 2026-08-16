# System-wide GNU make on macOS

**Date:** 2026-08-16
**Status:** Draft — awaiting review
**Closes:** `docs/superpowers/README.md` backlog rows "Decide whether GNU make should resolve for non-interactive shells, or only interactively" and "An agent tool shell is not the 3.81 actor `CLAUDE.md` describes"
**Related:** ADR-0018 (GNU Make 4.x on macOS), dotfiles#214

---

## Problem

dotfiles#214 put Homebrew's `make` gnubin directory on `PATH` via
`.config/.zshrc.d/6_path.zsh`. That file is sourced by **interactive zsh only**, so which
`make` a process resolves depends on how the process was started. The backlog recorded this
as an open decision rather than a bug, because widening the prepend changes the toolchain
under every hook, script and cron job on the machine.

The operator has decided the direction: GNU make should be the default for non-interactive
actors as well, at the widest scope — every process on the machine.

## Measurements

All measured on the Mac Studio (arm64, Darwin 25.6.0) on 2026-08-16. Each row is a real
command's real output, not a prediction.

### Which `make` each actor resolves

| actor                                               | resolves to                                  | version        |
| --------------------------------------------------- | -------------------------------------------- | -------------- |
| this session's Bash tool                            | `/opt/homebrew/opt/make/libexec/gnubin/make` | GNU Make 4.4.1 |
| `env -i bash -c`                                    | `/usr/bin/make`                              | GNU Make 3.81  |
| `env -i zsh -c`                                     | `/usr/bin/make`                              | GNU Make 3.81  |
| `env -i zsh -i -c`                                  | `/opt/homebrew/opt/make/libexec/gnubin/make` | 4.4.1          |
| `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -c` | `/usr/bin/make`                              | GNU Make 3.81  |

### Why `/usr/local/bin` is the only viable system target

```
$ cat /etc/paths
/usr/local/bin
/System/Cryptexes/App/usr/bin
/usr/bin
/bin
/usr/sbin
/sbin
```

`/usr/local/bin` precedes `/usr/bin`, so a symlink there shadows the bundled 3.81 for any
actor using the system default `PATH`. Two alternatives were checked and both fail:

- **`/etc/paths.d/` drop-in** cannot shadow. `path_helper` appends `paths.d` entries _after_
  the `/etc/paths` list — verified by observing the existing `dotnet` entry land after
  `/usr/bin` in `/usr/libexec/path_helper -s` output.
- **Editing `/etc/paths`** is Apple-owned and fights OS updates.

`/usr/local/bin` is `drwxr-xr-x root wheel` and is not writable by the operator without
`sudo`. `/usr/local/bin/make` does not currently exist.

### Scope: this is not a dotfiles-only problem

Four repos run `make` from a bash `scripts/pre-push`:

| repo           | hook shebang          | `make` invocations                |
| -------------- | --------------------- | --------------------------------- |
| `dotfiles`     | `#!/usr/bin/env bash` | 1 (`make -C "${REPO_ROOT}" test`) |
| `math`         | `#!/usr/bin/env bash` | 2                                 |
| `etch-cli`     | `#!/usr/bin/env bash` | 1                                 |
| `state-ledger` | `#!/usr/bin/env bash` | 1                                 |

A `.zshenv` widening — the mechanism the backlog row suggested — reaches non-interactive
_zsh_ and never touches any of these, because a git hook is bash.

## The honest yield

A git hook has no `PATH` of its own; it inherits the caller's. So the practical exposure is
narrower than the backlog row implies, and this spec states that plainly rather than
overselling the change:

| real invocation                                       | today | after this change |
| ----------------------------------------------------- | ----- | ----------------- |
| `make test` run by a session                          | 4.4.1 | 4.4.1 (unchanged) |
| `git push` from a session, tmux, Warp, or ssh login   | 4.4.1 | 4.4.1 (unchanged) |
| cron                                                  | 3.81  | **4.4.1**         |
| launchd agent, IDE-spawned git, `ssh host 'git push'` | 3.81  | **4.4.1**         |

Every routine gate run on this machine is _already_ on 4.4.1 — by way of the profile
lineage, by accident rather than by design.

**The value of this change is attestation, not the cron case.** Today's 4.4.1 depends on the
harness happening to initialise its Bash tool from the operator's profile, on `.zprofile`
happening to run, and on nobody launching `git` from a clean context. Nothing checks any of
that, nothing would report if it changed, and the failure is silent: a gate that quietly
drops to 3.81 emits exactly the same green. This change converts an accident into an
invariant, and adds a `doctor` check that asserts it.

## Decision

Create `/usr/local/bin/make` as a symlink to the Homebrew `make` keg's gnubin entry, on
**arm64 machines only**, during `setup_user`. Add a `doctor` check that asserts the
resulting invariant against a clean actor.

### Why arm64 only

On x86_64, `/usr/local` **is** the Homebrew prefix. A hand-made symlink at
`/usr/local/bin/make` would sit inside Homebrew's own directory, pointing at Homebrew's own
keg-only formula: `brew doctor` reports it as an unexpected symlink, and a future `brew link`
could contend for the same name. The fleet's one x86_64 mac is not a development machine, so
it keeps today's behaviour — 4.4.1 interactively, 3.81 for clean actors.

`brew link --overwrite --force make` was considered for that machine and rejected: keg-only
is Homebrew's deliberate choice for this formula, `--force` overrides it, and any
`brew upgrade` may silently re-unlink — a mechanism that can revert itself is worse than a
documented gap.

## Mechanism

New function in `lib/macos.sh`, called from `run_setup_user` immediately after the existing
`install_make_macos`.

```bash
link_make_system_macos() {
  local _gnubin="${_OVERRIDE_GNUBIN_ARM:-/opt/homebrew/opt/make/libexec/gnubin}"
  local _link="${_OVERRIDE_SYSTEM_MAKE_LINK:-/usr/local/bin/make}"
  local _target="${_gnubin}/make"

  [[ -d ${_gnubin} ]] || return 0

  [[ -x ${_target} ]] || {
    log_warn "GNU make gnubin present but ${_target} is not executable; not linking"
    return 0
  }

  if [[ -L ${_link} ]] && [[ "$(readlink "${_link}")" == "${_target}" ]]; then
    return 0
  fi

  if [[ -e ${_link} ]] && [[ ! -L ${_link} ]]; then
    log_warn "${_link} exists and is not a symlink; leaving it alone"
    return 2
  fi

  run_cmd sudo ln -sfn "${_target}" "${_link}" || return 1
}
```

Four properties are load-bearing rather than stylistic.

**The idempotency guard compares the link's target, not its existence.** A provisioned
machine re-running `setup_user` gets no `sudo` prompt. A guard that only tested `[[ -e ]]`
would still be idempotent in outcome while prompting for a password on every run, and a
guard that tested nothing would prompt _and_ silently repoint a link the operator had
deliberately changed.

**`[[ -x ${_target} ]]` is checked before linking.** A dangling `/usr/local/bin/make` does
not degrade to 3.81 — it breaks `make` outright for every actor on the machine, which is
strictly worse than the problem being solved. Checking first makes that state unreachable
rather than merely unlikely. This is the "verify at the moment of trust, against ground
truth" rule from `USER.md`.

**The return contract is `{0,1,2}`**, matching `install_git_hooks_all_repos`: 0 = linked or
already correct, 1 = the `ln` failed, 2 = refused to clobber a non-symlink. Both call sites
must branch on the value rather than testing truthiness — the bare-`||` trap recorded in
`shell.md` under "Widening a function's return contract silently breaks every `cmd || handler`
caller". `run_setup_user` distinguishes 1 ("failed") from 2 ("refused"); nothing else calls it.

Concretely, `run_setup_user` treats rc 1 as a failure and propagates it, and treats rc 2 as a
gap: it emits a warning naming the path and the remedy, and continues to the next step
without failing the workflow. This mirrors how it already handles
`install_git_hooks_all_repos`' rc 2, where a gap is something the operator must see but not
something that should abort provisioning.

**`_OVERRIDE_SYSTEM_MAKE_LINK` is a test seam** so no test ever writes to `/usr/local/bin`.
`tests/mocks/sudo` execs its target when resolvable and `tests/mocks/ln` passes through to
`/bin/ln`, so a fixture link is really created and tests assert on real filesystem state
rather than on a mock's return code.

### The single-prefix probe is the architecture check, deliberately

`install_make_macos` and `6_path.zsh` both scan **two** prefixes — the arm64
`/opt/homebrew/opt/make/libexec/gnubin` and the x86_64 `/usr/local/opt/make/libexec/gnubin` —
and `CLAUDE.md` records that the pairs must be kept in step. This function deliberately
breaks that pairing: it probes the arm64 prefix only, and that single probe _is_ how the
arm64-only decision is enforced.

This must be stated rather than left implicit, because it is a trap for the next reader. The
two neighbouring call sites establish a two-prefix idiom; someone maintaining consistency
would naturally add the x86_64 prefix to this loop, and doing so would silently begin
creating a symlink inside Homebrew's own prefix on the one machine this design excludes. The
implementation therefore carries a comment naming the exclusion and pointing at this section,
and the "gnubin absent (Intel path)" test asserts the no-op — so re-adding the second prefix
turns a test red rather than shipping quietly.

The alternative — an explicit `[[ "$(uname -m)" == arm64 ]]` guard — was considered and
rejected as redundant: the x86_64 prefix's absence on an arm64 machine and the arm64 prefix's
absence on an x86_64 machine are the same fact the probe already reads, and a second guard
saying it again can drift out of agreement with the first.

### Why not `.zshenv`

Rejected. It reaches every zsh invocation and no bash invocation, and every actor this change
exists for is bash: four repos' `pre-push` hooks, cron, and launchd. Adding `.zshenv` would
create new startup-file surface (there is no `~/.zshenv` today) while leaving the target
actors untouched.

### Why not per-repo hook changes

Rejected. Prepending gnubin inside each repo's `scripts/pre-push` would work, but it is four
repos today, every new hook must remember, and it does nothing for cron or launchd. The
system symlink covers all of them with one mechanism.

## Doctor check

New `_doctor_check_system_make()` in `lib/helpers.sh`, added to `run_doctor`'s check list.
Runs on macOS arm64 only; on any other platform it emits nothing.

Two assertions:

1. **Link integrity** — `/usr/local/bin/make` exists, is a symlink, and its target is
   executable.
2. **The invariant, against a clean actor** — `env -i bash -c 'command -v make'` resolves to
   `/usr/local/bin/make`.

Assertion 2 rests on bash's compiled-in default `PATH`, which is what a process with no
inherited environment receives. Measured on this machine:

```
$ env -i bash -c 'echo "$PATH"'
/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.
```

`/usr/local/bin` precedes `/usr/bin`, so the assertion is meaningful rather than
tautological. Recording the measured value here matters because the assertion silently
becomes untrue if a future bash is built with a different default, and nothing else in the
check would say so.

The second assertion is the point of the check, and its form is deliberate. Testing
`make --version` on the ambient `PATH` would report 4.4.1 on this machine **today, with no
symlink at all**, because the profile lineage already supplies gnubin. Such a check would
confirm the accident rather than the fix — precisely the failure `behavior.md` describes
under "A check derived from the same decision as the thing it checks cannot falsify it".
`env -i` is the only actor whose answer can change as a result of this work, so it is the
only actor whose answer constitutes evidence.

Where assertion 1 passes and assertion 2 fails, the check reports FAIL and names the
resolved path, because that combination means something else on the system `PATH` is
shadowing the link.

## Tests

`tests/setup_env/install_guards.bats`, driven through `_OVERRIDE_GNUBIN_ARM` and
`_OVERRIDE_SYSTEM_MAKE_LINK`. All three mandatory categories from `tdd.md` are covered.

| case                              | category         | asserts                                                        |
| --------------------------------- | ---------------- | -------------------------------------------------------------- |
| gnubin absent (Intel path)        | boundary         | rc 0; **no `sudo` line in `MOCK_CALLS_FILE`**; no link created |
| gnubin present, no link           | state transition | link created and points at the target                          |
| link already correct              | state transition | rc 0; **no `sudo` line in `MOCK_CALLS_FILE`**                  |
| link points elsewhere             | state transition | link replaced, points at the target                            |
| real file at the link path        | error path       | rc 2; file contents unchanged                                  |
| target present but not executable | boundary         | rc 0; no link created                                          |
| `MOCK_SUDO_EXIT=1`                | error path       | rc 1 propagates to the caller                                  |
| invoked twice in succession       | idempotency      | identical end state; second call issues no `sudo`              |

The two "no `sudo` line" assertions are what make the idempotency guard falsifiable. Without
them, an implementation that shells out to `sudo` unconditionally passes every other row in
this table, because the end state is the same either way.

A separate case covers `run_setup_user`'s branching: with `link_make_system_macos` stubbed to
return 2, `run_setup_user` must not report a failure, matching how it already treats
`install_git_hooks_all_repos`' rc 2.

Doctor tests use the same seams: link absent (FAIL), link present and clean actor resolving
to it (PASS), link present but clean actor resolving elsewhere (FAIL naming the resolved
path).

## Documentation

| file                                             | change                                                                                                                                                                                                                                                     |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE.md` (dotfiles)                           | Replace the make-actor bullets with the three-lineage table and the new invariant; state that arm64 machines are attested and the x86_64 mac is not                                                                                                        |
| `ai-config/.claude/standards/behavior.md`        | The actor-boundary section's `make` row currently reads `3.81 in agent shells, 4.4.1 in interactive zsh`. That row is the section's own worked example, so it is rewritten to record what was true before this change and what is true after — not deleted |
| `ai-config/.claude/standards/tdd.md`             | Pitfall G's premise ("macOS is structurally incapable of failing for the ≥4.0 class") stops holding on arm64. The pitfall itself stands; the qualifier changes                                                                                             |
| `docs/adr/0020-system-wide-gnu-make-on-macos.md` | New ADR, `Related: extends ADR-0018`. ADR-0018 recorded the interactive-only decision and stays as written — a decision record is a historical artifact                                                                                                    |
| `docs/superpowers/README.md`                     | Delete backlog rows 9 and 17; add the All Plans row                                                                                                                                                                                                        |

The two `ai-config` files are edited from this session only after messaging the live
`ai-config` peer session, per `git-workflow.md`'s concurrent-sessions rule.

## Verification

Every command below was run during design except those marked _(post-implementation)_.

**Pre-implementation, already run:**

```bash
env -i bash -c 'command -v make; make --version | head -1'   # /usr/bin/make, GNU Make 3.81
cat /etc/paths                                                # /usr/local/bin precedes /usr/bin
ls -ld /usr/local/bin                                         # drwxr-xr-x root wheel
ls /usr/local/bin/make                                        # No such file or directory
```

**Post-implementation:**

```bash
make test                       # full suite green, including the new cases
./setup_env.sh -t doctor        # new system-make check present and PASS
env -i bash -c 'command -v make'   # expect /usr/local/bin/make  (currently /usr/bin/make)
./setup_env.sh -t setup_user    # second run issues no sudo prompt for the link
```

The third command is the end-to-end proof and its current output is recorded above, so the
before/after difference is checkable rather than asserted.

**Mutation check.** Revert the `[[ -x ${_target} ]]` guard and confirm the
target-not-executable test goes red; revert the target comparison in the idempotency guard
and confirm the two "no `sudo` line" tests go red. A guard that cannot be falsified by
removing it is not being tested.

## Risks

**A machine-wide `make` change affects software that never asked for it.** Accepted
deliberately: the operator chose the widest radius over narrower options. GNU Make 4.4.1 is a
superset of 3.81 for practical purposes and the fleet's own Makefiles already target 4.x in
CI. Reversal is `sudo rm /usr/local/bin/make`, and the `doctor` check reports the state
either way — but note that reversal is not durable: the next `setup_user` run recreates the
link, and `doctor` reports the removed state as FAIL in the meantime. A permanent opt-out
means removing the call site, which is the correct friction for a machine-wide decision.

**`sudo` inside `setup_user`.** Not new — `lib/macos.sh` already calls `sudo` in
`install_homebrew` and `run_macos_update`. The idempotency guard means the prompt appears
only when the link is absent or wrong.

**A future Homebrew layout change could move gnubin.** The link points at
`/opt/homebrew/opt/make/...`, which is Homebrew's version-stable `opt` path rather than a
`Cellar` version directory, so a `brew upgrade make` does not break it. If the formula is
uninstalled the link dangles — which the `doctor` check reports as FAIL, and which
`link_make_system_macos` will not itself create.

**Tests that were structurally unable to fail locally can now fail.** `tdd.md` pitfall G
records that a mac could not exercise the ≥4.0 print-directory class. On arm64 that stops
being true for clean actors. This is the intended effect, but it may surface a latent failure
in the existing guarded/measuring partition; the full suite must be green before merge, and a
new failure there is a finding rather than a regression introduced by this change.

## Out of scope

- `.zshenv`, and any change to `6_path.zsh` — the interactive path already works.
- Changes to `math`, `etch-cli`, or `state-ledger` hooks — the symlink covers them.
- The x86_64 mac, deliberately, per the arm64-only decision above.
- The dead `push-bash-coverage` crontab entry, which is a separate backlog row with its own
  two independent failures.

---

## Multi-Lens Review

Reviewed at commit: `71b119d` (Step 7 self-review commit, before Step 8 dispatch)

All three lenses independently reached the same conclusion: **the proposed mechanism cannot
reach any of the actors this design exists for.** The finding is recorded per lens below, but
it is one finding, found three times.

### Goal-Fit

Finding: The yield table's four beneficiaries — cron, launchd agents, IDE-spawned git,
`ssh host 'git push'` — are all unreachable from a symlink at `/usr/local/bin/make`, because
none of their `PATH`s contains `/usr/local/bin` ahead of `/usr/bin` and most do not contain
it at all. `/usr/local/bin` leads `/usr/bin` in `/etc/paths`, which governs **login shells**
via `path_helper`; cron and launchd never consult it and use compiled-in constants instead
(`_PATH_DEFPATH` = `/usr/bin:/bin`, `_PATH_STDPATH` = `/usr/bin:/bin:/usr/sbin:/sbin`). By
the reads-it test the symlink is decoration: it changes no decision, because every actor that
can see it already resolves gnubin by another route. The doctor check is a real gate but
asserts the wrong invariant — a probe derived from the mechanism (a link at
`/usr/local/bin`) rather than from the goal (real non-interactive actors running 4.x).

Assumption: That every routine gate on this machine already runs at 4.4.1 — i.e. that no
editor-spawned `git` invokes `scripts/pre-commit` through a launchd-inherited `PATH`.
Settled by adding `make --version >> /tmp/hookmake.log` to the hook and committing once from
an editor UI and once from a terminal.

Disposition:

### Ergonomics

Finding: Same central kill, plus two defects in the test design that would have shipped.
(1) The `MOCK_SUDO_EXIT=1` case is structurally inert — `tests/mocks/sudo` execs its target
when resolvable, the very property the spec cites approvingly, so it never reaches its own
`exit` statement; measured `MOCK_SUDO_EXIT=1 sudo ln -sfn ... → rc=0`. It was the only
error-path test for the `|| return 1` branch. The working lever is `MOCK_LN_EXIT=1`.
(2) The doctor PASS case has no honest construction: `env -i` clears the environment by
definition, so `_OVERRIDE_SYSTEM_MAKE_LINK` cannot reach assertion 2's probe, and any seam
added to make it reachable makes the test measure the seam. Also raised: the `sudo` prompt
fires bare on 100% of first runs with no `log_info` naming its purpose; no doctor FAIL names
a remedy, below the bar the `core.hooksPath` check already sets; and doctor emits nothing on
the x86_64 mac, the one machine the design knowingly leaves unattested.

Assumption: That `/usr/local/bin` appears on the `PATH` of the non-interactive actors this
change exists for. Settled by `sudo launchctl config user path` and a throwaway one-minute
crontab entry capturing `$PATH`.

Disposition:

### Risk

Finding: Same central kill, measured by submitting a real launchd job rather than inferring
(`PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `command -v make` → `/usr/bin/make`). Two further
defects. (1) The `[[ -d ${_gnubin} ]] || return 0` guard fires **before** the link is
inspected, so `[[ -x ]]` makes the dangling-link state unreachable at creation and entirely
unguarded afterwards — which is where it actually arises. On `brew uninstall make`, every
clean actor's `make` becomes `ENOENT` rather than 3.81, `setup_user` returns 0 and repairs
nothing, and no test row covers "gnubin absent and stale link present". (2) No `mkdir -p` on
the link's parent; `/usr/local/bin` exists on this machine only because Docker Desktop, AWS
CLI and VirtualBox created it, and its absence would turn an attestation feature into a
provisioning abort. Proportionality: `/usr/local/bin` is the one directory in this design
dotfiles does not own — 27 entries from unrelated vendors.

Assumption: That at least one real, non-synthetic actor resolves through `/usr/local/bin`
ahead of `/usr/bin`. Settled by `ssh <host> 'echo "$PATH"; command -v make'`.

Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

---

## Post-review measurement

The assumption named by the Risk lens was measured immediately, and it is negative:

```
$ ssh -o BatchMode=yes localhost 'echo "PATH=$PATH"; command -v make; make --version | head -1'
PATH=/usr/bin:/bin:/usr/sbin:/sbin
/usr/bin/make
GNU Make 3.81
```

Four independent measurements now agree that no real actor on this machine resolves through
`/usr/local/bin` ahead of `/usr/bin`:

| actor | PATH | source of that PATH |
| --- | --- | --- |
| cron | `/usr/bin:/bin` | compiled `_PATH_DEFPATH`, stamped into every child |
| launchd job | `/usr/bin:/bin:/usr/sbin:/sbin` | compiled `_PATH_STDPATH`; `launchctl getenv PATH` unset |
| `ssh host '<cmd>'` | `/usr/bin:/bin:/usr/sbin:/sbin` | sshd; non-login zsh never calls `path_helper` |
| `env -i bash -c` | `/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.` | bash 3.2.57 compiled default — **synthetic** |

The problem the spec set out to solve is real and is confirmed by these same measurements:
every one of those actors resolves GNU Make **3.81** today. What is falsified is the
mechanism, not the problem.

**Status: this design is retired.** `/usr/local/bin` governs login shells, which already
resolve gnubin through `.zprofile`/`6_path.zsh`, so the symlink's entire observable effect
would have been to change the answer of a probe the same design introduced. A replacement
design must target the compiled-in constants directly — `launchctl config user path` for the
launchd tree (which sshd, IDEs and their child `git` processes inherit), and a `PATH=` line
in the crontab for cron — or abandon the environment approach and prepend gnubin inside each
repo's hooks.
