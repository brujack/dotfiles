#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
  # load_setup_env above sources lib/constants.sh BEFORE this HOME override, so
  # GITREPOS="${HOME}/git-repos" is already bound to the REAL home. update_aws_cli
  # ends with `cd "${PERSONAL_GITREPOS}/${DOTFILES}"`, so without these exports the
  # positive tests pass only on a machine where ~/git-repos/personal/dotfiles
  # happens to exist -- green here, red on ubuntu-latest, which has no such path.
  # Same shape as extracted_functions.bats:12-19, and at setup() scope so the trap
  # is not left armed for the next test added to this file.
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  # The VARIABLES are setup()-scope; the DIRECTORY is not. `clone_personal_repos:
  # calls git clone for dotfiles when dir missing` (below) requires
  # ${PERSONAL_GITREPOS}/${DOTFILES} to be ABSENT, so creating it here would make
  # that test assert nothing while still passing its status check. Each test that
  # needs the directory creates it itself.
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── setup_vim_plugins ────────────────────────────────────────────────────────

@test "setup_vim_plugins: creates .vim/plugged and .vim/autoload directories" {
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.vim/plugged" ]
  [ -d "${HOME}/.vim/autoload" ]
}

@test "setup_vim_plugins: downloads plug.vim when it does not exist" {
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  grep -q "curl.*plug.vim" "${MOCK_CALLS_FILE}"
}

@test "setup_vim_plugins: skips curl when plug.vim already exists" {
  mkdir -p "${HOME}/.vim/autoload"
  touch "${HOME}/.vim/autoload/plug.vim"
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  ! grep -q "curl.*plug.vim" "${MOCK_CALLS_FILE}"
}

# ── update_aws_cli ───────────────────────────────────────────────────────────

@test "update_aws_cli: returns 1 when curl fails on macOS" {
  export MACOS=1 HAS_AWS=1
  unset LINUX
  mkdir -p "${HOME}/software_downloads/awscli"
  export MOCK_CURL_EXIT=1
  run update_aws_cli
  [ "$status" -eq 1 ]
}

@test "update_aws_cli: returns 0 when every command succeeds on macOS" {
  # update_aws_cli ends with `cd "${PERSONAL_GITREPOS}/${DOTFILES}"`; this test
  # runs through to it, so the directory must exist. Created here rather than in
  # setup() -- see the note there.
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  export MACOS=1 HAS_AWS=1
  unset LINUX
  mkdir -p "${HOME}/software_downloads/awscli"
  run update_aws_cli
  [ "$status" -eq 0 ]
}

@test "update_aws_cli: removes the pkg when the installer fails on macOS" {
  export MACOS=1 HAS_AWS=1
  unset LINUX
  mkdir -p "${HOME}/software_downloads/awscli"
  export MOCK_INSTALLER_EXIT=1
  run update_aws_cli
  [ "$status" -eq 1 ]
  [ ! -f "${HOME}/software_downloads/awscli/AWSCLIV2.pkg" ]
}

@test "update_aws_cli: creates the awscli directory before cd on macOS" {
  # update_aws_cli ends with `cd "${PERSONAL_GITREPOS}/${DOTFILES}"`; this test
  # runs through to it, so the directory must exist. Created here rather than in
  # setup() -- see the note there.
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  export MACOS=1 HAS_AWS=1
  unset LINUX
  # software_downloads/awscli deliberately absent -- setup() only creates
  # software_downloads itself. This drives the macOS/Linux mkdir asymmetry:
  # the Linux branch has always created its own directory; the macOS branch
  # did not, and would fail here via the `cd ... || return 1` guard alone.
  run update_aws_cli
  [ "$status" -eq 0 ]
  [ -d "${HOME}/software_downloads/awscli" ]
}

# ── update_rust ──────────────────────────────────────────────────────────────

@test "update_rust: skips when UBUNTU not set" {
  unset UBUNTU
  export HAS_RUST=1
  run update_rust
  [ "$status" -eq 0 ]
  ! grep -q "rustup" "${MOCK_CALLS_FILE:-/dev/null}"
}

@test "update_rust: calls ~/.cargo/bin/rustup when it exists" {
  export UBUNTU=1
  export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
  grep -q "rustup component add" "${MOCK_CALLS_FILE}"
}

@test "update_rust: uses PATH rustup when ~/.cargo/bin/rustup is missing" {
  export UBUNTU=1
  export HAS_RUST=1
  # No ~/.cargo/bin/rustup in fake HOME; tests/mocks/rustup is in PATH via load_mocks
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
}

