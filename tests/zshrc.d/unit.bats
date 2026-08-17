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

@test "5_general.zsh initializes rbenv on a Linux Noble dev profile" {
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
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export HAS_DEVTOOLS=1
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

@test "5_general.zsh initializes rbenv on a Linux Resolute dev profile" {
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
    export LINUX=1; export UBUNTU=1; export RESOLUTE=1; export HAS_DEVTOOLS=1
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
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export HAS_DEVTOOLS=1
    export _OVERRIDE_RBENV_BINARY='/nonexistent/rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_RBENV_INIT_CALLED:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "5_general.zsh skips rbenv on a Linux host without devtools" {
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
    export LINUX=1; export UBUNTU=1; export NOBLE=1; unset HAS_DEVTOOLS
    export _OVERRIDE_RBENV_BINARY='${_tmp_dir}/mock_rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_RBENV_INIT_CALLED:-unset}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

# ── 5_general.zsh Homebrew prefix tests (CHRUBY_LOC / FZF_BASE) ─────────────
# _OVERRIDE_HOMEBREW_PREFIX_ARM / _OVERRIDE_HOMEBREW_PREFIX_INTEL are test
# seams, same convention as _OVERRIDE_GNUBIN_ARM/_OVERRIDE_GNUBIN_INTEL below
# -- the real /opt/homebrew exists on every provisioned mac including this
# one, so a test against the real path would pass whether or not the code
# under test reads the seam at all. Every case below unsets MACOS, LINUX,
# every legacy hostname var, and CHRUBY_LOC/FZF_BASE themselves before
# sourcing: the operator's own login shell exports STUDIO=1 and a full HAS_*
# set, which would otherwise leak into the zsh -c subprocess and mask the
# very branch under test.

@test "5_general.zsh sets CHRUBY_LOC and FZF_BASE for the ARM homebrew prefix" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"

  run zsh -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset CHRUBY_LOC FZF_BASE
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='${_tmp_dir}'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${CHRUBY_LOC:-unset}\"
    printf '%s\n' \"\${FZF_BASE:-unset}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  # Both expected values are built from ${_tmp_dir}, not a hardcoded literal
  # that merely happens to start with "/opt/homebrew" -- this is what pins
  # derivation rather than a bare existence check (a hardcoded-literal
  # assertion would still pass if the code ignored the seam's actual value).
  [ "$(printf '%s\n' "$output" | sed -n '1p')" = "${_tmp_dir}/opt/chruby/share/" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "${_tmp_dir}/bin/fzf" ]
}

@test "5_general.zsh sets CHRUBY_LOC for the Intel-only homebrew prefix, leaves FZF_BASE unset" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"

  run zsh -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset CHRUBY_LOC FZF_BASE
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='/nonexistent/homebrew-arm'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='${_tmp_dir}'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${CHRUBY_LOC:-unset}\"
    printf '%s\n' \"\${FZF_BASE:-unset}\"
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" = "${_tmp_dir}/opt/chruby/share" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "unset" ]
}

@test "5_general.zsh leaves CHRUBY_LOC and FZF_BASE unset when neither homebrew prefix is present" {
  run zsh -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset CHRUBY_LOC FZF_BASE
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='/nonexistent/homebrew-arm'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${CHRUBY_LOC:-unset}\"
    printf '%s\n' \"\${FZF_BASE:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" = "unset" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "unset" ]
}

# Regression pin for the `[[ -n {OFFICE} ]]` typo (missing $): zsh evaluated
# the braces as a literal non-empty string, so the branch was always taken
# regardless of platform or hostname, and FZF_BASE was exported to a path
# that does not exist on ratna or on either Linux box. Isolated from the
# case above so the regression has its own named, independently-runnable
# assertion.
@test "5_general.zsh no longer forces FZF_BASE on via the {OFFICE} typo when neither homebrew prefix is present" {
  run zsh -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset CHRUBY_LOC FZF_BASE
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='/nonexistent/homebrew-arm'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${FZF_BASE:-unset}\"
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
  : > "${1}/calls" # pre-create so a count is always readable, never a missing file
}

