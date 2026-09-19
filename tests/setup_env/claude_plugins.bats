#!/usr/bin/env bats

# `run --separate-stderr` is a 1.5.0 flag; without this declaration bats
# emits BW02 on every invocation. ubuntu-latest ships 1.10.0 via apt and the
# dev machines 1.14.0, so the floor is satisfied everywhere this runs.
bats_require_minimum_version 1.5.0

# Coverage for the plugin-manifest reader and the two CLI --json list readers
# (_claude_settings_path, _claude_plugin_manifest, _claude_registered_marketplaces,
# _claude_installed_user_ids). Task 2 of
# docs/superpowers/specs/2026-09-19-claude-plugin-provisioning-design.md.
# Later tasks (the write guard, the setup_claude_plugins reconcile) add more
# tests to this same file.

setup() {
  # A leaked GIT_DIR/GIT_INDEX_FILE (e.g. from a pre-push hook invoking this
  # suite from a worktree) would make _guard_repo_setup's `git init`/`add`/
  # `commit` calls operate on THAT repo instead of the throwaway fixture --
  # git -C does not override an inherited GIT_DIR (shell.md). Required at
  # setup scope per git-workflow.md for any bats setup that creates a
  # fixture repo.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  # Neutralize the operator's real global/system git config for the whole
  # suite, not just the fixture repo's own -c overrides. Without this, a
  # machine with commit.gpgsign=true hangs/fails on the fixture commits
  # below, and a machine with a global core.hooksPath pin actually RUNS
  # that real hook against the throwaway repo -- writing outside
  # BATS_TEST_TMPDIR from what looks like an isolated fixture. /dev/null
  # also closes the XDG_CONFIG_HOME route to the same file.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  SETTINGS="${BATS_TEST_TMPDIR}/claude-settings.json"
  cp "${REPO_ROOT}/tests/fixtures/claude-settings.json" "${SETTINGS}"
  export _OVERRIDE_CLAUDE_SETTINGS="${SETTINGS}"
  unset MOCK_CLAUDE_PLUGINS_LIST_JSON MOCK_CLAUDE_MARKETPLACE_LIST_JSON MOCK_CLAUDE_FAIL_ARGS

  # _claude_settings_git_state/_claude_settings_guard_check tests need a REAL
  # git, never tests/mocks/git (which answers almost everything with an empty
  # stdout / exit 0 -- shell.md's PATH-mock-shadows-production-code pitfall).
  # Resolve it with the mocks directory stripped by string filtering, the
  # same `_clean_path` idiom tests/scripts/unit.bats already uses, rather
  # than stripping a PATH directory outright -- that would also remove every
  # other tool co-located with the mock (shell.md's co-location pitfall). A
  # shim directory holding a symlink to the resolved binary keeps git's own
  # argv0/exec-path resolution intact.
  local _clean_path
  _clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  local _real_git
  _real_git="$(PATH="${_clean_path}" command -v git)"
  [[ -n "${_real_git}" ]]
  local _git_shim="${BATS_TEST_TMPDIR}/git-shim"
  mkdir -p "${_git_shim}"
  ln -sf "${_real_git}" "${_git_shim}/git"
  export _CLAUDE_GUARD_GIT="${_git_shim}/git"
}

# Builds ${BATS_TEST_TMPDIR}/repo as a real git repo tracking sub/settings.json
# (a SUBDIRECTORY, deliberately -- see the GIT_DIR-decoy test below, which
# needs the tracked file's directory to differ from the repo's top-level so
# an unstripped `rev-parse --show-toplevel` reports a distinguishably wrong
# answer rather than coincidentally the right one), then points the settings
# path at a symlink through it. HOME is relocated INSIDE the repo
# (${GUARD_REPO}/home, itself untracked) so a caller can also build an
# untracked-but-inside-a-repo file under ${HOME}/.claude without a second
# fixture -- see the "never committed" and "symlink replaced" tests below.
# Exports GUARD_REPO (the path git commands were run against) and
# GUARD_REPO_REAL (its realpath, the form _claude_settings_git_state
# reports).
_guard_repo_setup() {
  GUARD_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${GUARD_REPO}/sub"
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" init -q
  printf '{}' > "${GUARD_REPO}/sub/settings.json"
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" -c user.email=t@t -c user.name=T add sub/settings.json
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" -c user.email=t@t -c user.name=T commit -qm init
  GUARD_REPO_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${GUARD_REPO}")"
  export HOME="${GUARD_REPO}/home"
  mkdir -p "${HOME}/.claude"
  ln -sf "${GUARD_REPO}/sub/settings.json" "${HOME}/.claude/settings.json"
  export _OVERRIDE_CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
}

