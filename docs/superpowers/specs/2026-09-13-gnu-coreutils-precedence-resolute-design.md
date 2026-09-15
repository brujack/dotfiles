# GNU coreutils precedence on Ubuntu 26.04 (resolute)

**Date:** 2026-09-13
**Status:** Design — Multi-Lens Review complete (3 lenses, 2026-09-15); operator
dispositioned every finding. Next step: `writing-plans`.

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

| Option                                 | Why rejected                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apt install coreutils-from-gnu`       | Unsatisfiable, see above. Not a trade-off — it does not work.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `dpkg-divert /usr/bin/sort`            | The only genuinely machine-wide route that survives the `build-essential` pin (23 diversions already exist on the box, so the mechanism is established there). Rejected as disproportionate: it fights the package manager, needs re-asserting after coreutils updates, and silently changes one binary's behaviour with nothing in the repo explaining it.                                                                                                                                                                                                                                                                                       |
| Patch `pyenv-versions:47` post-install | The vendored-patch burden the operator rejected, and worse than first described: the file is pyenv **core** in the brew Cellar, erased by every `brew upgrade pyenv`, and the repair would need its own test proving the patch is still applied.                                                                                                                                                                                                                                                                                                                                                                                                  |
| Export `LC_ALL=C` narrowly             | A one-line `pyenv() { LC_ALL=C command pyenv "$@" }` fixes the measured defect exactly, with no package and no PATH reorder — so the coreutils route needs a reason this row originally did not give. The reason is **CI parity**: `claude`'s `pre-push` runs `make test` while CI runs `ubuntu-latest` (GNU 9.4), so today the _gating_ actor and CI disagree across 104 binaries — `tdd.md` pitfall G, where a local pass is not evidence. Installing GNU makes the gate match CI; the one-liner does not. Operator re-affirmed the coreutils route on 2026-09-15 after being shown the 26-binary install-time radius (as counted at the time; the correct count is 27 — see the Known limitation correction below) and the 3–4 broken tests. |

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
# NOTE the asymmetry: this gate is release-based, but the PATH half (section 2)
# gates on directory existence, so it is release-BLIND. If coreutils ever arrives
# on noble as a transitive brew dependency, that box silently gets the precedence
# change this comment argues against. Measured 2026-09-15: workstation has no
# linuxbrew coreutils today, so there is no divergence now — but nothing holds it.
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

**CORRECTED 2026-09-15 (Multi-Lens Review). Three to four tests break, not one, and the
mechanism is not the one described below.** Measured on `claude` by inserting this
spec's own block into a copy of `6_path.zsh` with its default pointing at a directory
that exists: `:355`, `:407` and `:492` go RED, and `:372` is byte-identical in construct
to `:355`. `:355`/`:372` assert `path[1]` equals the macOS gnubin tmpdir, and the new
prepend displaces it — an **ordering** failure that no `_OVERRIDE_*` seam repairs.
The root cause is pre-existing and already forbidden: `.config/.zshrc.d/1_init.zsh:3`
is `export LINUX=1`, which reaches bats grandchildren, while `:355`, `:372`, `:389` and
`:407` set `MACOS=1` and never unset `LINUX` — exactly what `CLAUDE.md:389` forbids
(_"A test whose outcome depends on OS detection must set the variables itself ... never
inherit them"_). The repair is `unset LINUX MACOS` plus explicit sets in each gnubin
test, **not** a fifth seam. Operator dispositioned this into THIS change (2026-09-15),
because `scripts/pre-push` runs `make test` and the branch would otherwise block every
push from `claude`. The original note is kept below as written, since it records what
was predicted rather than measured:

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

**CORRECTED 2026-09-15: this is false for 27 binaries, and false at INSTALL time,
independent of the PATH edit.** Homebrew's `coreutils.rb` sets `no_conflict` to an empty
list only on macOS; on Linux it is a 27-name list, and `bin.install_symlink "g#{cmd}" =>
cmd` runs unconditionally. The formula is not keg-only, so those names link into
`/home/linuxbrew/.linuxbrew/bin`, which `6_path.zsh:55-57` already appends — measured at
PATH index 5 on `claude`, ahead of `/usr/bin` at index 10. So `brew_install_formula
coreutils` alone replaces, for every actor with linuxbrew on PATH: `b2sum base32 basenc
chcon dir dircolors factor hostid md5sum nproc numfmt pinky ptx realpath runcon sha1sum
sha224sum sha256sum sha384sum sha512sum shred shuf stdbuf tac timeout truncate vdir`.
`sort` is **not** among them, so section 2's prepend is still genuinely required.

**CORRECTED again, 2026-09-15 (second pass, ADR-0031 Multi-Lens Review): the count directly
above was itself wrong — 26, omitting `chcon` and `runcon`, is now 27.** The direction
stated in this section was already correct: `bin.install_symlink "g#{cmd}" => cmd` names,
on the right of `=>`, the unprefixed target, so each name **in** `no_conflict` is the one
that gets the unprefixed link — only the count drifted here, and only here. The direction
was inverted later, while this section was being paraphrased into the ADR, and both ADR
reviewers derived the correction independently from the formula rather than from each other
or from this spec.

Repo impact, measured 2026-09-15 across `lib/ scripts/ .config/ setup_env.sh tests/`:
exactly **one** live executable call site — `lib/linux_ubuntu.sh:164`'s `sha256sum -c -`,
the rustup signature gate, which `tests/setup_env/linux_ubuntu.bats:358-360` deliberately
does not mock so the digest check runs for real. Every other hit is prose in comments.
GNU is the reference implementation uutils reimplements, so this moves that path toward
CI's behaviour rather than away from it. No `tests/mocks/` entry collides with any of the 27. Accepted by the operator on that basis.

The rest of this section is correct as written:

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

## Multi-Lens Review

Three independent lenses, dispatched 2026-09-15 as fresh agents with no prior context, against
this spec as committed at `05286e42`. Every lens was required to verify the spec's load-bearing
premise with a command and to name one falsifiable assumption. **All three named assumptions were
tested and all three were refuted** — the design survived its own adversarial review on mechanism,
and the findings below are about scope, observability and accuracy rather than about soundness.

### Findings and dispositions

| #   | Finding                                                                                                                                                        | Disposition                                                                                                                                                                                                                                                                                                   |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | The Known limitation is false for 27 binaries, and false at install time independent of the PATH edit                                                          | **Addressed** — corrected in place above, with the measured one-call-site repo impact. Count corrected again 2026-09-15 (second pass, ADR-0031 Multi-Lens Review): the "26" written here was itself wrong, omitting `chcon` and `runcon` — see the second `CORRECTED` note above the Known limitation's list. |
| F2  | "One existing test must change" understates by 3; the mechanism is an ordering failure no seam repairs; root cause is a pre-existing `CLAUDE.md:389` violation | **Addressed** — corrected above; operator scoped the test-hygiene fix into this change                                                                                                                                                                                                                        |
| F3  | Nothing reads the fix after the session: install failure degrades to a WARN, the PATH arm has no else, and the acceptance line writes to no file               | **Addressed** — a `_doctor_check_*` arm asserting the GNU _provider_ (`sort --version` contains `GNU`), not directory existence, is added to the plan                                                                                                                                                         |
| F4  | ~10 expected verdicts, all PASS, 3–4 satisfied equally by a dead mechanism (absence assertions with `2>/dev/null` sourcing)                                    | **Addressed** — plan pairs each absence assertion with the positive control already used at `:407`, and adds one discriminating case — `printf 'py.test\npytest\n' \| sort -u \| wc -l` must equal **2** (2 under GNU, 1 under uutils)                                                                        |
| F5  | `:173-178` names `workstation`, which is 24.04, is `RESOLUTE`-gated out, and never receives the formula                                                        | **Addressed** — corrected; caught independently by two lenses                                                                                                                                                                                                                                                 |
| F6  | The `LC_ALL=C` arm was dismissed with a ruling rather than a reason, and the argument that carries the 104-binary mechanism (CI parity) was absent             | **Addressed** — the Alternatives row now states the reason; operator re-affirmed the route knowing the costs                                                                                                                                                                                                  |

### Assumptions named, and their refutations

- **goal-fit — "no actor outside interactive zsh triggers `pyenv rehash`"**, the concern being that
  shims are last-writer-wins, so a uutils-side rehash would _delete_ the restored `pytest` shim and
  the fix would oscillate. **Refuted.** `bash -lc` on `claude` returns `NO_PYENV_ON_PATH` and
  `NO_BREW_ON_PATH`; that actor's PATH is the compiled default with no linuxbrew. `setup_env.sh:30`
  gates on `env which brew` and exits 1, and both `pyenv rehash` callers (`lib/developer.sh:537,567`)
  sit behind it.
- **ergonomics — the same assumption, reached from the observation that `~/.pyenv/shims` had been
  rewritten that afternoon by an unknown writer. Refuted, and the writer identified**: the review
  itself. `shims` mtime `16:15:03`, `py.test` `16:12:35`, both inside the lens run window. No
  runner-owned pyenv exists (`/opt/github-runner-*/.pyenv` — no matches across 12 runner dirs), the
  runner unit's hardcoded `Environment=PATH=` cannot reach pyenv, and no systemd timer touches it.
- **risk — "placing gnubin at global PATH index 1 is safe ahead of the four pyenv/rbenv shim
  directories it will now outrank"**, the concern being that a GNU binary could silently shadow a
  Python or Ruby entry point. **Refuted by measurement: 0 collisions** between 164 shim names
  (148 pyenv + 16 rbenv) and 104 gnubin names. The check carries a positive control — `sort` is
  present in the gnubin set and a seeded name returns through `comm` — so the zero discriminates.

### A lens disagreement, resolved by measurement

Ergonomics dismissed the shadowing risk on the grounds that `7_final.zsh:59` re-prepends shims after
`6_path.zsh`, so shims stay ahead. That is wrong: `7_final.zsh:56` only does
`export PATH="$PYENV_ROOT/bin:$PATH"`, and only `if ! command -v pyenv`. Shim ordering comes from
`.zprofile:9` (`eval "$(pyenv init --path)"`) and `.zprofile:12` (rbenv), which run at **login,
before** `.zshrc.d`. Measured interactive `$path` on `claude` begins: pyenv-virtualenv shims,
`~/.rbenv/shims`, pyenv-virtualenv shims, `~/.pyenv/shims`, then `linuxbrew/bin` at 5 and `/usr/bin`
at 10. So the prepend does land at index 1 ahead of all four, as risk argued — which is precisely
why the collision check above was required rather than optional.

### Instrument note

Four probes during this review returned well-formed wrong answers rather than errors: `ls` aliased
to long format inflating a count; `comm` fed input sorted by the very uutils `sort` under review;
`brew` absent from a non-interactive `ssh`; and `for n in ${NAMES}` not splitting under zsh, which
produced a clean `0 hits` for all 26 names that contradicted evidence already in hand. Only the last
was caught by a positive control rather than by noticing. Recorded because the acceptance checks in
this spec are themselves absence assertions, which is the same shape.
