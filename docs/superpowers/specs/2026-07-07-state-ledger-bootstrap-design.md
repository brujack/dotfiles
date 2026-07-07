# state-ledger: auto-bootstrap clone/pull, replace dead ensure_machine_id

## Context

`ensure_machine_id()` (`lib/workflows.sh:721`) is defined but never called anywhere in the
repo (confirmed by `grep -rn "ensure_machine_id" . --include="*.sh"` — only the definition
matches). Result: on any machine that never manually ran `ledger init`, `~/.config/dotfiles/machine-id`
is never created, and `_ledger_write_run_entry()` (`lib/update_summary.sh:364`) silently no-ops
on its `[[ ! -f "${_machine_id_path}" ]] && return 0` guard — every ledger write for that machine
is a silent skip, not an error, so the gap goes unnoticed.

Separately, dotfiles never clones or pulls `~/.local/share/state-ledger` itself. The only place
that repo gets refreshed is inside `~/git-repos/personal/state-ledger/scripts/ledger.py`'s
`_git_commit_and_push()`, which does a single `pull --rebase` immediately before `push` — one
attempt, no retry. When two machines write near-simultaneously, the second machine's push can
lose the race (non-fast-forward) with nothing to retry it; the entry gets spooled locally instead
of landing in the shared ledger. That race-condition fix belongs to `ledger.py` itself and is
tracked as a separate follow-up in the state-ledger repo's own SDLC — out of scope here.

This spec covers the dotfiles-side fix only: proactively bootstrap the state-ledger clone (and
machine-id/hook/symlink via the existing idempotent `ledger.py init`) at the start of every
dotfiles run, so the local clone is never more than one run's staleness behind origin, and so
`_ledger_write_run_entry` stops silently no-oping on unconfigured machines.

## Decision

Add `ensure_state_ledger()` to `lib/workflows.sh`, replacing the dead `ensure_machine_id()`.
Call it from `_dotfiles_run_tmpdir_setup()` — the single helper already shared by every
`run_*` workflow (`run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`,
`run_recreate_venv`, `run_recreate_ruby`, and `run_update` via `_update_summary`) — so one call
site covers all entry points.

### `ensure_state_ledger()` — `lib/workflows.sh`

Replaces `ensure_machine_id()` at the same location (`lib/workflows.sh:721`):

```bash
ensure_state_ledger() {
  local _dir="${HOME}/.local/share/state-ledger"
  local _url="git@github.com:brujack/state-ledger.git"

  if [[ -d "${_dir}/.git" ]]; then
    git -C "${_dir}" pull --ff-only >/dev/null 2>&1 \
      || log_warn "state-ledger pull failed — continuing without ledger sync"
  else
    git clone "${_url}" "${_dir}" >/dev/null 2>&1 \
      || { log_warn "state-ledger clone failed — continuing without ledger"; return 0; }
  fi

  [[ -x "${_dir}/scripts/ledger.py" ]] && \
    { "${_dir}/scripts/ledger.py" init >/dev/null 2>&1 \
      || log_warn "ledger init failed — continuing"; }
}
```

Mirrors the existing `setup_ai_config()` clone-or-pull pattern (`lib/workflows.sh:84-93`) for
consistency. Deliberately reuses `ledger.py`'s own `cmd_init` (already idempotent: writes
`machine-id` if absent, runs `pre-commit install`, verifies the hook, symlinks
`~/.local/bin/ledger`) instead of reimplementing that logic in bash — no new machine-id/symlink
code needed here, `cmd_init` already does it and is tested in the state-ledger repo.

**Why `--ff-only` and not `--rebase`**: this is a read-only bootstrap pull, not a write path —
dotfiles never commits into `~/.local/share/state-ledger` itself (only `ledger write`/`ledger
init`, both inside `ledger.py`, do). A fast-forward-only pull is the correct, simplest operation
here; there is no local work to rebase.