# Realpath, for asserting expected values the same way _claude_settings_git_state
# computes them -- a bare literal comparison fails on any machine whose
# TMPDIR is itself reached through a symlink (every mac; CI is Linux-only
# and cannot see this class of bug).
_realpath() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

# ── _claude_settings_path ───────────────────────────────────────────────────

@test "_claude_settings_path prints the override when set" {
  run _claude_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "${SETTINGS}" ]
}

@test "_claude_settings_path falls back to HOME/.claude/settings.json when unset" {
  unset _OVERRIDE_CLAUDE_SETTINGS
  run _claude_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "${HOME}/.claude/settings.json" ]
}

# ── _claude_plugin_manifest: marketplace lines ──────────────────────────────

@test "_claude_plugin_manifest emits a marketplace line for a github source" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'marketplace\tclaude-plugins-official\tanthropics/claude-plugins-official')"
}

@test "_claude_plugin_manifest emits a marketplace line for a git source, with the URL" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'marketplace\tcaveman\thttps://github.com/juliusbrussee/caveman.git')"
}

@test "_claude_plugin_manifest emits unsupported for an unknown source type" {
  cat > "${SETTINGS}" <<'JSON'
{"extraKnownMarketplaces":{"weird":{"source":{"source":"url","url":"https://example.com"}}}}
JSON
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$(printf 'unsupported\tweird\turl')"
}

@test "_claude_plugin_manifest emits unsupported for a github entry missing repo" {
  cat > "${SETTINGS}" <<'JSON'
{"extraKnownMarketplaces":{"broken":{"source":{"source":"github"}}}}
JSON
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$(printf 'unsupported\tbroken\tgithub')"
}

# ── _claude_plugin_manifest: plugin lines ───────────────────────────────────

@test "_claude_plugin_manifest emits true for an enabled plugin" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'plugin\tsuperpowers@claude-plugins-official\ttrue')"
}

@test "_claude_plugin_manifest emits false for a disabled plugin" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'plugin\tfrontend-design@claude-plugins-official\tfalse')"
}

@test "_claude_plugin_manifest emits false for a non-boolean enabledPlugins value" {
  cat > "${SETTINGS}" <<'JSON'
{"enabledPlugins":{"weird@m":"true"}}
JSON
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$(printf 'plugin\tweird@m\tfalse')"
}

# ── _claude_plugin_manifest: failure and empty-set contracts ────────────────

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file is missing" {
  rm -f "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file is not JSON" {
  printf 'not json' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file is a JSON array" {
  printf '[]' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 0 with no lines when neither key is present" {
  printf '{}' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when extraKnownMarketplaces is not an object" {
  printf '{"extraKnownMarketplaces": []}' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when enabledPlugins is not an object" {
  printf '{"enabledPlugins": []}' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file exists but is unreadable" {
  if [[ "$(id -u)" -eq 0 ]]; then
    skip "root ignores file mode bits"
  fi
  chmod 000 "${SETTINGS}"
  run _claude_plugin_manifest
  chmod 644 "${SETTINGS}"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when python3 cannot be resolved" {
  local _shim="${BATS_TEST_TMPDIR}/no-python3-shim"
  mkdir -p "${_shim}"
  # The function's own body reaches only bash builtins ([[ -r ]], command -v)
  # before it would need python3, so an otherwise-empty shim directory is
  # sufficient to make python3 unresolvable -- never strip a real PATH
  # directory (e.g. /usr/bin) to hide one binary, since that takes every
  # other binary in it down too (shell.md: "scrubbing PATH to hide a binary
  # also removes every binary that shares its directory").
  PATH="${_shim}" run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── _claude_registered_marketplaces ─────────────────────────────────────────

@test "_claude_registered_marketplaces prints one name per line" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  run _claude_registered_marketplaces
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'claude-plugins-official\ncaveman')" ]
}

