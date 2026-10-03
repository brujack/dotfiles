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
  # The azure-cli migration probes the brew az. tests/mocks/brew prints nothing
  # for `--prefix`, so without this seam the code would exec /bin/az -- on a
  # machine with the apt package that is the REAL az (tdd.md E2).
  export _BREW_AZ_BIN="${BATS_TEST_TMPDIR}/brew-az"
  printf '#!/usr/bin/env bash\nprintf "brew-az %%s\\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"\nexit "${MOCK_BREW_AZ_EXIT:-0}"\n' > "${_BREW_AZ_BIN}"
  chmod +x "${_BREW_AZ_BIN}"
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
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
  grep -qE '^frontend: dpkg -i .*DEBIAN_FRONTEND=noninteractive$' "${MOCK_CALLS_FILE}"
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
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
  grep -q "dpkg -i" "${MOCK_CALLS_FILE}"
  grep -q "apt update" "${MOCK_CALLS_FILE}"
  grep -qE "apt install powershell" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: wget failure warns naming wget and skips dpkg/apt" {
  export MOCK_WGET_EXIT=1
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"wget"* ]]
  refute_grep "dpkg -i" "${MOCK_CALLS_FILE}"
  refute_grep "^apt " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: dpkg failure warns naming dpkg and skips apt" {
  export MOCK_DPKG_EXIT=1
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"dpkg"* ]]
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
  refute_grep "^apt " "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: apt update failure warns naming apt update and skips apt install" {
  export MOCK_APT_EXIT=1
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"apt install"* ]]
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

  [ "$status" -eq 0 ]
  [ "${_elapsed}" -lt 20 ]
  [[ "$output" == *"apt install succeeded but pwsh still does not run"* ]]
}

# ── _install_ubuntu_go ───────────────────────────────────────────────────────

@test "_install_ubuntu_go: any version calls wget for tarball (no PPA path)" {
  export GO_VER="1.20"
  export GO_DOWNLOAD_FILENAME="go1.20.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.20.linux-amd64.tar.gz"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "wget.*${GO_DOWNLOAD_FILENAME}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: version >=1.21 calls wget for tarball" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "wget.*${GO_DOWNLOAD_FILENAME}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: version >=1.21 skips wget when tarball already exists" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  touch "${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME}"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  ! grep -q "wget.*${GO_DOWNLOAD_FILENAME}" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_go: prints success when go version matches after install" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  # Pre-create tarball so wget/tar are skipped
  touch "${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME}"
  # Fake go binary that reports matching version
  local _bin_dir="${BATS_TEST_TMPDIR}/gobin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\nprintf "go version go1.26 linux/amd64\\n"\n' > "${_bin_dir}/go"
  chmod +x "${_bin_dir}/go"
  export PATH="${_bin_dir}:${PATH}"
  # PATH alone does not reach this function: _install_ubuntu_go prefers the
  # absolute /usr/local/go/bin/go when it exists, deliberately, because that
  # path reaches PATH only via 6_path.zsh and a provision run is not
  # interactive. So on any box with Go actually installed the stub above is
  # bypassed and the real `go version` answers -- measured 2026-09-18 on claude
  # and workstation (both go1.27.1), where this test failed while passing on
  # macOS, which has no /usr/local/go/bin/go. That is shell.md's
  # absolute-path-default pitfall, and `make test` failing here means the
  # pre-push hook refuses every source push from those two boxes.
  #
  # _GO_BIN is the seam the function already reads for exactly this; the test
  # at the foot of this file has always set it.
  export _GO_BIN="${_bin_dir}/go"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  [[ "$output" == *"Go 1.26 is installed"* ]]
}

