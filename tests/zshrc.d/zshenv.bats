#!/usr/bin/env bats

# .zshenv is read by non-interactive zsh, the actor that resolves python3 to
# Apple's 3.9.6 on macOS. Every case runs zsh with HOME and ZDOTDIR pointed at
# fixtures so the real ~/.zshenv and ~/.zshenv.local are never read.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  FX_HOME="${BATS_TEST_TMPDIR}/home"
  FX_ZDOT="${BATS_TEST_TMPDIR}/zdot"
  FX_PREFIX="${BATS_TEST_TMPDIR}/brew"
  FX_BIN="${FX_PREFIX}/opt/python@3/libexec/bin"
  mkdir -p "${FX_HOME}" "${FX_ZDOT}" "${FX_BIN}"
  ln -s "${REPO_ROOT}/.zshenv" "${FX_ZDOT}/.zshenv"
  printf '#!/bin/sh\necho FIXTURE_PY3\n' > "${FX_BIN}/python3"
  chmod +x "${FX_BIN}/python3"
}

# Run zsh with the fixture environment; args are passed to zsh. The caller's
# CLAUDE_CODE_PLUGIN_DIRS is always dropped; set PLUGIN_DIRS to hand zsh one.
_zsh() {
  env -u CLAUDE_CODE_PLUGIN_DIRS ${PLUGIN_DIRS+CLAUDE_CODE_PLUGIN_DIRS="${PLUGIN_DIRS}"} \
    HOME="${FX_HOME}" ZDOTDIR="${FX_ZDOT}" PATH=/usr/bin:/bin \
    _OVERRIDE_HOMEBREW_PREFIX_ARM="${ARM:-${FX_PREFIX}}" \
    _OVERRIDE_HOMEBREW_PREFIX_INTEL="${INTEL:-${BATS_TEST_TMPDIR}/nonexistent}" \
    zsh "$@"
}

@test "non-interactive zsh resolves python3 to the fixture (positive control)" {
  run _zsh -c 'python3'
  [ "$status" -eq 0 ]
  [ "$output" = "FIXTURE_PY3" ]
}

@test "non-interactive PATH starts with the python@3 libexec/bin" {
  run _zsh -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [[ "$output" == "${FX_BIN}:"* ]]
}

@test "interactive zsh does not get the python@3 directory" {
  run _zsh +Z -i -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [[ "$output" != *"${FX_BIN}"* ]]
}

@test "absent python@3 directory leaves PATH unchanged" {
  rm -rf "${FX_BIN}"
  run _zsh -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin:/bin" ]
}

@test "INTEL prefix is used when ARM prefix is absent" {
  ARM="${BATS_TEST_TMPDIR}/nonexistent" INTEL="${FX_PREFIX}" run _zsh -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [[ "$output" == "${FX_BIN}:"* ]]
}

