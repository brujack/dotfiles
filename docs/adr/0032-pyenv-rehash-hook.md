# ADR-0032: A tracked pyenv rehash hook, installed as a copy

**Date:** 2026-09-17
**Status:** Accepted

## Context

ADR-0031 fixed the `pytest`-shim defect at its root — a non-GNU `sort -u` on Ubuntu
26.04 — by making the gating actor's `PATH` resolve GNU coreutils first. That fix reaches
exactly one actor: **interactive zsh**, because `.config/.zshrc.d/6_path.zsh` is sourced by
interactive shells only.

Four other actors call `pyenv rehash` without ever sourcing that file, and each one still
runs under uutils `sort` on a 26.04 box:

- `.zprofile:9` (login zsh) calls `pyenv init --path`, whose own `command pyenv rehash`
  runs before `6_path.zsh` (an interactive-only file) has had a chance to reorder `PATH`.
- `lib/developer.sh:537` and `:567` — `setup_ansible` and `recreate_python_venv` — both
  call `pyenv rehash` from bash, which never sources `6_path.zsh` at all.
- `ssh claude '<cmd>'`, which sources neither `.zprofile` nor `.zshrc.d`.
- pyenv's own `install` and `virtualenv` subcommands, which call rehash internally.

The defect is in pyenv core, not in this repo's `PATH`: `libexec/pyenv-rehash` feeds
`pyenv-versions --executables`' output through `sort -u` before calling `make_shims`, and
a non-GNU `sort -u` collates `py.test` and `pytest` as equal and drops one. Verified on
pyenv 2.8.6 (brew, on `claude` and `workstation`) and 2.8.5 (the Studio) — same three
`libexec/pyenv-rehash` lines in both:

```
186: shopt -s nullglob
193: make_shims $(pyenv-versions --executables)   # the uutils-damaged list
198: IFS=$'\n' scripts=(`pyenv-hooks rehash`) ... source "$script"
205: install_registered_shims
206: remove_stale_shims
```

Fixing `PATH` order at each of the four actors above would be four separate changes, one
of which (`ssh claude '<cmd>'`) has no rc file to edit at all. `pyenv-hooks rehash` is a
choke point every one of them already passes through: it globs `$path/rehash/*.bash` and
sources each one between `make_shims` and `install_registered_shims`, for every actor,
every time. pyenv-virtualenv's own `envs.bash` already ships a hook that calls
`make_shims` this way, so the mechanism is proven upstream, not novel here.

## Decision

Add a tracked hook, `pyenv.d/rehash/dotfiles-register-all-executables.bash`, and install
it as a **copy** into `${PYENV_ROOT}/pyenv.d/rehash/` — never a symlink.

