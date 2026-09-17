#!/usr/bin/env bats

# Covers _check_one_cargo_version and run_check_versions' CARGO_TOOLS loop
# (lib/workflows.sh). See
# docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md Part 3's
# check-versions bullet: run_check_versions is GitHub-release based, and two
# things break that for cargo pins -- cargo-audit's releases carry monorepo
# tags (cargo-audit/vX.Y.Z), and ~/.cargo/bin is not on the non-interactive
# PATH, so a command -v probe would SKIP every crate. crates.io answers
# instead, and requires a User-Agent or it returns 403 (measured from the
# Studio, `claude` and `workstation` on 2026-09-17).

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── run_check_versions — CARGO_TOOLS loop ───────────────────────────────────
#
# Ordered before the direct _check_one_cargo_version tests below: the stub
# definition in the second test here is the only place in this file that
# defines the function, and shellcheck (SC2218) treats function definitions
# as flat and file-order-dependent regardless of bats' per-@test scoping --
# a call textually before every definition reads as "used before defined".

@test "run_check_versions counts one OUTDATED cargo crate and returns non-zero" {
  _check_one_version() { printf "  [SKIP]     %-12s not installed\n" "$1"; }
  _check_cv_oh_my_zsh() { :; }
  _check_cv_homebrew_install() { :; }
  # Deterministic on crate name rather than a call counter, so the result
  # does not depend on whether `run` executes run_check_versions in the
  # current shell or a forked one.
  _check_one_cargo_version() {
    if [[ "$1" == "cargo-audit" ]]; then
      printf "  [OUTDATED] %-20s pinned=%-10s latest=999.0.0\n" "$1" "$2"
      return 1
    fi
    printf "  [OK]       %-20s pinned=%-10s latest=%s\n" "$1" "$2" "$2"
    return 0
  }
  run run_check_versions
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 outdated"* ]]
  [[ "$output" == *"7 OK"* ]]
}

@test "run_check_versions adds all-OK cargo crates to the OK total" {
  _check_one_version() { printf "  [SKIP]     %-12s not installed\n" "$1"; }
  _check_cv_oh_my_zsh() { :; }
  _check_cv_homebrew_install() { :; }
  # A max_stable_version far below every CARGO_TOOLS pin makes all eight
  # crates OK (the pin is newer than upstream) -- exercises the real,
  # unstubbed _check_one_cargo_version end to end.
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.0.1"}}'
  run run_check_versions
  [[ "$output" == *"0 outdated"* ]]
  [[ "$output" == *"8 OK"* ]]
}

# ── _check_one_cargo_version ────────────────────────────────────────────────

@test "_check_one_cargo_version prints OK when pin equals upstream max_stable_version" {
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.22.1"}}'
  run _check_one_cargo_version "cargo-audit" "0.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"cargo-audit"* ]]
  [[ "$output" == *"pinned=0.22.1"* ]]
  [[ "$output" == *"latest=0.22.1"* ]]
}

@test "_check_one_cargo_version prints OK when the pin is newer than upstream" {
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.20.0"}}'
  run _check_one_cargo_version "cargo-audit" "0.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"pinned=0.22.1"* ]]
  [[ "$output" == *"latest=0.20.0"* ]]
}

@test "_check_one_cargo_version prints OUTDATED with a latest= token when upstream is newer" {
  # 0.9.2 vs 0.10.0 is the discriminating pair (shell.md's semver pitfall): a
  # LEXICAL "${a} < ${b}" reads "0.9.2" as greater than "0.10.0" (the '9' wins
  # over the '1'), so this only reports OUTDATED under a real numeric compare.
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.10.0"}}'
  run _check_one_cargo_version "cargo-audit" "0.9.2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[OUTDATED]"* ]]
  [[ "$output" == *"cargo-audit"* ]]
  [[ "$output" == *"latest=0.10.0"* ]]
}

@test "_check_one_cargo_version prints WARN when the fetch fails" {
  export MOCK_CURL_EXIT=1
  unset MOCK_CURL_STDOUT
  run _check_one_cargo_version "cargo-audit" "0.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"cargo-audit"* ]]
  [[ "$output" == *"could not fetch latest version"* ]]
}

@test "_check_one_cargo_version's curl call carries -A followed by a token" {
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.22.1"}}'
  _check_one_cargo_version "cargo-audit" "0.22.1" > /dev/null
  # The mock logs "curl $*", which flattens quoting -- a multi-word User-Agent
  # string arrives as several bare words rather than one quoted argument, so
  # this matches the -A TOKEN shape rather than the quoted UA string itself.
  grep -qE '(^| )-A ([^[:space:]]+)' "${MOCK_CALLS_FILE}"
}