@test "5_general.zsh does not invoke keychain when sourced non-interactively" {
  local _tmp_dir _after_source _after_probe
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  # A count of zero has several producers, so this test cannot stand alone.
  # The probe below rules out two of them within this harness: it invokes the
  # mock directly and asserts the count moves 0 -> 1, so a zero after sourcing
  # cannot be explained by a non-executable mock or a mistyped calls path.
  #
  # It does NOT rule out the third: production ignoring _OVERRIDE_KEYCHAIN_BIN
  # entirely. Mutation-confirmed 2026-08-16 — reading the seam under a typo'd
  # name leaves THIS test green and fails only its interactive sibling. That is
  # inherent, not a gap to close here: production makes no call at all in the
  # non-interactive case, so this test has no signal that could observe the
  # seam being consumed. The sibling test below is that control, and the two
  # are a pair by design — deleting either one makes the other vacuous.
  run zsh -c "
    unset MACOS
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    wc -l < '${_tmp_dir}/calls'
    \"\${_OVERRIDE_KEYCHAIN_BIN}\" --eval probe
    wc -l < '${_tmp_dir}/calls'
  "
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  _after_source="$(printf '%s\n' "$output" | head -1 | tr -d ' ')"
  _after_probe="$(printf '%s\n' "$output" | tail -1 | tr -d ' ')"
  [ "${_after_source}" = "0" ]
  [ "${_after_probe}" = "1" ]
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
    export HAS_DEVTOOLS=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  _calls="$(wc -l < "${_tmp_dir}/calls" 2>/dev/null || printf '0')"
  rm -rf "${_tmp_dir}"
  [ "$(printf '%s' "${_calls}" | tr -d ' ')" = "4" ]
}

@test "5_general.zsh keychain path survives word splitting and a spaced path" {
  local _base _dir _calls
  _base="$(mktemp -d)"
  _dir="${_base}/dir with space"
  mkdir -p "${_dir}"
  _keychain_mock "${_dir}"

  # `setopt shwordsplit` is what makes this test able to fail. zsh does not
  # word-split unquoted parameter expansions by default, so with the option off
  # the quoted and unquoted forms are indistinguishable and this assertion would
  # pass either way — vacuous. Under shwordsplit an unquoted ${_keychain} splits
  # on the space and zsh reports `no such file or directory: .../dir`, while the
  # quoted form runs. Verified in both directions before this test was written.
  #
  # The option is not hypothetical: it is what `emulate sh`/`emulate ksh` set,
  # so any future code path that emulates another shell before sourcing this
  # file gets the split behaviour. Quoting makes the line correct under both.
  run zsh -f -i -c "
    setopt shwordsplit
    unset MACOS
    export LINUX=1; export UBUNTU=1; export NOBLE=1; export WORKSTATION=1
    export HAS_DEVTOOLS=1
    export _OVERRIDE_KEYCHAIN_BIN='${_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  _calls="$(wc -l < "${_dir}/calls" 2>/dev/null || printf '0')"
  rm -rf "${_base}"
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

# ── 5_general.zsh collapsed keychain key list ────────────────────────────────
#
# Seven per-host arms (RATNA/LAPTOP/STUDIO/RECEPTION/OFFICE/HOMES on macOS,
# WORKSTATION||CRUNCHER vs. everything else on Linux) collapsed to a
# capability test plus one shared key list. All six mac arms loaded the same
# four keys (id_rsa, home, github, gitlab); the Linux split was just "a known
# dev profile or not", which HAS_DEVTOOLS now expresses directly against
# config/profiles.sh's table (today: only linux_workstation/wsl2_workstation
# -- i.e. WORKSTATION/CRUNCHER -- carry it). These tests assert on the calls
# file's actual content (the recorded `--eval <key>` lines), not just a
# count, because "keychain wasn't invoked" and "keychain was invoked with the
# right keys" are different claims.

@test "5_general.zsh keychain loads the four standard keys on a mac profile" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  # _OVERRIDE_HOMEBREW_PREFIX_ARM is pointed at this same fixture dir (which
  # trivially exists) rather than left at its real /opt/homebrew default --
  # this test is about the KEY LIST, not the binary path, but the -d branch
  # still has to succeed for `_keychain` to be assigned at all. Relying on
  # the real prefix would make this test pass here and on any ubuntu-latest
  # runner (which has real /usr/local) for the wrong reason -- see the
  # header comment above the binary-path tests further down.
  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='${_tmp_dir}'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(cat "${_tmp_dir}/calls" 2>/dev/null)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "$(printf -- '--eval id_rsa\n--eval home\n--eval github\n--eval gitlab')" ]
}

