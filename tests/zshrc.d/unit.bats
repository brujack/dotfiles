#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  # Note: load_mocks() is NOT called here — prepending tests/mocks/ to the outer
  # PATH corrupts PATH for zsh subprocesses. Mocks are injected per-test inside
  # the zsh -c invocations that need them.
}

# ── syntax checks ────────────────────────────────────────────────────────────

@test "1_init.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/1_init.zsh"
  [ "$status" -eq 0 ]
}

@test "2_functions.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/2_functions.zsh"
  [ "$status" -eq 0 ]
}

@test "3_oh_my_zsh.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/3_oh_my_zsh.zsh"
  [ "$status" -eq 0 ]
}

@test "4_aliases.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/4_aliases.zsh"
  [ "$status" -eq 0 ]
}

@test "5_general.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/5_general.zsh"
  [ "$status" -eq 0 ]
}

@test "6_path.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/6_path.zsh"
  [ "$status" -eq 0 ]
}

@test "7_final.zsh has valid zsh syntax" {
  run zsh -n "${ZSHRC_D}/7_final.zsh"
  [ "$status" -eq 0 ]
}

# ── 1_init.zsh functional tests ──────────────────────────────────────────────
# PATH uses double quotes so ${PATH} is expanded by zsh (not single quotes).
# MACOS/LINUX are unset before sourcing to prevent inherited env from leaking in.

@test "1_init.zsh sets MACOS=1 on Darwin" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Darwin
    unset MACOS LINUX
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${MACOS}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "1_init.zsh sets LINUX=1 on Linux" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Linux
    unset MACOS LINUX
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${LINUX}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "1_init.zsh does not set MACOS on Linux" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Linux
    unset MACOS LINUX
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${MACOS:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}
