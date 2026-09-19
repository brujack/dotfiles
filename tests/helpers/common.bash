#!/usr/bin/env bash
# Shared BATS test helpers

# Absolute path to repo root (two levels up from tests/helpers/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Prepend tests/mocks/ to PATH so mock executables shadow real ones
load_mocks() {
  export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
  # Default pyenv-which to the mock python so run_update's pip section never
  # shells out to real python3/pip on dev machines (real pip is slow, hits the
  # network, and mutates the ansible venv). Individual tests may override it.
  export MOCK_PYENV_WHICH_STDOUT="${REPO_ROOT}/tests/mocks/python"
  # install_cargo_tools resolves _CARGO_BIN before ${HOME}/.cargo/bin/cargo or
  # a PATH cargo, so any suite that calls load_mocks gets the mock here and
  # cannot compile crates for real (tdd.md E2). Residual: a test that
  # deliberately unsets _CARGO_BIN (to exercise the other resolution
  # branches) is on its own to keep ${HOME}/.cargo/bin and PATH cargo-free,
  # and a suite that never calls load_mocks at all (e.g.
  # tests/setup_env/git_sync.bats) gets no protection from this seam.
  export _CARGO_BIN="${REPO_ROOT}/tests/mocks/cargo"
  # Every run_update/run_setup_user test runs under a redirected HOME with no
  # settings file; point the claude plugin manifest reader at a per-test COPY
  # of the fixture under BATS_TEST_TMPDIR, never the tracked file itself.
  # tests/mocks/claude's MOCK_CLAUDE_EDIT_SETTINGS mode appends to whatever
  # this points at, so pointing it at the tracked fixture would let a test
  # dirty the working tree (`git status` showing `M tests/fixtures/...`).
  cp "${REPO_ROOT}/tests/fixtures/claude-settings.json" "${BATS_TEST_TMPDIR}/claude-settings.json"
  export _OVERRIDE_CLAUDE_SETTINGS="${BATS_TEST_TMPDIR}/claude-settings.json"
}

# Assert a pattern is ABSENT from a file.
#
# Use this instead of `! grep -q ...`. A bare `!` only fails a bats test while
# it is the last command in the @test body — anywhere else the negation is
# silently ignored and the assertion cannot fail at all (shellcheck SC2314).
# Six assertions in this suite were inert for exactly that reason, each one the
# first of two consecutive negative checks, and each covering the "skips X"
# half of its test's claim. Failure output names what was actually found,
# which a bare `!` never did.
#
# Extra args are passed through to grep, so `refute_grep -E 'pat' file` works.
refute_grep() {
  local _pattern="$1" _file="$2"
  shift 2
  if grep -q "$@" -- "${_pattern}" "${_file}" 2>/dev/null; then
    printf 'expected no match for %s in %s, found:\n%s\n' \
      "${_pattern}" "${_file}" "$(grep "$@" -- "${_pattern}" "${_file}")" >&2
    return 1
  fi
}

# Write a stub for <name> that logs its argv plus the first line it can read
# from stdin, and print the stub's directory so the caller can prepend it to
# PATH. Pair it with a caller-supplied stdin file carrying a sentinel line:
# `stdin=[]` means the command's stdin was redirected away from the caller's,
# `stdin=[<sentinel>]` means it inherited it. The file is regular, so the read
# reaches EOF rather than blocking on an fd that never closes.
stdin_probe_stub_path() {
  local _name="$1" _dir _bash_bin
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  _bash_bin="$(command -v bash)"
  cat > "${_dir}/${_name}" << EOF
#!${_bash_bin}
IFS= read -r _line || true
printf '%s %s stdin=[%s]\n' "${_name}" "\$*" "\${_line}" >> "\${MOCK_CALLS_FILE}"
exit 0
EOF
  chmod +x "${_dir}/${_name}"
  printf '%s' "${_dir}"
}

# Source setup_env.sh — the sourcing guard prevents main body execution
load_setup_env() {
  source "${REPO_ROOT}/setup_env.sh"
  # shellcheck disable=SC2317 # NOT dead: setup_env.sh's own
  # `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` guard always returns
  # true here (this call is always a `source`), so control returns to this
  # point every time. shellcheck only reports this when it follows
  # setup_env.sh's body (e.g. `shellcheck -x`, or when setup_env.sh is also
  # passed on the command line) — it can't resolve the guard's BASH_SOURCE
  # condition statically, so it treats setup_env.sh's own unconditional
  # trailing `exit 0` as making everything after this `source` unreachable.
  export BATS_VER  # export so mock scripts can reference it
}
