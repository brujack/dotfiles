#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  ZSHRC_D="${REPO_ROOT}/.config/.zshrc.d"
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

@test ".zshrc has valid zsh syntax" {
  run zsh -n "${REPO_ROOT}/.zshrc"
  [ "$status" -eq 0 ]
}

@test ".zprofile has valid zsh syntax" {
  run zsh -n "${REPO_ROOT}/.zprofile"
  [ "$status" -eq 0 ]
}

@test "bruce.zsh-theme has valid zsh syntax" {
  run zsh -n "${REPO_ROOT}/bruce.zsh-theme"
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

@test "1_init.zsh sets RESOLUTE=1 for Ubuntu 26.04" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Linux
    export MOCK_AWK_OS_NAME=Ubuntu
    export MOCK_LSB_RELEASE_RS=26.04
    unset MACOS LINUX UBUNTU NOBLE RESOLUTE
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${RESOLUTE}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "1_init.zsh does not set BIONIC for Ubuntu 18.04" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Linux
    export MOCK_AWK_OS_NAME=Ubuntu
    export MOCK_LSB_RELEASE_RS=18.04
    unset MACOS LINUX UBUNTU NOBLE RESOLUTE BIONIC
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${BIONIC:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "1_init.zsh does not set JAMMY for Ubuntu 22.04" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Linux
    export MOCK_AWK_OS_NAME=Ubuntu
    export MOCK_LSB_RELEASE_RS=22.04
    unset MACOS LINUX UBUNTU NOBLE RESOLUTE JAMMY
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${JAMMY:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

# ── 5_general.zsh rbenv tests ─────────────────────────────────────────────────

@test "5_general.zsh initializes rbenv on Linux Noble WORKSTATION" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  cat > "${_tmp_dir}/mock_rbenv" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "init" ]]; then
  printf '_RBENV_INIT_CALLED=1\n'
elif [[ "$1" == "local" ]]; then
  printf '_RBENV_LOCAL_CALLED=1\n'
fi
exit 0
EOF
  chmod +x "${_tmp_dir}/mock_rbenv"

  run zsh -c "
    unset MACOS
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_RBENV_BINARY='${_tmp_dir}/mock_rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_RBENV_INIT_CALLED:-unset}\"
    printf '%s\n' \"\${_RBENV_LOCAL_CALLED:-unset}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "1" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "unset" ]
}

@test "5_general.zsh initializes rbenv on Linux Resolute CRUNCHER" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  cat > "${_tmp_dir}/mock_rbenv" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "init" ]]; then
  printf '_RBENV_INIT_CALLED=1\n'
elif [[ "$1" == "local" ]]; then
  printf '_RBENV_LOCAL_CALLED=1\n'
fi
exit 0
EOF
  chmod +x "${_tmp_dir}/mock_rbenv"

  run zsh -c "
    unset MACOS
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export LINUX=1; export UBUNTU=1; export RESOLUTE=1; export CRUNCHER=1
    export _OVERRIDE_RBENV_BINARY='${_tmp_dir}/mock_rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_RBENV_INIT_CALLED:-unset}\"
    printf '%s\n' \"\${_RBENV_LOCAL_CALLED:-unset}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "1" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "unset" ]
}

@test "5_general.zsh skips rbenv when rbenv binary absent" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_RBENV_BINARY='/nonexistent/rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_RBENV_INIT_CALLED:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

# ── 6_path.zsh GNU make gnubin tests ─────────────────────────────────────────
# _OVERRIDE_GNUBIN_ARM / _OVERRIDE_GNUBIN_INTEL are test seams, same convention
# as _OVERRIDE_RBENV_BINARY above -- default to the real Homebrew paths in
# production, redirected to a fixture dir here.

@test "6_path.zsh prepends ARM gnubin dir to PATH when present" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/gnubin"

  run zsh -c "
    export MACOS=1
    export _OVERRIDE_GNUBIN_ARM='${_tmp_dir}/gnubin'
    export _OVERRIDE_GNUBIN_INTEL='/nonexistent/gnubin-intel'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\${path[1]}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$output" = "${_tmp_dir}/gnubin" ]
}

@test "6_path.zsh prepends Intel gnubin dir to PATH when only /usr/local prefix present" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/gnubin"

  run zsh -c "
    export MACOS=1
    export _OVERRIDE_GNUBIN_ARM='/nonexistent/gnubin-arm'
    export _OVERRIDE_GNUBIN_INTEL='${_tmp_dir}/gnubin'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\${path[1]}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$output" = "${_tmp_dir}/gnubin" ]
}

@test "6_path.zsh gnubin entry is deduped across repeated sourcing" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/gnubin"

  run zsh -c "
    export MACOS=1
    export _OVERRIDE_GNUBIN_ARM='${_tmp_dir}/gnubin'
    export _OVERRIDE_GNUBIN_INTEL='/nonexistent/gnubin-intel'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \$path | grep -c '^${_tmp_dir}/gnubin\$'
  "
  rm -rf "${_tmp_dir}"
  [ "$output" = "1" ]
}

