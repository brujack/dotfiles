# GNU coreutils precedence on Ubuntu 26.04 (resolute)

**Date:** 2026-09-13
**Status:** Design — approved by operator, pending Multi-Lens Review

## Problem

Ubuntu 26.04 ships **uutils coreutils** as the system provider. Its `sort -u` collates two
keys differing only by punctuation as equal under a UTF-8 locale and discards one; GNU does
not.

Measured on `claude` (26.04), 2026-09-13:

```
/usr/bin/sort -> /usr/lib/cargo/bin/coreutils/sort      sort (uutils coreutils) 0.8.0
dpkg -S /usr/bin/sort                                    coreutils-from-uutils
```

The 24.04 box (`workstation`) shipping GNU 9.4 is **recorded in
`ai-config-uutils-sort-collates-punctuation-equal`, not re-measured here** — cited rather
than claimed.

### The observable

`pytest` has no pyenv shim on `claude`, breaking bare-`pytest` Makefile targets. Measured
against that box's real `PYENV_ROOT` (versions `3.14.6` and `ansible`):

```
pyenv versions --executables              names=148  pytest=0  py.test=1
LC_ALL=C pyenv versions --executables     names=149  pytest=1
```

148 matches the shims directory exactly. Exactly one name is lost and it is `pytest`,
because `py.test` collides with it.

### Where it actually comes from

The culprit is **pyenv core**, `libexec/pyenv-versions:47`, whose output feeds
`pyenv-rehash:193`'s `make_shims $(pyenv-versions --executables)`. pyenv and
pyenv-virtualenv are **brew-installed** — `~/.pyenv` holds only `bin`, `cache`, `shims`,
`versions`, and `~/.pyenv/plugins` is empty — so the code lives under
`/home/linuxbrew/.linuxbrew/Cellar/`.

`pyenv-virtualenv/1.4.0/etc/pyenv.d/rehash/envs.bash:10` contains a second `sort -u`. The
core enumeration **alone** reproduces the loss (148 vs 149), so core is sufficient to
explain it; this spec does not claim the plugin's call is harmless, only that it is not
required to produce the observed defect.

Upstream has not fixed either site. pyenv 2.8.5 / pyenv-virtualenv 1.4.0 are the versions
installed on `claude`, and `brew outdated` there lists neither — so this is a statement
about that box's brew, not about what upstream has released. PR #3410 ("Drop redundant `sort -u` from `make_shims`
call") removed a _different_, redundant call; `pyenv-rehash:193` is now clean and
`pyenv-versions:47` is not.

## Decision

Install GNU coreutils from linuxbrew and prepend its `gnubin` directory to `PATH` on
resolute. Operator chose this over patching pyenv after being shown that the apt route is
unavailable.

### Why not the package manager

`apt` **cannot** make GNU the system provider on 26.04 while keeping `build-essential`.
Every figure in this section comes from `claude`'s apt cache, measured 2026-09-13; no other
26.04 box was checked, so the claim is about this machine's package set rather than about
the release in general:

```
build-essential Depends: ..., coreutils-from-uutils      <- pins the provider BY NAME
coreutils-from-gnu Conflicts: coreutils-from             <- which uutils provides
```

`apt -s install coreutils-from-gnu` and the combined `install coreutils-from-gnu
build-essential` both fail with unsatisfiable dependencies. Only `remove
coreutils-from-uutils` resolves, and it removes `build-essential` — which is manually
marked and load-bearing, since pyenv compiles Python from source on this box.

### Alternatives considered and rejected

| Option                                 | Why rejected                                                                                                                                                                                                                                                                                                                                                |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apt install coreutils-from-gnu`       | Unsatisfiable, see above. Not a trade-off — it does not work.                                                                                                                                                                                                                                                                                               |
| `dpkg-divert /usr/bin/sort`            | The only genuinely machine-wide route that survives the `build-essential` pin (23 diversions already exist on the box, so the mechanism is established there). Rejected as disproportionate: it fights the package manager, needs re-asserting after coreutils updates, and silently changes one binary's behaviour with nothing in the repo explaining it. |
| Patch `pyenv-versions:47` post-install | The vendored-patch burden the operator rejected, and worse than first described: the file is pyenv **core** in the brew Cellar, erased by every `brew upgrade pyenv`, and the repair would need its own test proving the patch is still applied.                                                                                                            |
| Export `LC_ALL=C` narrowly             | Discarded by the operator's choice. Recorded so the arm is visible rather than absent.                                                                                                                                                                                                                                                                      |

## Design

### 1. Install — `lib/linux_ubuntu.sh`

A guarded call **after** the formula loop in `_install_ubuntu_brew_packages`, matching how
`shfmt`, `snyk` and `codex` are already handled there rather than adding the first
conditional to a flat list:

```bash
# uutils `sort -u` collates names differing only by punctuation as equal and drops
# one; pyenv-versions:47 pipes the shim list through it, losing `pytest` to `py.test`
# (148 names against 149 under C collation, measured on claude 2026-09-13).
# Resolute only: noble ships GNU already and needs no second copy, and prepending a
# gnubin there would change every coreutils binary on a box with no defect.
if [[ -n ${RESOLUTE} ]]; then
  brew_install_formula coreutils || _failed+=(coreutils)
