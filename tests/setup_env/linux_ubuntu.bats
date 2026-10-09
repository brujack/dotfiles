#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
  # Seed a rustup at the path _install_rustup_rs guards on, at SETUP scope. Without
  # it every _install_ubuntu_rust test enters the install path against a fake HOME
  # and attempts to download rustup-init -- tdd.md E2, a test whose FAILING branch
  # reaches outside the repo. Setup scope rather than per-test, so the trap is not
  # re-armed by the next test added to this file. These tests are about Rust
  # CONFIGURATION; _install_rustup_rs has its own tests, which drive the seams.
  mkdir -p "${HOME}/.cargo/bin"
  cp "${REPO_ROOT}/tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  # Same rule, one release-binary helper over: _RELEASE_BIN_DIR at SETUP
  # scope so a future HAS_DEVTOOLS=1 test that forgets to stub
  # _install_ubuntu_tflint/_install_ubuntu_tfsec cannot reach real
  # /usr/local/bin -- _install_pinned_release_binary has its own tests in
  # release_binary.bats, which drive the seams.
  export _RELEASE_BIN_DIR="${BATS_TEST_TMPDIR}/release-bin"
  mkdir -p "${_RELEASE_BIN_DIR}"
  # Same rule for the edge block of _install_ubuntu_gui_tools: it reads and
  # writes an apt sources dir and a keyring, and tests/mocks/sudo execs real
  # commands, so without these the edge block would touch the real /etc/apt and
  # /usr/share/keyrings. (albert is seamed via the _APT_* variables below.)
  export _EDGE_SOURCES_DIR="${BATS_TEST_TMPDIR}/apt-sources"
  export _EDGE_BOOTSTRAP_KEYRING="${BATS_TEST_TMPDIR}/edge-bootstrap.gpg"
  mkdir -p "${_EDGE_SOURCES_DIR}"
  # _build_pinned_keyring builds in a temp dir under this root; seamed so tests
  # can assert nothing is left behind and never touch the system temp dir.
  export _APT_KEY_TMP_ROOT="${BATS_TEST_TMPDIR}/apt-key-tmp"
  mkdir -p "${_APT_KEY_TMP_ROOT}"
  # _install_ubuntu_albert writes a source, a keyring and removes legacy files;
  # tests/mocks/sudo execs real commands, so without these it would touch the
  # real /etc/apt and /usr/share/keyrings.
  export _APT_SOURCES_DIR="${BATS_TEST_TMPDIR}/albert-sources"
  export _APT_TRUSTED_DIR="${BATS_TEST_TMPDIR}/albert-trusted"
  export _APT_KEYRINGS_DIR="${BATS_TEST_TMPDIR}/albert-keyrings"
  mkdir -p "${_APT_SOURCES_DIR}" "${_APT_TRUSTED_DIR}" "${_APT_KEYRINGS_DIR}"
  # _install_ubuntu_powershell verifies packages-microsoft-prod.deb before
  # installing it. tests/mocks/gpg cannot verify anything, so point the seam at
  # the real gpg, and have the wget mock hand back the real signed .deb. The
  # test that needs an unverifiable download unsets MOCK_WGET_FILE itself.
  _MS_GPG_BIN="$(PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')" command -v gpg)"
  export _MS_GPG_BIN="${_MS_GPG_BIN:-/nonexistent/gpg}"
  export MOCK_WGET_FILE="${REPO_ROOT}/tests/fixtures/packages-microsoft-prod.deb"
  # Microsoft's .deb stores GNU-format member names, which Apple's /usr/bin/ar
  # cannot extract (it prints an error and still exits 0). The verifier only
  # runs on Ubuntu, so on a Mac without GNU ar (Homebrew binutils' gar) the
  # verifier tests skip, and the install-flow tests stub the verifier so they
  # still exercise what happens after it.
  _MS_GNU_AR=""
  if ar --version 2>/dev/null | grep -q 'GNU ar'; then
    _MS_GNU_AR="ar"
  elif command -v gar > /dev/null 2>&1; then
    _MS_GNU_AR="gar"
  fi
  if [[ -n "${_MS_GNU_AR}" ]]; then
    export _MS_AR_BIN="${_MS_GNU_AR}"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    # Only on a Mac: elsewhere a missing GNU ar must fail, not skip, or a CI
    # image without binutils would silently drop every verifier test.
    _ms_verify_deb() { return 0; }
  fi
  # Default _PWSH_BIN to a path that cannot resolve, at SETUP scope. Without
  # it, a test that forgets its own override resolves the LITERAL `pwsh` --
  # and this Mac has a real /opt/homebrew/bin/pwsh, so that test would
  # silently take the early-return "already installed" branch and assert
  # nothing about the install path it meant to exercise.
  export _PWSH_BIN="${BATS_TEST_TMPDIR}/nonexistent-pwsh"
  # Go installs into _GO_INSTALL_ROOT, stamps into _DL_STAMP_DIR and extracts
  # under _DL_TMP_ROOT. tests/mocks/sudo execs real commands, so without these a
  # go test would write the real /usr/local/go. tar is the real one: the mock
  # only records, and the swap tests need a tree to move.
  export _GO_INSTALL_ROOT="${BATS_TEST_TMPDIR}/go-root"
  export _DL_STAMP_DIR="${BATS_TEST_TMPDIR}/stamps"
  export _DL_TMP_ROOT="${BATS_TEST_TMPDIR}/dl-tmp"
  mkdir -p "${_GO_INSTALL_ROOT}" "${_DL_TMP_ROOT}"
  _GO_CLEAN_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  _DL_TAR_BIN="$(PATH="${_GO_CLEAN_PATH}" command -v tar)"
  export _DL_TAR_BIN="${_DL_TAR_BIN:-/nonexistent/tar}"
  # k8s_tools and hashicorp install through _install_fetched_binary, which
  # writes under _DL_BIN_DIR (default /usr/local/bin) via the exec-ing sudo mock.
  # unzip and zip are the real ones: the mocks only record.
  export _DL_BIN_DIR="${BATS_TEST_TMPDIR}/dl-bin"
  mkdir -p "${_DL_BIN_DIR}"
  _DL_UNZIP_BIN="$(PATH="${_GO_CLEAN_PATH}" command -v unzip)"
  export _DL_UNZIP_BIN="${_DL_UNZIP_BIN:-/nonexistent/unzip}"
  _ZIP_BIN="$(PATH="${_GO_CLEAN_PATH}" command -v zip)"
  _ZIP_BIN="${_ZIP_BIN:-/nonexistent/zip}"
  # _install_ubuntu_docker and _install_ubuntu_nvidia fetch keyrings through
  # _install_apt_keyring and write a docker source list; tests/mocks/sudo execs
  # real commands, so these keep every write under the test tmpdir. The gpg stub
  # writes its -o target, which tests/mocks/gpg does not.
  export _APT_KEY_GPG_BIN="${REPO_ROOT}/tests/mocks/gpg-dearmor"
  export _DOCKER_KEYRING="${BATS_TEST_TMPDIR}/docker-keyrings/docker.asc"
  export _DOCKER_SOURCES_LIST="${BATS_TEST_TMPDIR}/docker.list"
  # There is no usermod mock, and the real one would run against the invoking
  # account. A shim directory on PATH holds a usermod that succeeds and an apt
  # wrapper that fails only for the packages named in SHIM_APT_FAIL_PKGS.
  export SHIM_DIR="${BATS_TEST_TMPDIR}/shims"
  mkdir -p "${SHIM_DIR}"
  printf '#!/usr/bin/env bash\nprintf "usermod %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit "${SHIM_USERMOD_EXIT:-0}"\n' > "${SHIM_DIR}/usermod"
  cat > "${SHIM_DIR}/apt" << SHIM
#!/usr/bin/env bash
for _a in "\$@"; do
  for _p in \${SHIM_APT_FAIL_PKGS:-}; do
    if [[ "\${_a}" == "\${_p}" ]]; then
      printf 'apt %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
      exit 100
    fi
  done
done
exec "${REPO_ROOT}/tests/mocks/apt" "\$@"
SHIM
  # cloud_tools installs cloudflare-warp through apt-get, so it needs the same
  # per-package failure wrapper.
  sed 's#tests/mocks/apt"#tests/mocks/apt-get"#' "${SHIM_DIR}/apt" > "${SHIM_DIR}/apt-get"
  # A real flatpak is installed on this box and tests/mocks/sudo execs real
  # commands, so without a shim `sudo flatpak ...` reaches the real binary
  # (tdd.md E2). SHIM_FLATPAK_REMOTE_EXIT / SHIM_FLATPAK_EXIT drive failures.
  cat > "${SHIM_DIR}/flatpak" << 'SHIM'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$*" >> "${MOCK_CALLS_FILE}"
case "$1" in
  remote-add) exit "${SHIM_FLATPAK_REMOTE_EXIT:-0}" ;;
  install) exit "${SHIM_FLATPAK_EXIT:-0}" ;;
esac
exit 0
SHIM
  # Per-argument failure wrappers, so one sub-install can fail on its own while
  # its siblings succeed: SHIM_SNAP_FAIL_ARGS / SHIM_TEE_FAIL_ARGS fail only a call
  # whose arguments contain that substring, and otherwise exec the repo mock.
  local _b
  for _b in snap tee; do
    cat > "${SHIM_DIR}/${_b}" << SHIM
#!/usr/bin/env bash
_failvar=SHIM_${_b^^}_FAIL_ARGS
if [[ -n "\${!_failvar:-}" && "\$*" == *"\${!_failvar}"* ]]; then
  cat > /dev/null 2>&1 < /dev/null
  printf '${_b} %s\\n' "\$*" >> "\${MOCK_CALLS_FILE}"
  exit 1
fi
exec "${REPO_ROOT}/tests/mocks/${_b}" "\$@"
SHIM
  done
  /bin/chmod +x "${SHIM_DIR}/usermod" "${SHIM_DIR}/apt" "${SHIM_DIR}/apt-get" "${SHIM_DIR}/flatpak" "${SHIM_DIR}/snap" "${SHIM_DIR}/tee"
  PATH="${SHIM_DIR}:${PATH}"
  # Truncate AFTER seeding: cp and chmod are pass-through mocks that log their own
  # invocation, so the seed writes a line containing "rustup" into the call log and
  # breaks any test asserting that string is absent. Every test already assumes it
  # starts from an empty log; this makes that invariant explicit rather than luck.
  : > "${MOCK_CALLS_FILE}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Writes a stub pwsh binary and prints its own file path (not a directory --
# the name says so). `_rc` is the exit status the stub returns when RUN -- 0
# for "pwsh already works", nonzero for "pwsh resolves but does not run",
# which is the distinction _install_ubuntu_powershell's guard exists to make
# (a `command -v`-only guard cannot see it: the file exists and is executable
# either way). "pwsh is absent entirely" needs no call to this helper at all
# -- setup()'s own _PWSH_BIN default already points at a path nothing creates.
_pwsh_stub_bin() {
  local _rc="${1:-0}" _dir
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  cat > "${_dir}/pwsh" << EOF
#!/usr/bin/env bash
exit ${_rc}
EOF
  # /bin/chmod, not the mocked `chmod` load_mocks put ahead of it on PATH --
  # that mock is a pass-through that ALSO logs to MOCK_CALLS_FILE, which
  # would pollute the very log a caller asserting "nothing was called" reads.
  /bin/chmod +x "${_dir}/pwsh"
  printf '%s/pwsh' "${_dir}"
}

# Writes a pwsh stub that sleeps past any sane probe timeout before exiting
# 0, and prints its own path. Simulates the half-installed hang state
# _PWSH_PROBE_TIMEOUT exists to bound -- driving a genuinely indefinite hang
# is not practical in a unit test, so the test that uses this measures
# wall-clock time to prove the probe was actually killed rather than run to
# completion. The stub calls /bin/sleep by absolute path, not a bare
# `sleep` lookup -- this file's setup() calls load_mocks, and
# tests/mocks/sleep is a pass-through fake that returns instantly without
# sleeping (shell.md: a PATH mock shadows the binary your own stub needs,
# not just the caller's), which would make the hang this helper exists to
# simulate impossible to produce.
_pwsh_hanging_stub_bin() {
  local _sleep_secs="${1:-5}" _dir
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  cat > "${_dir}/pwsh" << EOF
#!/usr/bin/env bash
/bin/sleep ${_sleep_secs}
exit 0
EOF
  /bin/chmod +x "${_dir}/pwsh"
  printf '%s/pwsh' "${_dir}"
}

# ── _install_ubuntu_base_packages ────────────────────────────────────────────

@test "_install_ubuntu_base_packages: installs hwe-24.04" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "apt install.*linux-generic-hwe-24.04" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_workstation: HAS_SNAP installs workstation snap packages" {
  export NOBLE=1
  unset RESOLUTE
  export HAS_SNAP=1
  run _install_ubuntu_workstation
  [ "$status" -eq 0 ]
  grep -q "snap install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: RESOLUTE installs hwe-26.04" {
  export RESOLUTE=1
  unset NOBLE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "apt install.*linux-generic-hwe-26.04" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: unsupported Ubuntu version returns 1" {
  unset NOBLE RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported Ubuntu version"* ]]
}

# Tri-state: 0 clean, 1 unsupported release, 2 an install failed.
@test "_install_ubuntu_base_packages: clean run returns 0 with no warning" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  cd "${REPO_ROOT}"
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  [[ "$output" != *"base:"*"failed"* ]]
}

@test "_install_ubuntu_base_packages: failed common list returns 2 and names it" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  cd "${REPO_ROOT}"
  export MOCK_XARGS_EXIT=1
  run _install_ubuntu_base_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"base: common list failed"* ]]
  # Both lists must be attempted and both failures recorded: the common list
  # failing must not short-circuit the release list.
  [[ "$output" == *"base: release list failed"* ]]
  [ "$(grep -c '^xargs ' "${MOCK_CALLS_FILE}")" -eq 2 ]
}

@test "_install_ubuntu_base_packages: only the release list failing is named alone" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  local _d="${BATS_TEST_TMPDIR}/commononly"
  mkdir -p "${_d}"
  printf 'build-essential\n' > "${_d}/ubuntu_common_packages.txt"
  cd "${_d}"
  run _install_ubuntu_base_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"base: release list failed"* ]]
  [[ "$output" != *"base: common list failed"* ]]
  # Positive control: the common list's install really ran.
  [ "$(grep -c '^xargs ' "${MOCK_CALLS_FILE}")" -eq 1 ]
}

@test "_install_ubuntu_base_packages: failed hwe kernel install returns 2" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  cd "${REPO_ROOT}"
  export MOCK_APT_FAIL_SUBCMD=install
  run _install_ubuntu_base_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"base: hwe kernel failed"* ]]
  # Positive control: the package lists were still attempted.
  grep -q "^xargs " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: apt update failure warns exactly once and is not a failure" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  cd "${REPO_ROOT}"
  export MOCK_APT_FAIL_SUBCMD=update
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | grep -c 'apt update reported errors')" -eq 1 ]
  grep -q "^xargs " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: a missing package list is a failure" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  local _empty="${BATS_TEST_TMPDIR}/nolists"
  mkdir -p "${_empty}"
  cd "${_empty}"
  run _install_ubuntu_base_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"base: common list failed"* ]]
}

@test "_install_ubuntu_base_packages: a package list with no packages is not a failure" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  local _d="${BATS_TEST_TMPDIR}/emptylists"
  mkdir -p "${_d}"
  printf '# only a comment\n' > "${_d}/ubuntu_common_packages.txt"
  printf '# only a comment\n' > "${_d}/ubuntu_2404_packages.txt"
  cd "${_d}"
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
}

@test "install_ubuntu_packages: base rc 2 is named and every later step still runs" {
  unset MACOS
  export LINUX=1 UBUNTU=1 NOBLE=1
  _install_ubuntu_base_packages() { return 2; }
  local _s
  for _s in inotify workstation powershell go docker nvidia k8s_tools hashicorp cloud_tools brew_packages rust gui_tools misc; do
    eval "_install_ubuntu_${_s}() { printf 'ran ${_s}\\n' >> \"\${MOCK_CALLS_FILE}\"; }"
  done
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"ubuntu packages: failed: base"* ]]
  [ "$(grep -c '^ran ' "${MOCK_CALLS_FILE}")" -eq 13 ]
}

@test "install_ubuntu_packages: real base with a failed install is named and later steps run" {
  unset MACOS
  export LINUX=1 UBUNTU=1 NOBLE=1
  unset RESOLUTE HAS_SNAP
  cd "${REPO_ROOT}"
  export MOCK_XARGS_EXIT=1
  local _s
  for _s in inotify workstation powershell go docker nvidia k8s_tools hashicorp cloud_tools brew_packages rust gui_tools misc; do
    eval "_install_ubuntu_${_s}() { printf 'ran ${_s}\\n' >> \"\${MOCK_CALLS_FILE}\"; }"
  done
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"ubuntu packages: failed: base"* ]]
  [ "$(grep -c '^ran ' "${MOCK_CALLS_FILE}")" -eq 13 ]
}

@test "install_ubuntu_packages: base rc 1 stops before any later step" {
  unset MACOS NOBLE RESOLUTE
  export LINUX=1 UBUNTU=1
  local _s
  for _s in inotify workstation powershell go docker nvidia k8s_tools hashicorp cloud_tools brew_packages rust gui_tools misc; do
    eval "_install_ubuntu_${_s}() { printf 'ran ${_s}\\n' >> \"\${MOCK_CALLS_FILE}\"; }"
  done
  : > "${MOCK_CALLS_FILE}"
  run install_ubuntu_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported Ubuntu version"* ]]
  run grep -c '^ran ' "${MOCK_CALLS_FILE}"
  [ "$output" -eq 0 ]
}

@test "_install_ubuntu_base_packages: NOBLE uses nala for package installs" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "nala install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: RESOLUTE uses nala for package installs" {
  export RESOLUTE=1
  unset NOBLE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "nala install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: nala install uses DEBIAN_FRONTEND=noninteractive" {
  # Regression: without DEBIAN_FRONTEND=noninteractive, dpkg post-install scripts
  # (e.g. iperf3 daemon prompt) pop up ncurses dialogs that freeze WSL2 sessions.
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "DEBIAN_FRONTEND=noninteractive.*nala install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: apt install uses DEBIAN_FRONTEND=noninteractive" {
  # Same regression: hwe kernel install can also trigger debconf prompts.
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "DEBIAN_FRONTEND=noninteractive.*apt install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: comment lines are not passed to nala" {
  # Regression: xargs -a fed comment lines straight to nala, and a comment
  # containing '--user' produced 'No such option: --user', aborting the whole
  # common-package install. Comments and blank lines must be filtered out.
  cd "${REPO_ROOT}"
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  # Real packages reach the install command...
  grep -q "xargs-stdin build-essential" "${MOCK_CALLS_FILE}"
  # ...but comment tokens (e.g. '--user' from the PEP 668 note) do not.
  run grep "xargs-stdin .*--user" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

# One bracketed line per xargs invocation; every one must carry the options after
# `nala install` and before -y, so a dropped -o or a misplaced array fails.
_NALA_CONFFILE_ARGV='argv: xargs [-r][sudo][DEBIAN_FRONTEND=noninteractive][nala][install][-o][Dpkg::Options::=--force-confdef][-o][Dpkg::Options::=--force-confold][-y]'

@test "conffile argv: noble base install passes the conffile options on every nala call" {
  cd "${REPO_ROOT}"
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  local _stub_dir
  _stub_dir="$(argv_probe_stub_path xargs)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  [ "$(grep -c '^argv: xargs ' "${MOCK_CALLS_FILE}")" -eq 2 ]
  [ "$(grep -cxF "${_NALA_CONFFILE_ARGV}" "${MOCK_CALLS_FILE}")" -eq 2 ]
}

@test "conffile argv: resolute base install passes the conffile options on every nala call" {
  cd "${REPO_ROOT}"
  export RESOLUTE=1
  unset NOBLE HAS_SNAP
  local _stub_dir
  _stub_dir="$(argv_probe_stub_path xargs)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  [ "$(grep -c '^argv: xargs ' "${MOCK_CALLS_FILE}")" -eq 2 ]
  [ "$(grep -cxF "${_NALA_CONFFILE_ARGV}" "${MOCK_CALLS_FILE}")" -eq 2 ]
}

@test "conffile argv: workstation install passes the conffile options on its nala call" {
  cd "${REPO_ROOT}"
  export NOBLE=1 HAS_SNAP=1
  unset RESOLUTE
  local _stub_dir
  _stub_dir="$(argv_probe_stub_path xargs)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_workstation
  [ "$status" -eq 0 ]
  # Two xargs calls: the nala package install and the snap install (no apt, no options).
  [ "$(grep -c '^argv: xargs ' "${MOCK_CALLS_FILE}")" -eq 2 ]
  [ "$(grep -cxF "${_NALA_CONFFILE_ARGV}" "${MOCK_CALLS_FILE}")" -eq 1 ]
}

@test "conffile argv: powershell apt install gets the conffile options in order" {
  _PWSH_BIN="$(_pwsh_stub_bin 1)"
  unset DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(argv_probe_stub_path apt)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  grep -qxF 'argv: apt [install][-o][Dpkg::Options::=--force-confdef][-o][Dpkg::Options::=--force-confold][powershell][-y]' "${MOCK_CALLS_FILE}"
}

# A scratch directory holding the two workstation lists, so one can be removed
# without touching the repo's own.
_ws_dir() {
  mkdir -p "${BATS_TEST_TMPDIR}/ws"
  printf 'font-manager\n' > "${BATS_TEST_TMPDIR}/ws/ubuntu_workstation_packages.txt"
  printf 'vlc\n' > "${BATS_TEST_TMPDIR}/ws/ubuntu_workstation_snap_packages.txt"
  cd "${BATS_TEST_TMPDIR}/ws" || return 1
  export HAS_SNAP=1
}

@test "_install_ubuntu_workstation: clean run returns 0" {
  _ws_dir
  run _install_ubuntu_workstation
  [ "$status" -eq 0 ]
  grep -q "xargs-stdin font-manager" "${MOCK_CALLS_FILE}"
  grep -q "xargs-stdin vlc" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_workstation: an unreadable snap list returns 1 after the package list was installed" {
  _ws_dir
  rm "${BATS_TEST_TMPDIR}/ws/ubuntu_workstation_snap_packages.txt"
  run --separate-stderr _install_ubuntu_workstation
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"workstation: snap list failed"* ]]
  grep -q "xargs-stdin font-manager" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_workstation: an unreadable package list returns 1 and the snap list is still installed" {
  _ws_dir
  rm "${BATS_TEST_TMPDIR}/ws/ubuntu_workstation_packages.txt"
  run --separate-stderr _install_ubuntu_workstation
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"workstation: package list failed"* ]]
  grep -q "xargs-stdin vlc" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_workstation: a failing snap install returns 1" {
  _ws_dir
  export MOCK_XARGS_EXIT=1
  run --separate-stderr _install_ubuntu_workstation
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"workstation: snap list failed"* ]]
}

@test "_install_ubuntu_workstation: a snap list holding only comments is an empty list, not a failure" {
  _ws_dir
  printf '# nothing yet\n\n' > "${BATS_TEST_TMPDIR}/ws/ubuntu_workstation_snap_packages.txt"
  run --separate-stderr _install_ubuntu_workstation
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"workstation:"* ]]
  # Positive control: the package list ran.
  grep -q "xargs-stdin font-manager" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_workstation: HAS_SNAP uses nala for workstation packages" {
  cd "${REPO_ROOT}"
  export NOBLE=1
  export HAS_SNAP=1
  unset RESOLUTE
  run _install_ubuntu_workstation
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing workstation packages"* ]]
  grep -q "xargs-stdin font-manager" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_brew_packages (pyenv via brew) ───────────────────────────

