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

**`_OVERRIDE_SYSTEM_MAKE_LINK` is a test seam** so no test ever writes to `/usr/local/bin`.
`tests/mocks/sudo` execs its target when resolvable and `tests/mocks/ln` passes through to
`/bin/ln`, so a fixture link is really created and tests assert on real filesystem state
rather than on a mock's return code.

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
either way.

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