@test "_install_ubuntu_go: any version succeeds (no version range guard)" {
  export GO_VER="1.99"
  export GO_DOWNLOAD_FILENAME="go1.99.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.99.linux-amd64.tar.gz"
  run _install_ubuntu_go
  [ "$status" -eq 0 ]
  grep -q "wget.*${GO_DOWNLOAD_FILENAME}" "${MOCK_CALLS_FILE}"
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

@test "_install_go_from_tarball: moves software_downloads/go to /usr/local/go when present" {
  export GO_VER="1.26"
  export GO_DOWNLOAD_FILENAME="go1.26.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://dl.google.com/go/go1.26.linux-amd64.tar.gz"
  mkdir -p "${HOME}/software_downloads/go"
  export MOCK_SUDO_EXIT=1
  run _install_go_from_tarball
  [ "$status" -eq 0 ]
  grep -q "sudo mv.*software_downloads/go" "${MOCK_CALLS_FILE}"
}

@test "_install_go_from_tarball: wget failure returns non-zero and does not call sudo rm -rf" {
  export GO_VER="1.27"
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://go.dev/dl/go1.27.1.linux-amd64.tar.gz"
  export MOCK_WGET_EXIT=1
  run _install_go_from_tarball
  [ "$status" -ne 0 ]
  ! grep -qF "sudo rm -rf /usr/local/go" "${MOCK_CALLS_FILE}"
}

@test "_install_go_from_tarball: tar failure returns non-zero and does not call sudo rm -rf" {
  export GO_VER="1.27"
  export GO_DOWNLOAD_FILENAME="go1.27.1.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://go.dev/dl/go1.27.1.linux-amd64.tar.gz"
  export MOCK_TAR_EXIT=1
  run _install_go_from_tarball
  [ "$status" -ne 0 ]
  ! grep -qF "sudo rm -rf /usr/local/go" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_docker ───────────────────────────────────────────────────

@test "_install_ubuntu_docker: HAS_DOCKER unset does nothing" {
  unset HAS_DOCKER
  run _install_ubuntu_docker
  [ "$status" -eq 0 ]
  ! grep -q "apt install docker-ce" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_docker: HAS_DOCKER set installs docker-ce" {
  export HAS_DOCKER=1
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

# ── _install_ubuntu_k8s_tools ────────────────────────────────────────────────

@test "_install_ubuntu_k8s_tools: HAS_K8S calls wget for kind" {
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  unset HAS_SNAP
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  grep -q "wget.*kind" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: HAS_K8S skips kind wget when already downloaded" {
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  touch "${HOME}/software_downloads/kind_0.22.0"
  unset HAS_SNAP
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  ! grep -q "wget.*kind_0.22.0" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: no HAS_K8S skips kind and telepresence" {
  unset HAS_K8S HAS_SNAP
  export KUBERNETES_VER="v1.29"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  ! grep -q "wget.*kind" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: removes stale helm-stable-debian.list before apt update" {
  # baltocdn sources.list.d file written by pre-PR#155 runs must be purged so
  # apt-get update does not hit the NOSPLIT/unsigned repo on subsequent runs.
  unset HAS_SNAP HAS_K8S
  export KUBERNETES_VER="v1.29"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  run grep -q "rm.*helm-stable-debian.list" "${MOCK_CALLS_FILE}"
  [ "$status" -eq 0 ]
}

@test "_install_ubuntu_k8s_tools: HAS_SNAP installs helm via snap" {
  export HAS_SNAP=1
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  grep -q "snap install helm" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_k8s_tools: does not call get-helm-3 curl installer" {
  # helm curl installer removed; brew handles the no-snap case via
  # _install_ubuntu_brew_packages.
  unset HAS_SNAP
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
  run _install_ubuntu_k8s_tools
  [ "$status" -eq 0 ]
  run grep "get-helm-3" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_k8s_tools: does not call install_kustomize curl installer" {
  # kustomize curl installer removed; brew handles it via
  # _install_ubuntu_brew_packages.
  export HAS_K8S=1
  export KIND_VER="0.22.0"
  export KIND_URL="https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
  export KUBERNETES_VER="v1.29"
  export TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
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

@test "_install_ubuntu_hashicorp: calls wget for consul when dir does not exist" {
  export CONSUL_VER="1.17.0"
  export VAULT_VER="1.15.0"
  export NOMAD_VER="1.7.0"
  export PACKER_VER="1.10.0"
  export VAGRANT_VER="2.4.0"
  export HASHICORP_URL="https://releases.hashicorp.com"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "wget.*consul" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: skips consul wget when dir already exists" {
  export CONSUL_VER="1.17.0"
  export VAULT_VER="1.15.0"
  export NOMAD_VER="1.7.0"
  export PACKER_VER="1.10.0"
  export VAGRANT_VER="2.4.0"
  export HASHICORP_URL="https://releases.hashicorp.com"
  mkdir -p "${HOME}/software_downloads/consul_1.17.0"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  ! grep -q "wget.*consul_1.17.0" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: uses _LINUX_ARCH in consul URL (arm64)" {
  export CONSUL_VER="2.0.0"
  export VAULT_VER="2.0.2"
  export NOMAD_VER="2.0.3"
  export PACKER_VER="1.15.4"
  export VAGRANT_VER="2.4.9"
  export HASHICORP_URL="https://releases.hashicorp.com"
  export _LINUX_ARCH="arm64"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "consul.*arm64" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_hashicorp: vagrant always uses amd64 regardless of _LINUX_ARCH" {
  export CONSUL_VER="2.0.0"
  export VAULT_VER="2.0.2"
  export NOMAD_VER="2.0.3"
  export PACKER_VER="1.15.4"
  export VAGRANT_VER="2.4.9"
  export HASHICORP_URL="https://releases.hashicorp.com"
  export _LINUX_ARCH="arm64"
  run _install_ubuntu_hashicorp
  [ "$status" -eq 0 ]
  grep -q "vagrant.*amd64" "${MOCK_CALLS_FILE}"
}

# ── _install_ubuntu_cloud_tools ──────────────────────────────────────────────

@test "_install_ubuntu_cloud_tools: installs google-cloud-cli packages, not retired google-cloud-sdk names" {
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
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
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: no HAS_DEVTOOLS skips teleport" {
  unset HAS_DEVTOOLS
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  ! grep -q "apt install teleport" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: cf-terraforming filename uses _LINUX_ARCH" {
  export CF_TERRAFORMING_VER="0.27.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.27.0/cf-terraforming_0.27.0_linux_arm64.tar.gz"
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
  export _CF_SOURCES_LIST="${BATS_TEST_TMPDIR}/cloudflare.list"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "noble" "${_CF_SOURCES_LIST}"
  run grep "resolute" "${_CF_SOURCES_LIST}"
  [ "$status" -ne 0 ]
}

# ── azure-cli via linuxbrew ──────────────────────────────────────────────────

_az_cloud_env() {
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING} (gpg missing or failed on"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING} (gpg missing or failed on"* ]]
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING}"* ]]
  [[ "$output" == *"fingerprint"* ]]
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
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING}"* ]]
  [ ! -e "${_EDGE_SOURCES_DIR}/microsoft-edge.list" ]
  [ ! -e "${_EDGE_BOOTSTRAP_KEYRING}" ]
}