@test "_install_ubuntu_brew_packages: installs pyenv via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -qxF "brew install pyenv" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: installs pyenv-virtualenv via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install pyenv-virtualenv" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: installs uv via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -qx "brew install uv" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: does not call pyenv.run curl installer" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  run grep "pyenv.run" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
}

# Writes a pwsh stub with an ABSOLUTE shebang (`#!/bin/bash`, not `#!/usr/bin/env
# bash`), and prints its own path. The two tests below scope PATH to a dir
# containing no `timeout` at all, to exercise _pwsh_probe_runs' timeout-absent
# ELSE branch directly (T1's approach in doctor_dev_tools.bats, for the
# sibling probe). `#!/usr/bin/env bash` (what _pwsh_stub_bin and
# _pwsh_hanging_stub_bin above use) needs `env` to resolve `bash` via THAT
# same restricted PATH and fails with rc 127 ("env: bash: No such file or
# directory") -- measured directly before writing these tests. An absolute
# shebang is resolved by the kernel exec, never by a PATH search, so it is
# unaffected by how narrow the invoking PATH is.
_pwsh_absolute_shebang_stub_bin() {
  local _rc="${1:-0}" _dir
  _dir="$(mktemp -d -p "${BATS_TEST_TMPDIR}")"
  cat > "${_dir}/pwsh" << EOF
#!/bin/bash
exit ${_rc}
EOF
  /bin/chmod +x "${_dir}/pwsh"
  printf '%s/pwsh' "${_dir}"
}

# ── _pwsh_probe_runs: the timeout-absent fallback branch, direct ───────────

@test "_pwsh_probe_runs: the timeout-absent fallback still succeeds when pwsh runs" {
  # Called directly, not through _install_ubuntu_powershell, which would
  # drag in wget/dpkg/apt and obscure which branch of the probe ran.
  local _no_timeout_dir="${BATS_TEST_TMPDIR}/no_timeout_ok"
  mkdir -p "${_no_timeout_dir}"
  _PWSH_BIN="$(_pwsh_absolute_shebang_stub_bin 0)"

  PATH="${_no_timeout_dir}" run _pwsh_probe_runs
  [ "$status" -eq 0 ]
}

@test "_pwsh_probe_runs: the timeout-absent fallback still fails when pwsh does not run" {
  # Companion negative case -- the fallback must discriminate a genuine
  # failure, not vacuously report success for every pwsh. Without this
  # pair, the ELSE branch (lib/linux_ubuntu.sh's _pwsh_probe_runs) is
  # executed by zero tests: `command -v timeout` resolves on every machine
  # this suite runs on, so nothing before this pair ever took it.
  local _no_timeout_dir="${BATS_TEST_TMPDIR}/no_timeout_fail"
  mkdir -p "${_no_timeout_dir}"
  _PWSH_BIN="$(_pwsh_absolute_shebang_stub_bin 1)"

  PATH="${_no_timeout_dir}" run _pwsh_probe_runs
  [ "$status" -ne 0 ]
}

# ── _ms_verify_deb ───────────────────────────────────────────────────────────
#
# packages-microsoft-prod.deb carries a debsig origin signature (_gpgorigin):
# Microsoft's release key signed debian-binary + control.tar.gz + data.tar.gz,
# concatenated. The fixture is the real 1.2-ubuntu24.04 .deb, so the pass case
# is checked against Microsoft's actual signature and the vendored key.
_ms_fixture="${BATS_TEST_DIRNAME}/../fixtures/packages-microsoft-prod.deb"

# _ms_rebuild_deb <out> <members...> -- re-archives the fixture's members
# (optionally modified in ${BATS_TEST_TMPDIR}/m) into <out>.
_ms_unpack() {
  mkdir -p "${BATS_TEST_TMPDIR}/m"
  (cd "${BATS_TEST_TMPDIR}/m" && "${_MS_AR_BIN}" x "${_ms_fixture}")
}
_ms_rebuild_deb() {
  local _out="$1"; shift
  (cd "${BATS_TEST_TMPDIR}/m" && "${_MS_AR_BIN}" rc "${_out}" "$@")
}

_ms_require_gnu_ar() {
  [[ -n "${_MS_GNU_AR}" ]] && return 0
  [[ "$(uname -s)" == "Darwin" ]] && skip "no GNU ar: Apple's ar cannot read the GNU member names in Microsoft's .deb; the verifier runs on Ubuntu only"
  printf 'GNU ar (binutils) is required to test _ms_verify_deb off macOS\n' >&2
  return 1
}

@test "_ms_verify_deb accepts the real Microsoft-signed .deb" {
  _ms_require_gnu_ar
  run _ms_verify_deb "${_ms_fixture}"
  [ "$status" -eq 0 ]
}

@test "_ms_verify_deb rejects a .deb whose data was changed after signing" {
  _ms_require_gnu_ar
  _ms_unpack
  printf 'X' >> "${BATS_TEST_TMPDIR}/m/data.tar.gz"
  _ms_rebuild_deb "${BATS_TEST_TMPDIR}/tampered.deb" debian-binary control.tar.gz data.tar.gz _gpgorigin
  run _ms_verify_deb "${BATS_TEST_TMPDIR}/tampered.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not verify"* ]]
}

@test "_ms_verify_deb rejects an unsigned .deb" {
  _ms_require_gnu_ar
  _ms_unpack
  _ms_rebuild_deb "${BATS_TEST_TMPDIR}/unsigned.deb" debian-binary control.tar.gz data.tar.gz
  run _ms_verify_deb "${BATS_TEST_TMPDIR}/unsigned.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no signature"* ]]
}

@test "_ms_verify_deb rejects a signature from a key other than Microsoft's" {
  _ms_require_gnu_ar
  # A throwaway key signs the same members; import it as the "vendored" key,
  # so only the fingerprint pin can refuse it.
  local _gh="${BATS_TEST_TMPDIR}/gh"
  mkdir -p "${_gh}" && chmod 700 "${_gh}"
  "${_MS_GPG_BIN}" --homedir "${_gh}" --batch --passphrase '' --quick-gen-key 'Not Microsoft <x@example.invalid>' ed25519 sign never 2>/dev/null
  "${_MS_GPG_BIN}" --homedir "${_gh}" --batch --armor --export > "${BATS_TEST_TMPDIR}/other.asc"
  _ms_unpack
  cat "${BATS_TEST_TMPDIR}/m/debian-binary" "${BATS_TEST_TMPDIR}/m/control.tar.gz" "${BATS_TEST_TMPDIR}/m/data.tar.gz" \
    | "${_MS_GPG_BIN}" --homedir "${_gh}" --batch --detach-sign > "${BATS_TEST_TMPDIR}/m/_gpgorigin"
  _ms_rebuild_deb "${BATS_TEST_TMPDIR}/other.deb" debian-binary control.tar.gz data.tar.gz _gpgorigin
  gpgconf --homedir "${_gh}" --kill all >/dev/null 2>&1
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/other.asc" run _ms_verify_deb "${BATS_TEST_TMPDIR}/other.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not verify"* ]]
}

@test "_ms_verify_deb rejects evil members placed ahead of repeated genuine ones" {
  _ms_require_gnu_ar
  _ms_unpack
  local _evil="${BATS_TEST_TMPDIR}/evil"
  mkdir -p "${_evil}"
  printf 'evil\n' > "${_evil}/control.tar.gz"
  printf 'evil\n' > "${_evil}/data.tar.gz"
  cp "${BATS_TEST_TMPDIR}/m/debian-binary" "${_evil}/"
  (cd "${_evil}" && "${_MS_AR_BIN}" rc "${BATS_TEST_TMPDIR}/dup.deb" debian-binary control.tar.gz data.tar.gz)
  (cd "${BATS_TEST_TMPDIR}/m" && "${_MS_AR_BIN}" q "${BATS_TEST_TMPDIR}/dup.deb" control.tar.gz data.tar.gz _gpgorigin)
  run _ms_verify_deb "${BATS_TEST_TMPDIR}/dup.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected members"* ]]
}

@test "_ms_verify_deb rejects an extra data.tar.xz alongside the genuine members" {
  _ms_require_gnu_ar
  _ms_unpack
  printf 'evil\n' > "${BATS_TEST_TMPDIR}/m/data.tar.xz"
  _ms_rebuild_deb "${BATS_TEST_TMPDIR}/xz.deb" debian-binary control.tar.gz data.tar.xz data.tar.gz _gpgorigin
  run _ms_verify_deb "${BATS_TEST_TMPDIR}/xz.deb"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected members"* ]]
}

@test "_ms_verify_deb rejects a revoked or expired key even when the signature is valid" {
  _ms_require_gnu_ar
  # gpg emits VALIDSIG for a revoked or expired key too, and exits 0, so the
  # reject check must run first. A stub gpg emits exactly that combination.
  local _stub="${BATS_TEST_TMPDIR}/gpg-expired"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case " $* " in\n'
    printf '  *" --verify "*)\n'
    printf '    printf "[GNUPG:] EXPKEYSIG %s Microsoft\\n"\n' "${MS_GPG_FPR}"
    printf '    printf "[GNUPG:] VALIDSIG %s 2026-01-01 0 4 0 1 10 00 %s\\n" ;;\n' "${MS_GPG_FPR}" "${MS_GPG_FPR}"
    printf 'esac\n'
    printf 'exit 0\n'
  } > "${_stub}"
  chmod +x "${_stub}"
  _MS_GPG_BIN="${_stub}" run _ms_verify_deb "${_ms_fixture}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"revoked or expired"* ]]
}

@test "_ms_verify_deb refuses when extraction yields nothing, as Apple's ar does" {
  _ms_require_gnu_ar
  # Lists the expected members, then "extracts" nothing and exits 0: the
  # failure mode of Apple's ar on GNU member names.
  local _stub="${BATS_TEST_TMPDIR}/ar-empty"
  {
    printf '#!/usr/bin/env bash\n'
    printf '[ "$1" = t ] && exec %q "$@"\n' "$(command -v "${_MS_AR_BIN}")"
    printf 'exit 0\n'
  } > "${_stub}"
  chmod +x "${_stub}"
  _MS_AR_BIN="${_stub}" run _ms_verify_deb "${_ms_fixture}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not extract"* ]]
}

@test "_ms_verify_deb refuses when the key cannot be imported" {
  _ms_require_gnu_ar
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/no-such-key.asc" run _ms_verify_deb "${_ms_fixture}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not import"* ]]
}

@test "_ms_verify_deb fails with a named cause when ar is missing" {
  _ms_require_gnu_ar
  _MS_AR_BIN="/nonexistent/ar" run _ms_verify_deb "${_ms_fixture}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ar not found"* ]]
}

@test "_ms_verify_deb fails with a named cause when gpg is missing" {
  _ms_require_gnu_ar
  _MS_GPG_BIN="/nonexistent/gpg" run _ms_verify_deb "${_ms_fixture}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gpg not found"* ]]
}

@test "the vendored Microsoft key has the pinned fingerprint" {
  # Derived from the key file by real gpg, independently of the constant it is
  # checked against: a key swap without a pin bump must go red.
  local _fpr
  _fpr="$("${_MS_GPG_BIN}" --show-keys --with-colons "${REPO_ROOT}/keys/microsoft.asc" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
  [ -n "${_fpr}" ]
  [ "${_fpr}" = "${MS_GPG_FPR}" ]
}

@test "_install_ubuntu_powershell does not dpkg -i a .deb that fails verification" {
  _ms_require_gnu_ar
  _PWSH_BIN="$(_pwsh_stub_bin 1)"
  unset MOCK_WGET_FILE  # the wget mock then writes an empty, unverifiable file
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed verification"* ]]
  [ "$(grep -c "dpkg -i" "${MOCK_CALLS_FILE}")" -eq 0 ]
  [ "$(grep -c "apt install powershell" "${MOCK_CALLS_FILE}")" -eq 0 ]
}

# ── _install_ubuntu_powershell ───────────────────────────────────────────────

@test "_install_ubuntu_powershell: pwsh already runs — installs nothing" {
  _PWSH_BIN="$(_pwsh_stub_bin 0)"
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  [[ "$output" == *"pwsh is installed"* ]]
  # Guard must return before touching wget/dpkg/sudo/apt.
  refute_grep "^(wget|dpkg|sudo|apt) " "${MOCK_CALLS_FILE}" -E
}

@test "_install_ubuntu_powershell: pwsh resolves but does not run still installs" {
  # A `command -v pwsh`-only guard would see this stub as "installed" (it
  # exists and is executable) and stop here -- the guard must actually RUN
  # it. This is the case a command-v mutation of the guard cannot pass.
  _PWSH_BIN="$(_pwsh_stub_bin 1)"
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
  grep -q "dpkg -i" "${MOCK_CALLS_FILE}"
  grep -q "apt update" "${MOCK_CALLS_FILE}"
  grep -qE "apt install powershell" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: dpkg -i sees DEBIAN_FRONTEND=noninteractive" {
  _PWSH_BIN="$(_pwsh_stub_bin 1)"
  unset DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path dpkg)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  grep -qE '^frontend: dpkg -i .*DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

@test "conffile argv: powershell dpkg -i restores a deleted conffile (confmiss) and keeps the rest" {
  _PWSH_BIN="$(_pwsh_stub_bin 1)"
  unset DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(argv_probe_stub_path dpkg)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  [ "$(grep -c '^argv: dpkg ' "${MOCK_CALLS_FILE}")" -eq 1 ]
  grep -qE '^argv: dpkg \[-i\]\[--force-confdef\]\[--force-confold\]\[--force-confmiss\]\[.*packages-microsoft-prod\.deb\]$' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: apt install succeeding does not mean pwsh runs" {
  # The condition this task exists for, one level out: apt exits 0 for
  # "powershell is already the newest version" even when the installed
  # binary is broken (measured on `claude`). The success message must be
  # gated on pwsh actually running afterward, not on apt's exit status.
  # tdd.md E5: the absence of "pwsh is installed" alone would also be
  # satisfied by the function never running at all, so also assert the WARN
  # naming the real cause is present.
  _PWSH_BIN="$(_pwsh_stub_bin 1)"
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"apt install succeeded but pwsh still does not run"* ]]
  [[ "$output" != *"pwsh is installed"* ]]
}

@test "_install_ubuntu_powershell: a genuinely successful install prints pwsh is installed only once verified" {
  # Companion to the test above: prove the fix does not just suppress the
  # success message unconditionally -- a run where pwsh genuinely starts
  # working after apt install must still print it. Modeled by having the
  # apt-install STEP materialize the working binary, since a stub's own
  # exit code is otherwise static for the life of one test.
  local _stub_dir="${BATS_TEST_TMPDIR}/apt-installs-pwsh"
  local _working_pwsh="${BATS_TEST_TMPDIR}/working-pwsh"
  mkdir -p "${_stub_dir}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_working_pwsh}"
  /bin/chmod +x "${_working_pwsh}"
  _PWSH_BIN="${BATS_TEST_TMPDIR}/pwsh-appears-after-install"
  cat > "${_stub_dir}/apt" << EOF
#!/usr/bin/env bash
printf "apt %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
[[ "\$1" == "install" ]] && cp "${_working_pwsh}" "${_PWSH_BIN}" && chmod +x "${_PWSH_BIN}"
exit 0
EOF
  chmod +x "${_stub_dir}/apt"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  [[ "$output" == *"pwsh is installed"* ]]
  [[ "$output" != *"[WARN]"* ]]
}

@test "_install_ubuntu_powershell: calls wget for packages-microsoft-prod.deb" {
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: a stale .deb from a prior failed attempt does not block reinstall" {
  # The regression this task exists to fix: a box whose first attempt hit the
  # resolute gap (see comment in lib/linux_ubuntu.sh) downloaded and
  # dpkg -i'd the WRONG config and left the .deb behind. Every run since
  # skipped the whole block because the file existed -- measured on `claude`,
  # 2026-09-17. The guard must now be independent of any pre-existing .deb.
  touch "${HOME}/software_downloads/packages-microsoft-prod.deb"
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
  grep -q "dpkg -i" "${MOCK_CALLS_FILE}"
  grep -q "apt update" "${MOCK_CALLS_FILE}"
  grep -qE "apt install powershell" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: wget failure warns naming wget and skips dpkg/apt" {
  export MOCK_WGET_EXIT=1
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"wget"* ]]
  refute_grep "dpkg -i" "${MOCK_CALLS_FILE}"
  refute_grep "^apt " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: dpkg failure warns naming dpkg and skips apt" {
  export MOCK_DPKG_EXIT=1
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"dpkg"* ]]
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
  refute_grep "^apt " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: apt update failure warns naming apt update and skips apt install" {
  export MOCK_APT_EXIT=1
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"apt update"* ]]
  grep -q "dpkg -i" "${MOCK_CALLS_FILE}"
  refute_grep "install powershell" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: apt install failure warns after a successful apt update" {
  # MOCK_APT_EXIT is one binary for both `apt update` and `apt install`, so
  # asserting install-only failure needs a stub that discriminates by
  # argument -- do not edit tests/mocks/apt, which every other test depends
  # on defaulting to success.
  local _stub_dir="${BATS_TEST_TMPDIR}/apt-install-fails"
  mkdir -p "${_stub_dir}"
  cat > "${_stub_dir}/apt" << 'EOF'
#!/usr/bin/env bash
printf "apt %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
[[ "$1" == "install" ]] && exit 1
exit 0
EOF
  chmod +x "${_stub_dir}/apt"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_powershell
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"apt install powershell failed"* ]]
  # The post-install probe also returns 1 and also says "apt install", so
  # without this the test passes even with the install check removed.
  [[ "$output" != *"still does not run"* ]]
  grep -q "apt update" "${MOCK_CALLS_FILE}"
  grep -q "apt install powershell" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: a hanging pwsh probe is bounded by timeout rather than blocking the run" {
  # timeout is real here, not mocked (shell.md: the point is whether OUR
  # wrapping resolves/wraps/reads rc correctly, not whether timeout itself
  # works). Both probes in the function (the initial guard and the
  # post-apt-install re-check) hit this same 20s hanging stub. Both bounded at
  # 1s costs about 2s; one bounded and one unbounded about 21s; neither
  # bounded 40s. A 20s ceiling still fails both unbounded cases while leaving
  # about 18s of headroom for a loaded CI runner (a 5s stub with a 5s ceiling
  # left only ~3s and flaked at 1 of 5 under bats --jobs).
  export _PWSH_PROBE_TIMEOUT=1
  _PWSH_BIN="$(_pwsh_hanging_stub_bin 20)"

  local _start _end _elapsed
  _start="$(date +%s)"
  run _install_ubuntu_powershell
  _end="$(date +%s)"
  _elapsed=$(( _end - _start ))

  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  [ "${_elapsed}" -lt 20 ]
  [[ "$output" == *"apt install succeeded but pwsh still does not run"* ]]
}

# ── _install_ubuntu_go ───────────────────────────────────────────────────────

# A go tarball whose go/bin/go and go/bin/v both hold "new".
_make_go_tarball() {
  local _src="${BATS_TEST_TMPDIR}/gosrc"
  mkdir -p "${_src}/go/bin"
  printf 'new' > "${_src}/go/bin/go"
  printf 'new' > "${_src}/go/bin/v"
  /bin/chmod +x "${_src}/go/bin/go"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/go.tgz" -C "${_src}" go
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/go.tgz"
}

# Stub go reporting <version>; every go test sets _GO_BIN (tdd.md pitfall G).
_go_stub() {
  local _v="${1:-1.27.1}"
  printf '#!/usr/bin/env bash\nprintf "go version go%s linux/amd64\\n"\n' "${_v}" > "${BATS_TEST_TMPDIR}/gostub"
  /bin/chmod +x "${BATS_TEST_TMPDIR}/gostub"
  export _GO_BIN="${BATS_TEST_TMPDIR}/gostub"
}

# An existing install in the fixture root whose go/bin/v holds "old".
_seed_go() {
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  printf 'old' > "${_GO_INSTALL_ROOT}/go/bin/v"
  printf 'old' > "${_GO_INSTALL_ROOT}/go/bin/go"
  /bin/chmod +x "${_GO_INSTALL_ROOT}/go/bin/go"
}

_go_tmpdir_from_calls() {
  grep '^wget ' "${MOCK_CALLS_FILE}" | head -1 | sed -E 's/.* -O ([^ ]+)\/go\.tgz .*/\1/'
}

_go_stamp() { printf '%s/go' "${_DL_STAMP_DIR}"; }

@test "_install_ubuntu_go: fetches the pinned URL, installs the tree and stamps it" {
  _make_go_tarball
  _go_stub 1.27.1
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "^wget .*${GO_DOWNLOAD_URL}" "${MOCK_CALLS_FILE}"
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
  [ "$(< "$(_go_stamp)")" = "${GO_DOWNLOAD_URL}" ]
}

@test "_install_ubuntu_go: an up-to-date stamp skips the fetch and prints the skip line" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${GO_DOWNLOAD_URL}" > "$(_go_stamp)"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [[ "$output" == *"go: up to date (stamp $(_go_stamp)); rm it to force a re-install"* ]]
  refute_grep "^wget " "${MOCK_CALLS_FILE}"
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
}

@test "_install_ubuntu_go: a stamp with no installed go does not skip" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${GO_DOWNLOAD_URL}" > "$(_go_stamp)"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "^wget " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: a stamp for a different URL does not skip" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  mkdir -p "${_DL_STAMP_DIR}"
  printf 'https://example.invalid/older.tar.gz\n' > "$(_go_stamp)"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "^wget " "${MOCK_CALLS_FILE}"
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
  [ "$(< "$(_go_stamp)")" = "${GO_DOWNLOAD_URL}" ]
}

@test "_install_ubuntu_go: series match, go1.27.1 against GO_VER 1.27, succeeds" {
  _make_go_tarball
  _go_stub 1.27.1
  export GO_VER="1.27"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [[ "$output" == *"Go 1.27 is installed"* ]]
}

@test "_install_ubuntu_go: an exact version equal to GO_VER succeeds" {
  _make_go_tarball
  _go_stub 1.26
  export GO_VER="1.26"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
}

@test "_install_ubuntu_go: a different series fails with the version warning" {
  _make_go_tarball
  _go_stub 1.26.3
  export GO_VER="1.27"
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: version check failed (installed 1.26.3, want 1.27)"* ]]
}

@test "_install_ubuntu_go: a longer series sharing a prefix does not match" {
  _make_go_tarball
  _go_stub 1.270.1
  export GO_VER="1.27"
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
}