The hook re-registers the same glob pyenv's own `make_shims $(pyenv-versions
--executables)` call would produce, without ever piping through `sort`:

```bash
declare -f make_shims >/dev/null || return 0
_dotfiles_rehash_opts="$(shopt -p nullglob dotglob || true)"
shopt -s nullglob dotglob
make_shims "${PYENV_ROOT}"/versions/*/bin/* "${PYENV_ROOT}"/versions/*/envs/*/bin/*
eval "${_dotfiles_rehash_opts}"
unset _dotfiles_rehash_opts
```

`make_shims` takes basenames and calls `register_shim`, which is additive — re-registering
a name pyenv's own unsorted enumeration would already produce is harmless, whatever order
the hooks run in.

`install_pyenv_rehash_hook` (`lib/helpers.sh`) is called from four places, each
**immediately before** a rehash that needs it: `run_setup_user`, `setup_ansible` (right
after `uv_sync_venv`), `recreate_python_venv`, and the `pyenv-shims` section of `run_update`
(ADR-0027's section-status machinery). Placing the install before the rehash rather than
"at the end" matters concretely: `-t setup_user` runs before pyenv creates `versions/` on a
fresh host, so the install is a silent no-op there and the _first_ rehash to see the
venv's console scripts is the one right after `uv sync` in `setup_ansible` — a hook
installed after that rehash would have already missed the shim it exists to save, and
nothing rehashes again until a later interactive shell's `pyenv init -` runs its own
`command pyenv rehash`.

Every call site treats a failed install as warn-and-continue:
`install_pyenv_rehash_hook || log_warn "pyenv rehash hook not installed — see above"`. A
failed copy must not skip the rehash itself or any step after it — the rehash stays the
function's last command, so its own return code still propagates through
`setup_ansible || return 1` exactly as before this hook existed.

## Consequences

**Good.** The defect is fixed once, at the one place every rehashing actor passes through,
rather than patched per-actor at a `PATH` reorder that at least one actor (`ssh`) has no
rc file to carry. The fix is additive and cannot make a correct rehash worse: the glob
mirrors what pyenv's own call would enumerate, so the hook cannot register a name pyenv's
unsorted list would lack.

**Costs, accepted.**

- **pyenv-rehash's internals churn.** `workstation`'s pyenv clone shows 8 commits to
  `libexec/pyenv-rehash` since 2025-12-05 alone, including `47871b2d rehash: drop
redundant sort -u from make_shims call` and `8037f226 rehash: streamline executables
discovery` — either could retire the defect this hook exists for, or change the
  contract the hook depends on (`make_shims`, the `pyenv.d/rehash/*.bash` hook point)
  without warning. That is why Part 2's doctor arm checks the _outcome_ (every venv
  binary has a shim) rather than trusting that the hook ran: a contract break makes the
  hook a silent no-op — `declare -f make_shims >/dev/null || return 0` — and doctor is
  what notices.
- **A copy, not a symlink, because a dangling symlink is silently worse than no hook at
  all.** Measured against brew pyenv 2.8.5 and on `claude`: a dangling
  `pyenv.d/rehash/*.bash` symlink makes `pyenv rehash` exit 1 with **no stderr**, install
  no shims, and `pyenv init --path` silently ignore the failing return code. The link
  would point into this repo's own checkout, and `claude`'s reflog shows that checkout
  parked on other branches for hours at a time (2026-08-12, 2026-08-24) — exactly the
  window in which a symlinked hook would dangle. A copy cannot dangle; its cost is that
  the installed copy goes stale until the next call site re-runs the install after the
  hook file itself changes in this repo.
- **The hook lands untracked inside a foreign git checkout on `workstation`.** `~/.pyenv`
  there is a `tfutils`-style git clone of pyenv itself (2.7.2), and the hook's
  destination, `pyenv.d/rehash/`, sits inside that clone's working tree. `pyenv update`
  (`lib/developer.sh`) already `git pull`s that clone and tolerates the untracked file —
  verified, not merely assumed — but a future `git status` inside `~/.pyenv` will show it
  as untracked, and that is expected rather than a sign of drift.
- **`shopt -p` exits 1 when any named option is already off, and `pyenv-rehash` runs
  under `set -e`.** Round 3 of this branch's review measured a scratch `PYENV_ROOT` where
  the bare capture aborted the entire rehash, silently, before a single shim was
  registered. The hook's `|| true` on that capture is load-bearing, not defensive
  boilerplate — without it, the fix can turn a working rehash into a zero-shim one.
- **The hook must own its own glob options, not assume the shell's.** On `workstation`,
  `~/.pyenv/pyenv.d/rehash/conda.bash` runs `shopt -u dotglob nullglob` before this hook
  does (pyenv sources `rehash/*.bash` alphabetically), so without setting both options
  itself the hook's unmatched-glob case would register a shim literally named `*`. It
  restores exactly what its caller had via `shopt -p`/`eval`, so it neither leaks its own
  `nullglob dotglob` into later hooks nor assumes a clean slate from earlier ones.

**Not covered by this ADR.** Whether a future pyenv release removes the need for this hook
entirely (by fixing `pyenv-versions --executables`'s own `sort -u`, per the "8 commits
since 2025-12-05" churn above) is left to Part 2's doctor arm to surface, not to this
document to predict — the contract guard (`declare -f make_shims >/dev/null || return 0`)
means an upstream fix makes the hook an inert no-op rather than a breaking one, and nothing
here removes the hook automatically once it stops being needed.

## Related

- [ADR-0031](0031-gnu-coreutils-precedence-on-resolute.md) — the `PATH`-order fix this ADR
  amends. That ADR's install is release-gated on `RESOLUTE` and its `PATH` edit reaches
  interactive zsh only; this ADR is the fix for the actors outside that reach.
- [ADR-0027](0027-update-run-exit-code-from-section-status.md) — the section-status
  machinery (`_update_record_end`/`_update_warn`, rc-2-means-partial-success) that the
  `pyenv-shims` section of `-t update` uses to report a missing shim as WARN rather than
  FAIL.
- `docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md` — the spec this
  shipped under (Part 1: the hook; Part 2: the doctor arm and the `-t update` section that
  verify the outcome).
- `CLAUDE.md` Test Seams (`_OVERRIDE_PYENV_ROOT`) and Layout (`pyenv.d/`) — the seam and
  tracked directory this decision introduces.