@test "update_rust: logs warning when rustup not found" {
  export UBUNTU=1
  export HAS_RUST=1
  # Restrict PATH so command -v rustup fails (no mocks, no ~/.cargo/bin/rustup)
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run update_rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"rustup not found"* ]]
}

@test "update_rust: does not call nextest curl when rustup found (brew manages updates)" {
  export UBUNTU=1
  export HAS_RUST=1
  mkdir -p "${HOME}/.cargo/bin"
  cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  printf '#!/usr/bin/env bash\n' > "${HOME}/.cargo/bin/cargo-nextest"
  chmod +x "${HOME}/.cargo/bin/cargo-nextest"
  export PATH="${HOME}/.cargo/bin:${PATH}"
  run update_rust
  [ "$status" -eq 0 ]
  run grep "nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
}

@test "update_rust: skips nextest update when rustup not found" {
  export UBUNTU=1
  export HAS_RUST=1
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  run update_rust
  [ "$status" -eq 0 ]
  ! grep -q "get.nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
}

# ── update_rust: fail-fast across all three rustup calls ─────────────────────
#
# One helper, driven four ways. Three tests asserting rc=1 and BOTH halves of
# fail-fast -- the failing subcommand ran, the NEXT one did not -- plus one
# all-succeed case pinning the whole sequence in order.
#
# Why not a single "returns 1 when rustup update fails" test: mutation showed it
# verified one of the three `|| return 1` guards. Deleting the guard from
# `self update` or from `component add` survived all 14 update_rust tests across
# both files, and asserting only `status -eq 1` also passes when rustup never
# resolves at all -- so it could not tell "the guard propagated" from "nothing
# ran". Each test below now names a guard no other test kills.
#
# PATH carries no inherited entries and no repo mock: the fixture bin, then the
# minimal system set. A filtered PATH is not inert -- it leaves ~/.cargo/bin
# reachable, which is how an earlier version of this test ran a real
# `rustup self update` against the operator's toolchain (tdd.md E2).
_rust_mock() {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> "%s/rustup_calls"\n' "${BATS_TEST_TMPDIR}"
    printf '[ "$*" = "%s" ] && exit 1\n' "$1"
    printf 'exit 0\n'
  } > "${BATS_TEST_TMPDIR}/bin/rustup"
  chmod +x "${BATS_TEST_TMPDIR}/bin/rustup"
  export PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export HOME="${BATS_TEST_TMPDIR}"
  export UBUNTU=1 HAS_RUST=1
}

@test "update_rust returns 1 and stops when 'self update' fails" {
  _rust_mock "self update"
  run update_rust
  [ "$status" -eq 1 ]
  grep -qx "self update" "${BATS_TEST_TMPDIR}/rustup_calls"
  # fail-fast: neither later subcommand may have run. Counted, not `! grep` --
  # SC2314: a leading `!` does NOT fail a bats test, so the negative form is
  # inert and would pass whether or not the subcommand ran.
  [ "$(grep -cx "update" "${BATS_TEST_TMPDIR}/rustup_calls")" -eq 0 ]
  [ "$(grep -cx "component add rust-analyzer" "${BATS_TEST_TMPDIR}/rustup_calls")" -eq 0 ]
}

@test "update_rust returns 1 and stops when 'update' fails" {
  _rust_mock "update"
  run update_rust
  [ "$status" -eq 1 ]
  grep -qx "self update" "${BATS_TEST_TMPDIR}/rustup_calls"
  grep -qx "update" "${BATS_TEST_TMPDIR}/rustup_calls"
  ! grep -qx "component add rust-analyzer" "${BATS_TEST_TMPDIR}/rustup_calls"
}

# The guard on `component add` is an EQUIVALENT MUTANT: it is the terminal
# statement, so dropping `|| return 1` leaves its non-zero exit as the function's
# return value regardless. Measured -- with the guard removed, this test still
# passes. Kept because the three calls should read alike, not because a test can
# tell the difference. Do not add an assertion to "cover" it; none can.
@test "update_rust returns 1 when 'component add' fails" {
  _rust_mock "component add rust-analyzer"
  run update_rust
  [ "$status" -eq 1 ]
  grep -qx "component add rust-analyzer" "${BATS_TEST_TMPDIR}/rustup_calls"
}