@test "_install_ubuntu_go: a failed download leaves the install, no stamp and no temp dir" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  export MOCK_WGET_FAIL_URL="${GO_DOWNLOAD_URL}"
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: download failed"* ]]
  # Positive control: the fetch really targeted the throwaway root.
  [[ "$(_go_tmpdir_from_calls)" == "${_DL_TMP_ROOT}/.dl."* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  [ ! -e "$(_go_stamp)" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

@test "_install_ubuntu_go: a tarball without go/bin/go fails the extract stage and cleans up" {
  _go_stub 1.27.1
  _seed_go
  printf 'not a tarball' > "${BATS_TEST_TMPDIR}/junk"
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/junk"
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: extract failed"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  [ ! -e "$(_go_stamp)" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

# The extract stage has three independent checks; each test below satisfies the
# other two so only the named one can fail it.
_assert_go_extract_refused() {
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: extract failed"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  [ ! -e "$(_go_stamp)" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

@test "_install_ubuntu_go: a real tarball with go/ but no bin/go fails the extract stage" {
  _go_stub 1.27.1
  _seed_go
  local _src="${BATS_TEST_TMPDIR}/gosrc-nobin"
  mkdir -p "${_src}/go/bin"
  printf 'new' > "${_src}/go/bin/v"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/nobin.tgz" -C "${_src}" go
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/nobin.tgz"
  run _install_ubuntu_go
  _assert_go_extract_refused
}

@test "_install_ubuntu_go: a go/bin/go that is a symlink fails the extract stage" {
  _go_stub 1.27.1
  _seed_go
  local _src="${BATS_TEST_TMPDIR}/gosrc-link"
  mkdir -p "${_src}/go/bin"
  printf 'new' > "${_src}/go/bin/v"
  ln -s v "${_src}/go/bin/go"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/link.tgz" -C "${_src}" go
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/link.tgz"
  run _install_ubuntu_go
  _assert_go_extract_refused
}

@test "_install_ubuntu_go: a tar that extracts a good tree and then exits non-zero fails the extract stage" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  local _real="${_DL_TAR_BIN}"
  local _stub="${BATS_TEST_TMPDIR}/tar-then-fail"
  printf '#!/usr/bin/env bash\n"%s" "$@"\nexit 1\n' "${_real}" > "${_stub}"
  /bin/chmod +x "${_stub}"
  export _DL_TAR_BIN="${_stub}"
  run _install_ubuntu_go
  _assert_go_extract_refused
}

@test "_install_ubuntu_go: the new tree is chowned root:root before the first swap move" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  local _tmp _chown_line _mv_line
  _tmp="$(_go_tmpdir_from_calls)"
  _chown_line="$(grep -n "^chown -R root:root ${_tmp}/go\$" "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  _mv_line="$(grep -n '^mv ' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  [ -n "${_chown_line}" ]
  [ -n "${_mv_line}" ]
  [ "${_chown_line}" -lt "${_mv_line}" ]
}

@test "_install_ubuntu_go: a failed chown fails the sub-install and leaves the install" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  export MOCK_CHOWN_EXIT=1
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: chown failed"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

@test "_install_ubuntu_go: replacing an install moves the old tree aside, then the new one in" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  local _tmp
  _tmp="$(_go_tmpdir_from_calls)"
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 1p)" = "mv ${_GO_INSTALL_ROOT}/go ${_GO_INSTALL_ROOT}/go.old" ]
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 2p)" = "mv ${_tmp}/go ${_GO_INSTALL_ROOT}/go" ]
  # go.old is deleted only once the new tree is in place.
  [ ! -e "${_GO_INSTALL_ROOT}/go.old" ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
}

@test "_install_ubuntu_go: a failing new-tree move restores the old tree" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  export MOCK_MV_FAIL_ARGS=".dl."
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: install failed"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  [ ! -e "$(_go_stamp)" ]
  # The aside move happened, then the restore ran (not a no-op).
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 1p)" = "mv ${_GO_INSTALL_ROOT}/go ${_GO_INSTALL_ROOT}/go.old" ]
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 3p)" = "mv ${_GO_INSTALL_ROOT}/go.old ${_GO_INSTALL_ROOT}/go" ]
  [ -z "$(ls -A "${_DL_TMP_ROOT}")" ]
}

@test "_install_ubuntu_go: no old tree and a failing new-tree move attempts no restore" {
  _make_go_tarball
  _go_stub 1.27.1
  export MOCK_MV_FAIL_ARGS=".dl."
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [ "$(grep -c '^mv ' "${MOCK_CALLS_FILE}")" -eq 1 ]
  grep -q "^mv .*\.dl\..*/go ${_GO_INSTALL_ROOT}/go\$" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: a go.old with no go is moved back first, then swapped in order" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'old' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  # A real previous install has a go binary; the restored tree must pass the
  # intactness check before go.old is replaced.
  printf 'old' > "${_GO_INSTALL_ROOT}/go.old/bin/go"
  /bin/chmod +x "${_GO_INSTALL_ROOT}/go.old/bin/go"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  local _tmp _r="${_GO_INSTALL_ROOT}"
  _tmp="$(_go_tmpdir_from_calls)"
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 1p)" = "mv ${_r}/go.old ${_r}/go" ]
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 2p)" = "mv ${_r}/go ${_r}/go.old" ]
  [ "$(grep '^mv ' "${MOCK_CALLS_FILE}" | sed -n 3p)" = "mv ${_tmp}/go ${_r}/go" ]
  [ "$(< "${_r}/go/bin/v")" = "new" ]
}

@test "_install_ubuntu_go: a go.old with no go and a failing new-tree move leaves the old content in go" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'old' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  _seed_intact_go_old
  export MOCK_MV_FAIL_ARGS=".dl."
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
}

@test "_install_ubuntu_go: a failing move-back fails the sub-install without touching go.old" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'old' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  _seed_intact_go_old
  export MOCK_MV_FAIL_ARGS="go.old ${_GO_INSTALL_ROOT}/go"
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: restore failed"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go.old/bin/v")" = "old" ]
  [ ! -e "${_GO_INSTALL_ROOT}/go" ]
  [ "$(grep -c '^mv ' "${MOCK_CALLS_FILE}")" -eq 1 ]
  [ ! -e "$(_go_stamp)" ]
}

@test "_install_ubuntu_go: a leftover go.old is replaced and the tree is not nested" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'stale' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
  [ ! -e "${_GO_INSTALL_ROOT}/go/go" ]
  [ ! -e "${_GO_INSTALL_ROOT}/go.old/go" ]
}

# An intact go.old (bin/go a real executable) holding "old" in bin/v.
_seed_intact_go_old() {
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'old' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  printf 'old' > "${_GO_INSTALL_ROOT}/go.old/bin/go"
  /bin/chmod +x "${_GO_INSTALL_ROOT}/go.old/bin/go"
}

# With the new-tree move failing, a damaged go (and damaged go.old) must have
# been deleted rather than kept or restored: go is absent, or a real directory
# without the damaged trees' marker. The fixture is restored afterwards.
_go_probe_damaged_dropped() {
  local _r="${_GO_INSTALL_ROOT}" _snap="${BATS_TEST_TMPDIR}/gosnap"
  rm -rf "${_snap}"; mkdir -p "${_snap}"
  cp -a "${_r}/." "${_snap}/"
  MOCK_MV_FAIL_ARGS=".dl." run _install_ubuntu_go
  [ "$status" -eq 1 ]
  # Explicit if: a failing `a || b` list does not trip bats' errexit here.
  if ! { { [ ! -e "${_r}/go" ] && [ ! -L "${_r}/go" ]; } \
    || { [ -d "${_r}/go" ] && [ ! -L "${_r}/go" ] && [ ! -e "${_r}/go/bin/marker" ]; }; }; then
    return 1
  fi
  rm -rf "${_r}/go" "${_r}/go.old"
  cp -a "${_snap}/." "${_r}/"
}

# Run _install_ubuntu_go twice; both must succeed (a damaged tree must heal).
_go_twice_ok() {
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
  [ -f "$(_go_stamp)" ]
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
}

@test "_install_ubuntu_go: a damaged go (no bin/go) is replaced, and a second run succeeds" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  printf 'partial' > "${_GO_INSTALL_ROOT}/go/bin/v"
  : > "${_GO_INSTALL_ROOT}/go/bin/marker"
  _go_probe_damaged_dropped
  _go_twice_ok
  [[ "$output" == *"up to date"* ]]
}

@test "_install_ubuntu_go: a damaged go beside an intact go.old is replaced and go.old removed" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  printf 'partial' > "${_GO_INSTALL_ROOT}/go/bin/v"
  _seed_intact_go_old
  : > "${_GO_INSTALL_ROOT}/go/bin/marker"
  _go_probe_damaged_dropped
  _go_twice_ok
  [ ! -e "${_GO_INSTALL_ROOT}/go.old" ]
}

@test "_install_ubuntu_go: a damaged go beside a damaged go.old is replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin" "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'partial' > "${_GO_INSTALL_ROOT}/go/bin/v"
  printf 'partial' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  : > "${_GO_INSTALL_ROOT}/go/bin/marker"
  : > "${_GO_INSTALL_ROOT}/go.old/bin/marker"
  _go_probe_damaged_dropped
  _go_twice_ok
  [ ! -e "${_GO_INSTALL_ROOT}/go.old" ]
}

@test "_install_ubuntu_go: a damaged go.old with no go is not restored" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  : > "${_GO_INSTALL_ROOT}/go.old/bin/marker"
  _go_probe_damaged_dropped
  _go_twice_ok
}

@test "_install_ubuntu_go: an intact go.old beside an intact go is removed after the swap" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  _seed_intact_go_old
  _go_twice_ok
  [ ! -e "${_GO_INSTALL_ROOT}/go.old" ]
}

@test "_install_ubuntu_go: a plain file at go is replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  printf 'junk' > "${_GO_INSTALL_ROOT}/go"
  _go_probe_damaged_dropped
  _go_twice_ok
}

@test "_install_ubuntu_go: a 0-byte go/bin/go is damaged and replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  : > "${_GO_INSTALL_ROOT}/go/bin/go"
  /bin/chmod +x "${_GO_INSTALL_ROOT}/go/bin/go"
  _seed_intact_go_old
  export MOCK_MV_FAIL_ARGS=".dl."
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  # The intact go.old was the restore source.
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  unset MOCK_MV_FAIL_ARGS
  rm -rf "${_GO_INSTALL_ROOT}/go"
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  : > "${_GO_INSTALL_ROOT}/go/bin/go"
  /bin/chmod +x "${_GO_INSTALL_ROOT}/go/bin/go"
  _go_twice_ok
}

@test "_install_ubuntu_go: a symlinked go/bin/go is damaged and replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  ln -s "${BATS_TEST_TMPDIR}/gostub" "${_GO_INSTALL_ROOT}/go/bin/go"
  _seed_intact_go_old
  export MOCK_MV_FAIL_ARGS=".dl."
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  unset MOCK_MV_FAIL_ARGS
  rm -rf "${_GO_INSTALL_ROOT}/go"
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  ln -s "${BATS_TEST_TMPDIR}/gostub" "${_GO_INSTALL_ROOT}/go/bin/go"
  _go_twice_ok
}

@test "_install_ubuntu_go: a directory at go/bin/go is damaged and replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin/go"
  printf 'x' > "${_GO_INSTALL_ROOT}/go/bin/go/f"
  : > "${_GO_INSTALL_ROOT}/go/bin/marker"
  _go_probe_damaged_dropped
  _go_twice_ok
}

@test "_install_ubuntu_go: a symlink at go to an intact tree is damaged and replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${BATS_TEST_TMPDIR}/elsewhere/bin"
  printf 'old' > "${BATS_TEST_TMPDIR}/elsewhere/bin/go"
  /bin/chmod +x "${BATS_TEST_TMPDIR}/elsewhere/bin/go"
  ln -s "${BATS_TEST_TMPDIR}/elsewhere" "${_GO_INSTALL_ROOT}/go"
  _go_probe_damaged_dropped
  _go_twice_ok
  [ ! -L "${_GO_INSTALL_ROOT}/go" ]
}

@test "_install_ubuntu_go: a non-executable go/bin/go is damaged and replaced" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  printf 'x' > "${_GO_INSTALL_ROOT}/go/bin/go"
  /bin/chmod -x "${_GO_INSTALL_ROOT}/go/bin/go"
  _seed_intact_go_old
  export MOCK_MV_FAIL_ARGS=".dl."
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  unset MOCK_MV_FAIL_ARGS
  rm -rf "${_GO_INSTALL_ROOT}/go"
  mkdir -p "${_GO_INSTALL_ROOT}/go/bin"
  printf 'x' > "${_GO_INSTALL_ROOT}/go/bin/go"
  /bin/chmod -x "${_GO_INSTALL_ROOT}/go/bin/go"
  _go_twice_ok
}

@test "_install_ubuntu_go: an intact go beside a stale go.old still replaces go.old" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'stale' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
  [ ! -e "${_GO_INSTALL_ROOT}/go.old" ]
}

@test "_install_ubuntu_go: a go.old that survives its delete is never moved onto, so nothing nests" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  mkdir -p "${_GO_INSTALL_ROOT}/go.old/bin"
  printf 'stale' > "${_GO_INSTALL_ROOT}/go.old/bin/v"
  # An rm that leaves go.old alone, as a delete that silently did nothing would.
  local _shim="${BATS_TEST_TMPDIR}/rmshim"
  mkdir -p "${_shim}"
  printf '#!/usr/bin/env bash\n[[ "$*" == *go.old* ]] && exit 0\nexec /bin/rm "$@"\n' > "${_shim}/rm"
  /bin/chmod +x "${_shim}/rm"
  PATH="${_shim}:${PATH}" run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: swap failed"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  [ ! -e "${_GO_INSTALL_ROOT}/go.old/go" ]
  refute_grep "^mv " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: a failed removal of a damaged go fails the run and keeps the intact go.old" {
  _make_go_tarball
  _go_stub 1.27.1
  mkdir -p "${_GO_INSTALL_ROOT}/go"
  printf 'damaged' > "${_GO_INSTALL_ROOT}/go/marker"
  _seed_intact_go_old
  # An rm that refuses exactly the damaged go and nothing else.
  local _shim="${BATS_TEST_TMPDIR}/rmshim"
  mkdir -p "${_shim}"
  printf '#!/usr/bin/env bash\n[[ "$*" == "-rf %s/go" ]] && exit 1\nexec /bin/rm "$@"\n' "${_GO_INSTALL_ROOT}" > "${_shim}/rm"
  /bin/chmod +x "${_shim}/rm"
  PATH="${_shim}:${PATH}" run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: swap failed"* ]]
  # The cause, not just the stage: go.old is the only good copy and must survive.
  [ "$(< "${_GO_INSTALL_ROOT}/go.old/bin/v")" = "old" ]
  [ -f "${_GO_INSTALL_ROOT}/go/marker" ]
  [ ! -e "${_DL_STAMP_DIR}/go" ]
  refute_grep "^mv " "${MOCK_CALLS_FILE}"
}

# A mv that logs like the mock, fails any call whose argv contains $1 (a
# substring), optionally leaving a go dir behind as a half-done move would.
_mv_shim() {
  local _fail="$1" _leave="${2:-}" _shim="${BATS_TEST_TMPDIR}/mvshim"
  mkdir -p "${_shim}"
  cat > "${_shim}/mv" << EOF
#!/usr/bin/env bash
printf 'mv %s\n' "\$*" >> "\${MOCK_CALLS_FILE}"
if [[ "\$*" == *"${_fail}"* ]]; then
  [[ -n "${_leave}" ]] && mkdir -p "${_leave}"
  exit 1
fi
exec /bin/mv "\$@"
EOF
  /bin/chmod +x "${_shim}/mv"
  printf '%s' "${_shim}"
}

@test "_install_ubuntu_go: an up-to-date stamp still runs the version check" {
  _make_go_tarball
  _go_stub 1.26.3
  _seed_go
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${GO_DOWNLOAD_URL}" > "$(_go_stamp)"
  export GO_VER="1.27"
  run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: version check failed (installed 1.26.3, want 1.27)"* ]]
  refute_grep "^wget " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: restore is not attempted onto a go that exists" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  local _shim
  _shim="$(_mv_shim ".dl." "${_GO_INSTALL_ROOT}/go")"
  PATH="${_shim}:${PATH}" run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not restore"* ]]
  [[ "$output" == *"${_GO_INSTALL_ROOT}/go.old"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go.old/bin/v")" = "old" ]
  # No nesting: the restore must not have moved go.old into the existing go.
  [ ! -e "${_GO_INSTALL_ROOT}/go/go.old" ]
  [ ! -e "$(_go_stamp)" ]
}

@test "_install_ubuntu_go: new-tree move and restore both failing keeps the old tree in go.old" {
  _make_go_tarball
  _go_stub 1.27.1
  _seed_go
  local _shim
  _shim="$(_mv_shim "NEVER-MATCHES")"
  # Fail both the new-tree move and the go.old -> go restore.
  printf '#!/usr/bin/env bash\nprintf "mv %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\n[[ "$*" == *.dl.* || "$*" == "%s/go.old %s/go" ]] && exit 1\nexec /bin/mv "$@"\n' "${_GO_INSTALL_ROOT}" "${_GO_INSTALL_ROOT}" > "${_shim}/mv"
  PATH="${_shim}:${PATH}" run _install_ubuntu_go
  [ "$status" -eq 1 ]
  [[ "$output" == *"go: install failed"* ]]
  [[ "$output" == *"could not restore the previous tree; it is at ${_GO_INSTALL_ROOT}/go.old"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go.old/bin/v")" = "old" ]
  [ ! -e "$(_go_stamp)" ]
}

@test "_install_ubuntu_go: an unwritable stamp warns and still succeeds" {
  _make_go_tarball
  _go_stub 1.27.1
  printf 'file' > "${BATS_TEST_TMPDIR}/not-a-dir"
  export _DL_STAMP_DIR="${BATS_TEST_TMPDIR}/not-a-dir/stamps"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [[ "$output" == *"go: could not write stamp"* ]]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
}

# ── _install_ubuntu_rust ─────────────────────────────────────────────────────

@test "_install_ubuntu_rust: HAS_RUST unset does nothing" {
  unset HAS_RUST
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
  ! grep -q "rustup" "${MOCK_CALLS_FILE}"
}

# Renamed rather than re-asserted: the assertion (no sh.rustup.rs call) still holds,
# but the old name said "brew provides rustup", which stopped being true when this
# repo began provisioning rustup.rs itself. Reconciling the assertion to match a new
# name would claim coverage nobody wrote; renaming records what it actually pins.
@test "_install_ubuntu_rust: never installs rustup via the curl|sh one-liner" {
  export HAS_RUST=1
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
  run grep "sh.rustup.rs" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_rust: does not call nextest curl installer" {
  export HAS_RUST=1
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
  run grep "nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_brew_packages: installs cargo-nextest via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install cargo-nextest" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: installs cargo-cyclonedx via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install cargo-cyclonedx" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: installs cyclonedx-python via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install cyclonedx-python" "${MOCK_CALLS_FILE}"
}

# shfmt comes from Homebrew on Linux, not apt: apt ships 3.8.0 on noble and
# 3.12.0 on resolute against brew's 3.13.1, and a formatter's output is the
# gate, so skew would flag files nobody edited.
@test "_install_ubuntu_brew_packages: installs shfmt via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install shfmt" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_brew_packages: tri-state contract ────────────────────────
#
# 0 clean / 1 hard failure / 2 partial success with the failed packages named,
# mirroring install_git_hooks_all_repos. Before this the calls were unchecked and
# brew_install_formula swallowed its own status, which is how go-task/tap/go-task
# failed with exit 127 on every Linux run since it was added and still reported
# success. These tests are what make that unfixable-in-silence again.

@test "_install_ubuntu_brew_packages: returns 2 and names the package when one install fails" {
  # tests/mocks/brew has only MOCK_BREW_INSTALL_EXIT, which fails EVERY install --
  # that would prove the tri-state fires but not that it names the right package,
  # since all ~35 would appear. Overriding the helper isolates one failure so the
  # assertion stays specific.
  brew_install_formula() {
    [[ "$1" == "hadolint" ]] && return 1
    return 0
  }
  run _install_ubuntu_brew_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"hadolint"* ]]
  # Named, not just counted: a bare count would pass if the accumulator recorded
  # the wrong package.
  [[ "$output" == *"1 package(s) failed"* ]]
}

@test "_install_ubuntu_brew_packages: returns 0 when every package installs" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
}

@test "_install_ubuntu_brew_packages: installs go-task unqualified, never the tap cask" {
  # go-task/tap/go-task resolves to a macOS Cask that shells out to /usr/bin/xattr
  # and exits 127 on Linux. Core ships the formula; the tap-qualified name must not
  # come back.
  run _install_ubuntu_brew_packages
  grep -q "brew install go-task" "${MOCK_CALLS_FILE}"
  refute_grep "brew install go-task/tap/go-task" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: installs claude plugins at USER scope with a marketplace" {
  # Task 7 of docs/superpowers/plans/2026-09-19-claude-plugin-provisioning.md:
  # the hardcoded 4-plugin loop is gone -- provision_claude_plugins reconciles
  # from settings.json instead. load_mocks (setup(), above) already points
  # _OVERRIDE_CLAUDE_SETTINGS at a per-test copy of
  # tests/fixtures/claude-settings.json, which declares the
  # claude-plugins-official marketplace and enables superpowers@claude-plugins-official
  # and caveman@caveman (frontend-design@claude-plugins-official is false and
  # code-simplifier is absent entirely). The old form
  # (`claude plugin install <bare-name>`, no marketplace step at all)
  # registered at PROJECT scope against whatever cwd the run had, so `claude
  # plugins update` later reported "not installed at scope user" for 12
  # plugins and failed the update's claude section. Measured on claude
  # 2026-09-12.
  export HAS_DEVTOOLS=1
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  local _marketplace_line _install_line
  _marketplace_line="$(grep -n '^claude plugins marketplace add anthropics/claude-plugins-official$' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  _install_line="$(grep -n '^claude plugins install -s user superpowers@claude-plugins-official$' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  [ -n "${_marketplace_line}" ]
  [ -n "${_install_line}" ]
  [ "${_marketplace_line}" -lt "${_install_line}" ]
  refute_grep "code-simplifier" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: returns 2 and names claude-plugins when plugin provisioning fails" {
  # MOCK_CLAUDE_FAIL_ARGS matches on substring against the mock's "$*", so
  # "plugins install" fails only the `claude plugins install -s user <id>`
  # calls -- "plugins list --json" and "plugins marketplace add ..." do not
  # contain that substring and still succeed.
  export HAS_DEVTOOLS=1
  export MOCK_CLAUDE_FAIL_ARGS="plugins install"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 2 ]
  # Anchor on the summary line, not on a bare substring: setup_claude_plugins
  # prints "failed to install Claude plugin: superpowers@claude-plugins-official"
  # on this path, which contains "claude-plugins" and satisfies a loose match
  # even when the _failed entry is named something else entirely.
  [[ "$output" == *"package(s) failed:"*"claude-plugins"* ]]
}

# ── _install_ubuntu_brew_packages: RESOLUTE-gated coreutils ──────────────────
#
# 26.04 ships uutils coreutils. Its `sort -u` collates `py.test` and `pytest`
# as equal and drops one, so pyenv's `versions` command -- which pipes its
# name list through `sort` -- emits no `pytest` shim. apt cannot make GNU the
# provider -- build-essential pins coreutils-from-uutils by name -- so the
# formula is the route, gated to 26.04 since earlier releases already ship
# GNU.

@test "_install_ubuntu_brew_packages: RESOLUTE installs coreutils via brew" {
  export RESOLUTE=1
  unset NOBLE
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install coreutils" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: neither RESOLUTE nor NOBLE set skips coreutils" {
  # NOBLE is held unset here, matching the RESOLUTE test above and the
  # accumulator test below -- RESOLUTE is the only variable that differs
  # between this test and those. An implementation gating on
  # `[[ -z ${NOBLE} ]]` instead of `[[ -n ${RESOLUTE} ]]` would install here
  # too, since NOBLE is unset, which is exactly what this test exists to
  # catch. This state is also reachable for real: any Linux actor where
  # detect_env never ran, or a release detect_env.sh:19 does not recognise.
  unset NOBLE RESOLUTE
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  refute_grep "brew install coreutils" "${MOCK_CALLS_FILE}"
  # Positive control downstream of the gate: the unconditional `brew trust`
  # call at the end of this function runs after every branch, including the
  # coreutils gate. A control emitted upstream of the gate (e.g. the shfmt
  # install near the top of the package list) would prove only that the
  # function body started, not that execution reached the code under test --
  # an early return between the two would leave the absence assertion above
  # vacuously satisfied with an upstream control still green.
  # Named by construct, not by line number: a cross-file address drifts the
  # moment a line is inserted above it, which CLAUDE.md records happening to
  # tests/mocks/curl's own citation.
  grep -q "brew trust" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: NOBLE (24.04) skips coreutils" {
  # The real 24.04 state the test above gives up by holding NOBLE constant:
  # NOBLE=1, RESOLUTE unset. 24.04 already ships GNU coreutils, so the gate
  # must skip here too.
  export NOBLE=1
  unset RESOLUTE
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  refute_grep "brew install coreutils" "${MOCK_CALLS_FILE}"
  # Same downstream positive control as above.
  grep -q "brew trust" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: coreutils failure feeds the _failed accumulator" {
  # tests/mocks/brew's shared MOCK_BREW_INSTALL_EXIT fails EVERY install, which
  # would prove the tri-state fires but not that it names the right package --
  # see the identical comment on the hadolint test above.
  brew_install_formula() {
    [[ "$1" == "coreutils" ]] && return 1
    return 0
  }
  export RESOLUTE=1
  unset NOBLE
  run _install_ubuntu_brew_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"coreutils"* ]]
  [[ "$output" == *"1 package(s) failed"* ]]
}

