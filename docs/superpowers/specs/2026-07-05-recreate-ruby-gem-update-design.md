# recreate-ruby: update gems after reinstall, fix Linux gem PATH gap

## Context

The original `recreate-ruby` design (`docs/superpowers/specs/2026-07-04-recreate-ruby-design.md`)
explicitly non-goaled gem handling: "`install_ruby_tools()` installs no global gem list analogous
to the ansible pip package list. Out of scope; revisit only if a future need for isolated gem sets
emerges."

That need has emerged, but not in the form the non-goal anticipated. There is no custom gem list
anywhere in the repo (confirmed by search — no `Gemfile`, no `RUBY_GEMS` constant, no `gem install`
call in `lib/*.sh`). The gems in question are Ruby's own bundled default gems (`bundler`, `rake`,
`json`, `minitest`, etc.) — every fresh Ruby install ships with older pinned versions of these, and
`gem update` (no args) is what brings them current. `run_update`'s existing gems section
(`lib/workflows.sh:519-530`, gated by `UPDATE_GEMS`) already does this for an existing install, but
`recreate_ruby()` never calls it — so a freshly recreated Ruby is left on stale bundled gem versions
until the next full `update` run.

Separately, `run_update`'s gem PATH-prepend logic only ever accounted for the macOS chruby layout:

```bash
local _ruby_gem_dir="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
```

On Linux this directory never exists, so `_extra_gem_path` stays empty and `gem update` falls
through to whatever `gem` happens to be first on `PATH` — not necessarily the rbenv-managed Ruby's
`gem`. This is a real bug independent of the recreate-ruby extension, surfaced while investigating
this change.

## Decision

Extract the gem-update logic into a shared `update_gems()` function (fixing the Linux PATH gap in
the extraction), call it from `recreate_ruby()` (fail-fast) and from `run_update`'s existing gems
section (unchanged soft-fail behavior).

### `update_gems()` — `lib/developer.sh`

Placed after `recreate_ruby()`. No arguments — always targets whatever Ruby is currently active for
the platform's version manager.

```bash
update_gems() {
  local _ruby_gem_dir=""
  if [[ -n ${MACOS} ]]; then
    _ruby_gem_dir="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  elif [[ -n ${LINUX} ]]; then
    _ruby_gem_dir="${HOME}/.rbenv/shims"
  fi
  local _extra_gem_path=""
  [[ -d "${_ruby_gem_dir}" ]] && _extra_gem_path="${_ruby_gem_dir}:"
  PATH="${_extra_gem_path}${PATH}" gem update
}
```

The Linux branch prepends `~/.rbenv/shims` — the same directory `rbenv init` puts on `PATH`
interactively (`.config/.zshrc.d/5_general.zsh:60`) — so `gem` resolves to the rbenv-managed Ruby's
gem binary regardless of what else is on `PATH` when this runs non-interactively (e.g. from
`run_update` or `recreate_ruby`, neither of which sources `rbenv init` themselves outside
`recreate_ruby`'s own delete step).

### `recreate_ruby()` extension — `lib/developer.sh`

After the existing `install_ruby || return 1` line:

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
  update_gems || { log_error "gem update failed after ruby recreate"; return 1; }
}
```

Fail-fast: a recreate should end in a known-good state (ruby installed AND gems current) or an
explicit error — not a silent partial success where the interpreter is fresh but gems are stale or
untouched. This is a deliberate departure from `run_update`'s soft-fail gems step (see below) — the
two call sites have different failure tolerances by design, not by oversight.

### `run_update` gems section — `lib/workflows.sh:519-530`

Swap the inline `gem update` invocation for the shared function. Tee-to-tmpdir and
`_update_record_end` bookkeeping stay in `workflows.sh` (they're specific to the update-summary
framework, not general-purpose):

```bash
if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
  _update_record_start "gems"
  printf "updating ruby gems\\n"
  update_gems 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_gems"
  _update_record_end "gems" "${PIPESTATUS[0]}"
else
  _update_skip "gems" "flag not set"
fi
```

Behavior unchanged from the caller's perspective: still gated by `UPDATE_GEMS`/`_run_all`, still
soft-fail (a failed `gem update` is recorded in the summary but does not abort `run_update`), still
writes `err_gems`. Only the PATH-prepend logic moves into `update_gems()` and gains the Linux fix.

### Non-Goals

- No custom/pinned gem list. The gems involved (`bundler`, `rake`, `json`, `minitest`, etc.) are
  Ruby's own bundled default gems — `gem update` already covers all installed gems including these,
  nothing to enumerate or pin.
- No change to `UPDATE_GEMS` flag semantics, no new `setup_env.sh` flag, no new entry point.
- No change to macOS gem-path logic — the existing chruby dir was already correct; only the missing
  Linux branch is added.

## Testing

TDD, one behavior at a time, in `tests/setup_env/install_functions.bats` (mirroring existing
`install_ruby`/`recreate_ruby` test patterns):

- `update_gems` macOS: prepends `${HOME}/.rubies/ruby-${RUBY_VER}/bin` to `PATH`, invokes `gem`
  mock with `update`.
- `update_gems` Linux: prepends `${HOME}/.rbenv/shims` to `PATH`, invokes `gem` mock with `update`.
- `update_gems` — platform gem dir absent (fresh mock `HOME`, no dir created): still invokes `gem
update` without crashing, `_extra_gem_path` empty.
- `recreate_ruby` happy path (both platforms) — updated to additionally assert the `gem` mock was
  invoked with `update` after the `install_ruby`/`rbenv install` mock call.
- `recreate_ruby` — `update_gems` failure (`MOCK_GEM_EXIT=1`) → `recreate_ruby` returns 1,
  `log_error "gem update failed after ruby recreate"` present, and the ruby-install/rbenv-install
  mock was still called (i.e. the interpreter install itself succeeded — only the gem step failed).
- `run_update` gems section (existing test in `tests/setup_env/*.bats` covering `UPDATE_GEMS`) —
  updated to assert `gem update` mock still invoked and `_update_record_end "gems" ...` still
  recorded; regression guard that swapping in `update_gems()` didn't change `run_update`'s observable
  behavior.

## Documentation

- No `CLAUDE.md` entry-points table change — no new entry point, `recreate-ruby` row already exists.
- `CLAUDE.md` Ruby Version Manager Split section: add one sentence noting `update_gems()` handles
  the rbenv-shims-vs-chruby-bin PATH difference, so future gem-related changes don't re-introduce
  the Linux gap.