@test "5_general.zsh keychain loads the four standard keys on a Linux dev profile" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  # HAS_DEVTOOLS is what a real workstation/cruncher host has already had set
  # by config/profiles.zsh before this file sources -- set directly here,
  # matching how the pre-existing rbenv tests above set WORKSTATION=1
  # directly rather than driving the full profile-resolution boot sequence.
  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    export LINUX=1; export UBUNTU=1; export NOBLE=1
    export HAS_DEVTOOLS=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    export _OVERRIDE_RBENV_BINARY='/nonexistent/rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(cat "${_tmp_dir}/calls" 2>/dev/null)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "$(printf -- '--eval id_rsa\n--eval home\n--eval github\n--eval gitlab')" ]
}

@test "5_general.zsh keychain loads only id_rsa on a Linux non-dev host" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    export LINUX=1; export UBUNTU=1; export NOBLE=1
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    export _OVERRIDE_RBENV_BINARY='/nonexistent/rbenv'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(cat "${_tmp_dir}/calls" 2>/dev/null)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "--eval id_rsa" ]
}

# Regression pin for the home-1 (mac_mini) arm's `--eval any home` typo:
# keychain has no `any` flag, so it was reading "any" as a key name, and no
# such key exists. Dropped so every mac profile -- home-1 included -- loads
# the identical four-key list. HOMES is exported even though production no
# longer branches on it, to document which host this pins.
@test "5_general.zsh keychain loads the same four keys on home-1, not 'any'" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    export MACOS=1
    export HOMES=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='${_tmp_dir}'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(cat "${_tmp_dir}/calls" 2>/dev/null)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "$(printf -- '--eval id_rsa\n--eval home\n--eval github\n--eval gitlab')" ]
}

# Third behaviour change, beyond the collapse and the home-1 typo drop: the
# old MACOS chain had no final `else`, so a mac whose hostname misses every
# legacy var (RATNA/LAPTOP/STUDIO/RECEPTION/OFFICE/HOMES -- i.e. a guest or a
# freshly-built mac not yet in config/profiles.sh's PROFILE_MAP) invoked
# keychain zero times. The collapsed MACOS arm has no per-host branch left to
# be absent from, so `_keychain_keys` is now assigned unconditionally and
# every such mac loads the four standard keys instead. Recorded rather than
# gated: gating would mean re-adding a "is this a known profile" branch,
# which is exactly the per-host testing this task collapsed away, and the
# direction (a new mac gets its keys instead of silently none) is the same
# one HAS_DEVTOOLS already takes on the Linux side. The test above ("on a
# mac profile") already exercises this exact case -- MACOS=1 with no legacy
# var set -- this one exists to name it as the change it is.
@test "5_general.zsh keychain now loads keys on an unmapped mac too (was zero before the collapse)" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='${_tmp_dir}'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    export _OVERRIDE_KEYCHAIN_BIN='${_tmp_dir}/mock_keychain'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(wc -l < "${_tmp_dir}/calls" 2>/dev/null | tr -d ' ')"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "4" ]
}

# ── 5_general.zsh keychain binary path resolution ────────────────────────────
# The binary-path selection used to test RATNA (Intel) vs. everything else
# (ARM) by hostname. Collapsed to the same _OVERRIDE_HOMEBREW_PREFIX_ARM /
# _OVERRIDE_HOMEBREW_PREFIX_INTEL seams 6_path.zsh's gnubin resolution and
# this file's own CHRUBY_LOC/FZF_BASE section already use -- reused rather
# than a third seam. The real /opt/homebrew exists on this dev machine (with
# a real keychain binary at /opt/homebrew/bin/keychain), so these tests never
# let production fall through to the hardcoded default -- _OVERRIDE_KEYCHAIN_BIN
# is left unset and the prefix seams are pointed at fixture directories that
# themselves contain the mock at bin/keychain, so the constructed path is
# provably inside the fixture rather than the real Homebrew prefix.