@test "_install_ubuntu_rust: sources .cargo/env when file exists" {
  export HAS_RUST=1
  mkdir -p "${HOME}/.cargo"
  printf '# cargo env stub\n' > "${HOME}/.cargo/env"
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
}

@test "_install_ubuntu_rust: HAS_RUST set calls rustup update and component add when rustup available" {
  export HAS_RUST=1
  run _install_ubuntu_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
  grep -q "rustup update" "${MOCK_CALLS_FILE}"
  grep -q "rustup component add rust-analyzer" "${MOCK_CALLS_FILE}"
}

# ── _install_rustup_rs ────────────────────────────────────────────────────────
#
# sha256sum and mktemp are deliberately NOT mocked, so the digest check runs for
# real and the mismatch case below is genuine rather than stubbed. _RUSTUP_INIT_SHA256
# supplies the expected digest instead: mocking sha256sum would make every one of
# these vacuous, which is the absence-claim failure behavior.md names.

@test "_install_rustup_rs: skips entirely when rustup already present" {
  # setup() seeds ${HOME}/.cargo/bin/rustup, so this is the already-installed path.
  run _install_rustup_rs
  [ "$status" -eq 0 ]
  refute_grep "rustup-init" "${MOCK_CALLS_FILE}"
}

@test "_install_rustup_rs: installs when absent, and passes --no-modify-path" {
  rm -f "${HOME}/.cargo/bin/rustup"
  # tests/mocks/curl does not fetch: it writes MOCK_CURL_STDOUT to the -o target
  # (or touches it when unset). So the digest must be taken over exactly those
  # bytes, not over a separate fixture file the mock never copies. sha256sum stays
  # real, so the verification is genuinely exercised rather than stubbed.
  export MOCK_CURL_STDOUT='#!/usr/bin/env bash
exit 0'
  local _digest
  _digest="$(printf '%s' "${MOCK_CURL_STDOUT}" | sha256sum | awk '{print $1}')"
  export _RUSTUP_INIT_SHA256="${_digest}"
  local _spy="${BATS_TEST_TMPDIR}/rustup-init-spy"
  printf '#!/usr/bin/env bash\nprintf "rustup-init %%s\\n" "$*" >> "%s"\n' \
    "${MOCK_CALLS_FILE}" > "${_spy}"
  chmod +x "${_spy}"
  export _RUSTUP_INIT_BIN="${_spy}"
  run _install_rustup_rs
  [ "$status" -eq 0 ]
  # --no-modify-path is mandatory: ~/.zshrc and ~/.zprofile are symlinks into this
  # repo, so without it rustup-init writes into the tracked working tree.
  grep -q -- "rustup-init .*--no-modify-path" "${MOCK_CALLS_FILE}"
}

@test "_install_rustup_rs: REFUSES to execute on a sha256 mismatch" {
  rm -f "${HOME}/.cargo/bin/rustup"
  local _fixture="${BATS_TEST_TMPDIR}/rustup-init-fixture"
  printf '#!/usr/bin/env bash\nprintf "SHOULD NOT RUN\\n" >> "%s"\n' \
    "${MOCK_CALLS_FILE}" > "${_fixture}"
  chmod +x "${_fixture}"
  export _RUSTUP_INIT_URL="file://${_fixture}"
  export _RUSTUP_INIT_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
  export _RUSTUP_INIT_BIN="${_fixture}"
  run _install_rustup_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch"* ]]
  # The positive control: the binary must not have run at all.
  refute_grep "SHOULD NOT RUN" "${MOCK_CALLS_FILE}"
}

@test "_install_rustup_rs: unknown machine type is a hard error, not an unverified download" {
  rm -f "${HOME}/.cargo/bin/rustup"
  export MOCK_UNAME_M="s390x"
  run _install_rustup_rs
  [ "$status" -eq 1 ]
  [[ "$output" == *"s390x"* ]]
  refute_grep "curl" "${MOCK_CALLS_FILE}"
}

@test "_install_rustup_rs: arm64 resolves the aarch64 digest rather than failing closed" {
  # The bats suite runs on the Studio, where uname -m is arm64. A case statement
  # matching only aarch64 makes this suite unrunnable locally for a reason that has
  # nothing to do with the code under test.
  rm -f "${HOME}/.cargo/bin/rustup"
  export MOCK_UNAME_M="arm64"
  export _RUSTUP_INIT_URL="file:///nonexistent-so-download-fails"
  run _install_rustup_rs
  # Reaches the download and fails there -- NOT at the arch guard.
  [ "$status" -eq 1 ]
  refute_grep "no pinned rustup-init sha256" "${MOCK_CALLS_FILE}"
  [[ "$output" != *"no pinned rustup-init sha256"* ]]
}

# ── _install_ubuntu_nvidia ────────────────────────────────────────────────────
#
# Gated on hardware, not on a HAS_* flag: claude and workstation share the
# linux_workstation profile, so a capability flag would fire the driver install on a
# GPU-less box with that profile and on WSL2, where the driver lives Windows-side.
# lspci is unmocked and absent on macOS, so the default here is "no GPU".

@test "_install_ubuntu_nvidia: no NVIDIA card means no driver and no apt calls" {
  export _OVERRIDE_NVIDIA_GPU_PRESENT=1
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  refute_grep "nvidia-driver" "${MOCK_CALLS_FILE}"
  refute_grep "nvidia-container-toolkit" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_nvidia: installs the pinned driver and the container toolkit when a card is present" {
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  grep -q "nvidia-driver-${NVIDIA_DRIVER_VER}" "${MOCK_CALLS_FILE}"
  grep -q "nvidia-container-toolkit" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_nvidia: warns that a reboot is required rather than implying the driver is live" {
  # Installing does not bind: nouveau holds the card until reboot. Silence here would
  # read as "GPU ready" on a box still running nouveau.
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  [[ "$output" == *"reboot required"* ]]
}

@test "_install_ubuntu_nvidia: registers the nvidia runtime with docker" {
  # Installing the toolkit does NOT register it: measured on claude 2026-09-12,
  # nvidia-container-toolkit 1.20.0 was installed and `docker run --gpus all`
  # still failed with "AMD CDI spec not found" because daemon.json carried no
  # nvidia runtime. The arm's own comment claimed otherwise.
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  export _OVERRIDE_DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  printf '{}\n' > "${_OVERRIDE_DOCKER_DAEMON_JSON}"
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  grep -q "nvidia-ctk runtime configure --runtime=docker" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_nvidia: restarts docker when runtime configure changes daemon.json" {
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  export _OVERRIDE_DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  printf '{}\n' > "${_OVERRIDE_DOCKER_DAEMON_JSON}"
  export MOCK_NVIDIA_CTK_TARGET="${_OVERRIDE_DOCKER_DAEMON_JSON}"
  export MOCK_NVIDIA_CTK_WRITES='{"runtimes":{"nvidia":{"path":"nvidia-container-runtime"}}}'
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  grep -q "systemctl restart docker" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_nvidia: does not restart docker when the runtime is already registered" {
  # The before/after compare is why this branch exists: claude and workstation both
  # run GitHub runners, and restarting docker on every provision would kill a live
  # job for no reason. Without this case the compare could be deleted and only the
  # restart-on-change test above would still pass.
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  export _OVERRIDE_DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  printf '{"runtimes":{"nvidia":{"path":"nvidia-container-runtime"}}}\n' \
    > "${_OVERRIDE_DOCKER_DAEMON_JSON}"
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  grep -q "nvidia-ctk runtime configure" "${MOCK_CALLS_FILE}"
  refute_grep "systemctl restart docker" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_nvidia: a runtime configure failure aborts and never restarts docker" {
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  export _OVERRIDE_DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  printf '{}\n' > "${_OVERRIDE_DOCKER_DAEMON_JSON}"
  export MOCK_NVIDIA_CTK_EXIT=1
  run _install_ubuntu_nvidia
  [ "$status" -eq 1 ]
  refute_grep "systemctl restart docker" "${MOCK_CALLS_FILE}"
}

# ── _install_go_from_tarball ──────────────────────────────────────────────────

@test "_install_go_from_tarball: moves the extracted tree into the install root" {
  _make_go_tarball
  run _install_go_from_tarball
  [ "$status" -eq 0 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "new" ]
  grep -q "^mv .*/go ${_GO_INSTALL_ROOT}/go\$" "${MOCK_CALLS_FILE}"
}

@test "_install_go_from_tarball: wget failure returns non-zero and leaves the installed tree" {
  _seed_go
  export MOCK_WGET_EXIT=1
  run _install_go_from_tarball
  [ "$status" -ne 0 ]
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  refute_grep "^mv " "${MOCK_CALLS_FILE}"
}

@test "_install_go_from_tarball: tar failure returns non-zero and leaves the installed tree" {
  _seed_go
  # The recording tar mock, not the real one the setup seam selects.
  unset _DL_TAR_BIN
  export MOCK_TAR_EXIT=1
  run _install_go_from_tarball
  [ "$status" -ne 0 ]
  grep -q "^tar " "${MOCK_CALLS_FILE}"
  [ "$(< "${_GO_INSTALL_ROOT}/go/bin/v")" = "old" ]
  refute_grep "^mv " "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_docker ───────────────────────────────────────────────────

# The binary keyring needs a non-empty fetched body to count as a key.
_docker_fetch_ok() {
  export MOCK_CURL_STDOUT="docker-key-body"
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  printf '{"existing": "config"}\n' > "${_DOCKER_DAEMON_JSON}"
}

@test "_install_ubuntu_docker: HAS_DOCKER unset does nothing" {
  unset HAS_DOCKER
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  ! grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: HAS_DOCKER set installs docker-ce" {
  export HAS_DOCKER=1
  MOCK_CURL_STDOUT="docker-key-body"; export MOCK_CURL_STDOUT
  # Both seams, even though this test is about the apt call. Unseamed,
  # _daemon_json falls back to the REAL /etc/docker/daemon.json — and since
  # `tee` is a pass-through mock and tests/mocks/sudo execs a resolvable
  # target, this test reaches for a system path outside the repo (tdd.md E2).
  # On ubuntu-latest `dockerd` also resolves, so the validation step invokes a
  # real dockerd against that path and returns 1. Green on macOS, where dockerd
  # is absent and the warn branch runs; red on the runner — tdd.md pitfall G.
  # This failed exactly that way on the first CI round of the PR that added the
  # validation, while its sibling test two blocks down passed because that one
  # had the seam.
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  local _stub="${BATS_TEST_TMPDIR}/dockerd-accept-apt"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_stub}"
  chmod +x "${_stub}"
  export _DOCKER_VALIDATE_BIN="${_stub}"
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: writes daemon.json when absent" {
  export HAS_DOCKER=1
  MOCK_CURL_STDOUT="docker-key-body"; export MOCK_CURL_STDOUT
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  # Seam the validator even though this test is about the written CONTENT.
  # ubuntu-latest has docker installed, so an unseamed run would resolve the
  # real dockerd and — because tests/mocks/sudo execs a resolvable target —
  # invoke it for real on a CI runner. Hermetic here, and it keeps this test
  # green-or-red for its own reason rather than the runner's.
  local _stub="${BATS_TEST_TMPDIR}/dockerd-accept-content"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_stub}"
  chmod +x "${_stub}"
  export _DOCKER_VALIDATE_BIN="${_stub}"
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  [ -f "${_DOCKER_DAEMON_JSON}" ]

  # Assert the artifact PARSES. The substring assertion this replaces could not
  # fail for the defect it was covering: the writer emitted a literal
  # backslash-n after the closing brace, so the file both contained
  # "native.cgroupdriver=systemd" AND was invalid JSON, and this test stayed
  # green over it from the day it was written.
  #
  # Measured on the claude box 2026-09-12, the first bare-metal provision in a
  # long time and therefore the first execution of this branch: 48 bytes,
  # python JSONDecodeError "Extra data: line 1 column 47 (char 46)", and
  # `dockerd --validate` refusing it with "invalid character '\\' after
  # top-level value". Latent rather than visible, because dockerd had started
  # four seconds before the file was written and never re-read it -- so every
  # functional check passed and only a cold start would have exposed it.
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${_DOCKER_DAEMON_JSON}"

  # Keep the content check too: parsing proves it is JSON, not that it is the
  # RIGHT JSON. Both assertions are needed and neither implies the other.
  grep -q "native.cgroupdriver=systemd" "${_DOCKER_DAEMON_JSON}"

  # And pin the byte-level shape, since that is where the defect lived. A
  # trailing literal backslash-n reads as content to grep and to a size check,
  # but not to a parser -- so assert the file ends in a real newline.
  [ "$(tail -c 1 "${_DOCKER_DAEMON_JSON}" | od -An -c | tr -d ' ')" = "\\n" ]
}

@test "_install_ubuntu_docker: skips daemon.json when already exists" {
  export HAS_DOCKER=1
  MOCK_CURL_STDOUT="docker-key-body"; export MOCK_CURL_STDOUT
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  printf '{"existing": "config"}\n' > "${_DOCKER_DAEMON_JSON}"
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  run grep '"existing"' "${_DOCKER_DAEMON_JSON}"
  [ "$status" -eq 0 ]
  run grep "tee.*daemon.json" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

# Escaping was the defect; this is the class. The write had no post-condition at
# all, so a malformed file was indistinguishable from a good one until a daemon
# cold-started days later and refused it -- on claude, that surfaced as a second
# dockerd restart-looping and an unrelated warmup unit failing downstream, a
# hundred tasks from the actual cause.
#
# dockerd --validate is the authoritative check: it exits non-zero and prints the
# parse error, so a bad write fails the provision loudly instead of arming a cold
# start. _DOCKER_VALIDATE_BIN seams it because dockerd does not exist on the macs
# this suite runs on, which is the same absolute-binary problem _OVERRIDE_KEYCHAIN_BIN
# and _AWS_GPG_BIN already carry -- without the seam this branch is unreachable
# under test on every machine that runs the suite most often.
@test "_install_ubuntu_docker: fails when the written daemon.json does not validate" {
  export HAS_DOCKER=1
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  local _stub="${BATS_TEST_TMPDIR}/dockerd-reject"
  cat > "${_stub}" << 'STUB'
#!/usr/bin/env bash
printf 'unable to configure the Docker daemon with file: invalid JSON\n' >&2
exit 1
STUB
  chmod +x "${_stub}"
  export _DOCKER_VALIDATE_BIN="${_stub}"
  run _install_ubuntu_docker
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not validate"* ]]
}

# Positive control for the test above. A non-zero return is a composite outcome,
# so without this the negative case could pass for reasons unrelated to
# validation -- and this also proves production actually reads the seam rather
# than skipping the branch entirely.
@test "_install_ubuntu_docker: succeeds when the written daemon.json validates" {
  export HAS_DOCKER=1
  MOCK_CURL_STDOUT="docker-key-body"; export MOCK_CURL_STDOUT
  export _DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/daemon.json"
  local _stub="${BATS_TEST_TMPDIR}/dockerd-accept"
  cat > "${_stub}" << 'STUB'
#!/usr/bin/env bash
printf 'configuration OK\n'
exit 0
STUB
  chmod +x "${_stub}"
  export _DOCKER_VALIDATE_BIN="${_stub}"
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  [[ "$output" != *"did not validate"* ]]
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${_DOCKER_DAEMON_JSON}"
}

# ── docker: rc 3 core / rc 1 other, and the dispatcher's nvidia skip ─────────

@test "_install_ubuntu_docker: clean run returns 0 and installs the keyring and source list" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  [ "$(cat "${_DOCKER_KEYRING}")" = "docker-key-body" ]
  grep -q "signed-by=${_DOCKER_KEYRING}" "${_DOCKER_SOURCES_LIST}"
  grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
  grep -q "usermod -a -G docker bruce" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed docker-ce install returns 3 and later installs still run" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="docker-ce"
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"docker: docker-ce: install failed"* ]]
  grep -q "docker-compose-plugin" "${MOCK_CALLS_FILE}"
  grep -q "usermod" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed containerd.io install is core, rc 3" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="containerd.io"
  run _install_ubuntu_docker
  [ "$status" -eq 3 ]
}

@test "_install_ubuntu_docker: a daemon.json that does not validate returns 3" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  rm -f "${_DOCKER_DAEMON_JSON}"
  local _stub="${BATS_TEST_TMPDIR}/dockerd-reject-core"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${_stub}"
  chmod +x "${_stub}"
  export _DOCKER_VALIDATE_BIN="${_stub}"
  run _install_ubuntu_docker
  [ "$status" -eq 3 ]
}

@test "_install_ubuntu_docker: a failed plugin install returns 1 and the other plugin is still tried" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="docker-buildx-plugin"
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: docker-buildx-plugin: install failed"* ]]
  grep -q "apt install docker-compose-plugin" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed keyring fetch returns 1 and the core installs still run" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export MOCK_CURL_FAIL_URL="download.docker.com"
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: keyring: install failed"* ]]
  # Positive control: the fetch was attempted, so absence below is a failure, not a skip.
  grep -q "curl .*download.docker.com" "${MOCK_CALLS_FILE}"
  [ ! -e "${_DOCKER_KEYRING}" ]
  grep -q "apt install docker-ce " "${MOCK_CALLS_FILE}"
  grep -q "apt install containerd.io" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed keyring fetch with no existing keyring writes no source list" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export MOCK_CURL_FAIL_URL="download.docker.com"
  run --separate-stderr _install_ubuntu_docker
  # Core installs succeed here (the apt shim), so rc 1 is the keyring alone.
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: keyring: install failed"* ]]
  [[ "$stderr" == *"docker: source list: source write skipped (no keyring)"* ]]
  [ ! -e "${_DOCKER_KEYRING}" ]
  [ ! -e "${_DOCKER_SOURCES_LIST}" ]
  grep -q "apt install docker-ce " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed keyring fetch over an existing keyring still writes the source list" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  mkdir -p "$(dirname "${_DOCKER_KEYRING}")"
  printf 'previous-key' > "${_DOCKER_KEYRING}"
  export MOCK_CURL_FAIL_URL="download.docker.com"
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: keyring: install failed"* ]]
  [ "$(cat "${_DOCKER_KEYRING}")" = "previous-key" ]
  grep -q "signed-by=${_DOCKER_KEYRING}" "${_DOCKER_SOURCES_LIST}"
}

@test "_install_ubuntu_docker: a failed usermod returns 1" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_USERMOD_EXIT=1
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: usermod: group add failed"* ]]
  grep -q "usermod" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed source list write returns 1 and the installs still run" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  # tests/mocks/tee swallows real write errors; MOCK_TEE_EXIT is its failure knob.
  export MOCK_TEE_EXIT=1
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: source list: source list write failed"* ]]
  grep -q "^tee ${_DOCKER_SOURCES_LIST}" "${MOCK_CALLS_FILE}"
  grep -q "apt install docker-ce " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed docker-ce-cli install is core, rc 3" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="docker-ce-cli"
  run _install_ubuntu_docker
  [ "$status" -eq 3 ]
}

@test "_install_ubuntu_docker: a failed apt update is not a failure" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="update"
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  # Positive control: update really failed, and the installs still ran.
  grep -q "^apt update" "${MOCK_CALLS_FILE}"
  grep -q "apt install docker-ce " "${MOCK_CALLS_FILE}"
  grep -q "apt install containerd.io" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a failed daemon.json write with no validator is rc 1, not core" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  rm -f "${_DOCKER_DAEMON_JSON}"
  export MOCK_TEE_EXIT=1
  export _DOCKER_VALIDATE_BIN="/nonexistent/dockerd"
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker: daemon.json: write failed"* ]]
  # Positive control: both writes failed (list and daemon.json), only core would be 3.
  grep -q "^tee ${_DOCKER_DAEMON_JSON}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: a keyring failure plus a core failure returns 3 and names both" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  export MOCK_CURL_FAIL_URL="download.docker.com"
  export SHIM_APT_FAIL_PKGS="docker-ce"
  run --separate-stderr _install_ubuntu_docker
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"docker: keyring: install failed"* ]]
  [[ "$stderr" == *"docker: docker-ce: install failed"* ]]
}

@test "_install_ubuntu_docker: removes a legacy docker.gpg beside the keyring" {
  export HAS_DOCKER=1
  _docker_fetch_ok
  mkdir -p "$(dirname "${_DOCKER_KEYRING}")"
  printf 'legacy' > "$(dirname "${_DOCKER_KEYRING}")/docker.gpg"
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  [ ! -e "$(dirname "${_DOCKER_KEYRING}")/docker.gpg" ]
}

_stub_all_steps_but_docker() {
  local _s
  for _s in inotify workstation powershell go nvidia k8s_tools hashicorp cloud_tools brew_packages rust gui_tools misc; do
    eval "_install_ubuntu_${_s}() { printf 'ran ${_s}\\n' >> \"\${MOCK_CALLS_FILE}\"; }"
  done
  _install_ubuntu_base_packages() { return 0; }
}

@test "install_ubuntu_packages: docker core failure skips nvidia and names both" {
  _stub_all_steps_but_docker
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="docker-ce"
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"skipping nvidia because docker failed"* ]]
  [[ "$stderr" == *"ubuntu packages: failed: docker nvidia"* ]]
  refute_grep '^ran nvidia' "${MOCK_CALLS_FILE}"
  # Positive control: later steps ran, so nvidia's absence is the skip.
  grep -q '^ran k8s_tools' "${MOCK_CALLS_FILE}"
}

@test "install_ubuntu_packages: a docker plugin failure is named but nvidia still runs" {
  _stub_all_steps_but_docker
  export HAS_DOCKER=1
  _docker_fetch_ok
  export SHIM_APT_FAIL_PKGS="docker-buildx-plugin"
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"ubuntu packages: failed: docker"* ]]
  [[ "$stderr" != *"skipping nvidia"* ]]
  grep -q '^ran nvidia' "${MOCK_CALLS_FILE}"
}

# ── nvidia: keyring and list fetched safely ──────────────────────────────────

_nvidia_seams() {
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _OVERRIDE_NVIDIA_KEYRING="${BATS_TEST_TMPDIR}/nvidia-keyring.gpg"
  export _OVERRIDE_NVIDIA_LIST="${BATS_TEST_TMPDIR}/nvidia-container-toolkit.list"
  export _OVERRIDE_DOCKER_DAEMON_JSON="${BATS_TEST_TMPDIR}/nvidia-daemon.json"
}