fi
```

`RESOLUTE` is already read in this file (`:39`, `:68`), so the gate needs no new plumbing.
Failure feeds `_failed`, so it flows into the documented rc-2 partial-success contract
rather than aborting a provision.

Install is clean on the target box, measured: `b2sum`, `gfold` and `idutils` — the
formula's declared conflicts — are all absent; `brew install --dry-run coreutils` would
install `coreutils`, `acl`, `attr`, with `gmp` already present.

### 2. PATH — `.config/.zshrc.d/6_path.zsh`

Inside the existing `LINUX` block:

```bash
_gnubin_linux="${_OVERRIDE_GNUBIN_LINUX:-/home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin}"
[[ -d ${_gnubin_linux} ]] && path=(${_gnubin_linux} $path)
unset _gnubin_linux
```

Three properties are deliberate:

- **Prepend, never `path+=`.** This file's existing comment records that an append leaves
  `/usr/bin` ahead of anything added, so it would be inert _and still look correct_.
- **Plain `${VAR:-default}` is safe here.** The rustup block below replaces its candidate
  list instead, but only because it has three candidates a nonexistent override could fall
  through to. There is one candidate here, so there is nothing to fall through to.
- **Self-gates on directory existence, not on `RESOLUTE`.** The install decides where the
  directory exists, so one gate is enough and the zsh side needs no release check.

`typeset -U path` at line 1 provides dedup.

**Placement inside the `LINUX` block is free, and that is worth stating because the lines
around it are appends.** An append's position matters relative to other appends; a prepend's
does not — `path=(${_gnubin_linux} $path)` puts the directory ahead of everything the block
has added or will add, whichever order the lines run in. Put it wherever it reads best; a
reviewer moving it up or down has not changed the resolved `PATH`.

## Verification

The mechanism is already proven on the target box, non-destructively, before any code
exists — a wrapper forcing C collation, prepended to `PATH`:

```
baseline                       names=148  pytest=0
with wrapper prepended         names=149  pytest=1
```

So `PATH` ordering demonstrably reaches pyenv's `sort`. This rules out the failure mode
where the tool resolves its helpers absolutely or runs under a sanitised environment.

Acceptance after implementation, run on `claude`:

```bash
pyenv rehash && test -x ~/.pyenv/shims/pytest && pyenv versions --executables | grep -cx pytest
```

Expect the shim to exist and the count to be 1.

## Testing

New cases in `tests/zshrc.d/unit.bats`, mirroring the four that already cover the macOS
gnubin pair: present, absent, deduped across repeated sourcing, and `_gnubin_linux` not
leaking after sourcing.

**One existing test must change, and this is the load-bearing test note.**
`tests/zshrc.d/unit.bats:492` — _"6_path.zsh adds no gnubin entry under LINUX, but still
adds a known Linux path"_ — asserts `NO_GNUBIN` under `LINUX=1` while setting only the two
macOS seams. With no `_OVERRIDE_GNUBIN_LINUX` it falls through to the real default. That
path does not exist on the Studio, so the test stays green there, and **will exist on
`claude` and `workstation` once coreutils is installed, turning it red on exactly the
machines the change targets** — while the pre-push hook runs `make test` on those boxes.
This is predicted from reading the test, not measured, because it cannot be measured until
the formula is installed. The repair is to set `_OVERRIDE_GNUBIN_LINUX` to a nonexistent
path there, giving it the same determinism the macOS seams already have two lines above.

A case in `tests/setup_env/` covering the install, both branches of the `RESOLUTE` gate.

`tests/setup_env/install_guards.bats:348` (_"gnubin prefixes match between lib/macos.sh and
6_path.zsh"_) is **unaffected** — measured: its regex is anchored to
`/(opt/homebrew|usr/local)/opt/make/libexec/gnubin`, which does not match a linuxbrew
coreutils path.

## Known limitation

This reaches only shells that source `6_path.zsh` — interactive zsh. `cron`,
`ssh host '<cmd>'` and systemd units keep uutils. Accepted because the actors that trigger
a rehash are interactive: `setup_env.sh` on Linux already cannot run non-interactively
(brew reaches `PATH` only through this same file), and pip/uv/pyenv invocations are the
operator's own. Stated here rather than discovered later, and it is the reason this is
_not_ the machine-wide change originally requested.

## ADR

Warranted. This is a toolchain-precedence decision with alternatives that were weighed and
measured, closer in kind to ADR-0029 (gate GPU provisioning on hardware, not a profile
capability) than to a routine flag change. To be written alongside the implementation.
