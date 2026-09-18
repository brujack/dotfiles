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
  # _check_one_cargo_version's isolation from the live crates.io endpoint
  # should not rest solely on the PATH mock intercepting `curl` -- the seam
  # (_CRATES_API) exists precisely so isolation is structural. Pinning a
  # sentinel here, at setup() scope, means every test in this file requests
  # the sentinel rather than the real host, and "requests _CRATES_API when
  # is set" below asserts that in the affirmative rather than trusting it by
  # absence of a network call.
  export _CRATES_API="https://crates-sentinel.invalid/api/v1/crates"
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

@test "run_check_versions does not prompt for an OUTDATED cargo crate" {
  # Report-only per the header comment on _check_one_cargo_version: the pins
  # live in one array (CARGO_TOOLS), so there is no single _var name to hand
  # _prompt_version_update the way _run_cv_check's tools each have one. This
  # is called out in a comment but nothing enforces it -- an unconditional
  # _prompt_version_update added to the OUTDATED arm would survive every
  # other test in this file.
  #
  # A shell-variable counter does NOT discriminate this: the cargo loop
  # invokes _check_one_cargo_version via `_out=$(...)` command substitution,
  # which forks a subshell, so a mutation calling _prompt_version_update
  # FROM INSIDE that function increments a copy of the counter that dies
  # with the subshell -- the parent test process still reads 0, and the
  # mutation survives. Measured directly: a debug build of exactly that
  # mutation printed "PROMPTED called" 8 times to fd 3 while the variable
  # read back 0 afterward. A file write crosses that boundary because the
  # subshell inherits the real filesystem, not a copy of it.
  _check_one_version() { printf "  [SKIP]     %-12s not installed\n" "$1"; }
  _check_cv_oh_my_zsh() { :; }
  _check_cv_homebrew_install() { :; }
  local _prompt_log="${BATS_TEST_TMPDIR}/prompt_calls"
  : > "${_prompt_log}"
  _prompt_version_update() { printf '%s\n' "$1" >> "${_prompt_log}"; }
  export UPDATE_VERSIONS=1
  # A max_stable_version far above every CARGO_TOOLS pin makes all eight
  # crates OUTDATED, maximizing the chance of catching a call in the arm.
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"999.0.0"}}'
  run_check_versions > /dev/null || true
  [ ! -s "${_prompt_log}" ]
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
  [[ "$output" != *"could not parse"* ]]
}

@test "_check_one_cargo_version prints a distinct WARN when the body has no max_stable_version" {
  # A 404 body from crates.io, or any response missing the field entirely --
  # curl succeeded (this is a real, non-empty JSON body), so the failure is
  # at parse time, not fetch time. _check_one_version (the GitHub sibling)
  # already separates these with two messages; this must not say "fetch".
  export MOCK_CURL_STDOUT='{"errors":[{"detail":"Not Found"}]}'
  run _check_one_cargo_version "cargo-audit" "0.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"could not parse latest version"* ]]
  [[ "$output" != *"could not fetch"* ]]
}

@test "_check_one_cargo_version prints a distinct WARN when max_stable_version is null" {
  # The real shape crates.io returns for a crate with no stable release --
  # JSON null, not a quoted empty string, so the "[^\"]*" capture cannot
  # match it either. Same parse-failure family as the missing-field case
  # above, not a fetch failure.
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":null}}'
  run _check_one_cargo_version "cargo-audit" "0.22.1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"could not parse latest version"* ]]
  [[ "$output" != *"could not fetch"* ]]
}

@test "_check_one_cargo_version's curl call carries the exact User-Agent string" {
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.22.1"}}'
  _check_one_cargo_version "cargo-audit" "0.22.1" > /dev/null
  # The mock logs "curl $*", which flattens quoting -- the multi-word
  # User-Agent arrives as several bare words rather than one quoted argument
  # ("-A dotfiles check-versions (bjackson@pobox.com) ..."). That flattening
  # changes the STRING'S FORM, not its determinism: the flattened form is
  # exactly reproducible, so a literal match on it pins the actual value sent
  # -- not just that -A was followed by some token, which a default-shaped
  # UA like "curl/8.7.1" (the value crates.io 403s on) would also satisfy.
  # -F (fixed string) avoids needing to escape the parentheses as regex.
  #
  # What this proves and does not prove: that the code SENDS the User-Agent
  # we intend. No offline test can prove crates.io's server accepts this
  # exact string -- that is a live-network fact, verified manually against
  # the real endpoint (spec Part 3) and unreachable from a mocked suite.
  grep -qF -- '-A dotfiles check-versions (bjackson@pobox.com)' "${MOCK_CALLS_FILE}"
}

@test "_check_one_cargo_version requests _CRATES_API, not the live crates.io default" {
  export MOCK_CURL_STDOUT='{"crate":{"max_stable_version":"0.22.1"}}'
  _check_one_cargo_version "cargo-audit" "0.22.1" > /dev/null
  # setup() pins _CRATES_API to a sentinel host. Isolation from the real
  # crates.io endpoint should be structural (the code reads the override),
  # not incidental (only the PATH mock stands between this suite and a real
  # network call) -- this asserts the override is actually consulted.
  grep -qF -- "${_CRATES_API}/cargo-audit" "${MOCK_CALLS_FILE}"
}