@test "5_general.zsh keychain binary resolves via the ARM prefix by default" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/arm/bin"
  _keychain_mock "${_tmp_dir}"
  cp "${_tmp_dir}/mock_keychain" "${_tmp_dir}/arm/bin/keychain"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    unset _OVERRIDE_KEYCHAIN_BIN
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='${_tmp_dir}/arm'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(cat "${_tmp_dir}/calls" 2>/dev/null)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "$(printf -- '--eval id_rsa\n--eval home\n--eval github\n--eval gitlab')" ]
}

@test "5_general.zsh keychain binary resolves via the Intel prefix when only that exists" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/intel/bin"
  _keychain_mock "${_tmp_dir}"
  cp "${_tmp_dir}/mock_keychain" "${_tmp_dir}/intel/bin/keychain"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    unset _OVERRIDE_KEYCHAIN_BIN
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='/nonexistent/homebrew-arm'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='${_tmp_dir}/intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
  " < /dev/null
  local _calls
  _calls="$(cat "${_tmp_dir}/calls" 2>/dev/null)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "$(printf -- '--eval id_rsa\n--eval home\n--eval github\n--eval gitlab')" ]
}

@test "5_general.zsh keychain makes no call when neither homebrew prefix is present" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  _keychain_mock "${_tmp_dir}"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    unset _OVERRIDE_KEYCHAIN_BIN
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='/nonexistent/homebrew-arm'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${_keychain:-unset}\"
  " < /dev/null
  local _calls _keychain_var
  _calls="$(wc -l < "${_tmp_dir}/calls" 2>/dev/null | tr -d ' ')"
  _keychain_var="$(printf '%s\n' "$output" | tail -1)"
  rm -rf "${_tmp_dir}"
  [ "${_calls}" = "0" ]
  [ "${_keychain_var}" = "unset" ]
}

# _OVERRIDE_HOMEBREW_PREFIX_ARM/_INTEL used to have two meanings in this
# file: an existence probe with a hardcoded-literal output (CHRUBY_LOC,
# FZF_BASE) and a path prefix an output was actually built from (the
# keychain binary). A test setting the seam once could not have told those
# apart -- it would pass for the keychain path (genuinely derived) and ALSO
# pass for CHRUBY_LOC/FZF_BASE (hardcoded, but the hardcoded literal happened
# to start with the real default prefix), because none of them asserted that
# the *fixture's own path* showed up in the result. This test points one
# seam at one fixture and checks all three consumers embed it, which is the
# check that discriminates a derived path from a coincidentally-matching
# hardcoded one.
@test "5_general.zsh derives CHRUBY_LOC, FZF_BASE, and the keychain binary from the same prefix seam" {
  local _tmp_dir
  _tmp_dir="$(mktemp -d)"
  mkdir -p "${_tmp_dir}/bin"
  _keychain_mock "${_tmp_dir}"
  cp "${_tmp_dir}/mock_keychain" "${_tmp_dir}/bin/keychain"

  run zsh -f -i -c "
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
    unset -m 'HAS_*'
    unset CHRUBY_LOC FZF_BASE _OVERRIDE_KEYCHAIN_BIN
    export MACOS=1
    export _OVERRIDE_HOMEBREW_PREFIX_ARM='${_tmp_dir}'
    export _OVERRIDE_HOMEBREW_PREFIX_INTEL='/nonexistent/homebrew-intel'
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\${CHRUBY_LOC:-unset}\"
    printf '%s\n' \"\${FZF_BASE:-unset}\"
  " < /dev/null
  local _calls
  _calls="$(wc -l < "${_tmp_dir}/calls" 2>/dev/null | tr -d ' ')"
  rm -rf "${_tmp_dir}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" = "${_tmp_dir}/opt/chruby/share/" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "${_tmp_dir}/bin/fzf" ]
  [ "${_calls}" = "4" ]
}