@test "6_path.zsh adds no gnubin entry when neither Homebrew prefix has it" {
  run zsh -c "
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export MACOS=1
    export _OVERRIDE_GNUBIN_ARM='/nonexistent/gnubin-arm'
    export _OVERRIDE_GNUBIN_INTEL='/nonexistent/gnubin-intel'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    if [[ \${path[(r)*gnubin*]} ]]; then
      printf 'HAS_GNUBIN\n'
    else
      printf 'NO_GNUBIN\n'
    fi
    printf '%s\n' \"\${#path}\"
  "
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "NO_GNUBIN" ]
  [ "$(printf '%s\n' "$output" | tail -1)" -gt 0 ]
}

@test "6_path.zsh adds no gnubin entry under LINUX, but still adds a known Linux path" {
  local _fake_home
  _fake_home="$(mktemp -d)"
  mkdir -p "${_fake_home}/.local/bin"

  run zsh -c "
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    unset MACOS
    export HOME='${_fake_home}'
    export LINUX=1
    export _OVERRIDE_GNUBIN_ARM='/nonexistent/gnubin-arm'
    export _OVERRIDE_GNUBIN_INTEL='/nonexistent/gnubin-intel'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    if [[ \${path[(r)*gnubin*]} ]]; then
      printf 'HAS_GNUBIN\n'
    else
      printf 'NO_GNUBIN\n'
    fi
    if [[ \${path[(r)${_fake_home}/.local/bin]} ]]; then
      printf 'HAS_LOCAL_BIN\n'
    else
      printf 'NO_LOCAL_BIN\n'
    fi
  "
  rm -rf "${_fake_home}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "NO_GNUBIN" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "HAS_LOCAL_BIN" ]
}

@test "6_path.zsh unsets _gnubin after sourcing, does not leak" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/gnubin"

  run zsh -c "
    export MACOS=1
    export _OVERRIDE_GNUBIN_ARM='${_tmp_dir}/gnubin'
    export _OVERRIDE_GNUBIN_INTEL='/nonexistent/gnubin-intel'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\${_gnubin:-unset}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "5_general.zsh does not call rbenv local (would overwrite project .ruby-version)" {
  local _tmp_dir _project_dir
  _tmp_dir="$(mktemp -d)"
  _project_dir="$(mktemp -d)"
  printf '3.2.0\n' > "${_project_dir}/.ruby-version"
  cat > "${_tmp_dir}/mock_rbenv" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "init" ]]; then
  printf '_RBENV_INIT_CALLED=1\n'
elif [[ "$1" == "local" ]]; then
  printf '_RBENV_LOCAL_CALLED=1\n'
fi
exit 0
EOF
  chmod +x "${_tmp_dir}/mock_rbenv"

  run zsh -c "
    unset MACOS
    cd '${_project_dir}'
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_RBENV_BINARY='${_tmp_dir}/mock_rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_RBENV_LOCAL_CALLED:-unset}\"
    cat '${_project_dir}/.ruby-version'
  "
  rm -rf "${_tmp_dir}" "${_project_dir}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "unset" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "3.2.0" ]
}

# ── 5_general.zsh keychain tests ──────────────────────────────────────────────
#
# keychain starts an ssh-agent that daemonizes, reparents to init, and keeps
# every fd it inherited. Sourcing this file non-interactively — which these
# very tests do, to reach the rbenv branch — leaked an agent still holding the
# bats-exec-suite output pipe, so bats never saw EOF and `make test` ran to
# completion and then hung forever on any machine with keychain installed.
# Measured 2026-08-16 on the Linux workstation: 16 agents pinning the pipe.

_keychain_mock() { # <dir>  — writes a recording mock, one line per invocation
  cat > "${1}/mock_keychain" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${1}/calls"
EOF
  chmod +x "${1}/mock_keychain"
}

@test "5_general.zsh does not invoke keychain when sourced non-interactively" {
  local _tmp_dir _calls
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  run zsh -c "
    unset MACOS
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  "
  _calls="$(wc -l < "${_tmp_dir}/calls" 2>/dev/null || printf '0')"
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "${_calls}" | tr -d ' ')" = "0" ]
}

@test "5_general.zsh does invoke keychain from an interactive shell" {
  local _tmp_dir _calls
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  # -f skips rc files so only the file under test runs; -i is the only way to
  # set the interactive option (zsh refuses `setopt interactive` at runtime).
  run zsh -f -i -c "
    unset MACOS
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  _calls="$(wc -l < "${_tmp_dir}/calls" 2>/dev/null || printf '0')"
  rm -rf "${_tmp_dir}"
  [ "$(printf '%s' "${_calls}" | tr -d ' ')" = "4" ]
}

@test "5_general.zsh unsets _keychain after sourcing, does not leak" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  run zsh -f -i -c "
    unset MACOS
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_keychain:-unset}\"
  " < /dev/null
  rm -rf "${_tmp_dir}"
  [ "$(printf '%s\n' "$output" | tail -1)" = "unset" ]
}
