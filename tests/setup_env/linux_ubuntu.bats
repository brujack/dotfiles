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
  # Seed a rustup at the path _install_rustup_rs guards on, at SETUP scope. Without
  # it every _install_ubuntu_rust test enters the install path against a fake HOME
  # and attempts to download rustup-init -- tdd.md E2, a test whose FAILING branch
  # reaches outside the repo. Setup scope rather than per-test, so the trap is not
  # re-armed by the next test added to this file. These tests are about Rust
  # CONFIGURATION; _install_rustup_rs has its own tests, which drive the seams.
  mkdir -p "${HOME}/.cargo/bin"
  cp "${REPO_ROOT}/tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
  chmod +x "${HOME}/.cargo/bin/rustup"
  # Truncate AFTER seeding: cp and chmod are pass-through mocks that log their own
  # invocation, so the seed writes a line containing "rustup" into the call log and
  # breaks any test asserting that string is absent. Every test already assumes it
  # starts from an empty log; this makes that invariant explicit rather than luck.
  : > "${MOCK_CALLS_FILE}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── _install_ubuntu_base_packages ────────────────────────────────────────────

@test "_install_ubuntu_base_packages: installs hwe-24.04" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "apt install.*linux-generic-hwe-24.04" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: HAS_SNAP installs workstation snap packages" {
  export NOBLE=1
  unset RESOLUTE
  export HAS_SNAP=1
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  grep -q "snap install" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_base_packages: no HAS_SNAP skips snap install" {
  export NOBLE=1
  unset RESOLUTE HAS_SNAP
  run _install_ubuntu_base_packages
  [ "$status" -eq 0 ]
  ! grep -q "snap install" "${MOCK_CALLS_FILE}"
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

@test "_install_ubuntu_base_packages: HAS_SNAP uses nala for workstation packages" {
  cd "${REPO_ROOT}"
  export NOBLE=1
  export HAS_SNAP=1
  unset RESOLUTE
  run _install_ubuntu_base_packages
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

# ── _install_ubuntu_powershell ───────────────────────────────────────────────

@test "_install_ubuntu_powershell: calls wget for packages-microsoft-prod.deb" {
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_powershell: skips wget when deb already downloaded" {
  touch "${HOME}/software_downloads/packages-microsoft-prod.deb"
  run _install_ubuntu_powershell
  [ "$status" -eq 0 ]
  ! grep -q "wget.*packages-microsoft-prod.deb" "${MOCK_CALLS_FILE}"
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
  # The old form (`claude plugins install <bare-name>`) registered at PROJECT scope
  # against whatever cwd the run had, so `claude plugins update` later reported
  # "not installed at scope user" for 12 plugins and failed the update's claude
  # section. Measured on claude 2026-09-12.
  export HAS_DEVTOOLS=1
  run _install_ubuntu_brew_packages
  grep -q "plugin install -s user superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
  refute_grep "plugins install superpowers$" "${MOCK_CALLS_FILE}"
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

@test "_install_ubuntu_cloud_tools: always calls apt install azure-cli" {
  export CF_TERRAFORMING_VER="0.13.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.13.0/cf-terraforming_0.13.0_linux_amd64.tar.gz"
  unset HAS_DEVTOOLS
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q "apt install azure-cli" "${MOCK_CALLS_FILE}"
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

@test "_install_ubuntu_cloud_tools: azure-cli APT stanza uses dpkg --print-architecture" {
  export CF_TERRAFORMING_VER="0.27.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.27.0/cf-terraforming_0.27.0_linux_arm64.tar.gz"
  export MOCK_DPKG_PRINT_ARCH="arm64"
  unset HAS_DEVTOOLS
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q 'add-apt-repository.*arch=arm64.*azure-cli' "${MOCK_CALLS_FILE}"
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

@test "_install_ubuntu_cloud_tools: on RESOLUTE uses noble for azure-cli repo" {
  export RESOLUTE=1
  unset HAS_DEVTOOLS
  export CF_TERRAFORMING_VER="0.27.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.27.0/cf-terraforming_0.27.0_linux_amd64.tar.gz"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  grep -q 'add-apt-repository.*azure-cli.*noble' "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_cloud_tools: removes stale azure-cli sources before add-apt-repository" {
  # add-apt-repository appends new dist lines rather than replacing old ones,
  # leaving a 'resolute' entry alongside the new 'noble' entry; the stale entry
  # causes apt-get update to 404 on every subsequent run.
  unset HAS_DEVTOOLS
  export CF_TERRAFORMING_VER="0.27.0"
  export CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v0.27.0/cf-terraforming_0.27.0_linux_amd64.tar.gz"
  run _install_ubuntu_cloud_tools
  [ "$status" -eq 0 ]
  # Both the add-apt-repository auto-named file and a canonical azure-cli.list
  # must be purged so no stale codename persists in apt sources.
  run grep -E "rm.*(packages.microsoft.com_repos_azure-cli|azure-cli).*\.list" "${MOCK_CALLS_FILE}"
  [ "$status" -eq 0 ]
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
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  grep -q "apt install albert" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_gui_tools: no HAS_SNAP skips albert and edge" {
  unset HAS_SNAP HAS_DEVTOOLS
  run _install_ubuntu_gui_tools
  [ "$status" -eq 0 ]
  refute_grep "apt install albert" "${MOCK_CALLS_FILE}"
  refute_grep "apt install microsoft-edge-stable" "${MOCK_CALLS_FILE}"
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
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "wget.*yq" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: no HAS_DEVTOOLS skips yq" {
  unset HAS_DEVTOOLS
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  ! grep -q "wget.*yq" "${MOCK_CALLS_FILE}"
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

@test "_install_ubuntu_misc: HAS_DEVTOOLS attempts dotnet-sdk-8.0 install" {
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  grep -q "apt install dotnet-sdk-8.0" "${MOCK_CALLS_FILE}"
}

@test "_install_ubuntu_misc: dotnet install failure is non-fatal" {
  # dotnet-sdk-8.0 is missing on resolute; a failed install must warn, not abort.
  export DOCKER_COMPOSE_VER="2.24.0"
  export DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64"
  export YQ_VER="4.40.5"
  export YQ_URL="https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64"
  export HAS_DEVTOOLS=1
  export MOCK_APT_EXIT=1
  run _install_ubuntu_misc
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotnet-sdk-8.0 not available"* ]]
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