# ── shared identity table (config/profiles.zsh) ──────────────────────────────
# .zprofile and 1_init.zsh each used to carry their own hand-maintained
# hostname list, and both had drifted from config/profiles.sh and from each
# other. These three regressions were live on master and are pinned here
# rather than left to profiles.bats, because profiles.bats only exercises
# config/profiles.zsh directly -- it can't see whether .zprofile / 1_init.zsh
# actually wire it in. Isolation mirrors tests/zshrc.d/profiles.bats'
# _profiles_snapshot: both the eight legacy vars and the HAS_* set must be
# unset before sourcing, because this session's own login shell exports
# STUDIO=1 (and, once wired, its own HAS_* set) which would otherwise mask a
# regression by supplying the expected value ambiently.

@test "1_init.zsh alone sets OFFICE for hostname office" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:\${PATH}\"
    export MOCK_UNAME_S=Darwin
    export MOCK_HOSTNAME_OUTPUT=office
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null
    printf '%s\n' \"\${OFFICE:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# MOCK_CALLS_FILE is set explicitly (not left to the mocks' own
# ${MOCK_CALLS_FILE:-/tmp/mock_calls} fallback): HOMES triggers .zprofile's
# own `[[ -n ${HOMES} ]] ... export PATH="/opt/homebrew/bin:$PATH"` branch,
# which on a machine with a real Homebrew pyenv installed shadows the mock
# pyenv for `eval "$(pyenv init --path)"` -- the real `pyenv rehash` that
# follows then resolves tests/mocks/xargs (still on PATH, after
# /opt/homebrew/bin) for a real xargs call, and that mock hard-codes
# "${MOCK_CALLS_FILE}" with no ':-' fallback.
@test ".zprofile alone sets HOMES for hostname home-1" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:/usr/bin:/bin:/usr/sbin:/sbin\"
    export MOCK_CALLS_FILE=\"${BATS_TEST_TMPDIR}/mock_calls_homes\"
    export MOCK_HOSTNAME_OUTPUT=home-1
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    source '${REPO_ROOT}/.zprofile' 2>/dev/null
    printf '%s\n' \"\${HOMES:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# CRUNCHER isn't in .zprofile's LAPTOP/STUDIO/RECEPTION/OFFICE/HOMES branch,
# so this host never shadows the mock pyenv with a real one the way HOMES
# and STUDIO do below -- MOCK_CALLS_FILE isn't load-bearing here. Set
# explicitly anyway, to a fixture path rather than the mocks' shared
# ${MOCK_CALLS_FILE:-/tmp/mock_calls} fallback: leaving it to the fallback
# would write to a cross-user /tmp file for no reason and make this test
# gratuitously inconsistent with its three siblings.
@test ".zprofile alone sets CRUNCHER for hostname cruncher" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:/usr/bin:/bin:/usr/sbin:/sbin\"
    export MOCK_CALLS_FILE=\"${BATS_TEST_TMPDIR}/mock_calls_cruncher\"
    export MOCK_HOSTNAME_OUTPUT=cruncher
    unset LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    source '${REPO_ROOT}/.zprofile' 2>/dev/null
    printf '%s\n' \"\${CRUNCHER:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# The real login+interactive sequence: .zprofile runs first, then 1_init.zsh,