@test "_claude_registered_marketplaces returns 1 when the CLI call fails" {
  export MOCK_CLAUDE_FAIL_ARGS="marketplace list --json"
  run _claude_registered_marketplaces
  [ "$status" -eq 1 ]
  # The mock prints nothing of its own on this path, and the reader no
  # longer captures-then-echoes stderr (that echo used to duplicate
  # whatever the 2>&1-merged capture held) -- it lets the CLI's real
  # stderr flow through uncaptured instead. Nothing here manufactures a
  # message, so $output (bats merges stdout+stderr) must be empty.
  [ -z "$output" ]
}

@test "_claude_registered_marketplaces returns 1 when the CLI output does not parse" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='not json'
  run _claude_registered_marketplaces
  [ "$status" -eq 1 ]
  [[ "$output" == *"unparsable JSON"* ]]
}

@test "_claude_registered_marketplaces prints zero bytes for an empty marketplace list" {
  # "\n".join([]) followed by print() would emit one blank line -- a single
  # "\n" byte. bats' `run`/$output is the WRONG instrument here: it captures
  # via command substitution, which strips a lone trailing newline on its
  # own, so [ -z "$output" ] would pass whether or not the reader itself
  # emits that byte (confirmed against a `printf '\n'` probe). Redirect to a
  # file instead, which preserves exactly what was written.
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[]'
  local _outfile="${BATS_TEST_TMPDIR}/mkt-empty-out"
  _claude_registered_marketplaces > "${_outfile}"
  local _rc=$?
  [ "${_rc}" -eq 0 ]
  [ ! -s "${_outfile}" ]
}

@test "_claude_registered_marketplaces returns 1 with no stdout when python3 cannot be resolved" {
  local _shim="${BATS_TEST_TMPDIR}/no-python3-shim-mkt"
  mkdir -p "${_shim}"
  # python3 is checked before the CLI is ever invoked, so the shim need
  # not resolve `claude` either -- same empty-shim approach as the
  # manifest's python3-absent test above.
  PATH="${_shim}" run _claude_registered_marketplaces
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── _claude_installed_user_ids ──────────────────────────────────────────────

@test "_claude_installed_user_ids prints only ids installed at user scope" {
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"a@m","scope":"user"},{"id":"b@m","scope":"project"}]'
  run _claude_installed_user_ids
  [ "$status" -eq 0 ]
  [ "$output" = "a@m" ]
}

@test "_claude_installed_user_ids returns 1 when the CLI call fails" {
  export MOCK_CLAUDE_FAIL_ARGS="plugins list --json"
  run _claude_installed_user_ids
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_installed_user_ids returns 1 when the CLI output does not parse" {
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='not json'
  run _claude_installed_user_ids
  [ "$status" -eq 1 ]
  [[ "$output" == *"unparsable JSON"* ]]
}

@test "_claude_installed_user_ids prints zero bytes for an empty plugin list" {
  # Same instrument fix as the marketplace-reader sibling above: $output
  # cannot discriminate a lone blank-line print from true emptiness because
  # `run` captures through command substitution, which strips it either way.
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[]'
  local _outfile="${BATS_TEST_TMPDIR}/ids-empty-out"
  _claude_installed_user_ids > "${_outfile}"
  local _rc=$?
  [ "${_rc}" -eq 0 ]
  [ ! -s "${_outfile}" ]
}

@test "_claude_installed_user_ids returns 1 with no stdout when python3 cannot be resolved" {
  local _shim="${BATS_TEST_TMPDIR}/no-python3-shim-ids"
  mkdir -p "${_shim}"
  PATH="${_shim}" run _claude_installed_user_ids
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── _claude_settings_git_state ──────────────────────────────────────────────

@test "_claude_settings_git_state reports clean for an unmodified tracked file" {
  _guard_repo_setup
  run _claude_settings_git_state
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'clean\t%s\tsub/settings.json' "${GUARD_REPO_REAL}")" ]
}