@test "_install_ubuntu_nvidia: a failed list fetch returns 1 and leaves the list untouched" {
  _nvidia_seams
  export MOCK_CURL_FAIL_URL="stable/deb/nvidia-container-toolkit.list"
  run --separate-stderr _install_ubuntu_nvidia
  [ "$status" -eq 1 ]
  # Positive control: the list fetch was attempted.
  grep -q "curl .*nvidia-container-toolkit.list" "${MOCK_CALLS_FILE}"
  [ ! -e "${_OVERRIDE_NVIDIA_LIST}" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_nvidia: a successful list fetch writes a signed-by list and leaves no tmp dir" {
  _nvidia_seams
  export MOCK_CURL_STDOUT="deb https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /"
  run _install_ubuntu_nvidia
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_OVERRIDE_NVIDIA_KEYRING}" "${_OVERRIDE_NVIDIA_LIST}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_nvidia: a failed keyring fetch returns 1 and creates no keyring or list" {
  _nvidia_seams
  export MOCK_CURL_FAIL_URL="libnvidia-container/gpgkey"
  run _install_ubuntu_nvidia
  [ "$status" -eq 1 ]
  [[ "$output" == *"nvidia: keyring: install failed"* ]]
  grep -q "curl .*gpgkey" "${MOCK_CALLS_FILE}"
  [ ! -e "${_OVERRIDE_NVIDIA_KEYRING}" ]
  [ ! -e "${_OVERRIDE_NVIDIA_LIST}" ]
}

# ── _install_ubuntu_k8s_tools ────────────────────────────────────────────────

# kind and telepresence go through _install_fetched_binary (a plain file as the
# download); telepresence resolves its "latest" link first, so curl's stdout must
# name a different URL. The same curl stdout is the kubectl key body.
_k8s_env() {
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.example/dl/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://tp.example/latest/telepresence"
  unset HAS_SNAP
  export MOCK_CURL_STDOUT="https://resolved.example/telepresence-2.20"
  printf 'binary-body' > "${BATS_TEST_TMPDIR}/blob"
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/blob"
}

@test "_install_ubuntu_k8s_tools: clean run returns 0 and installs kind, telepresence and the kubectl source" {
  _k8s_env
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  [ -x "${_DL_BIN_DIR}/kind" ]
  [ -x "${_DL_BIN_DIR}/telepresence" ]
  [ -f "${_DL_STAMP_DIR}/kind" ]
  [ -s "${_APT_KEYRINGS_DIR}/kubernetes-apt-keyring.gpg" ]
  grep -q "signed-by=${_APT_KEYRINGS_DIR}/kubernetes-apt-keyring.gpg" "${_APT_SOURCES_DIR}/kubernetes.list"
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: a stamped, installed kind is not fetched again" {
  _k8s_env
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${KIND_URL}" > "${_DL_STAMP_DIR}/kind"
  printf 'old' > "${_DL_BIN_DIR}/kind"
  chmod 0755 "${_DL_BIN_DIR}/kind"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"kind: up to date"* ]]
  refute_grep "wget .*kind.example" "${MOCK_CALLS_FILE}"
  grep -q "wget .*resolved.example" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: a failed kind download returns 1, names kind and leaves telepresence installed" {
  _k8s_env
  export MOCK_WGET_FAIL_URL="kind.example"
  printf 'old' > "${_DL_BIN_DIR}/kind"
  chmod 0755 "${_DL_BIN_DIR}/kind"
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: kind:"* ]]
  # Positive control: the kind fetch was really attempted.
  grep -q "wget .*kind.example" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_DL_BIN_DIR}/kind")" = "old" ]
  [ ! -e "${_DL_STAMP_DIR}/kind" ]
  [ -z "$(find "${_DL_TMP_ROOT}" -mindepth 1)" ]
  # Sibling still ran.
  [ -x "${_DL_BIN_DIR}/telepresence" ]
  [ -f "${_DL_STAMP_DIR}/telepresence" ]
}

@test "_install_ubuntu_k8s_tools: a failed telepresence resolve returns 1, names telepresence and leaves kind installed" {
  _k8s_env
  export MOCK_CURL_FAIL_URL="tp.example"
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: telepresence:"* ]]
  # Positive control: the resolve was really attempted.
  grep -q "curl .*tp.example" "${MOCK_CALLS_FILE}"
  [ ! -e "${_DL_BIN_DIR}/telepresence" ]
  [ ! -e "${_DL_STAMP_DIR}/telepresence" ]
  [ -x "${_DL_BIN_DIR}/kind" ]
  [ -f "${_DL_STAMP_DIR}/kind" ]
}

@test "_install_ubuntu_k8s_tools: no HAS_K8S skips kind and telepresence" {
  _k8s_env
  unset HAS_K8S
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  refute_grep "wget" "${MOCK_CALLS_FILE}"
  [ ! -e "${_DL_BIN_DIR}/kind" ]
}

@test "_install_ubuntu_k8s_tools: removes stale helm-stable-debian.list before apt update" {
  # baltocdn sources.list.d file written by pre-PR#155 runs must be purged so
  # apt-get update does not hit the NOSPLIT/unsigned repo on subsequent runs.
  _k8s_env
  unset HAS_K8S
  printf 'stale\n' > "${_APT_SOURCES_DIR}/helm-stable-debian.list"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  [ ! -e "${_APT_SOURCES_DIR}/helm-stable-debian.list" ]
}

@test "_install_ubuntu_k8s_tools: HAS_SNAP installs helm via snap" {
  _k8s_env
  export HAS_SNAP=1
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  grep -q "snap install helm" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: a failed helm snap install returns 1 and kubectl is still installed" {
  _k8s_env
  export HAS_SNAP=1
  export MOCK_SNAP_EXIT=1
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: helm:"* ]]
  grep -q "snap install helm" "${MOCK_CALLS_FILE}"
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: a failed kubectl keyring fetch returns 1 and the kubectl install is still attempted" {
  _k8s_env
  export MOCK_CURL_FAIL_URL="pkgs.k8s.io"
  printf 'old' > "${_APT_KEYRINGS_DIR}/kubernetes-apt-keyring.gpg"
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: kubectl: keyring"* ]]
  grep -q "curl .*pkgs.k8s.io" "${MOCK_CALLS_FILE}"
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_APT_KEYRINGS_DIR}/kubernetes-apt-keyring.gpg")" = "old" ]
  [ -z "$(find "${_DL_TMP_ROOT}" -mindepth 1)" ]
  # An existing non-empty keyring still backs a source list.
  [ -f "${_APT_SOURCES_DIR}/kubernetes.list" ]
}

@test "_install_ubuntu_k8s_tools: a failed keyring fetch with no keyring writes no source list" {
  _k8s_env
  export MOCK_CURL_FAIL_URL="pkgs.k8s.io"
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: kubectl: source write skipped (no keyring)"* ]]
  [ ! -e "${_APT_SOURCES_DIR}/kubernetes.list" ]
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: a failed kubectl source list write returns 1" {
  _k8s_env
  export MOCK_TEE_EXIT=1
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: kubectl: source list"* ]]
  # Positive control: the write was really attempted.
  grep -q "tee .*kubernetes.list" "${MOCK_CALLS_FILE}"
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: a failed kubectl apt install returns 1" {
  _k8s_env
  export MOCK_APT_FAIL_SUBCMD=install
  run --separate-stderr _install_ubuntu_k8s_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"k8s_tools: kubectl: install failed"* ]]
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: does not call get-helm-3 curl installer" {
  # helm curl installer removed; brew handles the no-snap case via
  # _install_ubuntu_brew_packages.
  _k8s_env
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  run grep "get-helm-3" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_k8s_tools: does not call install_kustomize curl installer" {
  # kustomize curl installer removed; brew handles it via
  # _install_ubuntu_brew_packages.
  _k8s_env
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  run grep "install_kustomize.sh" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_brew_packages: installs helm via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install helm" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: installs kustomize via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install kustomize" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_hashicorp ────────────────────────────────────────────────

# One real zip holding all five members serves every download.
_hc_env() {
  export CONSUL_VER="1.17.0"
  export VAULT_VER="1.15.0"
  export NOMAD_VER="1.7.0"
  export PACKER_VER="1.10.0"
  export VAGRANT_VER="2.4.0"
  export HASHICORP_URL="https://releases.hashicorp.com"
  local _src="${BATS_TEST_TMPDIR}/hc-src" _t
  mkdir -p "${_src}"
  for _t in consul vault nomad packer vagrant; do
    printf '%s-body' "${_t}" > "${_src}/${_t}"
  done
  (cd "${_src}" && "${_ZIP_BIN}" -q "${BATS_TEST_TMPDIR}/hc.zip" consul vault nomad packer vagrant)
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/hc.zip"
}

@test "_install_ubuntu_hashicorp: clean run returns 0 and installs all five tools" {
  _hc_env
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  local _t
  for _t in consul vault nomad packer vagrant; do
    [ -x "${_DL_BIN_DIR}/${_t}" ]
    [ -f "${_DL_STAMP_DIR}/${_t}" ]
  done
}

@test "_install_ubuntu_hashicorp: calls wget for consul when not stamped" {
  _hc_env
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "wget.*consul" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: a stamped, installed consul is not fetched again" {
  _hc_env
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${HASHICORP_URL}/consul/1.17.0/consul_1.17.0_linux_${_LINUX_ARCH}.zip" > "${_DL_STAMP_DIR}/consul"
  printf 'old' > "${_DL_BIN_DIR}/consul"
  chmod 0755 "${_DL_BIN_DIR}/consul"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  [[ "$output" == *"consul: up to date"* ]]
  refute_grep "wget .*consul_1.17.0" "${MOCK_CALLS_FILE}"
  grep -q "wget .*vault" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: a failed consul download returns 1, names consul and still installs vault" {
  _hc_env
  export MOCK_WGET_FAIL_URL="consul/"
  printf 'old' > "${_DL_BIN_DIR}/consul"
  chmod 0755 "${_DL_BIN_DIR}/consul"
  run --separate-stderr _install_ubuntu_hashicorp
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"hashicorp: consul:"* ]]
  grep -q "wget .*consul/" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_DL_BIN_DIR}/consul")" = "old" ]
  [ -z "$(find "${_DL_TMP_ROOT}" -mindepth 1)" ]
  [ ! -e "${_DL_STAMP_DIR}/consul" ]
  [ -x "${_DL_BIN_DIR}/vault" ]
  [ -f "${_DL_STAMP_DIR}/vault" ]
}

@test "_install_ubuntu_hashicorp: uses _LINUX_ARCH in consul URL (arm64)" {
  _hc_env
  export CONSUL_VER="2.0.0"
  export VAULT_VER="2.0.2"
  export NOMAD_VER="2.0.3"
  export PACKER_VER="1.15.4"
  export VAGRANT_VER="2.4.9"
  export _LINUX_ARCH="arm64"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "consul.*arm64" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: vagrant always uses amd64 regardless of _LINUX_ARCH" {
  _hc_env
  export CONSUL_VER="2.0.0"
  export VAULT_VER="2.0.2"
  export NOMAD_VER="2.0.3"
  export PACKER_VER="1.15.4"
  export VAGRANT_VER="2.4.9"
  export _LINUX_ARCH="arm64"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "vagrant.*amd64" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_cloud_tools ──────────────────────────────────────────────

# cf-terraforming arrives as a tarball holding the binary; _install_fetched_binary
# fetches it through the wget mock, which copies MOCK_WGET_FILE to the -O target.
_cf_tarball() {
  mkdir -p "${BATS_TEST_TMPDIR}/cfsrc"
  printf 'cf-body' > "${BATS_TEST_TMPDIR}/cfsrc/cf-terraforming"
  chmod 0755 "${BATS_TEST_TMPDIR}/cfsrc/cf-terraforming"
  "${_DL_TAR_BIN}" -czf "${BATS_TEST_TMPDIR}/cf.tgz" -C "${BATS_TEST_TMPDIR}/cfsrc" cf-terraforming
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/cf.tgz"
}

# HAS_DEVTOOLS cloud_tools run with a good cf-terraforming tarball and a URL
# naming its version; everything else is seamed by setup().
_cloud_env() {
  export HAS_DEVTOOLS=1
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://cf.example/dl/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  unset RESOLUTE
  _cf_tarball
}

@test "_install_ubuntu_cloud_tools: installs google-cloud-cli packages, not retired google-cloud-sdk names" {
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  _cf_tarball
  unset HAS_DEVTOOLS
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install google-cloud-cli -y" "${MOCK_CALLS_FILE}"
  grep -q "apt install google-cloud-cli-app-engine-go" "${MOCK_CALLS_FILE}"
  refute_grep "apt install google-cloud-sdk" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: HAS_DEVTOOLS installs teleport" {
  export HAS_DEVTOOLS=1
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  _cf_tarball
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: no HAS_DEVTOOLS skips teleport" {
  unset HAS_DEVTOOLS
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  _cf_tarball
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  ! grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: cf-terraforming filename uses _LINUX_ARCH" {
  export CF_TERRAFORMING_VER="0.27.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.27.0/cf-terraforming_0.27.0_linux_arm64.tar.gz"
  _cf_tarball
  export _LINUX_ARCH="arm64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "cf-terraforming.*arm64" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: on RESOLUTE uses noble for cloudflare repo" {
  export RESOLUTE=1
  export HAS_DEVTOOLS=1
  export CF_TERRAFORMING_VER="0.27.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.27.0/cf-terraforming_0.27.0_linux_amd64.tar.gz"
  _cf_tarball
  export _CF_SOURCES_LIST="${BATS_TEST_TMPDIR}/cloudflare.list"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "noble" "${_CF_SOURCES_LIST}"
  run grep "resolute" "${_CF_SOURCES_LIST}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_cloud_tools: clean run returns 0, writes the source lists and installs cf-terraforming" {
  _cloud_env
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_APT_KEYRINGS_DIR}/teleport-pubkey.gpg" "${_APT_SOURCES_DIR}/teleport.list"
  grep -q "signed-by=${_APT_KEYRINGS_DIR}/cloudflare-warp-archive-keyring.gpg" "${_APT_SOURCES_DIR}/cloudflare-client.list"
  grep -q "signed-by=${_APT_KEYRINGS_DIR}/cloud.google.gpg" "${_APT_SOURCES_DIR}/google-cloud-sdk.list"
  [ "$(cat "${_DL_BIN_DIR}/cf-terraforming")" = "cf-body" ]
  [ "$(cat "${_DL_STAMP_DIR}/cf-terraforming")" = "${CF_TERRAFORMING_URL}" ]
  [ -z "$(find "${_DL_TMP_ROOT}" -mindepth 1)" ]
}

@test "_install_ubuntu_cloud_tools: a failed teleport keyring fetch with no keyring returns 1, writes no list, and the siblings still run" {
  _cloud_env
  export MOCK_CURL_FAIL_URL="deb.releases.teleport.dev"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: teleport: keyring"* ]]
  [[ "$stderr" == *"cloud_tools: teleport: source write skipped (no keyring)"* ]]
  [ ! -e "${_APT_SOURCES_DIR}/teleport.list" ]
  # Positive controls: the fetch was attempted and the siblings completed.
  grep -q "curl .*deb.releases.teleport.dev" "${MOCK_CALLS_FILE}"
  [ -s "${_APT_SOURCES_DIR}/cloudflare-client.list" ]
  [ -s "${_APT_SOURCES_DIR}/google-cloud-sdk.list" ]
  [ -x "${_DL_BIN_DIR}/cf-terraforming" ]
}

@test "_install_ubuntu_cloud_tools: a failed cloudflared apt install returns 1 and gcloud is still attempted" {
  _cloud_env
  export SHIM_APT_FAIL_PKGS="cloudflare-warp"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: cloudflared: install failed"* ]]
  grep -q "apt-get install.*cloudflare-warp" "${MOCK_CALLS_FILE}"
  grep -q "apt install google-cloud-cli -y" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: a failed gcloud package install returns 1 and the second package is still attempted" {
  _cloud_env
  export SHIM_APT_FAIL_PKGS="google-cloud-cli"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: gcloud: google-cloud-cli install failed"* ]]
  grep -q "apt install google-cloud-cli-app-engine-go" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: a failed cf-terraforming download returns 1 and leaves the destination, stamp and workdir alone" {
  _cloud_env
  printf 'old' > "${_DL_BIN_DIR}/cf-terraforming"
  chmod 0755 "${_DL_BIN_DIR}/cf-terraforming"
  export MOCK_WGET_FAIL_URL="cf-terraforming"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: cf-terraforming: install failed"* ]]
  grep -q "wget .*cf-terraforming" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_DL_BIN_DIR}/cf-terraforming")" = "old" ]
  [ ! -e "${_DL_STAMP_DIR}/cf-terraforming" ]
  [ -z "$(find "${_DL_TMP_ROOT}" -mindepth 1)" ]
  # The earlier tools were not held up by it.
  [ -s "${_APT_SOURCES_DIR}/teleport.list" ]
}

@test "_install_ubuntu_cloud_tools: a failed teleport apt install returns 1" {
  _cloud_env
  export SHIM_APT_FAIL_PKGS="teleport"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: teleport: install failed"* ]]
  grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: a failed google-cloud-cli-app-engine-go install returns 1" {
  _cloud_env
  export SHIM_APT_FAIL_PKGS="google-cloud-cli-app-engine-go"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: gcloud: google-cloud-cli-app-engine-go install failed"* ]]
  # Positive control: the first package was not the one that failed.
  [[ "$stderr" != *"gcloud: google-cloud-cli install failed"* ]]
}

_cloud_tee_failure() {
  _cloud_env
  export SHIM_TEE_FAIL_ARGS="$1"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: $2: source list write failed"* ]]
  # Positive control: the write was really attempted, and only that one failed.
  grep -q "tee .*$1" "${MOCK_CALLS_FILE}"
  [ "$(grep -c 'source list write failed' <<< "${stderr}")" -eq 1 ]
}

@test "_install_ubuntu_cloud_tools: a failed teleport source list write returns 1" {
  _cloud_tee_failure "teleport.list" teleport
}

@test "_install_ubuntu_cloud_tools: a failed cloudflared source list write returns 1" {
  _cloud_tee_failure "cloudflare-client.list" cloudflared
}

@test "_install_ubuntu_cloud_tools: a failed gcloud source list write returns 1" {
  _cloud_tee_failure "google-cloud-sdk.list" gcloud
}

_cloud_keyring_failure() {
  _cloud_env
  local _ring="${_APT_KEYRINGS_DIR}/$1"
  printf 'old' > "${_ring}"
  export MOCK_CURL_FAIL_URL="$2"
  run --separate-stderr _install_ubuntu_cloud_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cloud_tools: $3: keyring install failed"* ]]
  grep -q "curl .*$2" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_ring}")" = "old" ]
  # The prior keyring still backs the source list, so only the keyring failed.
  [[ "$stderr" != *"source write skipped"* ]]
}

@test "_install_ubuntu_cloud_tools: a failed teleport keyring fetch with a prior keyring returns 1 and keeps it" {
  _cloud_keyring_failure teleport-pubkey.gpg deb.releases.teleport.dev teleport
}

@test "_install_ubuntu_cloud_tools: a failed cloudflared keyring fetch with a prior keyring returns 1 and keeps it" {
  _cloud_keyring_failure cloudflare-warp-archive-keyring.gpg pkg.cloudflareclient.com cloudflared
}

@test "_install_ubuntu_cloud_tools: a failed gcloud keyring fetch with a prior keyring returns 1 and keeps it" {
  _cloud_keyring_failure cloud.google.gpg packages.cloud.google.com gcloud
}

# ── azure-cli via linuxbrew ──────────────────────────────────────────────────

_az_cloud_env() {
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  _cf_tarball
  unset HAS_DEVTOOLS
}

@test "_install_ubuntu_brew_packages: installs azure-cli via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install azure-cli" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: removes the apt azure-cli once brew az runs" {
  export MOCK_DPKG_S_STATUS="install ok installed"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew-az version" "${MOCK_CALLS_FILE}"
  grep -q "apt-get remove -y azure-cli" "${MOCK_CALLS_FILE}"
  grep -q "sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y azure-cli" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: keeps the apt azure-cli when brew az is broken" {
  export MOCK_DPKG_S_STATUS="install ok installed"
  export MOCK_BREW_AZ_EXIT=1
  run _install_ubuntu_brew_packages
  grep -q "brew-az version" "${MOCK_CALLS_FILE}"
  refute_grep "apt-get remove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: does not remove azure-cli when dpkg says config-files only" {
  export MOCK_DPKG_S_STATUS="deinstall ok config-files"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew-az version" "${MOCK_CALLS_FILE}"
  grep -q "dpkg -s azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "apt-get remove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: does not remove azure-cli when dpkg reports nothing" {
  unset MOCK_DPKG_S_STATUS
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew-az version" "${MOCK_CALLS_FILE}"
  grep -q "dpkg -s azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "apt-get remove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: does not remove azure-cli when dpkg status is deinstall ok installed" {
  export MOCK_DPKG_S_STATUS="deinstall ok installed"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew-az version" "${MOCK_CALLS_FILE}"
  grep -q "dpkg -s azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "apt-get remove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: probes <brew prefix>/bin/az when no override is set" {
  unset _BREW_AZ_BIN
  local _prefix="${BATS_TEST_TMPDIR}/brew-prefix"
  mkdir -p "${_prefix}/bin"
  printf '#!/usr/bin/env bash\nprintf "prefix-az %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\n' > "${_prefix}/bin/az"
  chmod +x "${_prefix}/bin/az"
  export MOCK_BREW_PREFIX="${_prefix}"
  export MOCK_DPKG_S_STATUS="install ok installed"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "prefix-az version" "${MOCK_CALLS_FILE}"
  grep -q "apt-get remove -y azure-cli" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: empty brew prefix skips the migration without probing any az" {
  unset _BREW_AZ_BIN
  unset MOCK_BREW_PREFIX
  export MOCK_DPKG_S_STATUS="install ok installed"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "az version" "${MOCK_CALLS_FILE}"
  refute_grep "dpkg -s azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "apt-get remove" "${MOCK_CALLS_FILE}"
}

@test "_is_system_az_path: true for exactly /bin/az and /usr/bin/az, false otherwise" {
  # Pure string predicate: no az is ever executed here.
  run _is_system_az_path /bin/az
  [ "$status" -eq 0 ]
  run _is_system_az_path /usr/bin/az
  [ "$status" -eq 0 ]
  run ! _is_system_az_path /home/linuxbrew/.linuxbrew/bin/az
  run ! _is_system_az_path ""
  run ! _is_system_az_path /usr/bin/az2
}