@test "nested non-interactive zsh carries the directory exactly once" {
  run _zsh -c 'zsh -c "print -r -- \$PATH"'
  [ "$status" -eq 0 ]
  local stripped="${output//${FX_BIN}/}"
  [[ "$output" == *"${FX_BIN}"* ]]
  [ $(( (${#output} - ${#stripped}) / ${#FX_BIN} )) -eq 1 ]
}

@test ".zshenv.local is sourced by non-interactive and interactive zsh" {
  printf 'export ZSHENV_LOCAL_MARK=1\n' > "${FX_HOME}/.zshenv.local"
  run _zsh -c 'print -r -- "mark=${ZSHENV_LOCAL_MARK}"'
  [ "$status" -eq 0 ]
  [ "$output" = "mark=1" ]
  run _zsh +Z -i -c 'print -r -- "mark=${ZSHENV_LOCAL_MARK}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"mark=1" ]]
}

@test "inherited PATH that already resolves python3 elsewhere is kept" {
  mkdir -p "${BATS_TEST_TMPDIR}/shims"
  printf '#!/bin/sh\necho INHERITED_PY3\n' > "${BATS_TEST_TMPDIR}/shims/python3"
  chmod +x "${BATS_TEST_TMPDIR}/shims/python3"
  run env HOME="${FX_HOME}" ZDOTDIR="${FX_ZDOT}" PATH="${BATS_TEST_TMPDIR}/shims:/usr/bin:/bin" \
    _OVERRIDE_HOMEBREW_PREFIX_ARM="${FX_PREFIX}" \
    _OVERRIDE_HOMEBREW_PREFIX_INTEL="${BATS_TEST_TMPDIR}/nonexistent" \
    zsh -c 'python3'
  [ "$status" -eq 0 ]
  [ "$output" = "INHERITED_PY3" ]
  run env HOME="${FX_HOME}" ZDOTDIR="${FX_ZDOT}" PATH="${BATS_TEST_TMPDIR}/shims:/usr/bin:/bin" \
    _OVERRIDE_HOMEBREW_PREFIX_ARM="${FX_PREFIX}" \
    _OVERRIDE_HOMEBREW_PREFIX_INTEL="${BATS_TEST_TMPDIR}/nonexistent" \
    zsh -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [[ "$output" != *"${FX_BIN}"* ]]
}

@test "PATH with no python3 at all still gets the python@3 directory" {
  local _nopy="${BATS_TEST_TMPDIR}/nopy"
  mkdir -p "${_nopy}"
  run env HOME="${FX_HOME}" ZDOTDIR="${FX_ZDOT}" PATH="${_nopy}" \
    _OVERRIDE_HOMEBREW_PREFIX_ARM="${FX_PREFIX}" \
    _OVERRIDE_HOMEBREW_PREFIX_INTEL="${BATS_TEST_TMPDIR}/nonexistent" \
    "$(command -v zsh)" -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [ "$output" = "${FX_BIN}:${_nopy}" ]
}

@test "ARM prefix wins when both ARM and INTEL python@3 directories exist" {
  local _intel="${BATS_TEST_TMPDIR}/intel"
  mkdir -p "${_intel}/opt/python@3/libexec/bin"
  INTEL="${_intel}" run _zsh -c 'print -r -- $PATH'
  [ "$status" -eq 0 ]
  [[ "$output" == "${FX_BIN}:"* ]]
  [[ "$output" != *"${_intel}"* ]]
}

# CLAUDE_CODE_PLUGIN_DIRS: Claude Code loads each ':'-separated absolute path as a
# --plugin-dir. FX_HOME stands in for HOME, so the guarded path is a fixture.

@test "present progress mod dir is exported as CLAUDE_CODE_PLUGIN_DIRS" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  run _zsh -c 'print -r -- "${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "${FX_HOME}/.claude/mods/progress" ]
}

@test "absent progress mod dir leaves CLAUDE_CODE_PLUGIN_DIRS unset" {
  run _zsh -c 'print -r -- "set=${+CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "set=0" ]
}

@test "inherited CLAUDE_CODE_PLUGIN_DIRS is kept and the mod dir appended" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  PLUGIN_DIRS=/opt/other-mod run _zsh -c 'print -r -- "${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/other-mod:${FX_HOME}/.claude/mods/progress" ]
}

@test "nested zsh carries the progress mod dir exactly once" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  PLUGIN_DIRS=/opt/other-mod run _zsh -c 'zsh -c "print -r -- \${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/other-mod:${FX_HOME}/.claude/mods/progress" ]
}

@test "mod dir already first in an inherited list is not appended again" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  PLUGIN_DIRS="${FX_HOME}/.claude/mods/progress:/opt/other-mod" run _zsh -c 'print -r -- "${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "${FX_HOME}/.claude/mods/progress:/opt/other-mod" ]
}

@test "a path that only extends the mod dir does not count as the mod dir" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  PLUGIN_DIRS="${FX_HOME}/.claude/mods/progress-old" run _zsh -c 'print -r -- "${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "${FX_HOME}/.claude/mods/progress-old:${FX_HOME}/.claude/mods/progress" ]
}

@test "empty inherited CLAUDE_CODE_PLUGIN_DIRS gets the mod dir with no leading colon" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  PLUGIN_DIRS='' run _zsh -c 'print -r -- "${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "${FX_HOME}/.claude/mods/progress" ]
}

@test "CLAUDE_CODE_PLUGIN_DIRS reaches child processes of interactive zsh" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  run _zsh +Z -i -c 'printenv CLAUDE_CODE_PLUGIN_DIRS'
  [ "$status" -eq 0 ]
  [[ "$output" == *"${FX_HOME}/.claude/mods/progress" ]]
}

@test "absent progress mod dir keeps an inherited CLAUDE_CODE_PLUGIN_DIRS unchanged" {
  PLUGIN_DIRS=/opt/other-mod run _zsh -c 'print -r -- "${CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/other-mod" ]
}

@test ".zshenv.local runs after the export and can override it" {
  mkdir -p "${FX_HOME}/.claude/mods/progress"
  printf 'unset CLAUDE_CODE_PLUGIN_DIRS\n' > "${FX_HOME}/.zshenv.local"
  run _zsh -c 'print -r -- "set=${+CLAUDE_CODE_PLUGIN_DIRS}"'
  [ "$status" -eq 0 ]
  [ "$output" = "set=0" ]
}