@test "_claude_settings_git_state reports dirty after the tracked file is modified" {
  _guard_repo_setup
  printf 'x' >> "${GUARD_REPO}/sub/settings.json"
  run _claude_settings_git_state
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'dirty\t%s\tsub/settings.json' "${GUARD_REPO_REAL}")" ]
}

@test "_claude_settings_git_state reports untracked for a file outside any git repo" {
  local _outside="${BATS_TEST_TMPDIR}/outside-settings.json"
  printf '{}' > "${_outside}"
  mkdir -p "${HOME}/.claude"
  ln -sf "${_outside}" "${HOME}/.claude/settings.json"
  export _OVERRIDE_CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
  local _outside_real
  _outside_real="$(_realpath "${_outside}")"
  run _claude_settings_git_state
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'untracked\t-\t%s' "${_outside_real}")" ]
}

@test "_claude_settings_git_state reports untracked for a file inside a repo that was never committed" {
  _guard_repo_setup
  local _uncommitted="${GUARD_REPO}/sub/uncommitted.json"
  printf '{}' > "${_uncommitted}"
  export _OVERRIDE_CLAUDE_SETTINGS="${_uncommitted}"
  local _uncommitted_real
  _uncommitted_real="$(_realpath "${_uncommitted}")"
  run _claude_settings_git_state
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'untracked\t%s\t%s' "${GUARD_REPO_REAL}" "${_uncommitted_real}")" ]
}

@test "_claude_settings_git_state reports untracked when the symlink is replaced by a regular file" {
  _guard_repo_setup
  local _settings_path="${HOME}/.claude/settings.json"
  rm -f "${_settings_path}"
  printf '{}' > "${_settings_path}"
  local _settings_real
  _settings_real="$(_realpath "${_settings_path}")"
  run _claude_settings_git_state
  [ "$status" -eq 0 ]
  # ${HOME}/.claude lives INSIDE the fixture repo (_guard_repo_setup), so
  # this is genuinely detachment from a tracked file -- the replacement
  # file is still inside a repo, just no longer the tracked one -- not the
  # weaker "outside any repo" case the "-" placeholder would report.
  [ "$output" = "$(printf 'untracked\t%s\t%s' "${GUARD_REPO_REAL}" "${_settings_real}")" ]
}

@test "_claude_settings_git_state ignores an exported GIT_DIR pointing at a decoy repo" {
  _guard_repo_setup
  local _decoy="${BATS_TEST_TMPDIR}/decoy"
  mkdir -p "${_decoy}"
  "${_CLAUDE_GUARD_GIT}" -C "${_decoy}" init -q
  GIT_DIR="${_decoy}/.git" run _claude_settings_git_state
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'clean\t%s\tsub/settings.json' "${GUARD_REPO_REAL}")" ]
}

# ── _claude_settings_guard_check ────────────────────────────────────────────

