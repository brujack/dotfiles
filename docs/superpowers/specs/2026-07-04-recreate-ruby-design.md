# recreate-ruby: force-delete and reinstall the pinned Ruby version

## Context

`setup_env.sh -t recreate-venv` gives an escape hatch for a broken pyenv
virtualenv: delete it, rebuild from the pinned `PYTHON_VER`. Ruby has no
equivalent. After PR#171 (system-OpenSSL `RUBY_CONFIGURE_OPTS` fix), the only
way to force a clean Ruby rebuild — e.g. to pick up a `RUBY_CONFIGURE_OPTS`
change, or recover from a broken openssl link — is manual: find the install
directory, delete it by hand, re-run setup.

Ruby has no built-in virtualenv equivalent (no gemsets in scope here — see
Non-Goals). "Recreate" for Ruby means: force-delete and reinstall the pinned
Ruby interpreter itself (`RUBY_VER` in `lib/constants.sh`), via whichever
version manager the platform uses — rbenv on Linux, ruby-install/chruby on
macOS.

## Decision

Add a new `setup_env.sh -t recreate-ruby` entry point, wired the same way as
`recreate-venv`.

### `recreate_ruby()` — `lib/developer.sh`

Placed next to `install_ruby()`. No arguments — always targets `RUBY_VER`.

1. **Guard tool presence before any destructive step** (same ordering as
   `recreate_python_venv`'s `quiet_which pyenv` check before it deletes
   anything):
   - macOS: `quiet_which ruby-install` — if absent, `log_error` and
     `return 1`.
   - Linux: `quiet_which rbenv` — if absent, `log_error` and `return 1`.
2. **Delete the existing install:**
   - macOS: `rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"`.
   - Linux: set up rbenv on `PATH` and init it the same way
     `recreate_python_venv` does for pyenv (`export PATH="${HOME}/.rbenv/bin:${PATH}"; eval "$(rbenv init -)"`),
     then `rbenv uninstall -f "${RUBY_VER}" 2>/dev/null || true`.
3. **Rebuild via the existing `install_ruby()`.** No duplicated build logic —
   deleting the version directory makes `install_ruby()`'s own idempotency
   guards (`[[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]` on macOS,
   `[[ ! -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]` on Linux) re-trigger a real
   install, reusing the PR#171 `RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"`
   fix, the ruby-build git refresh, and `--skip-existing` unchanged.

```bash
recreate_ruby() {
  if [[ -n ${MACOS} ]]; then
    if ! quiet_which ruby-install; then
      log_error "ruby-install not found — cannot recreate ruby"
      return 1
    fi
    printf "Deleting ruby %s\\n" "${RUBY_VER}"
    rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"
  fi
  if [[ -n ${LINUX} ]]; then
    if ! quiet_which rbenv; then
      log_error "rbenv not found — cannot recreate ruby"
      return 1
    fi
    export PATH="${HOME}/.rbenv/bin:${PATH}"
    eval "$(rbenv init -)"
    printf "Deleting ruby %s\\n" "${RUBY_VER}"
    rbenv uninstall -f "${RUBY_VER}" 2>/dev/null || true
  fi
  install_ruby || return 1
}
```

### Wiring (mirrors `recreate-venv` exactly)

- `lib/helpers.sh`:
  - usage text: `recreate-ruby : Force-delete and reinstall the pinned Ruby version`
  - arg parse case: `recreate-ruby) readonly RECREATE_RUBY=1 ;;`
- `lib/workflows.sh`:
  ```bash
  run_recreate_ruby() {
    recreate_ruby || return 1
    _ledger_write_run_entry "recreate_ruby" 0 || true
  }
  ```
- `setup_env.sh`: `[[ -n ${RECREATE_RUBY:-} ]] && _run_or_exit run_recreate_ruby`
  (placed next to the existing `RECREATE_VENV` line)
- `lib/update_summary.sh`: add `recreate_ruby` to the `RUN_TYPE` comment list
  (`update | setup_user | setup | developer | recreate_venv | recreate_ruby`)
- `CLAUDE.md`: new row in the entry-points table

### Non-Goals

- No gemset-style per-project isolation (`rbenv-gemset` or similar). Ruby
  has no cross-platform virtualenv equivalent today and none of the repo's
  Ruby usage needs one — `install_ruby_tools()` installs no global gem list
  analogous to the ansible pip package list. Out of scope; revisit only if a
  future need for isolated gem sets emerges.
- No `--ruby-version` flag. `recreate_python_venv` takes a `--venv-name`
  because multiple named virtualenvs can exist; there is exactly one pinned
  Ruby version (`RUBY_VER`), so no parallel flag is needed.
- No `DRY_RUN` support. `recreate_python_venv` and `install_ruby` do not
  respect `DRY_RUN` today either — this stays consistent with the existing
  sibling function rather than introducing new behavior out of scope.

## Testing

TDD, one behavior at a time, in `tests/setup_env/install_functions.bats`
(mirroring the existing `install_ruby` and `recreate_python_venv` test
patterns) and `tests/setup_env/unit.bats` (arg parsing):

- macOS: `recreate_ruby` removes `${HOME}/.rubies/ruby-${RUBY_VER}` then
  invokes the `ruby-install` mock.
- Linux: `recreate_ruby` calls `rbenv uninstall -f` then re-invokes the
  `rbenv install` mock — assert `RUBY_CONFIGURE_OPTS` is still passed
  (regression guard for the PR#171 fix).
- Error path, macOS: `ruby-install` absent → `return 1`, no delete attempted,
  `log_error` message present.
- Error path, Linux: `rbenv` absent → `return 1`, no delete attempted,
  `log_error` message present.
- `-t recreate-ruby` sets `RECREATE_RUBY=1` (arg-parsing test in
  `unit.bats`).
- `run_recreate_ruby` calls `recreate_ruby` and writes the
  `recreate_ruby` ledger entry (workflows test).

## Documentation

- `CLAUDE.md` entry-points table: add `recreate-ruby` row.
- No CHANGELOG.md entry needed — that file is updated by a separate weekly
  job, not per-PR.