@test "_install_ubuntu_brew_packages: never probes a path _is_system_az_path flags" {
  # A stub stands in for the system az: a literal /usr/bin/az here would run the
  # operator's real az the day this guard regresses (tdd.md E2). The literal
  # paths are covered by the _is_system_az_path unit test, which runs nothing.
  local _sys="${BATS_TEST_TMPDIR}/system-az"
  printf '#!/usr/bin/env bash\nprintf "system-az %%s\\n" "$*" >> "%s"\n' "${MOCK_CALLS_FILE}" > "${_sys}"
  chmod +x "${_sys}"
  export _BREW_AZ_BIN="${_sys}"
  _is_system_az_path() { [[ $1 == "${_BREW_AZ_BIN}" ]]; }
  export MOCK_DPKG_S_STATUS="install ok installed"
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "^system-az " "${MOCK_CALLS_FILE}"
  refute_grep "dpkg -s azure-cli" "${MOCK_CALLS_FILE}"
  refute_grep "apt-get remove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: names azure-cli-apt-remove and returns 2 when removal fails" {
  export MOCK_DPKG_S_STATUS="install ok installed"
  export MOCK_APT_EXIT=1
  run _install_ubuntu_brew_packages
  [ "$status" -eq 2 ]
  [[ "$output" == *"azure-cli-apt-remove"* ]]
}

@test "_install_ubuntu_cloud_tools: has no azure apt path but still installs gcloud" {
  _az_cloud_env
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install google-cloud-cli -y" "${MOCK_CALLS_FILE}"
  refute_grep "add-apt-repository" "${MOCK_CALLS_FILE}"
  refute_grep "apt install azure-cli" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: removes every legacy azure-cli key and source" {
  _az_cloud_env
  local _files=(
    "${_APT_TRUSTED_DIR}/microsoft.asc.gpg"
    "${_APT_SOURCES_DIR}/archive_uri-http_packages_microsoft_com_repos_azure-cli_-resolute.list"
    "${_APT_SOURCES_DIR}/packages.microsoft.com_repos_azure-cli.list"
    "${_APT_SOURCES_DIR}/azure-cli.list"
  )
  local _f
  for _f in "${_files[@]}"; do
    printf 'x\n' > "${_f}"
    [ -e "${_f}" ]
  done
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  for _f in "${_files[@]}"; do
    [ ! -e "${_f}" ]
  done
}

@test "_install_ubuntu_cloud_tools: warns when the legacy azure-cli cleanup cannot remove a file" {
  # tests/mocks/rm swallows a real EACCES (/bin/rm ... || true), so a 0555 directory
  # cannot fail the cleanup under the mock; MOCK_RM_EXIT is the mock's failure seam.
  _az_cloud_env
  printf 'x\n' > "${_APT_SOURCES_DIR}/azure-cli.list"
  MOCK_RM_EXIT=1 run --separate-stderr _install_ubuntu_cloud_tools
  [[ "$stderr" == *"could not remove legacy azure-cli apt key/sources"* ]]
}

# ── _install_ubuntu_brew_packages ────────────────────────────────────────────

@test "_install_ubuntu_brew_packages: calls brew_install_formula for core packages" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install bat" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: HAS_DEVTOOLS installs ggshield" {
  export HAS_DEVTOOLS=1
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew install ggshield" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: no HAS_DEVTOOLS skips ggshield" {
  unset HAS_DEVTOOLS
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  ! grep -q "brew install ggshield" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_brew_packages: calls install_homebrew when brew is absent" {
  install_homebrew() { printf "install_homebrew_called\n"; }
  local _saved_path="${PATH}"
  export PATH="/usr/bin:/bin"
  run _install_ubuntu_brew_packages
  export PATH="${_saved_path}"
  [[ "$output" == *"install_homebrew_called"* ]]
}

@test "_install_ubuntu_brew_packages: calls brew trust for third-party taps including getagentseal and bun" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -q "brew trust.*getagentseal/codeburn" "${MOCK_CALLS_FILE}"
  grep -q "brew trust.*oven-sh/bun" "${MOCK_CALLS_FILE}"
  refute_grep "brew trust.* go-task/tap" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_gui_tools ────────────────────────────────────────────────

@test "_install_ubuntu_gui_tools: HAS_DEVTOOLS installs virtualbox" {
  export HAS_DEVTOOLS=1
  export VIRTUALBOX_VER="virtualbox-7.0"
  unset HAS_SNAP
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "apt install ${VIRTUALBOX_VER}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: no HAS_DEVTOOLS skips virtualbox" {
  unset HAS_DEVTOOLS HAS_SNAP
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  ! grep -q "apt install virtualbox" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: HAS_SNAP installs albert" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS
  _albert_good_key
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "apt install albert" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failing albert install is named and its rc propagates" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS
  _install_ubuntu_albert() { return 2; }
  run _install_ubuntu_gui_tools
  [ "$status" -eq 2 ]
  [[ "$output" == *"gui_tools: albert: install failed"* ]]
}

@test "_install_ubuntu_gui_tools: a clean albert install logs no albert failure" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS
  _install_ubuntu_albert() { return 0; }
  run _install_ubuntu_gui_tools
  [[ "$output" != *"gui_tools: albert: install failed"* ]]
}

# Fixture for a package-owned, enabled Edge source (deb822).
_edge_live_sources() {
  printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/edge-stable\nSuites: stable\n' \
    > "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
}

@test "_install_ubuntu_edge_source: live .sources removes stale .list and bootstrap keyring" {
  _edge_live_sources
  local _before
  _before="$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  printf 'stale-key' > "${_EDGE_BOOTSTRAP_KEYRING}"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
  [ "$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")" = "${_before}" ]
}

@test "_install_ubuntu_edge_source: live .sources with Enabled: yes counts as live" {
  _edge_live_sources
  printf 'Enabled: yes\n' >> "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
}

@test "_install_ubuntu_edge_source: .sources with Enabled: no still bootstraps a .list" {
  _edge_live_sources
  printf 'Enabled: no\n' >> "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  local _before
  _before="$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "packages.microsoft.com/repos/edge stable main" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ "$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")" = "${_before}" ]
}

@test "_install_ubuntu_edge_source: zero-byte .sources still bootstraps a .list" {
  : > "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "packages.microsoft.com/repos/edge stable main" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
}

@test "_install_ubuntu_edge_source: bootstrap .list is key-scoped to a keyring equal to the vendored key" {
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_EDGE_BOOTSTRAP_KEYRING}" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ -s "${_EDGE_BOOTSTRAP_KEYRING}" ]
  "${_MS_GPG_BIN}" --dearmor < "${REPO_ROOT}/keys/microsoft.asc" > "${BATS_TEST_TMPDIR}/expected.gpg"
  cmp "${BATS_TEST_TMPDIR}/expected.gpg" "${_EDGE_BOOTSTRAP_KEYRING}"
}

@test "_install_ubuntu_edge_source: fails closed when the key cannot be read" {
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/no-such-key.asc" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING} (gpg missing or failed, no usable key read from"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

# A working keyring + list from a real first run, so each failure below has
# verified state to keep or remove; the before-checksums make "kept" mean
# byte-identical, not merely present.
_edge_working_source() {
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [ -s "${_EDGE_BOOTSTRAP_KEYRING}" ]
  _ring_sum="$(cksum < "${_EDGE_BOOTSTRAP_KEYRING}")"
  _list_sum="$(cksum < "${_EDGE_SOURCES_DIR}/microsoft-edge.list")"
}

@test "_install_ubuntu_edge_source: keeps a working keyring and list when the key cannot be read (rc 2)" {
  _edge_working_source
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/no-such-key.asc" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"keeping last verified source"* ]]
  [ "$(cksum < "${_EDGE_BOOTSTRAP_KEYRING}")" = "${_ring_sum}" ]
  [ "$(cksum < "${_EDGE_SOURCES_DIR}/microsoft-edge.list")" = "${_list_sum}" ]
}

@test "_install_ubuntu_edge_source: keeps a working keyring and list on a local build failure (rc 3)" {
  _edge_working_source
  _APT_KEY_TMP_ROOT="${BATS_TEST_TMPDIR}/no-such-tmp-root" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"keeping last verified source"* ]]
  [ "$(cksum < "${_EDGE_BOOTSTRAP_KEYRING}")" = "${_ring_sum}" ]
  [ "$(cksum < "${_EDGE_SOURCES_DIR}/microsoft-edge.list")" = "${_list_sum}" ]
}

@test "_install_ubuntu_edge_source: removes keyring and list when the key is not the pinned one (rc 1)" {
  _edge_working_source
  MS_GPG_FPR="0000000000000000000000000000000000000000" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not the pinned key"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_edge_source: does not keep a zero-byte keyring when the key cannot be read (rc 2)" {
  : > "${_EDGE_BOOTSTRAP_KEYRING}"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/no-such-key.asc" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"no verified keyring present"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_edge_source: keep note says no source is present when the keyring has no .list (rc 2)" {
  _edge_working_source
  rm -f "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/no-such-key.asc" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"no verified edge source is present"* ]]
  [[ "$output" != *"keeping last verified source"* ]]
  [ "$(cksum < "${_EDGE_BOOTSTRAP_KEYRING}")" = "${_ring_sum}" ]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
}

@test "_install_ubuntu_edge_source: .sources absent writes bootstrap .list and no .sources" {
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "packages.microsoft.com/repos/edge stable main" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.sources" ]
}

@test "_install_ubuntu_edge_source: bootstrap .list is idempotent across two runs" {
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  cp "${_EDGE_BOOTSTRAP_KEYRING}" "${BATS_TEST_TMPDIR}/keyring-after-first"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [ "$(wc -l < "${_EDGE_SOURCES_DIR}/microsoft-edge.list")" -eq 1 ]
  cmp "${BATS_TEST_TMPDIR}/keyring-after-first" "${_EDGE_BOOTSTRAP_KEYRING}"
}

@test "_install_ubuntu_edge_source: .sources with Enabled: false is inert and bootstraps a .list" {
  _edge_live_sources
  printf 'Enabled: false\n' >> "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  local _before
  _before="$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_EDGE_BOOTSTRAP_KEYRING}" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ "$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")" = "${_before}" ]
}

@test "_install_ubuntu_edge_source: .sources with Enabled: 0 is inert and bootstraps a .list" {
  _edge_live_sources
  printf 'Enabled: 0\n' >> "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  local _before
  _before="$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_EDGE_BOOTSTRAP_KEYRING}" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ "$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")" = "${_before}" ]
}

@test "_install_ubuntu_edge_source: .sources with Enabled:no (no space) is inert and bootstraps a .list" {
  _edge_live_sources
  printf 'Enabled:no\n' >> "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  local _before
  _before="$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_EDGE_BOOTSTRAP_KEYRING}" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ "$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")" = "${_before}" ]
}

@test "_install_ubuntu_edge_source: .sources with URIs only in a comment is inert and bootstraps a .list" {
  printf '# URIs: https://packages.microsoft.com/repos/edge-stable\nTypes: deb\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  local _before
  _before="$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_EDGE_BOOTSTRAP_KEYRING}" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  [ "$(cat "${_EDGE_SOURCES_DIR}/microsoft-edge.sources")" = "${_before}" ]
}

@test "_install_ubuntu_edge_source: .sources with Enabled: true is live" {
  _edge_live_sources
  printf 'Enabled: true\n' >> "${_EDGE_SOURCES_DIR}/microsoft-edge.sources"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  printf 'stale-key' > "${_EDGE_BOOTSTRAP_KEYRING}"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_edge_source: .sources with no Enabled line is live" {
  _edge_live_sources
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  printf 'stale-key' > "${_EDGE_BOOTSTRAP_KEYRING}"
  run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_edge_source: fails closed when gpg fails but still emits bytes (truncated key)" {
  head -c 400 "${REPO_ROOT}/keys/microsoft.asc" > "${BATS_TEST_TMPDIR}/trunc.asc"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/trunc.asc" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING} (gpg missing or failed, no usable key read from"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

# gpg 2.5 exits 0 on a truncated key and still writes bytes (measured on
# GnuPG 2.5.24; 2.4.8 exits 2), so gpg's status alone cannot be the guard. This
# stub reproduces the 2.5 behaviour on any platform: --dearmor "succeeds", and
# the keyring then holds no key.
@test "_install_ubuntu_edge_source: fails closed when gpg exits 0 but the keyring lacks the pinned fingerprint" {
  local _stub="${BATS_TEST_TMPDIR}/gpg-lenient"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do [[ "$a" == --dearmor ]] && { cat; exit 0; }; done\nexit 0\n' > "${_stub}"
  chmod +x "${_stub}"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_GPG_BIN="${_stub}" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING}"* ]]
  [[ "$output" == *"no usable key read from"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

# A well-formed key that is not Microsoft's: it dearmors and lists cleanly, so
# only the exact fingerprint comparison can refuse it.
@test "_install_ubuntu_edge_source: fails closed on a valid key with a different fingerprint" {
  local _gh="${BATS_TEST_TMPDIR}/gh-edge"
  mkdir -p "${_gh}" && chmod 700 "${_gh}"
  "${_MS_GPG_BIN}" --homedir "${_gh}" --batch --passphrase '' --quick-gen-key 'Not Microsoft <x@example.invalid>' ed25519 sign never 2> /dev/null
  "${_MS_GPG_BIN}" --homedir "${_gh}" --batch --armor --export > "${BATS_TEST_TMPDIR}/other-edge.asc"
  gpgconf --homedir "${_gh}" --kill all > /dev/null 2>&1
  [ -s "${BATS_TEST_TMPDIR}/other-edge.asc" ]
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_KEY_PATH="${BATS_TEST_TMPDIR}/other-edge.asc" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING}"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

# A listing that prints the right fingerprint but exits non-zero is not a
# trustworthy listing; the status must be honoured, not only the text.
@test "_install_ubuntu_edge_source: fails closed when the listing prints the pinned fingerprint but exits non-zero" {
  local _stub="${BATS_TEST_TMPDIR}/gpg-listing-fails"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do\n  [[ "$a" == --dearmor ]] && { cat; exit 0; }\n  [[ "$a" == --show-keys ]] && { printf "fpr:::::::::%%s:\\n" "'"${MS_GPG_FPR}"'"; exit 2; }\ndone\nexit 0\n' > "${_stub}"
  chmod +x "${_stub}"
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_GPG_BIN="${_stub}" run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING}"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_edge_source: fails closed when gpg is missing" {
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_GPG_BIN=/nonexistent/gpg run _install_ubuntu_edge_source
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING} (gpg missing or failed, no usable key read from"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_gui_tools: HAS_SNAP wires the edge source helper and installs edge" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS
  _albert_good_key
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "packages.microsoft.com/repos/edge stable main" "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  grep -q "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: no HAS_SNAP skips albert and edge" {
  unset HAS_SNAP HAS_DEVTOOLS
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
  refute_grep "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
}

@test "_install_ubuntu_gui_tools: HAS_FLATPAK installs steam via flatpak" {
  export HAS_FLATPAK=1
  unset HAS_DEVTOOLS HAS_SNAP
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "sudo flatpak install flathub" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: no HAS_FLATPAK skips steam" {
  unset HAS_FLATPAK HAS_DEVTOOLS HAS_SNAP
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  run grep "sudo flatpak install" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

# gui_tools with every sub-install enabled; the albert key is good so a failure
# in a test below is that test's own doing.
_gui_env() {
  export HAS_DEVTOOLS=1 HAS_SNAP=1 HAS_FLATPAK=1
  export VIRTUALBOX_VER="virtualbox-7.0"
  _albert_good_key
}

@test "_install_ubuntu_gui_tools: clean run with every capability returns 0" {
  _gui_env
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "signed-by=${_APT_KEYRINGS_DIR}/oracle-virtualbox-2016.gpg" "${_APT_SOURCES_DIR}/virtualbox.list"
  grep -q "apt install ${VIRTUALBOX_VER}" "${MOCK_CALLS_FILE}"
  grep -q "snap install certbot-dns-route53" "${MOCK_CALLS_FILE}"
  grep -q "flatpak install flathub" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed virtualbox keyring fetch with no keyring returns 1, writes no list, and the snaps still install" {
  _gui_env
  export MOCK_CURL_FAIL_URL="virtualbox.org"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: virtualbox: keyring"* ]]
  [[ "$stderr" == *"gui_tools: virtualbox: source write skipped (no keyring)"* ]]
  [ ! -e "${_APT_SOURCES_DIR}/virtualbox.list" ]
  grep -q "curl .*virtualbox.org" "${MOCK_CALLS_FILE}"
  grep -q "snap install code --classic" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed snap install returns 1 and steam is still attempted" {
  _gui_env
  export MOCK_SNAP_EXIT=1
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: snap code: install failed"* ]]
  grep -q "snap install code --classic" "${MOCK_CALLS_FILE}"
  grep -q "flatpak install flathub" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed edge source setup returns 1 and the edge package install is still attempted" {
  _gui_env
  _install_ubuntu_edge_source() { return 1; }
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: edge: source setup failed"* ]]
  grep -q "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed edge package install returns 1" {
  _gui_env
  export SHIM_APT_FAIL_PKGS="microsoft-edge-stable"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: edge: install failed"* ]]
}

@test "_install_ubuntu_gui_tools: a failed steam flatpak install returns 1" {
  _gui_env
  export SHIM_FLATPAK_EXIT=1
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: steam: install failed"* ]]
  grep -q "flatpak install flathub" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed flathub remote-add returns 1" {
  _gui_env
  export SHIM_FLATPAK_REMOTE_EXIT=1
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: steam: flathub remote-add failed"* ]]
  grep -q "flatpak remote-add" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed virtualbox apt install returns 1" {
  _gui_env
  export SHIM_APT_FAIL_PKGS="${VIRTUALBOX_VER}"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: virtualbox: install failed"* ]]
  grep -q "apt install ${VIRTUALBOX_VER}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed virtualbox source list write returns 1" {
  _gui_env
  export SHIM_TEE_FAIL_ARGS="virtualbox.list"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: virtualbox: source list write failed"* ]]
  grep -q "tee .*virtualbox.list" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed 'snap set certbot' returns 1 and the route53 plugin is still installed" {
  _gui_env
  export SHIM_SNAP_FAIL_ARGS="set certbot"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: snap certbot: trust-plugin-with-root failed"* ]]
  [[ "$stderr" != *"certbot-dns-route53: install failed"* ]]
  grep -q "snap set certbot trust-plugin-with-root=ok" "${MOCK_CALLS_FILE}"
  grep -q "snap install certbot-dns-route53" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: a failed certbot-dns-route53 install returns 1" {
  _gui_env
  export SHIM_SNAP_FAIL_ARGS="certbot-dns-route53"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: snap certbot-dns-route53: install failed"* ]]
  [[ "$stderr" != *"trust-plugin-with-root failed"* ]]
  grep -q "snap install certbot-dns-route53" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: the real edge helper failing to build its keyring returns 1 and names the edge source" {
  _gui_env
  unset HAS_DEVTOOLS HAS_FLATPAK
  export _MS_KEY_PATH="${BATS_TEST_TMPDIR}/no-such-key.asc"
  run --separate-stderr _install_ubuntu_gui_tools
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gui_tools: edge: source setup failed"* ]]
  [[ "$stderr" == *"edge: could not build"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  # Positive control: albert was fine, and the edge package install still ran.
  [ -s "${_APT_SOURCES_DIR}/albert.list" ]
  grep -q "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_misc ─────────────────────────────────────────────────────

@test "_install_ubuntu_misc: calls wget for docker-compose when file does not exist" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "wget.*docker-compose" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: a docker-compose fetch failure is named misc: docker-compose and returns 1" {
  export DOCKER_COMPOSE_URL="https://example.invalid/docker-compose"
  export YQ_URL="https://example.invalid/yq"
  export MOCK_WGET_FAIL_URL="${DOCKER_COMPOSE_URL}"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$output" == *"misc: docker-compose: install failed"* ]]
}

@test "_install_ubuntu_misc: a yq fetch failure is named misc: yq and returns 1, docker-compose unaffected" {
  export DOCKER_COMPOSE_URL="https://example.invalid/docker-compose"
  export YQ_URL="https://example.invalid/yq"
  export MOCK_WGET_FAIL_URL="${YQ_URL}"
  export HAS_DEVTOOLS=1
  run _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$output" == *"misc: yq: install failed"* ]]
  [[ "$output" != *"misc: docker-compose:"* ]]
  [ -x "${_DL_BIN_DIR}/docker-compose" ]
}

@test "_install_ubuntu_misc: a failing nala install is named, returns 1 and autoremove is still attempted" {
  export DOCKER_COMPOSE_URL="https://example.invalid/docker-compose"
  export YQ_URL="https://example.invalid/yq"
  unset HAS_DEVTOOLS
  check_and_install_nala() { return 1; }
  run _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$output" == *"misc: nala: install failed"* ]]
  grep -q "nala autoremove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: a successful nala install logs no nala failure" {
  export DOCKER_COMPOSE_URL="https://example.invalid/docker-compose"
  export YQ_URL="https://example.invalid/yq"
  unset HAS_DEVTOOLS
  check_and_install_nala() { return 0; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [[ "$output" != *"misc: nala: install failed"* ]]
}

@test "_install_ubuntu_misc: nala autoremove does not inherit the caller's stdin" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS
  local _stub_dir _stdin="${BATS_TEST_TMPDIR}/caller_stdin"
  _stub_dir="$(stdin_probe_stub_path nala)"
  printf 'CALLER-STDIN\n%.0s' 1 2 3 > "${_stdin}"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_misc < "${_stdin}"
  [ "$status" -eq 0 ]
  grep -qF "nala autoremove -y stdin=[]" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: nala autoremove sees DEBIAN_FRONTEND=noninteractive" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS DEBIAN_FRONTEND
  local _stub_dir
  _stub_dir="$(frontend_probe_stub_path nala)"
  PATH="${_stub_dir}:${PATH}" run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -qE '^frontend: nala autoremove .* DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: skips docker-compose wget when file already exists" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  # Idempotency is the stamp (URL) plus an executable destination, not a file
  # left in ~/software_downloads.
  printf 'old' > "${_DL_BIN_DIR}/docker-compose"
  chmod 0755 "${_DL_BIN_DIR}/docker-compose"
  mkdir -p "${_DL_STAMP_DIR}"
  printf '%s\n' "${DOCKER_COMPOSE_URL}" > "${_DL_STAMP_DIR}/docker-compose"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker-compose: up to date"* ]]
  ! grep -qF "wget -O" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: HAS_DEVTOOLS installs yq" {
  export HAS_DEVTOOLS=1
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  # Stubbed: _install_pinned_release_binary has its own coverage in
  # release_binary.bats; without this, HAS_DEVTOOLS=1 here would also reach
  # tflint/tfsec's real curl+sha256sum path.
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -qE "wget -O .* ${YQ_URL}$" "${MOCK_CALLS_FILE}"
  [ -x "${_DL_BIN_DIR}/yq" ]
}

@test "_install_ubuntu_misc: no HAS_DEVTOOLS skips yq" {
  unset HAS_DEVTOOLS
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  ! grep -qF "${YQ_URL}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: calls nala autoremove" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "nala autoremove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: does not pip install glances" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  run grep "pip.*glances" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_misc: HAS_DEVTOOLS attempts dotnet-sdk-10.0 install" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "apt install dotnet-sdk-10.0" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: dotnet install failure is non-fatal" {
  # 10.0 is stock on both live releases -- noble 10.0.112-0ubuntu1~24.04.1 and
  # resolute 10.0.112-0ubuntu1~26.04.1, measured 2026-09-13 -- so this guard is
  # no longer covering a known-missing package. It stays for the next release
  # that drops it, which is how 8.0 failed on resolute in the first place.
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  # Fail dotnet only. A blanket MOCK_APT_EXIT also failed the opentofu install,
  # which runs only on a host without tofu, so the test passed or failed by host.
  export SHIM_APT_FAIL_PKGS="dotnet-sdk-10.0"
  export _FORCE_OPENTOFU_INSTALL=1
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  # nala install failure is now fatal for misc; keep this test about dotnet only.
  check_and_install_nala() { return 0; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotnet-sdk-10.0 not available"* ]]
}

@test "_install_ubuntu_misc: opentofu absent installs via apt (not piped sh)" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  # tofu may already be installed on the host (/usr/bin/tofu on Linux, brew on
  # macOS); force the install branch so the test is independent of host state.
  export _FORCE_OPENTOFU_INSTALL=1
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  # The package is named `tofu`, not `opentofu`: that repo's amd64 index
  # carries exactly one package and this assertion previously pinned the
  # wrong name -- encoding the bug, which is why the install failed silently
  # on every Ubuntu release while this test stayed green. Measured on claude
  # 2026-09-12: keyring and sources.list present, apt-cache policy empty.
  grep -q "DEBIAN_FRONTEND=noninteractive.*apt-get install.* tofu" "${MOCK_CALLS_FILE}"
  run grep "install-opentofu.sh" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_misc: opentofu apt setup adds GPG key" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  # tofu may already be installed on the host (/usr/bin/tofu on Linux, brew on
  # macOS); force the install branch so the test is independent of host state.
  export _FORCE_OPENTOFU_INSTALL=1
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "opentofu-archive-keyring.gpg" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: opentofu creates /etc/apt/keyrings before GPG import" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  # tofu may already be installed on the host (/usr/bin/tofu on Linux, brew on
  # macOS); force the install branch so the test is independent of host state.
  export _FORCE_OPENTOFU_INSTALL=1
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -qF "sudo mkdir -p ${_APT_KEYRINGS_DIR}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: opentofu already present skips install" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  # Mock tofu present on PATH and no force flag — install branch must be skipped
  # regardless of whether the host actually has tofu.
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  local _tofudir="${BATS_TEST_TMPDIR}/tofubin"
  mkdir -p "${_tofudir}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_tofudir}/tofu"
  chmod +x "${_tofudir}/tofu"
  PATH="${_tofudir}:${PATH}" run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  run grep "apt-get install -y tofu" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

# HAS_DEVTOOLS misc with seamed fetch targets. The dotnet/tflint/tfsec/tfenv
# members are stubbed: they are advisory and have their own coverage.
_misc_env() {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://dc.example/dl/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://yq.example/dl/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  export _FORCE_OPENTOFU_INSTALL=1
  _install_ubuntu_shellcheck() { :; }
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/fetched-body"
  printf 'body' > "${MOCK_WGET_FILE}"
}

@test "_install_ubuntu_misc: a clean run installs both binaries, stamps them, and returns 0" {
  _misc_env
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [ -x "${_DL_BIN_DIR}/docker-compose" ]
  [ -x "${_DL_BIN_DIR}/yq" ]
  [ "$(cat "${_DL_STAMP_DIR}/docker-compose")" = "${DOCKER_COMPOSE_URL}" ]
  [ "$(cat "${_DL_STAMP_DIR}/yq")" = "${YQ_URL}" ]
  [ -s "${_APT_SOURCES_DIR}/opentofu.list" ]
  grep -q "apt-get install.* tofu" "${MOCK_CALLS_FILE}"
  [[ "$stderr" != *"misc:"* ]]
}

@test "_install_ubuntu_misc: a failed docker-compose download returns 1 and leaves destination, stamp and workdir alone; yq still installs" {
  _misc_env
  printf 'old' > "${_DL_BIN_DIR}/docker-compose"
  chmod 0755 "${_DL_BIN_DIR}/docker-compose"
  export MOCK_WGET_FAIL_URL="docker-compose"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"docker-compose: download failed"* ]]
  grep -q "wget .*docker-compose" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_DL_BIN_DIR}/docker-compose")" = "old" ]
  [ ! -e "${_DL_STAMP_DIR}/docker-compose" ]
  [ -z "$(find "${_DL_TMP_ROOT}" -mindepth 1)" ]
  # Positive control: the sibling was not held up.
  [ -x "${_DL_BIN_DIR}/yq" ]
  [ -s "${_DL_STAMP_DIR}/yq" ]
}

@test "_install_ubuntu_misc: a failed yq download returns 1 and docker-compose still installs" {
  _misc_env
  printf 'old' > "${_DL_BIN_DIR}/yq"
  chmod 0755 "${_DL_BIN_DIR}/yq"
  export MOCK_WGET_FAIL_URL="yq.example"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"yq: download failed"* ]]
  grep -q "wget .*yq.example" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_DL_BIN_DIR}/yq")" = "old" ]
  [ ! -e "${_DL_STAMP_DIR}/yq" ]
  [ -x "${_DL_BIN_DIR}/docker-compose" ]
  [ -s "${_DL_STAMP_DIR}/docker-compose" ]
}

@test "_install_ubuntu_misc: a failed opentofu keyring fetch with no keyring returns 1, writes no list, and skips with a warning" {
  _misc_env
  export MOCK_CURL_FAIL_URL="packages.opentofu.org"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"misc: opentofu: keyring install failed"* ]]
  [[ "$stderr" == *"misc: opentofu: source write skipped (no keyring)"* ]]
  [ ! -e "${_APT_SOURCES_DIR}/opentofu.list" ]
  # Positive controls: the fetch was attempted; the earlier tools completed.
  grep -q "curl .*packages.opentofu.org" "${MOCK_CALLS_FILE}"
  [ -x "${_DL_BIN_DIR}/yq" ]
}

@test "_install_ubuntu_misc: a failed opentofu keyring fetch with a prior keyring returns 1 and keeps it" {
  _misc_env
  local _ring="${_APT_KEYRINGS_DIR}/opentofu-archive-keyring.gpg"
  printf 'old' > "${_ring}"
  export MOCK_CURL_FAIL_URL="packages.opentofu.org"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"misc: opentofu: keyring install failed"* ]]
  grep -q "curl .*packages.opentofu.org" "${MOCK_CALLS_FILE}"
  [ "$(cat "${_ring}")" = "old" ]
  # The prior keyring still backs the source list, so only the keyring failed.
  [[ "$stderr" != *"source write skipped"* ]]
  [ -s "${_APT_SOURCES_DIR}/opentofu.list" ]
}

