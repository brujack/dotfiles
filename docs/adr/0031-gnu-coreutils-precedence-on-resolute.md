# ADR-0031: GNU coreutils precedence on resolute (Ubuntu 26.04)

**Date:** 2026-09-15
**Status:** Accepted

**Amended by [ADR-0032](0032-pyenv-rehash-hook.md):** this ADR's `PATH` fix reaches
interactive zsh only. ADR-0032 adds a tracked pyenv rehash hook for the four actors that
call `pyenv rehash` without ever sourcing `6_path.zsh` — login zsh's own `pyenv init
--path`, `lib/developer.sh`'s two rehash call sites, `ssh claude '<cmd>'`, and pyenv's
own `install`/`virtualenv` subcommands.

## Context

Ubuntu 26.04 ships **uutils coreutils** as `/usr/bin/sort` and friends, not GNU. uutils'
`sort -u` collates two keys differing only by punctuation as equal under a UTF-8 locale and
discards one; GNU does not.

That divergence is not academic. pyenv core (`libexec/pyenv-versions`) feeds its executable
enumeration through `sort -u` before generating shims. `py.test` and `pytest` collide under
uutils' collation, one is dropped, and pyenv silently stops emitting a `pytest` shim — every
bare-`pytest` Makefile target on the box breaks. Measured on `claude`: `pyenv versions
--executables` returns 148 names with `pytest` absent and `py.test` present; forcing
`LC_ALL=C` returns 149 with both. Upstream has not fixed the `pyenv-versions` call site.

**Why not apt.** The obvious fix — `apt install coreutils-from-gnu` — is unsatisfiable.
`build-essential` depends on `coreutils-from-uutils` by name, and `coreutils-from-gnu`
conflicts with whatever `coreutils-from-uutils` provides, so installing it would remove
`build-essential`. apt cannot make GNU the system provider on this release; nothing short
of `dpkg-divert`-ing `/usr/bin/sort` can, and that was rejected as disproportionate — it
fights the package manager, needs re-asserting after every coreutils update, and silently
changes one binary's behavior fleet-wide with nothing in the repo explaining it.

**Why not `LC_ALL=C` at the call site.** A one-line `pyenv() { LC_ALL=C command pyenv
"$@" }` wrapper fixes the measured defect exactly, with no new package and no `PATH`
reorder. It was rejected for **CI parity**, not preference: the box that runs the gating
`pre-push` hook and the `ubuntu-latest` runner that runs CI already disagree on coreutils
provider — measured at 104 binaries differing between uutils and CI's GNU 9.4, the same
104-name set named again below as "gnubin names" (the full command list the coreutils
formula installs unprefixed into `libexec/gnubin`, counted on `claude` during the Step 8
collision check, 2026-09-15; the Studio cannot confirm it — macOS ships neither `chcon`
nor `runcon`, and its gnubin holds 102 commands; and re-counted on `claude` after the
formula actually installed, the gnubin directory holds **103** entries at coreutils
9.12, so the difference-set and the gnubin name-set are near-identical rather than the
same set — the 104 stands as the figure measured during the Step 8 review and is not
restated here) — which is `tdd.md` pitfall G, a local pass that is not evidence for
what CI will do. Installing GNU
coreutils locally makes the gating actor match CI instead of diverging further from it; the
wrapper would not.

## Decision

Two changes, gated by two different predicates, and the asymmetry is deliberate.

**The install is release-gated.** `_install_ubuntu_brew_packages` in `lib/linux_ubuntu.sh`
runs `brew_install_formula coreutils` only when `RESOLUTE` is set, feeding the existing
tri-state `_failed+=()` contract rather than aborting the bootstrap on failure. 24.04 and
earlier already ship GNU, so installing a second copy there would be pure cost.

**The `PATH` edit is release-blind.** `.config/.zshrc.d/6_path.zsh` prepends
`${_OVERRIDE_GNUBIN_LINUX:-/home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin}` to
`path` inside the existing `LINUX` block, gated only on `[[ -d ${_gnubin_linux} ]]` — no
`RESOLUTE` check. A reader will want to "fix" this to match the install's gate. Don't: the
directory test verifies the artifact the shell actually needs (a resolvable gnubin path),
where a release-string gate would verify a proxy for it. A hand install, a future
non-24.04-vs-26.04 release split, or an operator who installs the formula for an unrelated
reason all produce the directory without `RESOLUTE`, and the prepend should fire in every
one of those cases. The consequence of firing early is benign — Homebrew's GNU coreutils
ahead of the distro's GNU coreutils on 24.04 is a version bump, not a semantic change.

It must be a **prepend**, matching the existing `make` gnubin convention in this same file
(see the Key Conventions bullet in `CLAUDE.md`): every other entry in this block is
appended via `path+=`, which lands behind `/usr/bin` (index 10 on `claude`) and would leave
the change completely inert while still reading as correct to a reviewer.

**The install has a side effect the `PATH` edit does not cause.** Homebrew's `coreutils.rb`
sets its `no_conflict` list to empty only on macOS; on Linux it lists `b2sum base32 basenc
chcon dir dircolors factor hostid md5sum nproc numfmt pinky ptx realpath runcon sha1sum
sha224sum sha256sum sha384sum sha512sum shred shuf stdbuf tac timeout truncate vdir`. The
formula's `no_conflict.each { |cmd| bin.install_symlink "g#{cmd}" => cmd }` links every
name **in** that list unprefixed into `/home/linuxbrew/.linuxbrew/bin` — the direction is
load-bearing: everything else is installed only as `g<cmd>` there, reachable unprefixed
solely through `libexec/gnubin`. That `bin` directory is already appended to `path` by
this same file, at index 5 on `claude`, ahead of `/usr/bin` at index 10 — so those
binaries change provider at **brew-install time**, independent of and before this change's
prepend ever runs. `sort` is not on the list, which is why the prepend is still required
to fix the defect this ADR exists for.

Repo-wide impact of that install-time shift was measured across `lib/ scripts/ .config/
setup_env.sh tests/`: exactly one live executable call site, the rustup signature gate in
`lib/linux_ubuntu.sh` (`sha256sum -c -` against a pinned digest), and its test
(`tests/setup_env/linux_ubuntu.bats`) deliberately does not mock `sha256sum`, so the real
GNU binary now runs the real check. GNU is the reference implementation uutils
reimplements, so this moves that call site toward CI's behavior, not away from it.

**A doctor arm asserts the provider, not the directory.** `_doctor_check_gnu_coreutils` in
`lib/helpers.sh` is gated on `RESOLUTE` and branches on `sort --version` into four
outcomes, not two. A literal `(GNU coreutils)` match — not a bare `*GNU*`, since
`version_etc` emits the package name untranslated and a bare match would pass a future
non-GNU banner that merely mentions GNU — passes. Empty output fails, naming the failure
"could not determine the provider": `sort` absent from `PATH`, rejecting `--version`, and
not executable are three distinct states behind that emptiness, and none of them means
"not GNU" — asserting a provider verdict there would claim a probe that never ran, which is
the three-valued-outcome distinction this branch spent two review rounds winning. A gnubin
directory existing is explicitly **not** sufficient on its own to explain a non-GNU result:
the same directory exists for an interactive shell whose prepend has regressed (block
deleted, `opt` path renamed, a shadowing `PATH` entry earlier in the file) as for one where
it works. The arm distinguishes that regressed-prepend case from a third, non-regression
cause — `-t doctor` is one of two `-t` workflows (`doctor`, `check-versions`) that bypass
the brew prereq check (`--brew-install` is a third bypass, but a flag rather than a
workflow), so `doctor` is reachable non-interactively (`ssh`, cron, launchd), while
`6_path.zsh` is sourced by interactive zsh only. Reaching the doctor check from a
non-interactive actor on an otherwise-healthy machine produces "directory present, not on
this shell's `PATH`" — rendered as a **warning**, not a failure, because a FAIL there would
carry the `setup_env.sh -t setup` remedy, which fixes nothing for an actor that was never
going to source `6_path.zsh` in the first place. The remaining cases — the gnubin directory absent because the formula was
never installed, or present and on `PATH` with `sort` still not GNU — fail.

## Consequences

**Good.** The pyenv shim defect is fixed at its root — a non-GNU `sort -u` — rather than
patched at pyenv's one known call site, so any other tool on the box relying on GNU
collation semantics is fixed the same way. The gating actor (`claude`'s `pre-push`) now
matches CI's coreutils provider instead of diverging from it further. The doctor arm makes
a regressed prepend or a genuinely non-GNU `sort` visible without conflating them with a
merely-non-interactive actor.

**Costs, accepted.**

- The install unprefixes the `no_conflict` list's binaries into `linuxbrew/bin` at
  install time, ahead of `/usr/bin`, independent of this ADR's `PATH` prepend. One live
  call site is affected (the rustup `sha256sum` signature check) and it was accepted
  deliberately rather than overlooked — moving toward the reference implementation is the
  safer direction.
- The prepend lands at global `PATH` index 1, ahead of all four pyenv/rbenv shim
  directories (pyenv-virtualenv, `~/.rbenv/shims`, pyenv-virtualenv again, `~/.pyenv/shims`
  — that ordering itself set at login by `.zprofile`, before `.zshrc.d` runs). A GNU
  coreutils name could in principle shadow a Python or Ruby shim sharing that name.
  Measured: **0 collisions** between 164 shim names (148 pyenv + 16 rbenv) and the same
  104 gnubin names cited above, with a positive control (`sort` is present in the gnubin
  set and a seeded name returns through `comm`) so the zero discriminates rather than
  reflecting a broken probe.
  Nothing re-runs that check on an ongoing basis — a future pyenv or rbenv entry point that
  happens to share a coreutils name would shadow silently, and this paragraph is the only
  record of the risk having been checked once.
- This reaches only shells that source `6_path.zsh` — interactive zsh. `cron`,
  `ssh host '<cmd>'`, and systemd units keep uutils. Accepted because `setup_env.sh`
  already cannot run non-interactively on Linux for an unrelated reason (`brew` itself is
  only on `PATH` for an interactive shell), and every `pyenv rehash` call site in this repo
  runs under `lib/developer.sh`, reached from an interactive setup.

**Not covered by this ADR.** Whether `dpkg-divert` or an upstream pyenv fix ever supersedes
this is a future decision; nothing here forecloses it. The doctor arm's `RESOLUTE` gate
means a future release that ships GNU coreutils again would need this ADR revisited rather
than silently continuing to install a formula nobody needs — not automated, and not
expected to be silently correct.

## Related

- [ADR-0018](0018-gnu-make-4-on-macos.md) — the same prepend-not-append `PATH` convention,
  for a different tool and platform; also the origin of the interactive-shell actor
  boundary this ADR's doctor arm re-applies. ADR-0018 named this exact widening in
  advance — "a future change that widens the prepend beyond this single directory —
  `coreutils`' `gnubin` holds ~100 binaries against this one's single `make` — is a
  materially different trade and should be argued on its own terms, not inherited from
  this decision" — so this ADR is that argument, not a silent extension of ADR-0018's
  decision.
- [ADR-0029](0029-gate-gpu-provisioning-on-hardware-not-capability.md) — nearest peer in
  shape: a provisioning decision with measured, rejected alternatives and an accepted,
  named cost rather than a silent one
- `docs/superpowers/specs/2026-09-13-gnu-coreutils-precedence-resolute-design.md` — the
  spec this shipped under, including the Multi-Lens Review that found and corrected the
  install-time side effect and required the collision measurement
- `CLAUDE.md` Test Seams (`_OVERRIDE_GNUBIN_LINUX`) and Key Conventions (the gnubin
  prepend bullet) — the seam and convention this decision introduces