# in one process. This is the export-not-readonly property config/profiles.zsh
# documents at its own top -- a readonly reassignment on the second pass makes
# that second `source` return 126 (caught here by `|| exit 1`) rather than
# merely producing a wrong value, so this is checked for absence-of-error as
# well as consistency. The first-pass values are asserted explicitly, not just
# compared for consistency across the two sources: an unset first pass and a
# genuinely-consistent-but-wrong pass would otherwise look identical to this
# test, and only the explicit check fails on its own terms.
#
# PATH is a hermetic minimal set, not the mocks-prepended-to-inherited-PATH
# pattern used elsewhere in this file -- but that alone does NOT keep
# .zprofile off the real pyenv. STUDIO triggers .zprofile's own
# `[[ -n ${STUDIO} ]] ... export PATH="/opt/homebrew/bin:$PATH"` branch,
# which on a machine with a real Homebrew pyenv installed puts it ahead of
# the mock regardless of what PATH this test sets -- measured, `command -v
# pyenv` resolves /opt/homebrew/bin/pyenv here, same as the HOMES test
# above. The real `pyenv rehash` that follows then reaches
# tests/mocks/xargs (still on PATH) for a real xargs call, and that mock
# hard-codes "${MOCK_CALLS_FILE}" with no ':-' fallback -- MOCK_CALLS_FILE
# below is what actually keeps this test from crashing, not the PATH.
@test ".zprofile then 1_init.zsh in one process does not error and stays consistent" {
  run zsh -c "
    export PATH=\"${REPO_ROOT}/tests/mocks:/usr/bin:/bin:/usr/sbin:/sbin\"
    export MOCK_CALLS_FILE=\"${BATS_TEST_TMPDIR}/mock_calls_sequence\"
    export MOCK_UNAME_S=Darwin
    export MOCK_HOSTNAME_OUTPUT=studio
    unset MACOS LINUX LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA PROFILE
    unset -m 'HAS_*'
    source '${REPO_ROOT}/.zprofile' 2>/dev/null || exit 1
    first_studio=\"\${STUDIO:-unset}\"
    first_profile=\"\${PROFILE:-unset}\"
    if [[ \"\${first_profile}\" != \"mac_workstation\" ]]; then
      printf 'first-pass PROFILE wrong: got %s want mac_workstation\n' \"\${first_profile}\" >&2
      exit 1
    fi
    if [[ \"\${first_studio}\" != \"1\" ]]; then
      printf 'first-pass STUDIO wrong: got %s want 1\n' \"\${first_studio}\" >&2
      exit 1
    fi
    source '${ZSHRC_D}/1_init.zsh' 2>/dev/null || exit 1
    if [[ \"\${STUDIO:-unset}\" != \"\${first_studio}\" ]]; then
      printf 'STUDIO changed across sequence\n' >&2
      exit 1
    fi
    if [[ \"\${PROFILE:-unset}\" != \"\${first_profile}\" ]]; then
      printf 'PROFILE changed across sequence\n' >&2
      exit 1
    fi
    printf '%s\n' \"\${STUDIO:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# ── production actor: a real login shell, not the source builtin ────────────
# All four tests above use `source '${REPO_ROOT}/.zprofile'` -- the one actor
# where zsh sets $0 (FUNCTION_ARGZERO covers the source builtin and
# functions; zsh's own startup reader does not). This test drives .zprofile
# the way setup_env.sh actually installs it and a real terminal actually
# invokes it: symlinked into $HOME, read by zsh's internal startup reader via
# a real login shell (`-l`), with cwd deliberately NOT the repo root -- the
# one condition a `${0:A:h}`-based resolution needs in order to fail, and the
# one condition none of the tests above can ever produce.
#
# PATH is real /usr/bin:/bin, not tests/mocks -- `hostname -s` resolves the
# actual machine hostname, which is why the assertion is "PROFILE got set to
# something" rather than a specific profile name: an unmapped hostname
# (PROFILE=unknown) is a correct, non-empty result and must not read as a
# failure here. What this test can tell apart is "the resolution ran at all"
# versus "it silently produced nothing", which is exactly what the ${0:A:h}
# bug did from any cwd but the repo root.
@test "a real login shell resolves PROFILE with cwd outside the repo" {
  local _fixture
  _fixture="$(mktemp -d)"
  ln -s "${REPO_ROOT}/.zprofile" "${_fixture}/.zprofile"

  run bash -c "
    cd / &&
    env -i HOME='${_fixture}' ZDOTDIR='${_fixture}' TERM=dumb PATH=/usr/bin:/bin \
      zsh -l -c 'printf \"%s\n\" \"\${PROFILE:-unset}\"'
  "
  rm -rf "${_fixture}"
  [ "$status" -eq 0 ]
  [ "$output" != "unset" ]
}