@test "_install_ubuntu_misc: a failed opentofu source list write returns 1" {
  _misc_env
  export SHIM_TEE_FAIL_ARGS="opentofu.list"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"misc: opentofu: source list write failed"* ]]
  # Positive control: the write was attempted, and only that failed.
  grep -q "tee .*opentofu.list" "${MOCK_CALLS_FILE}"
  [[ "$stderr" != *"keyring install failed"* ]]
}

@test "_install_ubuntu_misc: a failed opentofu package install returns 1" {
  _misc_env
  export SHIM_APT_FAIL_PKGS="tofu"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"misc: opentofu: install failed"* ]]
  grep -q "apt-get install.* tofu" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: a failed nala autoremove warns and still returns 0" {
  _misc_env
  export MOCK_NALA_EXIT=1
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"misc: nala autoremove failed"* ]]
  # Positive control: autoremove was attempted.
  grep -q "nala autoremove" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: the opentofu source line is signed-by the seamed keyring" {
  _misc_env
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [ "$(cat "${_APT_SOURCES_DIR}/opentofu.list")" = "deb [signed-by=${_APT_KEYRINGS_DIR}/opentofu-archive-keyring.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" ]
}

@test "_install_ubuntu_misc: a failed apt-get update does not mask the install result" {
  _misc_env
  export MOCK_APT_FAIL_SUBCMD="update"
  run --separate-stderr _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "apt-get update" "${MOCK_CALLS_FILE}"
  grep -q "apt-get install.* tofu" "${MOCK_CALLS_FILE}"
}

# ── Ubuntu 26.04 (resolute) provisioning gaps, both measured on `claude` ─────

@test "_install_ubuntu_powershell: RESOLUTE pins the Microsoft config to 24.04" {
  export RESOLUTE=1
  # The harness default is 24.04, which would make this assertion match the
  # DEFAULT rather than the fix. Force the mock to report resolute so unfixed
  # code builds a 26.04 URL and this test can actually go red.
  export MOCK_LSB_RELEASE_RS="26.04"
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  # packages.microsoft.com/config/ubuntu/26.04 exists (HTTP 200) and its
  # resolute dist carries ZERO powershell packages, measured 2026-09-12;
  # 24.04/noble carries 54. So the config URL, not the dist, is what falls back.
  grep -qE "wget.*config/ubuntu/24\.04/packages-microsoft-prod\.deb" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: non-RESOLUTE keeps the lsb_release version" {
  unset RESOLUTE
  export NOBLE=1
  # Positive control: assert the version the mock actually reports is the one
  # used, rather than asserting the absence of 26.04 -- an absence that is
  # trivially true whenever the mock does not emit 26.04 in the first place.
  export MOCK_LSB_RELEASE_RS="24.10"
  run _install_ubuntu_powershell
  [ "$status" -eq 1 ] # post-install probe fails: the stub pwsh never runs
  grep -qE "wget.*config/ubuntu/24\.10/packages-microsoft-prod\.deb" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: version probe does not depend on interactive PATH" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  touch "${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME}"
  # /usr/local/go/bin reaches PATH only via 6_path.zsh, which interactive zsh
  # alone sources -- so a provision run resolves nothing and the check is dead.
  # Point the seam at a stand-in that reports the matching version.
  local _bin_dir="${BATS_TEST_TMPDIR}/goroot/bin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\nprintf "go version go1.26 linux/amd64\\n"\n' > "${_bin_dir}/go"
  chmod +x "${_bin_dir}/go"
  export _GO_BIN="${_bin_dir}/go"
  run env PATH="/usr/bin:/bin" bash -c "
    source '${REPO_ROOT}/lib/constants.sh' 2>/dev/null
    source '${REPO_ROOT}/lib/linux_ubuntu.sh'
    _install_go_from_tarball() { :; }
    GO_VER='1.26' _GO_BIN='${_bin_dir}/go' _install_ubuntu_go"
  [[ "$output" == *"Go 1.26 is installed"* ]]
}

# --- _build_pinned_keyring: build in temp, verify the pin, install only on success ---

_fpr_of_ring() {
  "${_MS_GPG_BIN}" --homedir "${BATS_TEST_TMPDIR}/fprhome" --batch --show-keys --with-colons "$1" 2> /dev/null \
    | grep '^fpr:' | cut -d: -f10
}

_seed_ring() {
  _ring="${BATS_TEST_TMPDIR}/final.gpg"
  printf 'old' > "${_ring}"
  [ -f "${_ring}" ]
}

@test "_build_pinned_keyring: pinned key installs a 0644 keyring listing exactly the pinned fingerprint" {
  mkdir -p "${BATS_TEST_TMPDIR}/fprhome"
  local _ring="${BATS_TEST_TMPDIR}/final.gpg"
  run _build_pinned_keyring "${REPO_ROOT}/keys/microsoft.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 0 ]
  [ "$(_fpr_of_ring "${_ring}")" = "${MS_GPG_FPR}" ]
  [ "$(stat -c %a "${_ring}" 2> /dev/null || stat -f %Lp "${_ring}")" = "644" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_build_pinned_keyring: a different single key returns 1 and leaves the existing keyring untouched" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  run _build_pinned_keyring "${REPO_ROOT}/tests/fixtures/albert-obs.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 1 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_build_pinned_keyring: two keys in one file returns 1 and leaves the existing keyring untouched" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  cat "${REPO_ROOT}/keys/microsoft.asc" "${REPO_ROOT}/tests/fixtures/albert-obs.asc" > "${BATS_TEST_TMPDIR}/two.asc"
  run _build_pinned_keyring "${BATS_TEST_TMPDIR}/two.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 1 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_build_pinned_keyring: a truncated key returns 2 and leaves the existing keyring untouched" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  head -c 200 "${REPO_ROOT}/keys/microsoft.asc" > "${BATS_TEST_TMPDIR}/trunc.asc"
  run _build_pinned_keyring "${BATS_TEST_TMPDIR}/trunc.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 2 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_build_pinned_keyring: a non-key body returns 2 and leaves the existing keyring untouched" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  printf '<html>x</html>' > "${BATS_TEST_TMPDIR}/html.asc"
  run _build_pinned_keyring "${BATS_TEST_TMPDIR}/html.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 2 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_build_pinned_keyring: gpg exiting non-zero returns 2 even when it still wrote a good key" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  # Fails ONLY the dearmor, after writing the correct bytes, so the fingerprint
  # check alone would pass: only the dearmor exit-status check can return 2 here.
  printf '#!/usr/bin/env bash\nif [[ $1 == --dearmor ]]; then "%s" --dearmor; exit 2; fi\nexec "%s" "$@"\n' "${_MS_GPG_BIN}" "${_MS_GPG_BIN}" > "${BATS_TEST_TMPDIR}/gpg-fail"
  chmod +x "${BATS_TEST_TMPDIR}/gpg-fail"
  _MS_GPG_BIN="${BATS_TEST_TMPDIR}/gpg-fail" run _build_pinned_keyring "${REPO_ROOT}/keys/microsoft.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 2 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

# tests/fixtures/subkey-pin.asc: an rsa2048 primary (0F686855...F39878D) carrying a
# cv25519 encryption subkey, generated once offline so no test needs a gpg-agent
# (a keygen under BATS_TEST_TMPDIR overflows macOS's unix-socket path limit).
@test "_build_pinned_keyring: a pin equal to a SUBKEY fingerprint returns 1 and leaves the existing keyring untouched" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  run _build_pinned_keyring "${REPO_ROOT}/tests/fixtures/subkey-pin.asc" "${_ring}" "05E7C322791E474134B4CC27A3B2ED738EF1BBCA"
  [ "$status" -eq 1 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_build_pinned_keyring: the fixture's primary fingerprint does install" {
  _seed_ring
  run _build_pinned_keyring "${REPO_ROOT}/tests/fixtures/subkey-pin.asc" "${_ring}" "0F6868553876AAD0A8C17C72591C21DEFD39878D"
  [ "$status" -eq 0 ]
  ! cmp -s <(printf 'old') "${_ring}"
}

@test "_build_pinned_keyring: install ok but mv failing returns 3, keeps the keyring and removes the staged file" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  mkdir "${BATS_TEST_TMPDIR}/mvstub"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/mvstub/mv"
  chmod +x "${BATS_TEST_TMPDIR}/mvstub/mv"
  PATH="${BATS_TEST_TMPDIR}/mvstub:${PATH}" run _build_pinned_keyring "${REPO_ROOT}/keys/microsoft.asc" "${_ring}" "${MS_GPG_FPR}"
  [ "$status" -eq 3 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ ! -e "${_ring}.new" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_keyring_has_pinned_fpr: an empty pin returns 1" {
  local _h
  _h="$(mktemp -d "${_APT_KEY_TMP_ROOT}/h.XXXXXXXX")"
  "${_MS_GPG_BIN}" --dearmor < "${REPO_ROOT}/keys/microsoft.asc" > "${BATS_TEST_TMPDIR}/ms.gpg"
  run _keyring_has_pinned_fpr "${BATS_TEST_TMPDIR}/ms.gpg" "" "${_h}"
  [ "$status" -eq 1 ]
}

@test "_build_pinned_keyring: an empty keyring path, key path or pin is refused before anything runs" {
  run _build_pinned_keyring "${REPO_ROOT}/keys/microsoft.asc" "" "${MS_GPG_FPR}"
  [ "$status" -eq 3 ]
  run _build_pinned_keyring "" "${BATS_TEST_TMPDIR}/final.gpg" "${MS_GPG_FPR}"
  [ "$status" -eq 3 ]
  [ ! -e "${BATS_TEST_TMPDIR}/final.gpg" ]
  run _build_pinned_keyring "${REPO_ROOT}/keys/microsoft.asc" "${BATS_TEST_TMPDIR}/final.gpg" ""
  [ "$status" -eq 3 ]
  [ ! -e "${BATS_TEST_TMPDIR}/final.gpg" ]
}

@test "_build_pinned_keyring: an unwritable keyring directory returns 3, keeps the keyring and leaves no staging file" {
  if [[ ${EUID} -eq 0 ]]; then
    skip "root can write into a 0555 directory, so the install cannot be made to fail"
  fi
  mkdir "${BATS_TEST_TMPDIR}/ro"
  local _ring="${BATS_TEST_TMPDIR}/ro/final.gpg"
  printf 'old' > "${_ring}"
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  chmod 555 "${BATS_TEST_TMPDIR}/ro"
  [ -f "${_ring}" ]
  run _build_pinned_keyring "${REPO_ROOT}/keys/microsoft.asc" "${_ring}" "${MS_GPG_FPR}"
  chmod 755 "${BATS_TEST_TMPDIR}/ro"
  [ "$status" -eq 3 ]
  cmp "${BATS_TEST_TMPDIR}/expect" "${_ring}"
  [ ! -e "${_ring}.new" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_keyring_has_pinned_fpr: a listing with no pub: record returns 2" {
  local _h
  _h="$(mktemp -d "${_APT_KEY_TMP_ROOT}/h.XXXXXXXX")"
  printf '#!/usr/bin/env bash\nprintf "tru::1:0:0:0:0:0\\n"\nexit 0\n' > "${BATS_TEST_TMPDIR}/gpg-nopub"
  chmod +x "${BATS_TEST_TMPDIR}/gpg-nopub"
  _MS_GPG_BIN="${BATS_TEST_TMPDIR}/gpg-nopub" run _keyring_has_pinned_fpr "${BATS_TEST_TMPDIR}/any.gpg" "${MS_GPG_FPR}" "${_h}"
  [ "$status" -eq 2 ]
}

@test "_keyring_has_pinned_fpr: a pub: record with no fpr: record returns 2" {
  local _h
  _h="$(mktemp -d "${_APT_KEY_TMP_ROOT}/h.XXXXXXXX")"
  printf '#!/usr/bin/env bash\nprintf "pub:-:2048:1:591C21DEFD39878D:1:::::scESC:\\n"\nexit 0\n' > "${BATS_TEST_TMPDIR}/gpg-nofpr"
  chmod +x "${BATS_TEST_TMPDIR}/gpg-nofpr"
  _MS_GPG_BIN="${BATS_TEST_TMPDIR}/gpg-nofpr" run _keyring_has_pinned_fpr "${BATS_TEST_TMPDIR}/any.gpg" "${MS_GPG_FPR}" "${_h}"
  [ "$status" -eq 2 ]
}

@test "_keyring_has_pinned_fpr: an empty homedir argument is refused with 2" {
  run _keyring_has_pinned_fpr "${REPO_ROOT}/keys/microsoft.asc" "${MS_GPG_FPR}" ""
  [ "$status" -eq 2 ]
}

# ── _install_ubuntu_albert ───────────────────────────────────────────────────

_ALBERT_FPR="A4B83CD05FDF5C5178482D4A1488EB46E192A257"
_MS_FPR="BC528686B50D79E339D3721CEB3E94ADBE1229CF"

_albert_good_key() {
  local _k
  _k="$(cat "${REPO_ROOT}/tests/fixtures/albert-obs.asc")"
  export MOCK_CURL_STDOUT="${_k}"
}

_albert_wrong_key() {
  local _k
  _k="$(cat "${REPO_ROOT}/keys/microsoft.asc")"
  export MOCK_CURL_STDOUT="${_k}"
}

# Pre-seed a last-known-good source and keyring, asserting they exist first.
_albert_seed_last_good() {
  printf 'deb [signed-by=x] https://old.example/ /\n' > "${_APT_SOURCES_DIR}/albert.list"
  printf 'OLDKEYRING' > "${_APT_KEYRINGS_DIR}/albert-obs.gpg"
  [ -f "${_APT_SOURCES_DIR}/albert.list" ]
  [ -f "${_APT_KEYRINGS_DIR}/albert-obs.gpg" ]
  cp "${_APT_SOURCES_DIR}/albert.list" "${BATS_TEST_TMPDIR}/list.orig"
  cp "${_APT_KEYRINGS_DIR}/albert-obs.gpg" "${BATS_TEST_TMPDIR}/ring.orig"
}

_albert_assert_last_good_untouched() {
  [ -f "${_APT_SOURCES_DIR}/albert.list" ]
  [ -f "${_APT_KEYRINGS_DIR}/albert-obs.gpg" ]
  cmp "${_APT_SOURCES_DIR}/albert.list" "${BATS_TEST_TMPDIR}/list.orig"
  cmp "${_APT_KEYRINGS_DIR}/albert-obs.gpg" "${BATS_TEST_TMPDIR}/ring.orig"
}

@test "_install_ubuntu_albert: good key writes an https signed-by source and installs albert" {
  _albert_good_key
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 0 ]
  [ -s "${_APT_KEYRINGS_DIR}/albert-obs.gpg" ]
  grep -q "https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_" "${_APT_SOURCES_DIR}/albert.list"
  grep -q "signed-by=${_APT_KEYRINGS_DIR}/albert-obs.gpg" "${_APT_SOURCES_DIR}/albert.list"
  refute_grep "deb http://" "${_APT_SOURCES_DIR}/albert.list"
  grep -q "apt install albert" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_albert: curl failure keeps the last good source and returns 2" {
  _albert_seed_last_good
  export MOCK_CURL_EXIT=22
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  _albert_assert_last_good_untouched
  [[ "$stderr" == *"download.opensuse.org"* ]]
  [[ "$stderr" == *"fetch failed"* ]]
  [[ "$stderr" != *"no key could be read"* ]]
  [[ "$stderr" == *"keeping last verified source"* ]]
  grep -q "^curl " "${MOCK_CALLS_FILE}"
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_albert: a non-key body keeps the last good source and returns 2" {
  _albert_seed_last_good
  export MOCK_CURL_STDOUT='<html>captive portal</html>'
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  _albert_assert_last_good_untouched
  [[ "$stderr" == *"download.opensuse.org"* ]]
  [[ "$stderr" == *"no key could be read"* ]]
  [[ "$stderr" != *"fetch failed"* ]]
  grep -q "^curl " "${MOCK_CALLS_FILE}"
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_albert: wrong fingerprint removes the source and keyring, warns with both fingerprints" {
  _albert_seed_last_good
  _albert_wrong_key
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  [ ! -e "${_APT_SOURCES_DIR}/albert.list" ]
  [ ! -e "${_APT_KEYRINGS_DIR}/albert-obs.gpg" ]
  [[ "$stderr" == *"${_MS_FPR}"* ]]
  [[ "$stderr" == *"${_ALBERT_FPR}"* ]]
  grep -q "^curl " "${MOCK_CALLS_FILE}"
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_albert: keyring install failure (builder 3) keeps the last good source and returns 2" {
  _albert_seed_last_good
  _albert_good_key
  _build_pinned_keyring() { return 3; }
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  _albert_assert_last_good_untouched
  [[ "$stderr" == *"${_APT_KEYRINGS_DIR}/albert-obs.gpg"* ]]
  grep -q "^curl " "${MOCK_CALLS_FILE}"
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_albert: fetches into a temp dir under _APT_KEY_TMP_ROOT and leaves it empty (success)" {
  _albert_good_key
  run _install_ubuntu_albert
  [ "$status" -eq 0 ]
  grep -q "curl .*-o ${_APT_KEY_TMP_ROOT}/albert-key\." "${MOCK_CALLS_FILE}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_albert: leaves the temp root empty after a curl failure" {
  export MOCK_CURL_EXIT=22
  run _install_ubuntu_albert
  [ "$status" -eq 2 ]
  grep -q "curl .*-o ${_APT_KEY_TMP_ROOT}/albert-key\." "${MOCK_CALLS_FILE}"
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_ubuntu_albert: removes the legacy global key and http source on success" {
  _albert_good_key
  printf 'x' > "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg"
  printf 'x' > "${_APT_SOURCES_DIR}/home:manuelschneid3r.list"
  [ -f "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg" ]
  [ -f "${_APT_SOURCES_DIR}/home:manuelschneid3r.list" ]
  run _install_ubuntu_albert
  [ "$status" -eq 0 ]
  [ ! -e "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg" ]
  [ ! -e "${_APT_SOURCES_DIR}/home:manuelschneid3r.list" ]
}

@test "_install_ubuntu_albert: removes the legacy global key and http source on the wrong-fingerprint path" {
  _albert_wrong_key
  printf 'x' > "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg"
  printf 'x' > "${_APT_SOURCES_DIR}/home:manuelschneid3r.list"
  [ -f "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg" ]
  [ -f "${_APT_SOURCES_DIR}/home:manuelschneid3r.list" ]
  run _install_ubuntu_albert
  [ "$status" -eq 2 ]
  [ ! -e "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg" ]
  [ ! -e "${_APT_SOURCES_DIR}/home:manuelschneid3r.list" ]
}

@test "_install_ubuntu_albert: a second run leaves albert.list byte-identical" {
  _albert_good_key
  run _install_ubuntu_albert
  [ "$status" -eq 0 ]
  [ -s "${_APT_SOURCES_DIR}/albert.list" ]
  cp "${_APT_SOURCES_DIR}/albert.list" "${BATS_TEST_TMPDIR}/first.list"
  run _install_ubuntu_albert
  [ "$status" -eq 0 ]
  cmp "${_APT_SOURCES_DIR}/albert.list" "${BATS_TEST_TMPDIR}/first.list"
}

@test "_install_ubuntu_gui_tools: an albert failure makes the step return non-zero after the rest runs" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS HAS_FLATPAK
  export MOCK_CURL_EXIT=22
  run _install_ubuntu_gui_tools
  [ "$status" -eq 2 ]
  grep -q "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
}

@test "install_ubuntu_packages: names gui_tools when albert fails" {
  unset MACOS
  export LINUX=1 UBUNTU=1 NOBLE=1 HAS_SNAP=1
  unset HAS_DEVTOOLS HAS_FLATPAK
  export MOCK_CURL_EXIT=22
  _install_ubuntu_base_packages() { :; }
  local _s
  for _s in inotify workstation powershell go docker nvidia k8s_tools hashicorp cloud_tools brew_packages rust misc; do
    eval "_install_ubuntu_${_s}() { :; }"
  done
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"failed: gui_tools"* ]]
  [[ "$stderr" == *"albert key fetch failed"* ]]
}