@test "_install_ubuntu_edge_source: fails closed when gpg is missing" {
  printf 'deb stale\n' > "${_EDGE_SOURCES_DIR}/microsoft-edge.list"
  _MS_GPG_BIN=/nonexistent/gpg run _install_ubuntu_edge_source
  [ "$status" -eq 0 ]
  [[ "$output" == *"edge: could not build ${_EDGE_BOOTSTRAP_KEYRING} (gpg missing or failed on"* ]]
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
  touch "${HOME}/software_downloads/docker-compose_2.24.0"
  unset HAS_DEVTOOLS
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  ! grep -q "wget.*docker-compose_2.24.0" "${MOCK_CALLS_FILE}"
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
  grep -qF "wget -O ${HOME}/software_downloads/yq_${YQ_VER} ${YQ_URL}" "${MOCK_CALLS_FILE}"
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
  export MOCK_APT_EXIT=1
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
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
  grep -q "mkdir.*-p.*/etc/apt/keyrings" "${MOCK_CALLS_FILE}"
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

# ── Ubuntu 26.04 (resolute) provisioning gaps, both measured on `claude` ─────

@test "_install_ubuntu_powershell: RESOLUTE pins the Microsoft config to 24.04" {
  export RESOLUTE=1
  # The harness default is 24.04, which would make this assertion match the
  # DEFAULT rather than the fix. Force the mock to report resolute so unfixed
  # code builds a 26.04 URL and this test can actually go red.
  export MOCK_LSB_RELEASE_RS="26.04"
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
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

@test "_build_pinned_keyring: gpg exiting non-zero returns 2 and leaves the existing keyring untouched" {
  _seed_ring
  printf 'old' > "${BATS_TEST_TMPDIR}/expect"
  printf '#!/usr/bin/env bash\nexit 2\n' > "${BATS_TEST_TMPDIR}/gpg-fail"
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
  for _s in workstation powershell go docker nvidia k8s_tools hashicorp cloud_tools brew_packages rust misc; do
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