@test "_claude_settings_guard_check prints nothing and returns 0 when state is unchanged (clean)" {
  local _clean
  _clean="$(printf 'clean\t/some/repo\tsettings.json')"
  run _claude_settings_guard_check "${_clean}" "${_clean}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_claude_settings_guard_check warns and returns 2 when clean becomes dirty" {
  local _before _after
  _before="$(printf 'clean\t/some/repo\tsettings.json')"
  _after="$(printf 'dirty\t/some/repo\tsettings.json')"
  run _claude_settings_guard_check "${_before}" "${_after}"
  [ "$status" -eq 2 ]
  [ "$output" = "/some/repo/settings.json changed during plugin provisioning — review: git -C /some/repo diff -- settings.json" ]
}

@test "_claude_settings_guard_check warns and returns 2 when clean becomes untracked" {
  local _before _after
  _before="$(printf 'clean\t/some/repo\tsettings.json')"
  _after="$(printf 'untracked\t-\t/some/repo/settings.json')"
  run _claude_settings_guard_check "${_before}" "${_after}"
  [ "$status" -eq 2 ]
  # Full line, not a substring: pins _br/_bp (BEFORE fields) as the message's
  # source, so a mutant swapping in _ar/_ap (AFTER fields, "-"/abspath here)
  # is caught rather than passing on the shared "no longer resolves..." text.
  [ "$output" = "/some/repo/settings.json no longer resolves into a tracked file" ]
}

@test "_claude_settings_guard_check warns and returns 2 when clean becomes unknown" {
  local _before _after
  _before="$(printf 'clean\t/some/repo\tsettings.json')"
  _after="$(printf 'unknown\t/some/repo\tsettings.json')"
  run _claude_settings_guard_check "${_before}" "${_after}"
  [ "$status" -eq 2 ]
  # unknown means the git-status READ failed, not that the file stopped
  # being tracked -- a distinct message from the untracked case above, so
  # asserting only a shared "not checked"/"tracked file" substring could not
  # tell the two branches apart.
  [ "$output" = "could not read git status for /some/repo/settings.json (was clean)" ]
}

@test "_claude_settings_guard_check returns 0 and says not checked when already dirty before" {
  local _dirty
  _dirty="$(printf 'dirty\t/some/repo\tsettings.json')"
  run _claude_settings_guard_check "${_dirty}" "${_dirty}"
  [ "$status" -eq 0 ]
  [ "$output" = "/some/repo/settings.json was already modified; not checked" ]
}

@test "_claude_settings_guard_check returns 0 and says not checked when already untracked before" {
  local _untracked
  _untracked="$(printf 'untracked\t-\t/some/path/settings.json')"
  run _claude_settings_guard_check "${_untracked}" "${_untracked}"
  [ "$status" -eq 0 ]
  # Full line: distinguishes this catch-all ("%s is %s; not checked") from
  # the dirty branch's "%s/%s was already modified; not checked" -- both
  # previously satisfied a bare "not checked" substring, so line 174's
  # message could be copied onto line 175 with nothing catching it.
  [ "$output" = "/some/path/settings.json is untracked; not checked" ]
}

# ── setup_claude_plugins: reconcile ─────────────────────────────────────────
#
# Task 4 of docs/superpowers/specs/2026-09-19-claude-plugin-provisioning-design.md.
# All cases below use the default fixture copy `load_mocks` already points
# `_OVERRIDE_CLAUDE_SETTINGS` at (via `${SETTINGS}`, this file's `setup()`),
# which declares one github marketplace (claude-plugins-official), one git
# marketplace (caveman), and three plugins: superpowers@claude-plugins-official
# (true), caveman@caveman (true), frontend-design@claude-plugins-official
# (false). MOCK_CLAUDE_MARKETPLACE_LIST_JSON and MOCK_CLAUDE_PLUGINS_LIST_JSON
# both default to `[]` (nothing registered, nothing installed) per Task 1,
# so a bare `run setup_claude_plugins` with no overrides exercises the
# "everything missing" path.

@test "setup_claude_plugins adds an unregistered github marketplace as owner/repo" {
  run setup_claude_plugins
  grep -qF "claude plugins marketplace add anthropics/claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins adds an unregistered git marketplace as its URL" {
  run setup_claude_plugins
  grep -qF "claude plugins marketplace add https://github.com/juliusbrussee/caveman.git" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins does not re-add an already-registered marketplace" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  run setup_claude_plugins
  refute_grep "marketplace add" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins installs a missing enabled plugin at user scope" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  run setup_claude_plugins
  grep -qF "claude plugins install -s user superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins never installs a disabled plugin" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  run setup_claude_plugins
  refute_grep "install -s user frontend-design@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins does not count a superstring id as installed" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official-fork","scope":"user"}]'
  run setup_claude_plugins
  grep -qF "claude plugins install -s user superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins does not count a project-scope install as installed" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"project"}]'
  run setup_claude_plugins
  grep -qF "claude plugins install -s user superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins: one marketplace add failing still processes the rest and returns 2" {
  export MOCK_CLAUDE_FAIL_ARGS="marketplace add https"
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$output" == *"caveman"* ]]
  grep -qF "claude plugins install -s user superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins returns 2 and names an unsupported marketplace source and its type" {
  cat > "${SETTINGS}" <<'JSON'
{"extraKnownMarketplaces":{"weird":{"source":{"source":"url","url":"https://example.com"}}},
 "enabledPlugins":{"superpowers@claude-plugins-official":true}}
JSON
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$output" == *"weird"* ]]
  [[ "$output" == *"url"* ]]
}

@test "setup_claude_plugins returns 2 and names it when no plugin is enabled" {
  cat > "${SETTINGS}" <<'JSON'
{"enabledPlugins":{"frontend-design@claude-plugins-official":false}}
JSON
  # --separate-stderr discriminates step 8's channel: log_warn writes
  # recorded failures to stderr, never stdout. Asserting only against
  # $output (bats' merged stream) cannot tell log_warn from log_info --
  # swapping one for the other would fail zero tests.
  run --separate-stderr setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no enabled plugins declared in ${SETTINGS}"* ]]
  # shellcheck disable=SC2154 # $stdout is bats' run --separate-stderr variable; shellcheck's known-names list omits it (unlike $stderr, which it already accepts)
  [[ "$stdout" != *"no enabled plugins declared"* ]]
}

@test "setup_claude_plugins returns 1 with zero claude plugins calls when settings is missing" {
  rm -f "${SETTINGS}"
  run setup_claude_plugins
  [ "$status" -eq 1 ]
  refute_grep "claude plugins" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins returns 1 with zero claude plugins calls when settings is unparsable" {
  printf 'not json' > "${SETTINGS}"
  run setup_claude_plugins
  [ "$status" -eq 1 ]
  refute_grep "claude plugins" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins returns 1 with zero claude plugins calls when settings is a JSON array" {
  printf '[]' > "${SETTINGS}"
  run setup_claude_plugins
  [ "$status" -eq 1 ]
  refute_grep "claude plugins" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins returns 2 with zero add/install calls when the plugin list call fails" {
  export MOCK_CLAUDE_FAIL_ARGS="plugins list --json"
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  refute_grep "marketplace add" "${MOCK_CALLS_FILE}"
  refute_grep "plugins install" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins returns 2 with zero add/install calls when the marketplace list call fails" {
  export MOCK_CLAUDE_FAIL_ARGS="marketplace list --json"
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  refute_grep "marketplace add" "${MOCK_CALLS_FILE}"
  refute_grep "plugins install" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins returns 0 with zero add/install calls when everything is already present" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"},{"id":"caveman@caveman","scope":"user"}]'
  # G3 guard: prove the manifest actually declares at least one enabled
  # plugin before trusting the "zero calls" result below -- otherwise an
  # empty-manifest bug would satisfy this test just as well as a correct
  # reconcile would.
  _claude_plugin_manifest | grep -qE $'^plugin\t[^\t]+\ttrue$'
  run setup_claude_plugins
  [ "$status" -eq 0 ]
  refute_grep "marketplace add" "${MOCK_CALLS_FILE}"
  refute_grep "plugins install" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins: claude not on PATH returns 0 and skips (unchanged)" {
  local _clean_path
  _clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | while read -r _dir; do
    [[ -x "${_dir}/claude" ]] || printf '%s\n' "${_dir}"
  done | tr '\n' ':' | sed 's/:$//')"
  PATH="${_clean_path}" run setup_claude_plugins
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping plugin setup"* ]]
}