@test "_install_ubuntu_gui_tools: albert succeeding returns 0 (the step's own tail status)" {
  export HAS_SNAP=1
  unset HAS_DEVTOOLS HAS_FLATPAK
  _albert_good_key
  run _install_ubuntu_gui_tools
  # The step ends in `if [[ -n ${HAS_FLATPAK} ]]` with no else, so its tail status
  # is 0 by construction today; this pins that albert's success does not alter it.
  [ "$status" -eq 0 ]
  grep -q "apt install albert" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_albert: no existing source says no verified source is present" {
  [ ! -e "${_APT_SOURCES_DIR}/albert.list" ]
  export MOCK_CURL_EXIT=22
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no verified albert source is present"* ]]
  [[ "$stderr" != *"keeping last verified source"* ]]
}

@test "_install_ubuntu_albert: removes legacy files even when the fetch fails" {
  export MOCK_CURL_EXIT=22
  printf 'x' > "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg"
  printf 'x' > "${_APT_SOURCES_DIR}/home:manuelschneid3r.list"
  [ -f "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg" ]
  [ -f "${_APT_SOURCES_DIR}/home:manuelschneid3r.list" ]
  run _install_ubuntu_albert
  [ "$status" -eq 2 ]
  [ ! -e "${_APT_TRUSTED_DIR}/home_manuelschneid3r.gpg" ]
  [ ! -e "${_APT_SOURCES_DIR}/home:manuelschneid3r.list" ]
}

@test "_install_ubuntu_albert: a failed apt install albert warns and returns 2" {
  _albert_good_key
  export MOCK_APT_EXIT=1
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  grep -q "apt install albert" "${MOCK_CALLS_FILE}"
  [[ "$stderr" == *"apt install albert failed"* ]]
}

@test "_install_ubuntu_albert: a failed source write warns and returns 2" {
  _albert_good_key
  export MOCK_TEE_EXIT=1
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  grep -q "^tee " "${MOCK_CALLS_FILE}"
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
  [[ "$stderr" == *"could not write ${_APT_SOURCES_DIR}/albert.list"* ]]
}

@test "_install_ubuntu_albert: mismatch WARN lists only the primary fingerprint, never a subkey" {
  export MOCK_CURL_STDOUT
  MOCK_CURL_STDOUT="$(cat "${REPO_ROOT}/tests/fixtures/subkey-pin.asc")"
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"0F6868553876AAD0A8C17C72591C21DEFD39878D"* ]]
  [[ "$stderr" == *"not the pinned key"* ]]
  [[ "$stderr" != *"05E7C322791E474134B4CC27A3B2ED738EF1BBCA"* ]]
}

@test "_install_ubuntu_albert: mismatch WARN uses multi-key wording when several primary keys arrive" {
  export MOCK_CURL_STDOUT
  MOCK_CURL_STDOUT="$(cat "${REPO_ROOT}/keys/microsoft.asc" "${REPO_ROOT}/tests/fixtures/albert-obs.asc")"
  run --separate-stderr _install_ubuntu_albert
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"2 primary keys"* ]]
  [[ "$stderr" == *"${_MS_FPR}"* ]]
  [[ "$stderr" != *"not the pinned key"* ]]
}

# ── install_ubuntu_packages: clean run, every step real ──────────────────────

# wget shim that hands back the right fixture per URL: the Go tarball, the
# HashiCorp zip, the cf-terraforming tarball, or a plain body. tests/mocks/wget
# serves one MOCK_WGET_FILE for every call, which cannot satisfy a dispatcher run.
_dispatch_wget_shim() {
  cat > "${SHIM_DIR}/wget" << SHIM
#!/usr/bin/env bash
case "\$*" in
  *"${GO_DOWNLOAD_URL}"*) export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/go.tgz" ;;
  *releases.hashicorp.com*) export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/hc.zip" ;;
  *cf-terraforming*) export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/cf.tgz" ;;
  *) export MOCK_WGET_FILE="${BATS_TEST_TMPDIR}/blob" ;;
esac
exec "${REPO_ROOT}/tests/mocks/wget" "\$@"
SHIM
  /bin/chmod +x "${SHIM_DIR}/wget"
}

@test "install_ubuntu_packages: a clean run reaches every step, and a second run re-fetches nothing" {
  unset MACOS RESOLUTE
  export LINUX=1 UBUNTU=1 NOBLE=1
  export HAS_DOCKER=1 HAS_K8S=1 HAS_DEVTOOLS=1 HAS_SNAP=1 HAS_FLATPAK=1
  export _OVERRIDE_NVIDIA_GPU_PRESENT=1
  # Stubbed: brew_packages and rust (linuxbrew and rustup have their own tests and
  # would reach the network); everything else runs for real.
  _install_ubuntu_brew_packages() { :; }
  _install_ubuntu_rust() { :; }
  _ws_dir
  cd "${REPO_ROOT}"
  _hc_env
  _cloud_env
  _misc_env
  _k8s_env
  _gui_env
  _docker_fetch_ok
  _go_stub 1.27.1
  _PWSH_BIN="$(_pwsh_stub_bin 0)"
  export _PWSH_BIN
  # The albert key is the one fixture with a pinned fingerprint, so it is the curl
  # body for every fetch; it is also the "resolved" telepresence URL (!= its link).
  _albert_good_key
  # _make_go_tarball and _cf_tarball write go.tgz and cf.tgz where the shim reads them;
  # _hc_env wrote hc.zip and _k8s_env wrote blob.
  _make_go_tarball
  _cf_tarball
  [ -s "${BATS_TEST_TMPDIR}/hc.zip" ] && [ -s "${BATS_TEST_TMPDIR}/blob" ]
  _dispatch_wget_shim
  # --resolve's curl asks for %{url_effective}, which must be an https URL
  # different from the link; every other curl (key fetches) keeps the key body.
  cat > "${SHIM_DIR}/curl" << SHIM
#!/usr/bin/env bash
if [[ "\$*" == *'%{url_effective}'* ]]; then
  printf 'curl %s\\n' "\$*" >> "\${MOCK_CALLS_FILE}"
  printf 'https://example.invalid/telepresence-resolved'
  exit 0
fi
exec "${REPO_ROOT}/tests/mocks/curl" "\$@"
SHIM
  /bin/chmod +x "${SHIM_DIR}/curl"

  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"ubuntu packages: failed"* ]]
  [[ "$output" == *"inotify: conf written"* ]]
  grep -q "nala install" "${MOCK_CALLS_FILE}"
  grep -q "snap install" "${MOCK_CALLS_FILE}"
  grep -q "^wget .*${GO_DOWNLOAD_URL}" "${MOCK_CALLS_FILE}"
  grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
  grep -q "apt install kubectl" "${MOCK_CALLS_FILE}"
  local _t
  for _t in consul vault nomad packer vagrant; do
    grep -q "^wget .*releases.hashicorp.com/${_t}/" "${MOCK_CALLS_FILE}"
  done
  grep -q "^wget .*${KIND_URL}" "${MOCK_CALLS_FILE}"
  grep -q "^wget .*${CF_TERRAFORMING_URL}" "${MOCK_CALLS_FILE}"
  grep -q "^wget .*${DOCKER_COMPOSE_URL}" "${MOCK_CALLS_FILE}"
  grep -q "^wget .*${YQ_URL}" "${MOCK_CALLS_FILE}"
  # Its wget URL is the resolved one (the key body here), so assert on the stamp.
  [ -s "${_DL_STAMP_DIR}/telepresence" ]
  grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
  grep -q "apt-get install.* cloudflare-warp" "${MOCK_CALLS_FILE}"
  grep -q "apt install google-cloud-cli" "${MOCK_CALLS_FILE}"
  grep -q "apt install ${VIRTUALBOX_VER}" "${MOCK_CALLS_FILE}"
  grep -q "apt install .*microsoft-edge" "${MOCK_CALLS_FILE}"
  grep -q "snap install certbot-dns-route53" "${MOCK_CALLS_FILE}"
  grep -q "flatpak install flathub" "${MOCK_CALLS_FILE}"
  grep -q "apt-get install.* tofu" "${MOCK_CALLS_FILE}"

  local _before _after
  _before="$(grep -c '^wget ' "${MOCK_CALLS_FILE}")"
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"ubuntu packages: failed"* ]]
  _after="$(grep -c '^wget ' "${MOCK_CALLS_FILE}")"
  # Go is stamped too, so the only wget the second run may add is none.
  [ "${_after}" -eq "${_before}" ]
  for _t in go consul vault nomad packer vagrant kind telepresence cf-terraforming docker-compose yq; do
    [[ "$output$stderr" == *"${_t}: up to date (stamp"* ]]
  done
}

# ── _install_ubuntu_inotify ──────────────────────────────────────────────────
# load_mocks points _SYSCTL_CONF, _INOTIFY_PROC, _SYSTEMD_RUN_DIR and
# _SYSCTL_BIN at BATS_TEST_TMPDIR; the live value starts at 1024.

_inotify_live() { printf '%s\n' "$1" > "${_INOTIFY_PROC}"; }
_inotify_sysctl_calls() { grep -c '^sysctl ' "${MOCK_CALLS_FILE}" || true; }

@test "inotify: absent conf and live 128 writes the conf and applies 1024" {
  export HAS_DOCKER=1
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 1024" ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
  [[ "$output" == *"inotify: conf written (1024)"* ]]
  [[ "$output" == *"inotify: applied"* ]]
}

@test "inotify: absent conf and live 4096 writes 4096 and never applies" {
  export HAS_DOCKER=1
  _inotify_live 4096
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 4096" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
  [[ "$output" == *"inotify: conf written (4096)"* ]]
  [[ "$output" != *"already"* ]]
}

@test "inotify: conf key=1024 with live 1024 is left alone and says already" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances=1024\n' > "${_SYSCTL_CONF}"
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances=1024" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
}

@test "inotify: a conf raised to 4096 is not lowered" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 4096\n' > "${_SYSCTL_CONF}"
  _inotify_live 4096
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 4096" ]
  [[ "$output" == *"inotify: already"* ]]
}

@test "inotify: slash spelling and leading dash count as the value" {
  export HAS_DOCKER=1
  printf 'fs/inotify/max_user_instances = 4096\n' > "${_SYSCTL_CONF}"
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs/inotify/max_user_instances = 4096" ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
  printf -- '-fs.inotify.max_user_instances = 2048\n' > "${_SYSCTL_CONF}"
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "-fs.inotify.max_user_instances = 2048" ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: the last assignment wins, in both directions" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 512\nfs.inotify.max_user_instances = 4096\n' > "${_SYSCTL_CONF}"
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "$(printf 'fs.inotify.max_user_instances = 512\nfs.inotify.max_user_instances = 4096')" ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
  printf 'fs.inotify.max_user_instances = 4096\nfs.inotify.max_user_instances = 512\n' > "${_SYSCTL_CONF}"
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 1024" ]
  [[ "$output" == *"inotify: persisted 1024 to ${_SYSCTL_CONF} (was 512)"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 1 ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
}

@test "inotify: a conf below 1024 is rewritten to 1024" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 512\n' > "${_SYSCTL_CONF}"
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 1024" ]
  [[ "$output" == *"inotify: persisted 1024 to ${_SYSCTL_CONF} (was 512)"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 1 ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
}

@test "inotify: a correct conf with live 128 is not rewritten but is applied" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 1024\n' > "${_SYSCTL_CONF}"
  # -nt against a marker made after the conf proves no write: BSD stat lacks -c.
  touch -r "${_SYSCTL_CONF}" "${BATS_TEST_TMPDIR}/marker"
  sleep 1
  touch "${BATS_TEST_TMPDIR}/marker"
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ ! "${_SYSCTL_CONF}" -nt "${BATS_TEST_TMPDIR}/marker" ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 1024" ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
  [[ "$output" != *"conf written"* ]]
}

@test "inotify: conf 4096 with live 128 applies the conf value" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 4096\n' > "${_SYSCTL_CONF}"
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 4096" ]
  [ "$(_inotify_sysctl_calls)" -eq 1 ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=4096$' "${MOCK_CALLS_FILE}"
  [[ "$output" == *"inotify: applied"* ]]
}

@test "inotify: a non-numeric live value returns 1 and applies nothing" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 1024\n' > "${_SYSCTL_CONF}"
  _inotify_live abc
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read live value"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a missing live file returns 1 and applies nothing" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 1024\n' > "${_SYSCTL_CONF}"
  rm -f "${_INOTIFY_PROC}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read live value"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a valid assignment followed by an invalid one is unparseable and untouched" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 4096\nfs.inotify.max_user_instances = 08\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "$(printf 'fs.inotify.max_user_instances = 4096\nfs.inotify.max_user_instances = 08')" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a leading-zero live value returns 1 and applies nothing" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 1024\n' > "${_SYSCTL_CONF}"
  _inotify_live 08
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read live value"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: only the instances key is applied when the conf carries another" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_watches = 1\nfs.inotify.max_user_instances = 1024\n' > "${_SYSCTL_CONF}"
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(_inotify_sysctl_calls)" -eq 1 ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
  ! grep -q 'sysctl -p' "${MOCK_CALLS_FILE}"
}

@test "inotify: an unreadable conf returns 1 and is left untouched" {
  # root reads mode-000 files, so the premise cannot be built there.
  [ "$(id -u)" -ne 0 ] || skip "root can read a mode-000 file"
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 4096\n' > "${_SYSCTL_CONF}"
  chmod 000 "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  chmod 600 "${_SYSCTL_CONF}"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unreadable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 4096" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: an unparseable conf returns 1 and is left untouched" {
  export HAS_DOCKER=1
  printf '# nothing\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "# nothing" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a failing tee returns 1 and applies nothing" {
  export HAS_DOCKER=1
  _inotify_live 128
  export MOCK_TEE_EXIT=1
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"write failed"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a tee that exits 0 but writes nothing is caught by the read-back" {
  export HAS_DOCKER=1
  _inotify_live 128
  # An existing stale conf keeps the file readable, so the failure is the value check.
  printf 'fs.inotify.max_user_instances = 512\n' > "${_SYSCTL_CONF}"
  printf '#!/usr/bin/env bash\ncat > /dev/null\nexit 0\n' > "${SHIM_DIR}/tee"
  /bin/chmod +x "${SHIM_DIR}/tee"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"read-back mismatch (${_SYSCTL_CONF})"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a tee that writes then locks the conf reports cannot read back" {
  # root reads mode-000 files, so the read-back never fails there.
  [ "$(id -u)" -ne 0 ] || skip "root can read a mode-000 file"
  export HAS_DOCKER=1
  _inotify_live 128
  printf '#!/usr/bin/env bash\nfor _a in "$@"; do _f="${_a}"; done\ncat > "${_f}"\nchmod 000 "${_f}"\nexit 0\n' > "${SHIM_DIR}/tee"
  /bin/chmod +x "${SHIM_DIR}/tee"
  run --separate-stderr _install_ubuntu_inotify
  chmod 600 "${_SYSCTL_CONF}" 2> /dev/null || true
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read back"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a failing sysctl returns 1 and says apply failed" {
  export HAS_DOCKER=1
  _inotify_live 128
  export MOCK_SYSCTL_STUB_EXIT=1
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"apply failed (_SYSCTL_BIN set, ran without sudo)"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 1024" ]
}

@test "inotify: conf 1024 with live 4096 is raised to 4096 and never applies" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 1024\n' > "${_SYSCTL_CONF}"
  _inotify_live 4096
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 4096" ]
  [[ "$output" == *"inotify: persisted 4096 to ${_SYSCTL_CONF} (was 1024)"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: conf 8192 with live 4096 stays byte-identical and says already" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 8192\n' > "${_SYSCTL_CONF}"
  _inotify_live 4096
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 8192" ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
  [[ "$output" != *"persisted"* ]]
}

@test "inotify: conf 512 with live 2048 is raised to 2048" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 512\n' > "${_SYSCTL_CONF}"
  _inotify_live 2048
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 2048" ]
  [[ "$output" == *"inotify: persisted 2048 to ${_SYSCTL_CONF} (was 512)"* ]]
}

@test "inotify: an unreadable live value with no conf returns 1 and writes nothing" {
  export HAS_DOCKER=1
  rm -f "${_INOTIFY_PROC}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"inotify: cannot read live value ${_INOTIFY_PROC}"* ]]
  [ ! -e "${_SYSCTL_CONF}" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: live 2147483648 returns 1 and writes no conf" {
  export HAS_DOCKER=1
  _inotify_live 2147483648
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read live value"* ]]
  [ ! -e "${_SYSCTL_CONF}" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a 20-digit live value that wraps to 0 returns 1 and writes no conf" {
  export HAS_DOCKER=1
  _inotify_live 18446744073709551616
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read live value"* ]]
  [ ! -e "${_SYSCTL_CONF}" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: live 2147483647 with no conf is accepted and persisted" {
  export HAS_DOCKER=1
  _inotify_live 2147483647
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 2147483647" ]
  [[ "$output" == *"inotify: conf written (2147483647)"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a conf above INT_MAX is unparseable and untouched" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 3000000000\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 3000000000" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a conf at INT_MAX is parsed, and 4096 then a non-numeric last line is unparseable" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 2147483647\n' > "${_SYSCTL_CONF}"
  _inotify_live 4096
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
  printf 'fs.inotify.max_user_instances = 2048\nfs.inotify.max_user_instances = abc\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "$(printf 'fs.inotify.max_user_instances = 2048\nfs.inotify.max_user_instances = abc')" ]
}

@test "inotify: a valid line then an empty right-hand side is unparseable; abc then 2048 reads 2048" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 2048\nfs.inotify.max_user_instances =\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  printf 'fs.inotify.max_user_instances = abc\nfs.inotify.max_user_instances = 2048\n' > "${_SYSCTL_CONF}"
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
}

@test "inotify: with _SYSCTL_BIN set apply runs the seam without sudo" {
  export HAS_DOCKER=1
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  grep -q '^sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
  [ "$(grep -c "^sudo .*${_SYSCTL_BIN} -w" "${MOCK_CALLS_FILE}" || true)" -eq 0 ]
  [[ "$output" == *"inotify: applied"* ]]
}

@test "inotify: with _SYSCTL_BIN unset apply goes through sudo sysctl -w" {
  export HAS_DOCKER=1
  _inotify_live 128
  unset _SYSCTL_BIN
  local stub="${BATS_TEST_TMPDIR}/pathstub"
  mkdir -p "${stub}"
  printf '#!/usr/bin/env bash\nprintf "STUB-MARKER-7f3a9c %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 0\n' > "${stub}/sysctl"
  chmod +x "${stub}/sysctl"
  PATH="${stub}:${PATH}"
  [ "$(command -v sysctl)" = "${stub}/sysctl" ]
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  grep -q '^STUB-MARKER-7f3a9c -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
  grep -q '^sudo sysctl -w fs.inotify.max_user_instances=1024$' "${MOCK_CALLS_FILE}"
  [[ "$output" == *"inotify: applied"* ]]
}

@test "inotify: a failing sudo sysctl with the seam unset says plain apply failed" {
  export HAS_DOCKER=1
  _inotify_live 128
  unset _SYSCTL_BIN
  local stub="${BATS_TEST_TMPDIR}/pathstub"
  mkdir -p "${stub}"
  printf '#!/usr/bin/env bash\nprintf "STUB-MARKER-7f3a9c %%s\\n" "$*" >> "${MOCK_CALLS_FILE}"\nexit 1\n' > "${stub}/sysctl"
  chmod +x "${stub}/sysctl"
  PATH="${stub}:${PATH}"
  [ "$(command -v sysctl)" = "${stub}/sysctl" ]
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  grep -q '^STUB-MARKER-7f3a9c ' "${MOCK_CALLS_FILE}"
  [[ "$stderr" == *"inotify: apply failed"* ]]
  [[ "$stderr" != *"_SYSCTL_BIN"* ]]
}

@test "inotify: a tee that writes 1024 when the target is 4096 reports a read-back mismatch" {
  export HAS_DOCKER=1
  _inotify_live 4096
  printf '#!/usr/bin/env bash\nfor _a in "$@"; do _f="${_a}"; done\nprintf "fs.inotify.max_user_instances = 1024\\n" > "${_f}"\nexit 0\n' > "${SHIM_DIR}/tee"
  /bin/chmod +x "${SHIM_DIR}/tee"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"read-back mismatch (${_SYSCTL_CONF})"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 1024" ]
}

@test "inotify: HAS_DOCKER unset skips with a reason and touches nothing" {
  unset HAS_DOCKER
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [[ "$output" == *"inotify: skipped"* ]]
  [ ! -e "${_SYSCTL_CONF}" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a missing systemd run dir skips with a reason and touches nothing" {
  export HAS_DOCKER=1
  rmdir "${_SYSTEMD_RUN_DIR}"
  _inotify_live 128
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [[ "$output" == *"inotify: skipped"* ]]
  [ ! -e "${_SYSCTL_CONF}" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "install_ubuntu_packages: a failing inotify step is named, rc 2, and later steps still run" {
  unset MACOS
  export LINUX=1 UBUNTU=1 NOBLE=1
  _install_ubuntu_base_packages() { :; }
  _install_ubuntu_inotify() { printf 'ran inotify\n' >> "${MOCK_CALLS_FILE}"; return 1; }
  local _s
  for _s in workstation powershell go docker nvidia k8s_tools hashicorp cloud_tools brew_packages rust gui_tools misc; do
    eval "_install_ubuntu_${_s}() { printf 'ran ${_s}\\n' >> \"\${MOCK_CALLS_FILE}\"; }"
  done
  run --separate-stderr install_ubuntu_packages
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"failed: inotify"* ]]
  [ "$(grep -c '^ran ' "${MOCK_CALLS_FILE}")" -eq 13 ]
  [ "$(grep '^ran ' "${MOCK_CALLS_FILE}" | head -1)" = "ran inotify" ]
}

@test "inotify: a leading-zero conf value is unparseable and untouched" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 08\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 08" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a 20-digit conf value is unparseable and untouched" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances = 99999999999999999999\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances = 99999999999999999999" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: a longer key name is not the instances key" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances_extra = 5\n' > "${_SYSCTL_CONF}"
  run --separate-stderr _install_ubuntu_inotify
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"unparseable"* ]]
  [ "$(cat "${_SYSCTL_CONF}")" = "fs.inotify.max_user_instances_extra = 5" ]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}

@test "inotify: tabs around the equals sign and trailing are accepted" {
  export HAS_DOCKER=1
  printf 'fs.inotify.max_user_instances\t=\t2048\t\n' > "${_SYSCTL_CONF}"
  _inotify_live 2048
  run _install_ubuntu_inotify
  [ "$status" -eq 0 ]
  [ "$(cat "${_SYSCTL_CONF}")" = "$(printf 'fs.inotify.max_user_instances\t=\t2048\t')" ]
  [[ "$output" == *"inotify: already 1024 or higher"* ]]
  [ "$(_inotify_sysctl_calls)" -eq 0 ]
}