@test "update_rust runs all three subcommands in order when each succeeds" {
  _rust_mock "__none__"
  run update_rust
  [ "$status" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/rustup_calls")" = "self update
update
component add rust-analyzer" ]
}

# ── clone_personal_repos ─────────────────────────────────────────────────────

@test "clone_personal_repos: skips git clone when dotfiles dir exists" {
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  mkdir -p "${PERSONAL_GITREPOS}/dotfiles"
  run clone_personal_repos
  [ "$status" -eq 0 ]
  ! grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
}

@test "clone_personal_repos: calls git clone for dotfiles when dir missing" {
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  mkdir -p "${PERSONAL_GITREPOS}"
  run clone_personal_repos
  [ "$status" -eq 0 ]
  grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
}

# ── setup_ansible — Linux branch ─────────────────────────────────────────────

@test "setup_ansible: calls pyenv update on Linux when Python version absent" {
  export LINUX=1; unset MACOS
  export HAS_DEVTOOLS=1
  run setup_ansible
  grep -q "pyenv update" "${MOCK_CALLS_FILE}"
}

@test "the manifest still declares passlib" {
  # passlib backs ansible's password_hash filter; it has no other consumer and
  # is the package most likely to look droppable to someone pruning the list
  grep -q '"passlib"' "${BATS_TEST_DIRNAME}/../../pyproject.toml"
}

# ── declared package set ──────────────────────────────────────────────────────
#
# The package set now lives in one place. wheel's deletion is asserted against
# that declaration rather than against a pip invocation, because there is no
# longer a pip invocation to inspect. The positive control is a package that
# must still be declared, so a renamed or moved manifest fails loudly instead
# of making the absence assertion vacuous.

@test "pyproject.toml declares the package set and no longer carries wheel" {
  local _manifest="${BATS_TEST_DIRNAME}/../../pyproject.toml"
  [ -f "${_manifest}" ]
  grep -q '"ansible-lint"' "${_manifest}"
  if grep -qE '^\s*"wheel"' "${_manifest}"; then
    printf "wheel is still declared in pyproject.toml\n" >&2
    return 1
  fi
}

@test "pyproject.toml no longer declares boto3" {
  # AWS CLI v1 was a Python package and needed botocore on the same interpreter,
  # which is why boto3 was declared here in the first place. v2 ships a
  # self-contained binary with its own vendored Python, so that reason lapsed.
  # The package itself is still INSTALLED -- checkov and cloudsplaining both
  # require it -- so this pins the declaration only. Without the assertion the
  # lapsed reason is invisible in the file and a future prune or re-add is silent.
  local _manifest="${BATS_TEST_DIRNAME}/../../pyproject.toml"
  [ -f "${_manifest}" ]
  # positive control: a declaration that must still be there, so a renamed or
  # moved manifest fails loudly instead of making the absence vacuous
  grep -q '"ansible"' "${_manifest}"
  if grep -qE '^\s*"boto3' "${_manifest}"; then
    printf "boto3 is declared again in pyproject.toml\n" >&2
    return 1
  fi
}

@test "checkov carries a floor at or above 3.3.13" {
  # dotfiles#227, titled "bump asteval from 1.0.6 to 1.0.9", silently walked
  # checkov 3.3.13 -> 3.2.414 and auto-merged. checkov pins asteval exactly, so
  # forcing 1.0.9 made every checkov >=3.2.459 unsatisfiable and the resolver
  # quietly chose an older one -- taking openai 0.28.1 with it, which held
  # shell-gpt five minor versions back. The floor does not prevent that
  # conflict; it makes it LOUD, because a forced bump now errors naming both
  # packages instead of resolving backwards. A bare "checkov" restores the
  # silence, so the floor's presence is the property under test.
  local _manifest="${BATS_TEST_DIRNAME}/../../pyproject.toml"
  local _decl _floor
  _decl=$(grep -oE '"checkov[^"]*"' "${_manifest}" | head -1)
  if [[ -z ${_decl} ]]; then
    printf "checkov is not declared in pyproject.toml at all\n" >&2
    return 1
  fi
  _floor=$(printf '%s' "${_decl}" | grep -oE '>=[0-9]+(\.[0-9]+)*' | tr -d '>=')
  if [[ -z ${_floor} ]]; then
    printf "checkov is declared as %s -- no >= floor, so it can walk backwards silently\n" \
      "${_decl}" >&2
    return 1
  fi
  # sort -V rather than a literal match, so raising the floor stays green
  if [[ "$(printf '3.3.13\n%s\n' "${_floor}" | sort -V | head -1)" != "3.3.13" ]]; then
    printf "checkov floor %s is below 3.3.13\n" "${_floor}" >&2
    return 1
  fi
}

@test "the package set is declared once — not in lib/developer.sh" {
  if grep -q '_pip_pkgs' "${BATS_TEST_DIRNAME}/../../lib/developer.sh"; then
    printf "lib/developer.sh still carries a hardcoded package array\n" >&2
    return 1
  fi
}

# ── uv-managed dependency install (step 4) ───────────────────────────────────
#
# Both venv-creating sites install from the committed lock rather than from a
# hardcoded array. Each absence assertion carries a positive control, and the
# missing-uv cases assert the function FAILS rather than silently installing
# nothing — a new hard dependency with no guard is worse than the duplication
# it replaces.

@test "setup_ansible: installs from the lock, not a package array" {
  export LINUX=1; unset MACOS
  export HAS_DEVTOOLS=1
  run setup_ansible
  grep -q "uv sync" "${MOCK_CALLS_FILE}"
  if grep -q "pip install" "${MOCK_CALLS_FILE}"; then
    printf "still installing from a hardcoded package list\n" >&2
    return 1
  fi
}

@test "setup_ansible: uv sync targets the ansible venv" {
  export LINUX=1; unset MACOS
  export HAS_DEVTOOLS=1
  run setup_ansible
  grep -q "uv sync.*--group runtime" "${MOCK_CALLS_FILE}"
  grep -q "uv sync.*--group test-lint" "${MOCK_CALLS_FILE}"
  grep -q "uv sync.*--frozen" "${MOCK_CALLS_FILE}"
}

@test "recreate_python_venv: installs from the lock, not a package array" {
  export LINUX=1; unset MACOS
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  run recreate_python_venv ansible
  grep -q "uv sync" "${MOCK_CALLS_FILE}"
  if grep -q "pip install" "${MOCK_CALLS_FILE}"; then
    printf "still installing from a hardcoded package list\n" >&2
    return 1
  fi
}

# resolve_uv has TWO distinct failure branches and they must not be conflated:
# a misconfigured UV_BIN, and uv genuinely absent. Both mention "uv", so an
# assertion on that substring cannot tell them apart -- and most of the run's
# output mentions uv anyway. Each test below pins its branch's own message.

@test "recreate_python_venv: fails loudly when UV_BIN points at a non-executable" {
  export LINUX=1; unset MACOS
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export UV_BIN="${BATS_TEST_TMPDIR}/no-such-uv"
  run recreate_python_venv ansible
  [ "${status}" -ne 0 ]
  if [[ "${output}" != *"UV_BIN is set to"* ]]; then
    printf "took a different failure branch than the UV_BIN one\n" >&2
    return 1
  fi
}

@test "resolve_uv fails with an install remedy when uv is genuinely absent" {
  unset UV_BIN
  # Empty PATH plus an empty candidate list is the only way to reach this
  # branch: on a machine that has uv the real prefixes always resolve.
  # shellcheck disable=SC2034 # read by resolve_uv, which is sourced, not defined here
  UV_FALLBACK_PATHS=("${BATS_TEST_TMPDIR}/nope")
  local _out _rc=0
  _out="$(PATH="${BATS_TEST_TMPDIR}" resolve_uv 2>&1)" || _rc=$?
  [ "${_rc}" -ne 0 ]
  if [[ "${_out}" != *"uv not found"* ]]; then
    printf "wrong branch: %s\n" "${_out}" >&2
    return 1
  fi
  if [[ "${_out}" == *"UV_BIN is set to"* ]]; then
    printf "took the UV_BIN branch instead of the not-found branch\n" >&2
    return 1
  fi
}

@test "resolve_uv falls back to a brew prefix when uv is not on PATH" {
  # This is the branch resolve_uv exists for: a git hook or cron job whose PATH
  # never sourced a profile and so cannot see the brew prefix. Stripping the
  # mocks dir is what makes the fallback reachable — with the mock present the
  # `command -v` branch answers first and this path never runs.
  unset UV_BIN
  local _found
  _found="$(PATH="/usr/bin:/bin" resolve_uv)" || _found=""
  if [[ -z "${_found}" ]]; then
    printf "resolve_uv found nothing with a bare PATH; the prefix fallback is dead\n" >&2
    return 1
  fi
  [[ "${_found}" == /* ]]
  [[ -x "${_found}" ]]
}

@test "resolve_uv prefers an explicit UV_BIN over PATH" {
  local _fake="${BATS_TEST_TMPDIR}/my-uv"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_fake}"; chmod +x "${_fake}"
  export UV_BIN="${_fake}"
  local _got
  _got="$(resolve_uv)"
  [ "${_got}" = "${_fake}" ]
}