@test "setup_claude_plugins redirects marketplace-add and install stdin from /dev/null (mutation pin)" {
  # Regression pin for the `< /dev/null` on BOTH the `claude plugins
  # marketplace add` call and the `claude plugins install` call inside the
  # manifest-reading while loops. tests/mocks/claude never reads its own
  # stdin, so it cannot observe this hazard.
  #
  # Uses the repo's stdin_probe_stub_path helper rather than a hand-rolled
  # stub: it logs `claude <argv> stdin=[<line>]` directly, which lets this
  # test assert the leaked content itself instead of inferring it from an
  # install-count proxy, and it resolves bash to an absolute path at
  # generation time -- required because this test resolves `claude` from a
  # directory holding nothing else, so a `#!/usr/bin/env bash` shebang would
  # depend on `env` still finding `bash` on that scoped PATH.
  #
  # Two unregistered marketplaces and three enabled, not-yet-installed
  # plugins: if either claude call's stdin is a loop's own here-string fd
  # rather than /dev/null, the stub's `read` consumes the NEXT manifest
  # line before that loop's own `read` gets to it, silently dropping an
  # entry -- one fewer add or install than declared, and a non-empty
  # `stdin=[...]` on the line that stole it.
  cat > "${SETTINGS}" <<'JSON'
{
  "extraKnownMarketplaces": {
    "official": {"source": {"source": "github", "repo": "org/official"}},
    "extra": {"source": {"source": "github", "repo": "org/extra"}}
  },
  "enabledPlugins": {
    "a@official": true,
    "b@official": true,
    "c@official": true
  }
}
JSON

  local _stub_dir _orig
  _stub_dir="$(stdin_probe_stub_path claude)"
  _orig="$(cat "${_stub_dir}/claude")"
  # Splice a --json short-circuit ahead of the helper's generic
  # read-then-log body (line 1 is its shebang) so the reconcile's two list
  # reads get a valid empty array instead of being routed into the stdin
  # probe meant for marketplace-add/install.
  {
    head -n1 <<<"${_orig}"
    cat <<'CASE'
case "$*" in
  "plugins marketplace list --json") printf '[]\n'; exit 0 ;;
  "plugins list --json") printf '[]\n'; exit 0 ;;