### Call site — `lib/workflows.sh:95-105`

```bash
_dotfiles_run_tmpdir_setup() {
  _DOTFILES_RUN_TMPDIR=$(mktemp -d)
  export _DOTFILES_RUN_TMPDIR
  trap 'rm -rf "${_DOTFILES_RUN_TMPDIR}"; unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
  date -u +%Y-%m-%dT%H:%M:%SZ > "${_DOTFILES_RUN_TMPDIR}/started_at"
  date +%s > "${_DOTFILES_RUN_TMPDIR}/start_epoch"
  python3 -c "import uuid; print(str(uuid.uuid4()))" \
    > "${_DOTFILES_RUN_TMPDIR}/run_id" 2>/dev/null || true
  git -C "${PERSONAL_GITREPOS}/${DOTFILES}" rev-parse HEAD \
    > "${_DOTFILES_RUN_TMPDIR}/git_sha" 2>/dev/null || true
  ensure_state_ledger || true
}
```

### Error handling

Every failure path is non-fatal — `log_warn` and continue. Covers: offline machine, no SSH key
configured for `git@github.com`, `pre-commit` binary absent (so `ledger.py init`'s
`pre-commit install` step throws), or any other clone/pull/init failure. This matches the
existing philosophy for ledger integration: `ledger write` already warns-and-spools rather than
failing `run_update`/etc. A ledger sync problem must never block a dotfiles setup or update run.

### Non-Goals

- No retry/backoff logic for the ledger.py push race — separate follow-up spec in the
  state-ledger repo's own SDLC (its own branch/PR, its own CLAUDE.md conventions).
- No new `config/local.sh` variable — the clone URL is hardcoded
  (`git@github.com:brujack/state-ledger.git`), matching the single-owner personal-repo pattern
  already used by `setup_ai_config()`'s hardcoded `git@github.com:brujack/ai-config`.
- No change to `_ledger_write_run_entry()` or `ledger_write_entry()` — the write path is
  untouched; this spec only ensures the clone exists and is current before any write is attempted.
- No `doctor` check added for ledger staleness — out of scope; `ledger drift` (via the
  `ledger-status` skill) already surfaces this on demand.

## Testing

TDD, one behavior at a time, in `tests/setup_env/install_guards.bats` (mirroring the existing
`setup_ai_config` test block at line 431):

- `ensure_state_ledger` clones when `~/.local/share/state-ledger/.git` absent — asserts `git`
  mock invoked with `clone git@github.com:brujack/state-ledger.git <dir>`.
- `ensure_state_ledger` pulls (`--ff-only`) when the dir already has a `.git`.
- `ensure_state_ledger` clone failure → `log_warn` message present, function returns 0 (does not
  propagate failure to the caller).
- `ensure_state_ledger` pull failure → `log_warn` message present, function returns 0, and
  `ledger.py init` is still attempted afterward (pull failure doesn't skip the init step).
- `ensure_state_ledger` invokes `<dir>/scripts/ledger.py init` when the script exists and is
  executable (stub script in the mock `HOME`).
- `ensure_state_ledger` skips the init call cleanly when `scripts/ledger.py` is absent or not
  executable (fresh mock `HOME` with no stub) — no error, function still returns 0.
- `_dotfiles_run_tmpdir_setup` regression check — existing tests for this function (if any)
  updated/extended to assert `ensure_state_ledger` is invoked as part of tmpdir setup, using an
  inline override (`ensure_state_ledger() { :; }`) so those tests stay focused on tmpdir/run_id
  behavior rather than re-testing ledger bootstrap.

## Documentation

- `CLAUDE.md` — add `ensure_state_ledger()` to the state-ledger integration notes (the existing
  `update` entry-point table row already mentions the state-ledger write; add a sentence noting
  the clone/pull bootstrap now runs on every run type, not just `update`).
- No new entry point, no new flag — no `Entry Points` table change.