esac
CASE
    tail -n +2 <<<"${_orig}"
  } > "${_stub_dir}/claude"
  chmod +x "${_stub_dir}/claude"

  PATH="${_stub_dir}:${PATH}" run setup_claude_plugins
  [ "$status" -eq 0 ]
  local _n_add _n_install
  _n_add="$(grep -c 'plugins marketplace add' "${MOCK_CALLS_FILE}")"
  _n_install="$(grep -c 'plugins install -s user' "${MOCK_CALLS_FILE}")"
  [ "${_n_add}" -eq 2 ]
  [ "${_n_install}" -eq 3 ]
  # Direct assertion on the leaked content itself, not just the count: every
  # logged add/install line carries an empty stdin=[] when correctly
  # redirected.
  refute_grep 'stdin=\[.\+\]' "${MOCK_CALLS_FILE}" -E
}

# ── setup_claude_plugins: malformed manifest entries ────────────────────────

@test "setup_claude_plugins records a failure for an empty marketplace name rather than treating it as registered" {
  # An empty-string marketplace key emits "marketplace\t\torg/repo" -- two
  # ADJACENT tabs. `IFS=$'\t' read -r _type _name _ref` would silently
  # collapse that run of tabs into one delimiter (bash always treats tab as
  # "IFS whitespace" regardless of what else IFS holds), landing "org/repo"
  # in _name and leaving _ref empty -- a field-shift bug, not merely an
  # empty _name. Verified directly: `printf 'a\t\tb\n' | { IFS=$'\t' read -r
  # x y z; ...; }` yields x=a y=b z=[]. _claude_manifest_split_line exists
  # to avoid this; this test pins the empty-name outcome it restores.
  cat > "${SETTINGS}" <<'JSON'
{"extraKnownMarketplaces":{"":{"source":{"source":"github","repo":"org/repo"}}}}
JSON
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$output" == *"empty name"* ]]
  refute_grep "marketplace add" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins records a failure for an empty plugin id rather than treating it as installed" {
  cat > "${SETTINGS}" <<'JSON'
{"enabledPlugins":{"":true}}
JSON
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$output" == *"empty id"* ]]
  refute_grep "plugins install" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins records a failure for a marketplace name containing an embedded tab, and does not add it" {
  # A key containing a literal tab re-splits the manifest line into a 4th
  # field: "marketplace\ta\tb\torg/repo" reads (under the old 3-var read)
  # as _name="a", _ref="b<TAB>org/repo" -- the real source silently lost.
  # Verified directly against the manifest reader before this fix existed.
  printf '{"extraKnownMarketplaces":{"a\\tb":{"source":{"source":"github","repo":"org/repo"}}}}' > "${SETTINGS}"
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed"* ]]
  refute_grep "marketplace add" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins records a failure for a plugin id containing an embedded tab, and does not install it" {
  # Confirmed against the pre-fix reader: id "a\tb" makes _ref literally
  # "b<TAB>true", which fails the old `_ref == "true"` check and silently
  # drops the entry entirely -- no install, no failure, no count. This
  # entry must now surface as a recorded failure instead of vanishing.
  printf '{"enabledPlugins":{"a\\tb":true}}' > "${SETTINGS}"
  run setup_claude_plugins
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed"* ]]
  refute_grep "plugins install" "${MOCK_CALLS_FILE}"
}

# ── provision_claude_plugins ─────────────────────────────────────────────────

@test "provision_claude_plugins warns but still returns setup_claude_plugins's rc when settings.json changes during provisioning" {
  _guard_repo_setup
  # Overwrite the {} _guard_repo_setup committed with a manifest carrying
  # one enabled, not-yet-installed plugin, then commit it -- the BEFORE
  # state this test needs is "clean", so the change must be committed
  # rather than left dirty (that is the second test below).
  cat > "${GUARD_REPO}/sub/settings.json" <<'JSON'
{"enabledPlugins":{"superpowers@claude-plugins-official":true}}
JSON
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" -c user.email=t@t -c user.name=T add sub/settings.json
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" -c user.email=t@t -c user.name=T commit -qm update
  # tests/mocks/claude appends a newline to _OVERRIDE_CLAUDE_SETTINGS on the
  # `install` call that this manifest triggers, simulating the CLI editing
  # settings.json as a side effect of installing a plugin.
  export MOCK_CLAUDE_EDIT_SETTINGS=install
  run provision_claude_plugins
  # setup_claude_plugins itself has no failures (the install call the mock
  # intercepts still exits 0), so the wrapper's rc must be 0 -- the guard's
  # own rc (2, since the file just went clean -> dirty) must not leak out.
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed during plugin provisioning"* ]]
  # A guard warning must reach log_warn, not log_info. bats merges stderr
  # into $output, so without this the routing is unobserved and swapping
  # the two calls leaves every other assertion in this file green.
  [[ "$output" == *"[WARN]"* ]]
}

@test "provision_claude_plugins reports an already-dirty settings.json without checking further, and still returns setup_claude_plugins's rc" {
  _guard_repo_setup
  # Dirty the tracked file BEFORE calling provision_claude_plugins, so the
  # state it captures going in is already "dirty" -- distinct from the
  # clean-then-dirty case above.
  printf '\n' >> "${GUARD_REPO}/sub/settings.json"
  run provision_claude_plugins
  # {} (from _guard_repo_setup) declares no enabled plugins, so
  # setup_claude_plugins's own "no enabled plugins declared" failure is
  # what sets this rc -- the guard's "not checked" branch always returns 0
  # on its own account and must not override it.
  [ "$status" -eq 2 ]
  [[ "$output" == *"was already modified; not checked"* ]]
  # An informational guard line is log_info, never log_warn: a file that
  # was already dirty before provisioning started is not a finding.
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" != *"[WARN]  ${GUARD_REPO_REAL}"* ]]
}

@test "provision_claude_plugins prints no guard line at all when settings.json stays clean" {
  _guard_repo_setup
  # clean -> clean is the third routing case the guard has to handle, and
  # the only one whose correct output is nothing. Without this test the
  # `[[ -n ${_msg} ]]` emptiness guard can be deleted and the suite stays
  # green while every clean provision emits a bare, contentless log line.
  run provision_claude_plugins
  [ "$status" -eq 2 ]
  # Nothing on this path logs at INFO: the {} manifest reaches no install
  # and no marketplace add, so an [INFO] line here can only be the guard's.
  # Asserting on the level rather than on each message text is what makes
  # the emptiness guard load-bearing -- `log_info ""` still prints a line,
  # and it carries none of the guard's message text to match against.
  [[ "$output" != *"[INFO]"* ]]
}
