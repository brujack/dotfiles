#!/usr/bin/env bash
# lib/linux_ubuntu.sh — Ubuntu-specific install functions

# install_ubuntu_packages -- 0 when every step succeeded, 1 when the base
# step hit an unsupported release (nothing else runs), 2 when any step failed,
# base included (_install_ubuntu_base_packages returns 2 for a failed install).
# Every step after the base packages runs regardless of the others, and the
# failed ones are named on stderr: most steps return whatever their LAST
# command returned, so chaining them with `|| return 1` let one flaky
# third-party repo abort every later step and, through run_setup_or_developer,
# the whole pyenv/ansible half. _install_ubuntu_brew_packages is itself
# tri-state; its rc 2 counts as a failed step here too.
install_ubuntu_packages() {
  local -a _failed=()
  local _base_rc=0 _docker_core=0
  _install_ubuntu_base_packages || _base_rc=$?
  ((_base_rc == 1)) && return 1
  ((_base_rc == 0)) || _failed+=(base)
  local _step
  # Order matters: the nvidia container toolkit configures docker's runtime,
  # so nvidia runs after docker and is skipped when docker's core failed (rc 3),
  # driver install included. It would otherwise rewrite a daemon.json docker's own
  # step rejected, then restart docker on a box running live CI runners.
  for _step in workstation powershell go docker nvidia k8s_tools hashicorp \
    cloud_tools brew_packages rust gui_tools misc; do
    if [[ ${_step} == nvidia ]] && ((_docker_core == 1)); then
      printf 'ubuntu packages: skipping nvidia because docker failed\n' >&2
      _failed+=("${_step}")
      continue
    fi
    local _step_rc=0
    "_install_ubuntu_${_step}" || _step_rc=$?
    if ((_step_rc != 0)); then
      _failed+=("${_step}")
      # Only docker's rc 3 (a core install or daemon.json failure) skips nvidia;
      # a failed plugin or usermod leaves docker usable for the toolkit.
      if [[ ${_step} == docker ]] && ((_step_rc == 3)); then
        _docker_core=1
      fi
    fi
  done

  if ((${#_failed[@]} > 0)); then
    printf 'ubuntu packages: failed: %s\n' "${_failed[*]}" >&2
    return 2
  fi
  return 0
}

# Install the packages named in a list file, skipping comments and blank lines.
# A missing list is a failure; a list with no packages is not (xargs -r then
# runs nothing). The grep|xargs status is read from PIPESTATUS, which the very
# next line must copy: any command in between, `local` included, resets it.
_install_ubuntu_package_list() {
  local _list="$1"
  [[ -r ${_list} ]] || return 1
  grep -vE '^[[:space:]]*(#|$)' "${_list}" | xargs -r sudo DEBIAN_FRONTEND=noninteractive nala install "${APT_CONFFILE_OPTS[@]}" -y
  local -a _ps=("${PIPESTATUS[@]}")
  # grep exits 1 for "no lines selected", which is a legitimate empty list.
  ((_ps[0] <= 1 && _ps[1] == 0))
}

_install_ubuntu_base_packages() {
  local _release _hwe
  if [[ -n ${NOBLE} ]]; then
    _release=2404
    _hwe=linux-generic-hwe-24.04
    printf "Installing hwe, common, and 24.04 packages\\n"
  elif [[ -n ${RESOLUTE} ]]; then
    _release=2604
    _hwe=linux-generic-hwe-26.04
    printf "Installing hwe, common, and 26.04 packages\\n"
  else
    log_error "Unsupported Ubuntu version: ${UBUNTU_VERSION:-unknown}"
    return 1
  fi

  # A failed update is one warning, not a failure: the installs below still
  # work from the cached indexes, and apt names the offending source itself.
  sudo -H apt update || log_warn "base: apt update reported errors (see apt's E:/W: lines above); continuing"

  local -a _failed=()
  sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" --install-recommends "${_hwe}" -y || {
    log_warn "base: hwe kernel failed"
    _failed+=("hwe kernel")
  }
  check_and_install_nala || {
    log_warn "base: nala failed"
    _failed+=("nala")
  }
  # Strip comments/blank lines: xargs -a feeds every line to nala, and a
  # comment token like '--user' aborts the whole install ("No such option").
  _install_ubuntu_package_list ./ubuntu_common_packages.txt || {
    log_warn "base: common list failed"
    _failed+=("common list")
  }
  _install_ubuntu_package_list "./ubuntu_${_release}_packages.txt" || {
    log_warn "base: release list failed"
    _failed+=("release list")
  }
  ((${#_failed[@]} == 0)) || return 2
  return 0
}

# The HAS_SNAP workstation packages, split out of the base step so a flaky
# snap is one failed step rather than a failed base.
_install_ubuntu_workstation() {
  [[ -n ${HAS_SNAP} ]] || return 0
  # rc 1 when either list failed; both are attempted regardless.
  local _ws_rc=0
  printf "Installing workstation packages\\n"
  _install_ubuntu_package_list ./ubuntu_workstation_packages.txt || {
    log_warn "workstation: package list failed"
    _ws_rc=1
  }

  printf "Installing workstation snap packages\\n"
  # Same PIPESTATUS shape as _install_ubuntu_package_list: copy it on the very
  # next line, and read grep's 1 ("no lines selected") as an empty list.
  grep -vE '^[[:space:]]*(#|$)' ./ubuntu_workstation_snap_packages.txt | xargs -r sudo snap install
  local -a _ps=("${PIPESTATUS[@]}")
  ((_ps[0] <= 1 && _ps[1] == 0)) || {
    log_warn "workstation: snap list failed"
    _ws_rc=1
  }
  ((_ws_rc == 0)) || return 1
  return 0
}

# Whether pwsh actually runs, bounded by `timeout` so a hung binary cannot
# block install_ubuntu_packages -- and therefore the whole -t setup/
# -t developer run -- indefinitely. Mirrors _doctor_check_dev_tools's
# identical probe/fallback shape in lib/helpers.sh: an absent `timeout`
# degrades to running the probe unbounded rather than failing outright,
# since every Ubuntu target this runs on ships coreutils by construction --
# the fallback exists for a shim-scoped test PATH, not an expected
# production gap.
_pwsh_probe_runs() {
  local _timeout_bin
  _timeout_bin="$(command -v timeout 2>/dev/null)"
  if [[ -n "${_timeout_bin}" ]]; then
    "${_timeout_bin}" "${_PWSH_PROBE_TIMEOUT:-10}" "${_PWSH_BIN:-pwsh}" -NoProfile -Command exit &>/dev/null
  else
    "${_PWSH_BIN:-pwsh}" -NoProfile -Command exit &>/dev/null
  fi
}

# _ms_verify_deb <deb> -- 0 when the .deb's debsig origin signature
# (_gpgorigin, over debian-binary + control.tar.gz + data.tar.gz) verifies
# against the vendored Microsoft key with the pinned fingerprint, else 1.
# packages-microsoft-prod.deb is installed as root, and Microsoft rewrites it
# in place per release, so a sha256 pin cannot work; the signature can.
# Seams: _MS_GPG_BIN, _MS_AR_BIN, _MS_KEY_PATH (defaults gpg, ar, the vendored
# key). Mirrors lib/developer.sh:_aws_verify_zip.
_ms_verify_deb() {
  local _deb="$1"
  command -v "${_MS_GPG_BIN:-gpg}" > /dev/null 2>&1 || {
    log_error "gpg not found; cannot verify packages-microsoft-prod.deb"
    return 1
  }
  command -v "${_MS_AR_BIN:-ar}" > /dev/null 2>&1 || {
    log_error "ar not found (binutils); cannot verify packages-microsoft-prod.deb"
    return 1
  }
  local _key="${_MS_KEY_PATH:-${DOTFILES_REPO_ROOT}/keys/microsoft.asc}"
  local _abs_deb
  _abs_deb="$(cd "$(dirname "${_deb}")" && pwd)/$(basename "${_deb}")"

  (
    _ring="$(mktemp -d)" || exit 1
    # gpg 2.x leaves gpg-agent and scdaemon bound to the homedir; see
    # _aws_verify_zip. EXIT in a subshell fires once with _ring in scope.
    trap 'gpgconf --homedir "${_ring}" --kill all >/dev/null 2>&1; rm -rf "${_ring}"' EXIT
    # The member list must be exactly the four signed-for members, in order.
    # dpkg reads the FIRST control.tar.* and data.tar.* it meets while `ar x`
    # keeps the LAST of a repeated name, so a genuine signed .deb with an evil
    # data.tar.xz, or evil members ahead of repeated genuine ones, would
    # otherwise verify here and install something else.
    local _members
    _members="$("${_MS_AR_BIN:-ar}" t "${_abs_deb}" 2> /dev/null | sed 's|/$||' | tr '\n' ' ')"
    case "${_members}" in
      "debian-binary control.tar.gz data.tar.gz _gpgorigin ") ;;
      "debian-binary control.tar.gz data.tar.gz ")
        log_error "packages-microsoft-prod.deb carries no signature (_gpgorigin); not installing"
        exit 1
        ;;
      *)
        log_error "packages-microsoft-prod.deb has unexpected members (${_members% }); not installing"
        exit 1
        ;;
    esac
    mkdir "${_ring}/deb" || exit 1
    # The member list is already known good, so this fails only when extraction
    # itself breaks: an I/O error, or an ar that exits 0 having extracted
    # nothing (Apple's, on GNU member names). cat catches the second.
    { (cd "${_ring}/deb" && "${_MS_AR_BIN:-ar}" x "${_abs_deb}") &&
      cat "${_ring}/deb/debian-binary" "${_ring}/deb/control.tar.gz" \
        "${_ring}/deb/data.tar.gz" > "${_ring}/signed"; } 2> /dev/null || {
      log_error "could not extract packages-microsoft-prod.deb; not installing"
      exit 1
    }
    "${_MS_GPG_BIN:-gpg}" --homedir "${_ring}" --batch --import "${_key}" \
      > /dev/null 2>&1 || { log_error "could not import ${_key}"; exit 1; }
    "${_MS_GPG_BIN:-gpg}" --homedir "${_ring}" --batch --status-fd 1 \
      --verify "${_ring}/deb/_gpgorigin" "${_ring}/signed" > "${_ring}/status" 2> /dev/null
    # Reject before accepting: VALIDSIG is emitted for a revoked or expired key
    # too, and gpg exits 0 for both.
    if grep -qE '^\[GNUPG:\] (REVKEYSIG|KEYREVOKED|EXPSIG|EXPKEYSIG|KEYEXPIRED)' "${_ring}/status"; then
      log_error "packages-microsoft-prod.deb: Microsoft key revoked or expired; not installing"
      exit 1
    fi
    if ! grep -q "^\[GNUPG:\] VALIDSIG ${MS_GPG_FPR} " "${_ring}/status"; then
      log_error "packages-microsoft-prod.deb signature did not verify against the Microsoft key; not installing"
      exit 1
    fi
    exit 0
  )
}

_install_ubuntu_powershell() {
  # Judge by whether pwsh RUNS, not merely resolves -- a box whose first
  # attempt hit the resolute gap below downloaded and dpkg -i'd the WRONG
  # config, leaving a `pwsh` that resolves via `command -v` but is absent or
  # broken. A presence-only guard would loop forever on that box.
  if _pwsh_probe_runs; then
    printf "pwsh is installed\\n"
    return 0
  fi

  printf "Installing powershell Ubuntu\\n"
  # Microsoft publishes a 26.04 config (HTTP 200) whose `resolute` dist carries
  # ZERO powershell packages -- measured 2026-09-12, against 54 in 24.04/noble.
  # So `apt install powershell` fails with "Unable to locate package" even
  # though every step before it succeeded. Unlike the WARP case
  # the fallback belongs on the CONFIG url, not on a dist codename.
  local _ms_rel="${_MS_CONFIG_REL:-$(lsb_release -rs)}"
  [[ -n "${RESOLUTE:-}" ]] && _ms_rel="24.04"

  # Independent of any pre-existing .deb: a box whose first attempt failed
  # (see above) left a stale/wrong .deb behind, and only a fresh download and
  # a fresh dpkg -i repair it -- measured on `claude`, 2026-09-17. Every step
  # below checks its own exit status, so one broken upstream repository warns
  # and returns 1 rather than aborting the whole bootstrap.
  if ! wget -O "${HOME}"/software_downloads/packages-microsoft-prod.deb \
    "https://packages.microsoft.com/config/ubuntu/${_ms_rel}/packages-microsoft-prod.deb"; then
    log_warn "powershell: wget for packages-microsoft-prod.deb failed; skipping"
    return 1
  fi

  if ! _ms_verify_deb "${HOME}"/software_downloads/packages-microsoft-prod.deb; then
    log_warn "powershell: packages-microsoft-prod.deb failed verification; skipping"
    return 1
  fi

  # --force-confmiss: this package carries only a vendor apt keyring/source, so
  # restoring a conffile the operator deleted is always right here. Without it a
  # deleted keyring stays missing and every later `apt update` fails (measured,
  # spec 2026-10-03-apt-conffile-noninteractive-design.md Decision table).
  # confmiss is used on these archive-setup debs only, nowhere else.
  if ! sudo -H DEBIAN_FRONTEND=noninteractive dpkg -i --force-confdef --force-confold --force-confmiss "${HOME}"/software_downloads/packages-microsoft-prod.deb; then
    log_warn "powershell: dpkg -i packages-microsoft-prod.deb failed; skipping"
    return 1
  fi

  if ! sudo apt update; then
    log_warn "powershell: apt update failed; skipping"
    return 1
  fi

  if ! sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" powershell -y; then
    log_warn "powershell: apt install powershell failed; skipping"
    return 1
  fi

  # apt exits 0 for "powershell is already the newest version" even when the
  # installed binary is broken -- the `claude` failure mode one level out.
  # Re-run the same execution check the guard opened with rather than
  # trusting apt's own exit status for this claim.
  if ! _pwsh_probe_runs; then
    log_warn "powershell: apt install succeeded but pwsh still does not run"
    return 1
  fi

  printf "pwsh is installed\\n"
}

# Install the pinned Go tarball into ${_GO_INSTALL_ROOT:-/usr/local}/go. The
# tarball is extracted in a throwaway directory under _DL_TMP_ROOT, chowned to
# root:root (tar ran as the user and a rename keeps ownership), then swapped in.
# The moves are renames only because ~/software_downloads and /usr/local share a
# filesystem on claude and workstation (measured); on a separate /home they
# become copies. Every move's destination is checked absent first instead of
# using `mv -T`, which macOS mv lacks and the test-macos job runs this suite.
# The previous tree is kept as go.old until the new one is in place and is
# restored if the new tree's move fails. The stamp `go` holds the URL and is
# written only after the swap succeeded, so an interrupted run installs again
# next time.
# Returns 0 installed or up to date; 1 on a failed stage (named in a warning).
# Seams, read at call time: _GO_INSTALL_ROOT, _DL_STAMP_DIR, _DL_TAR_BIN. The
# owner is hardcoded root:root so an inherited variable cannot choose it.
# No EXIT/RETURN trap (check-lib-exit-traps.sh; shell.md): every path after
# mktemp reaches the explicit sudo rm -rf below.
_install_go_from_tarball() {
  local _root="${_GO_INSTALL_ROOT:-/usr/local}"
  local _stamp="${_DL_STAMP_DIR:-${HOME}/.local/share/dotfiles/installed}/go"
  local _tmp _stage="" _moved=0

  if [[ -f ${_stamp} && -x ${_root}/go/bin/go && "$(< "${_stamp}")" == "${GO_DOWNLOAD_URL}" ]]; then
    printf 'go: up to date (stamp %s); rm it to force a re-install\n' "${_stamp}"
    return 0
  fi

  mkdir -p "${_DL_TMP_ROOT:-${HOME}/software_downloads}" || {
    log_warn "go: workdir failed"
    return 1
  }
  _tmp="$(mktemp -d "${_DL_TMP_ROOT:-${HOME}/software_downloads}/.dl.XXXXXXXX")" || {
    log_warn "go: workdir failed"
    return 1
  }

  if ! wget -O "${_tmp}/go.tgz" "${GO_DOWNLOAD_URL}"; then
    _stage="download"
  elif ! "${_DL_TAR_BIN:-tar}" -xzf "${_tmp}/go.tgz" -C "${_tmp}"; then
    _stage="extract"
  elif ! [[ -f ${_tmp}/go/bin/go && ! -L ${_tmp}/go/bin/go && -s ${_tmp}/go/bin/go ]]; then
    _stage="extract"
  elif ! sudo chown -R root:root "${_tmp}/go"; then
    _stage="chown"
  elif [[ ! -e ${_root}/go && ! -L ${_root}/go && ( -e ${_root}/go.old || -L ${_root}/go.old ) ]] \
    && ! sudo mv "${_root}/go.old" "${_root}/go"; then
    # A previous run's restore failed, so go.old may be the only good copy.
    _stage="restore"
  fi
  if [[ -z ${_stage} ]]; then
    # Reached with go.old either absent or beside a live go; it is stale now.
    if [[ -e ${_root}/go ]]; then
      sudo rm -rf "${_root}/go.old" || _stage="swap"
    fi
  fi
  if [[ -z ${_stage} && -e ${_root}/go ]]; then
    if [[ -e ${_root}/go.old || -L ${_root}/go.old ]] || ! sudo mv "${_root}/go" "${_root}/go.old"; then
      _stage="swap"
    else
      _moved=1
    fi
  fi
  if [[ -z ${_stage} ]]; then
    if [[ -e ${_root}/go || -L ${_root}/go ]] || ! sudo mv "${_tmp}/go" "${_root}/go"; then
      _stage="install"
      if [[ ${_moved} -eq 1 ]] \
        && { [[ -e ${_root}/go || -L ${_root}/go ]] || ! sudo mv "${_root}/go.old" "${_root}/go"; }; then
        log_warn "go: could not restore the previous tree; it is at ${_root}/go.old"
      fi
    elif [[ ${_moved} -eq 1 ]]; then
      sudo rm -rf "${_root}/go.old" || log_warn "go: could not remove ${_root}/go.old"
    fi
  fi
  sudo rm -rf "${_tmp}" || log_warn "go: could not remove ${_tmp}"
  if [[ -n ${_stage} ]]; then
    log_warn "go: ${_stage} failed"
    return 1
  fi

  if ! { mkdir -p "$(dirname "${_stamp}")" && printf '%s\n' "${GO_DOWNLOAD_URL}" > "${_stamp}"; } 2> /dev/null; then
    log_warn "go: could not write stamp ${_stamp}; it will be re-installed next run"
  fi
  return 0
}

_install_ubuntu_go() {
  printf "Installing Go Ubuntu\\n"
  # Best effort: the Go install below does not use apt, so a stale index here
  # must not block it (the base step reports apt update failures once).
  sudo -H apt update || :
  _install_go_from_tarball || return 1
  # /usr/local/go/bin reaches PATH only via 6_path.zsh, which interactive zsh
  # alone sources -- so during a provision this probe resolved nothing and
  # printed "go: command not found" twice. Prefer the absolute install path,
  # fall back to PATH so an existing `go` (and the suite's mock) still drives it.
  local _go_bin="${_GO_BIN:-}"
  if [[ -z "${_go_bin}" ]]; then
    if [[ -x ${_GO_INSTALL_ROOT:-/usr/local}/go/bin/go ]]; then _go_bin="${_GO_INSTALL_ROOT:-/usr/local}/go/bin/go"; else _go_bin=go; fi
  fi
  INSTALLED_GO_VER=$("${_go_bin}" version 2>/dev/null | awk '{print $3}' | sed 's/go//g')
  # GO_VER is a series ("1.27") while the toolchain reports a patch ("1.27.1").
  if [[ ${INSTALLED_GO_VER} == "${GO_VER}" || ${INSTALLED_GO_VER} == "${GO_VER}".* ]]; then
    printf "Go %s is installed\\n" "${GO_VER}"
  else
    log_warn "go: version check failed (installed ${INSTALLED_GO_VER:-none}, want ${GO_VER})"
    return 1
  fi
}

# Installs rustup.rs into ~/.cargo when absent, from a version-pinned rustup-init
# whose sha256 is verified BEFORE it is executed (ci.md's third-party binary rule);
# `curl … | sh` satisfies neither half.
#
# --no-modify-path is mandatory, not stylistic: rustup-init edits shell rc files by
# default, and on this fleet ~/.zshrc and ~/.zprofile are symlinks into this repo,
# so an unguarded run writes into the tracked working tree.
#
# Seams exist because every test runs against a fake HOME with no ~/.cargo/bin/rustup,
# so all of them would otherwise enter this path and reach the network — tdd.md E2.
# _RUSTUP_INIT_SHA256 is exposed rather than mocking sha256sum: there is no sha256sum
# mock, and supplying the expected digest keeps the real check running so a mismatch
# is genuinely exercised instead of stubbed away.
_install_rustup_rs() {
  local _cargo_bin="${_OVERRIDE_CARGO_BIN_DIR:-${HOME}/.cargo/bin}"
  if [[ -x "${_cargo_bin}/rustup" ]]; then
    return 0
  fi

  # Match on the machine type, normalising Apple's `arm64` to the kernel name
  # rustup publishes under. macOS never reaches this in production (the caller is
  # HAS_RUST + Ubuntu gated), but the bats suite runs on the Studio, and a case
  # statement that fails closed on the developer's own arch makes the suite
  # unrunnable locally for a reason that has nothing to do with the code.
  local _sha _machine
  _machine="$(uname -m)"
  case "${_machine}" in
    x86_64 | amd64) _sha="${RUSTUP_INIT_SHA256_X86_64}" ;;
    aarch64 | arm64) _sha="${RUSTUP_INIT_SHA256_AARCH64}" ;;
    *)
      log_error "no pinned rustup-init sha256 for ${_machine} — refusing an unverified download"
      return 1
      ;;
  esac
  _sha="${_RUSTUP_INIT_SHA256:-${_sha}}"

  local _tmp
  _tmp="$(mktemp -d)" || return 1

  if ! curl -fsSL -o "${_tmp}/rustup-init" "${_RUSTUP_INIT_URL:-${RUSTUP_INIT_URL}}"; then
    log_error "rustup-init download failed"
    rm -rf "${_tmp}"
    return 1
  fi

  if ! printf '%s  %s\n' "${_sha}" "${_tmp}/rustup-init" | sha256sum -c - > /dev/null 2>&1; then
    log_error "rustup-init sha256 mismatch — refusing to execute"
    rm -rf "${_tmp}"
    return 1
  fi

  chmod +x "${_tmp}/rustup-init" || {
    rm -rf "${_tmp}"
    return 1
  }

  if ! "${_RUSTUP_INIT_BIN:-${_tmp}/rustup-init}" -y --no-modify-path; then
    log_error "rustup-init failed"
    rm -rf "${_tmp}"
    return 1
  fi

  rm -rf "${_tmp}"
}

_install_ubuntu_rust() {
  if [[ -n ${HAS_RUST} ]]; then
    printf "Configuring Rust Ubuntu\\n"
    _install_rustup_rs || return 1
    if [[ -f ${HOME}/.cargo/env ]]; then
      . "${HOME}"/.cargo/env
    fi
    # Resolve explicitly rather than calling bare `rustup`: Homebrew also ships a
    # rustup on this fleet and it shadows ~/.cargo/bin on PATH, but brew builds it
    # with self-update compiled out, so `rustup self update` exits 1 there. Bare
    # calls would install the right binary and then not use it.
    local _rustup
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      _rustup="${HOME}/.cargo/bin/rustup"
    elif command -v rustup > /dev/null 2>&1; then
      _rustup="rustup"
    else
      log_warn "rustup not found; skipping Rust configuration"
      return 0
    fi
    "${_rustup}" self update || return 1
    "${_rustup}" update || return 1
    "${_rustup}" component add rust-analyzer || return 1
  fi
}

# Gated on HARDWARE, not on a profile capability. `claude` and `workstation` both
# map to linux_workstation, so a HAS_* flag would fire the driver install on any
# future GPU-less box with that profile, and on WSL2 where the driver lives on the
# Windows side. 10de is NVIDIA's PCI vendor ID.
_nvidia_gpu_present() {
  if [[ -n ${_OVERRIDE_NVIDIA_GPU_PRESENT+x} ]]; then
    return "${_OVERRIDE_NVIDIA_GPU_PRESENT}"
  fi
  lspci -nn 2> /dev/null | grep -qi '\[10de:'
}

# Driver comes from Ubuntu's own repo (610.57.04-0ubuntu0.26.04.3 on resolute), so
# it needs no third-party source. The container toolkit does, and that repo's GPG
# key is NOT checksum-pinned the way rustup-init is -- NVIDIA publishes no digest
# for it. The mitigation is `signed-by=`, which scopes the key to this one repo so
# it cannot vouch for anything else. Weaker than the rustup path, and recorded as a
# known limitation rather than left to look deliberate.
#
# Installing the driver does NOT bind it: nouveau holds the card until a reboot, so
# this warns rather than pretending success. Measured on claude 2026-09-12.
_install_ubuntu_nvidia() {
  if ! _nvidia_gpu_present; then
    return 0
  fi
  printf "Installing NVIDIA driver and container toolkit\\n"

  if ! dpkg -l "nvidia-driver-${NVIDIA_DRIVER_VER}" 2> /dev/null | grep -q '^ii'; then
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" -y "nvidia-driver-${NVIDIA_DRIVER_VER}" || return 1
    log_warn "NVIDIA driver installed — reboot required before the nvidia module replaces nouveau"
  fi

  local _keyring="${_OVERRIDE_NVIDIA_KEYRING:-${NVIDIA_CONTAINER_KEYRING}}"
  local _list="${_OVERRIDE_NVIDIA_LIST:-/etc/apt/sources.list.d/nvidia-container-toolkit.list}"

  if [[ ! -f ${_keyring} ]]; then
    _install_apt_keyring "${NVIDIA_CONTAINER_GPGKEY_URL}" "${_keyring}" armored || {
      log_warn "nvidia: keyring: install failed"
      return 1
    }
  fi

  if [[ ! -f ${_list} ]]; then
    # NVIDIA serves no per-release list -- ubuntu26.04 and ubuntu24.04 both 404 while
    # stable/deb returns 200 and is distro-agnostic. Measured 2026-09-12.
    # Fetched, rewritten and installed as three checked stages: in a pipe the
    # last command's status masks a failed fetch and an empty list gets written.
    local _ltmp
    _ltmp="$(mktemp -d "${_APT_KEY_TMP_ROOT:-${TMPDIR:-/tmp}}/nvidia-list.XXXXXXXX")" || return 1
    # shellcheck disable=SC2024 # the redirect is read by the invoking user on purpose: the throwaway dir is user-owned and sudo only needs the content on stdin
    if ! curl -fsSL -o "${_ltmp}/list" "${NVIDIA_CONTAINER_LIST_URL}" \
      || ! sed "s#deb https://#deb [signed-by=${_keyring}] https://#g" "${_ltmp}/list" > "${_ltmp}/list.signed" \
      || ! sudo -H tee "${_list}" < "${_ltmp}/list.signed" > /dev/null; then
      log_warn "nvidia: container toolkit source list failed"
      rm -rf "${_ltmp}"
      return 1
    fi
    rm -rf "${_ltmp}"
    sudo -H apt update || return 1
  fi

  if ! dpkg -l nvidia-container-toolkit 2> /dev/null | grep -q '^ii'; then
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" -y nvidia-container-toolkit || return 1
  fi

  # Installing the toolkit does NOT register it with docker. Measured on claude
  # 2026-09-12: with nvidia-container-toolkit 1.20.0 installed, `docker run --gpus
  # all` still failed `AMD CDI spec not found` -- an AMD-named error for a missing
  # NVIDIA runtime, which misdirects whoever reads it next. workstation had been
  # configured by hand and so never surfaced the gap.
  #
  # `runtime configure` merges rather than overwrites: verified with --dry-run
  # against a daemon.json already carrying exec-opts, which survived.
  #
  # Restart only when the config actually changed -- these boxes run GitHub
  # runners, and bouncing docker on every provision would kill a live job.
  local _daemon="${_OVERRIDE_DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
  local _before _after
  _before="$(sudo -H cat "${_daemon}" 2> /dev/null || true)"
  sudo -H nvidia-ctk runtime configure --runtime=docker || return 1
  _after="$(sudo -H cat "${_daemon}" 2> /dev/null || true)"
  if [[ ${_before} != "${_after}" ]]; then
    sudo -H systemctl restart docker || return 1
  fi
}

_install_ubuntu_docker() {
  [[ -n ${HAS_DOCKER} ]] || return 0
  printf "Installing docker\\n"
  # rc 3 when a core piece failed (docker-ce, docker-ce-cli, containerd.io or
  # daemon.json) -- install_ubuntu_packages skips nvidia on exactly that; rc 1
  # for any other failure (keyring, source, plugins, usermod); 0 otherwise.
  local _core=0 _other=0
  local _keyring="${_DOCKER_KEYRING:-/etc/apt/keyrings/docker.asc}"
  local _list="${_DOCKER_SOURCES_LIST:-/etc/apt/sources.list.d/docker.list}"
  local _pkg
  sudo mkdir -p "$(dirname "${_keyring}")"
  if [[ -f "$(dirname "${_keyring}")/docker.gpg" ]]; then
    sudo rm -f "$(dirname "${_keyring}")/docker.gpg"
  fi
  # A keyring or source failure does not stop the installs below: apt is the
  # authoritative check on whether the repo is usable.
  _install_apt_keyring https://download.docker.com/linux/ubuntu/gpg "${_keyring}" binary || {
    log_warn "docker: keyring: install failed"
    _other=1
  }
  printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "${_keyring}" "$(. /etc/os-release && echo "${VERSION_CODENAME}")" \
    | sudo tee "${_list}" > /dev/null || {
    log_warn "docker: source list: write failed"
    _other=1
  }
  # base owns the update warning; a failed refresh must not mask the install result.
  sudo -H apt update || :
  for _pkg in docker-ce docker-ce-cli containerd.io; do
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" "${_pkg}" -y || {
      log_warn "docker: ${_pkg}: install failed"
      _core=1
    }
  done
  for _pkg in docker-buildx-plugin docker-compose-plugin; do
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" "${_pkg}" -y || {
      log_warn "docker: ${_pkg}: install failed"
      _other=1
    }
  done
  local _daemon_json="${_DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
  if [[ ! -f ${_daemon_json} ]]; then
    printf "Configuring Docker for cgroup v2\\n"
    # SINGLE-quoted, so the escape is \n and not \\n. Every other printf in
    # this file is double-quoted -- `printf "Docker is installed\\n"` -- where
    # the shell collapses \\ to \ and printf then sees \n and emits a newline.
    # Inside single quotes nothing collapses: printf receives \\n, turns \\
    # into a literal backslash, and the n stays an n. The correct idiom
    # inverts when copied across the quoting boundary, and the result is
    # 46 bytes of valid JSON followed by two bytes of garbage.
    #
    # Measured on claude 2026-09-12: 48 bytes, `dockerd --validate` refusing
    # it with "invalid character '\\' after top-level value". It was latent
    # rather than visible -- dockerd had started before the file was written
    # and never re-read it -- so docker info, systemctl is-active and every
    # functional check passed, and only a cold start would have exposed it.
    # It surfaced when a second daemon (docker-ci) parsed the file on its own
    # cold start and restart-looped.
    if ! printf '{"exec-opts": ["native.cgroupdriver=systemd"]}\n' | \
      sudo tee "${_daemon_json}" > /dev/null; then
      log_warn "docker: daemon.json: write failed"
      _other=1
    fi
    # Write, then prove the artifact is loadable. The escaping bug above was
    # only half the defect: the write had no post-condition, so a file dockerd
    # could not parse looked identical to a good one. dockerd holds whatever
    # config it read at start, so `docker info`, `systemctl is-active` and
    # every functional check keep passing over a broken file -- the only
    # observable is a cold start, which may be days away and will land on
    # whoever reboots rather than on whoever provisioned.
    #
    # dockerd --validate is the authoritative reader and exits non-zero with
    # the parse error. _DOCKER_VALIDATE_BIN seams it for the suite, which runs
    # on macs where dockerd does not exist -- same absolute-binary problem
    # _OVERRIDE_KEYCHAIN_BIN and _AWS_GPG_BIN carry.
    local _docker_validate="${_DOCKER_VALIDATE_BIN:-dockerd}"
    if command -v "${_docker_validate}" > /dev/null 2>&1; then
      if ! sudo "${_docker_validate}" --validate --config-file "${_daemon_json}" > /dev/null 2>&1; then
        log_error "${_daemon_json} did not validate — refusing to leave a config dockerd cannot parse"
        log_warn "docker: daemon.json: validation failed"
        _core=1
      fi
    else
      # Absent validator is not evidence the file is good. Say so rather than
      # passing silently, which is the shape that let the original bug ship.
      log_warn "dockerd not resolvable — ${_daemon_json} written but NOT validated"
    fi
  fi
  sudo usermod -a -G docker bruce || {
    log_warn "docker: usermod: group add failed"
    _other=1
  }
  if [[ -x $(command -v docker) ]]; then
    printf "Docker is installed\\n"
  fi
  ((_core == 0)) || return 3
  ((_other == 0)) || return 1
  return 0
}

_install_ubuntu_k8s_tools() {
  # rc 1 when any tool failed; each is named in a warning. Every tool is
  # attempted regardless of an earlier failure.
  local _k8s_rc=0
  local _sources="${_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local _keyring="${_APT_KEYRINGS_DIR:-/etc/apt/keyrings}/kubernetes-apt-keyring.gpg"
  if [[ -n ${HAS_K8S} ]]; then
    printf "Installing kind\\n"
    _install_fetched_binary kind "${KIND_URL}" bin kind || {
      log_warn "k8s_tools: kind: install failed"
      _k8s_rc=1
    }
    printf "Installing telepresence\\n"
    _install_fetched_binary telepresence "${TELEPRESENCE_URL}" bin telepresence --resolve || {
      log_warn "k8s_tools: telepresence: install failed"
      _k8s_rc=1
    }
  fi

  # Purge stale baltocdn helm APT source left by pre-PR#155 runs — the repo
  # serves unsigned/NOSPLIT data and has no resolute suite, causing apt update
  # to fail on every subsequent setup run even after the code was fixed.
  # Advisory cleanup: a failure here is not a failed install.
  sudo rm -f "${_sources}/helm-stable-debian.list" 2> /dev/null || true

  # Advisory: the keyring helper's own install reports a real failure.
  sudo mkdir -p "$(dirname "${_keyring}")" || log_warn "k8s_tools: kubectl: keyring directory could not be created"
  _install_apt_keyring "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/Release.key" "${_keyring}" armored || {
    log_warn "k8s_tools: kubectl: keyring install failed"
    _k8s_rc=1
  }
  # A source signed-by a missing keyring would break every later apt update; the
  # helper writes it only when a non-empty keyring exists (a previous one is kept on failure).
  _write_apt_source_list k8s_tools kubectl "${_keyring}" "${_sources}/kubernetes.list" \
    "deb [signed-by=${_keyring}] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/deb/ /" || _k8s_rc=1
  # base owns the update warning; a failed refresh must not mask the install result.
  sudo -H apt update || :
  sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" kubectl -y || {
    log_warn "k8s_tools: kubectl: install failed"
    _k8s_rc=1
  }

  if [[ -n ${HAS_SNAP} ]]; then
    sudo snap install helm --classic || {
      log_warn "k8s_tools: helm: snap install failed"
      _k8s_rc=1
    }
  fi
  # helm and kustomize on non-snap systems are installed via brew in
  # _install_ubuntu_brew_packages(); no curl installer needed here.
  ((_k8s_rc == 0)) || return 1
  return 0
}

_install_ubuntu_hashicorp() {
  # rc 1 when any tool failed; the helper names the failing stage and each
  # failure is named here. Every tool is attempted regardless.
  local _hc_rc=0 _tool _ver _var _arch
  for _tool in consul vault nomad packer vagrant; do
    printf "Installing Hashicorp %s Ubuntu\\n" "${_tool}"
    _var="${_tool^^}_VER"
    _ver="${!_var}"
    _arch="${_LINUX_ARCH}"
    # vagrant has no ARM64 Linux build — amd64 only
    [[ ${_tool} == "vagrant" ]] && _arch="amd64"
    _install_fetched_binary "${_tool}" \
      "${HASHICORP_URL}/${_tool}/${_ver}/${_tool}_${_ver}_linux_${_arch}.zip" zip "${_tool}" || {
      log_warn "hashicorp: ${_tool}: install failed"
      _hc_rc=1
    }
  done
  ((_hc_rc == 0)) || return 1
  return 0
}

# Write an apt source list only when its keyring is a non-empty file: a source
# signed-by a missing keyring would break every later apt update. Returns 1 (with a
# warning naming <step>: <tool>) when the keyring is absent or the write fails.
# Usage: _write_apt_source_list <step> <tool> <keyring> <list> <line>
_write_apt_source_list() {
  local _step="$1" _tool="$2" _ring="$3" _list="$4" _line="$5"
  if [[ ! -s ${_ring} ]]; then
    log_warn "${_step}: ${_tool}: source write skipped (no keyring)"
    return 1
  fi
  printf '%s\n' "${_line}" | sudo tee "${_list}" > /dev/null || {
    log_warn "${_step}: ${_tool}: source list write failed"
    return 1
  }
  return 0
}

_install_ubuntu_cloud_tools() {
  # rc 1 when any tool failed; each is named in a warning. Every tool is
  # attempted regardless of an earlier failure.
  local _cloud_rc=0
  local _sources="${_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local _keyrings="${_APT_KEYRINGS_DIR:-/usr/share/keyrings}"
  local _ring _list
  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing teleport\\n"
    _ring="${_keyrings}/teleport-pubkey.gpg"
    _install_apt_keyring "https://deb.releases.teleport.dev/teleport-pubkey.asc" "${_ring}" armored || {
      log_warn "cloud_tools: teleport: keyring install failed"
      _cloud_rc=1
    }
    # Advisory cleanup of a stale source: a failure here is not a failed install.
    sudo rm -f "${_sources}/archive_uri-https_deb_releases_teleport_dev_-noble.list" 2> /dev/null || true
    _write_apt_source_list cloud_tools teleport "${_ring}" "${_sources}/teleport.list" \
      "deb [signed-by=${_ring}] https://deb.releases.teleport.dev/ stable main" || _cloud_rc=1
    # base owns the update warning; a failed refresh must not mask the install result.
    sudo -H apt update || :
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" teleport -y || {
      log_warn "cloud_tools: teleport: install failed"
      _cloud_rc=1
    }
    if [[ -x $(command -v tsh) ]]; then
      printf "Teleport is installed\\n"
    fi
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing cloudflared\\n"
    local _cf_codename
    _cf_codename="$(lsb_release -cs)"
    # Cloudflare WARP has no Ubuntu 26.04 packages yet; fall back to noble
    [[ -n "${RESOLUTE:-}" ]] && _cf_codename="noble"
    local _cf_sources="${_CF_SOURCES_LIST:-${_sources}/cloudflare-client.list}"
    _ring="${_keyrings}/cloudflare-warp-archive-keyring.gpg"
    _install_apt_keyring "https://pkg.cloudflareclient.com/pubkey.gpg" "${_ring}" armored || {
      log_warn "cloud_tools: cloudflared: keyring install failed"
      _cloud_rc=1
    }
    _write_apt_source_list cloud_tools cloudflared "${_ring}" "${_cf_sources}" \
      "deb [signed-by=${_ring}] https://pkg.cloudflareclient.com/ ${_cf_codename} main" || _cloud_rc=1
    # base owns the update warning; a failed refresh must not mask the install result.
    sudo apt-get update || :
    sudo DEBIAN_FRONTEND=noninteractive apt-get install "${APT_CONFFILE_OPTS[@]}" cloudflare-warp -y || {
      log_warn "cloud_tools: cloudflared: install failed"
      _cloud_rc=1
    }
    if [[ -x $(command -v cloudflared) ]]; then
      printf "cloudflared is installed\\n"
    fi
  fi

  # azure-cli now comes from linuxbrew (see _install_ubuntu_brew_packages). Remove
  # the legacy Microsoft key and source files an earlier version of this function
  # left behind; the glob stays outside the quotes and an unmatched one is harmless.
  local _apt_sources="${_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local _apt_trusted="${_APT_TRUSTED_DIR:-/etc/apt/trusted.gpg.d}"
  sudo rm -f "${_apt_trusted}/microsoft.asc.gpg" \
    "${_apt_sources}"/archive_uri-http_packages_microsoft_com_repos_azure-cli_-*.list \
    "${_apt_sources}/packages.microsoft.com_repos_azure-cli.list" \
    "${_apt_sources}/azure-cli.list" \
    || log_warn "could not remove legacy azure-cli apt key/sources under ${_apt_trusted} and ${_apt_sources}"

  printf "Installing gcloud-sdk\\n"
  _ring="${_keyrings}/cloud.google.gpg"
  _list="${_sources}/google-cloud-sdk.list"
  if [[ ! -f ${_list} ]]; then
    _install_apt_keyring "https://packages.cloud.google.com/apt/doc/apt-key.gpg" "${_ring}" armored || {
      log_warn "cloud_tools: gcloud: keyring install failed"
      _cloud_rc=1
    }
    _write_apt_source_list cloud_tools gcloud "${_ring}" "${_list}" \
      "deb [signed-by=${_ring}] https://packages.cloud.google.com/apt cloud-sdk main" || _cloud_rc=1
  fi
  # base owns the update warning; a failed refresh must not mask the install result.
  sudo apt update || :
  sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" google-cloud-cli -y || {
    log_warn "cloud_tools: gcloud: google-cloud-cli install failed"
    _cloud_rc=1
  }
  sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" google-cloud-cli-app-engine-go -y || {
    log_warn "cloud_tools: gcloud: google-cloud-cli-app-engine-go install failed"
    _cloud_rc=1
  }

  printf "Installing cf-terraforming Ubuntu\\n"
  _install_fetched_binary cf-terraforming "${CF_TERRAFORMING_URL}" tar cf-terraforming || {
    log_warn "cloud_tools: cf-terraforming: install failed"
    _cloud_rc=1
  }
  ((_cloud_rc == 0)) || return 1
  return 0
}

# Returns 0 clean, 1 hard failure, 2 partial success with the failed packages named.
# The tri-state mirrors install_git_hooks_all_repos: a bootstrap must not abort
# because one upstream formula was briefly unavailable, but it must not report
# success over a package that never landed either. Before this, every call was
# unchecked and brew_install_formula swallowed its own status -- which is how
# `go-task/tap/go-task` failed with exit 127 on every Linux run since it was added,
# silently, leaving claude without it. Measured 2026-09-12.
_install_ubuntu_brew_packages() {
  local _failed=()
  # Was `install_homebrew` unchecked inside an if/elif, so a fresh box installed brew
  # and then skipped the entire package list for that run. Install, then fall through.
  if ! [ -x "$(command -v brew)" ]; then
    install_homebrew || return 1
  fi
  if ! [ -x "$(command -v brew)" ]; then
    log_error "brew still unavailable after install_homebrew"
    return 1
  fi

  printf "Installing brew packages in Ubuntu\\n"
  brew_update

  local _f
  for _f in \
    argocd bat cargo-nextest cargo-cyclonedx cyclonedx-python git-lfs fzf gh \
    hadolint helm k9s kustomize lazydocker linkerd mongosh mongodb-atlas neovim \
    pyenv pyenv-virtualenv rbenv ripgrep rustup \
    starship tgenv uv zig zoxide redpanda-data/tap/redpanda \
    git-cliff kcov mdbook bun getagentseal/codeburn/codeburn \
    go-task azure-cli; do
    # go-task is `go-task`, NOT `go-task/tap/go-task`: the tap-qualified name resolves
    # to a macOS Cask that shells out to /usr/bin/xattr and exits 127 on Linux. Core
    # ships the formula now. Same for `bun` over `oven-sh/bun/bun`, and `codeburn` is
    # only ever the tap-qualified name -- bare `codeburn` resolves to nothing.
    brew_install_formula "${_f}" || _failed+=("${_f}")
  done

  # Migration: once the brew az demonstrably runs, drop the apt package it replaces.
  # Gated on dpkg's exact Status line so a config-files-only residue is not re-removed.
  # An empty or failed `brew --prefix` must skip, never fall back to /bin/az: on a
  # merged-usr Ubuntu that IS the apt az, which would "prove" itself and then be removed.
  local _bp _az_probe
  _bp="$(brew --prefix 2> /dev/null)"
  if [[ -n ${_BREW_AZ_BIN:-} || -n ${_bp} ]]; then
    _az_probe="${_BREW_AZ_BIN:-${_bp}/bin/az}"
    if ! _is_system_az_path "${_az_probe}" \
      && "${_az_probe}" version > /dev/null 2>&1 \
      && dpkg -s azure-cli 2> /dev/null | grep -qx 'Status: install ok installed'; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y azure-cli || _failed+=(azure-cli-apt-remove)
    fi
  fi

  # Homebrew rather than apt deliberately: apt ships shfmt 3.8.0 on noble and
  # 3.12.0 on resolute, against 3.13.1 from brew. A formatter's output is the
  # gate, so version skew across machines would flag files nobody touched.
  brew_install_formula shfmt || _failed+=(shfmt)

  brew_tap_if_missing snyk/tap
  brew_install_formula snyk || _failed+=(snyk)

  # codex is a Cask on Linux as well as macOS, so it needs the cask-aware guard:
  # brew_formula_installed greps `brew list --formula` and would never see it,
  # reinstalling on every run.
  brew_install_cask codex || _failed+=(codex)

  # Ubuntu 26.04 ships uutils coreutils. Its `sort -u` collates `py.test` and
  # `pytest` as equal under UTF-8 and drops one, so pyenv's `versions` command
  # (`libexec/pyenv-versions`), which pipes its name list through `sort`, emits
  # no `pytest` shim and every bare-`pytest` Makefile target breaks. apt cannot
  # make GNU the provider -- build-essential pins coreutils-from-uutils by name
  # -- so the formula is the route. 24.04 and earlier already ship GNU; gate to
  # avoid installing a second copy on machines that do not need it. Measured
  # 2026-09-15.
  if [[ -n ${RESOLUTE} ]]; then
    brew_install_formula coreutils || _failed+=(coreutils)
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    brew_tap_if_missing gitguardian/tap
    brew_install_formula ggshield || _failed+=(ggshield)
    brew_install_formula claude-code@latest || _failed+=(claude-code@latest)
    if command -v claude &> /dev/null; then
      provision_claude_plugins < /dev/null || _failed+=(claude-plugins)
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    brew_install_formula ollama || _failed+=(ollama)
  fi

  # Trust third-party taps for Homebrew 6.0 (idempotent — no-op if already trusted or tap absent)
  brew trust cloudflare/cloudflare datawire/blackbird getagentseal/codeburn gitguardian/tap go-task/tap oven-sh/bun redpanda-data/tap snyk/tap 2> /dev/null || true

  if [[ ${#_failed[@]} -gt 0 ]]; then
    log_warn "brew: ${#_failed[@]} package(s) failed: ${_failed[*]}"
    return 2
  fi
}

# True for the apt-packaged az, which on a merged-usr Ubuntu is also what a bare
# /bin/az resolves to; the brew migration must never accept it as the brew az.
_is_system_az_path() {
  [[ $1 == /bin/az || $1 == /usr/bin/az ]]
}

# gpg 2.5 exits 0 when it dearmors a truncated key and still writes bytes, so
# a keyring is judged by its content: it must hold exactly one primary key and
# the fingerprint of that primary key (the fpr: record right after its pub:
# record, never a subkey's) must equal the pin. Returns 0 match, 1 mismatch,
# 2 when the listing failed or showed no usable primary key (gpg missing, junk
# input, a pub: record with no fpr: record after it, or an empty homedir
# argument). <home> is a throwaway gpg homedir the caller owns and removes; an
# empty one would make gpg use the operator's ~/.gnupg.
_keyring_has_pinned_fpr() {
  local _ring="$1" _fpr="$2" _home="$3" _listing _rc _pubs _primary
  [[ -n ${_home} ]] || return 2
  _listing="$("${_MS_GPG_BIN:-gpg}" --homedir "${_home}" --batch --show-keys --with-colons "${_ring}" 2> /dev/null)"
  _rc=$?
  [[ ${_rc} -eq 0 ]] || return 2
  _pubs="$(printf '%s\n' "${_listing}" | grep -c '^pub:')"
  [[ ${_pubs} -ge 1 ]] || return 2
  [[ ${_pubs} -eq 1 ]] || return 1
  _primary="$(printf '%s\n' "${_listing}" | awk -F: '/^pub:/{p=1;next} p&&/^fpr:/{print $10;exit}')"
  [[ -n ${_primary} ]] || return 2
  [[ -n ${_fpr} ]] || return 1
  [[ ${_primary} == "${_fpr}" ]] || return 1
}

# Dearmor <key_file> into a temp dir, verify it holds exactly the pinned key,
# and only then install it at <keyring>. The final path is never modified on
# failure, so a keyring that already works survives a bad fetch: the install
# is staged to <keyring>.new and renamed into place, because GNU install
# unlinks its target before copying.
# Returns 0 installed; 1 the key is not the pinned one (not exactly one primary
# key, or its fingerprint differs); 2 no usable key could be read (gpg failed,
# the input held no key, or a primary key had no fingerprint); 3 a local
# failure (temp dir, staging, install) that left the final path unchanged.
# No EXIT/RETURN trap: scripts/check-lib-exit-traps.sh ratchets `trap ... EXIT`
# in lib/, and a RETURN trap is not function-scoped (shell.md), so every path
# below reaches the single rm -rf instead.
_build_pinned_keyring() {
  local _key="$1" _ring="$2" _fpr="$3" _dir _gpg_rc _rc
  [[ -n ${_key} && -n ${_ring} && -n ${_fpr} ]] || return 3
  _dir="$(mktemp -d "${_APT_KEY_TMP_ROOT:-${TMPDIR:-/tmp}}/apt-key.XXXXXXXX")" || return 3
  if ! mkdir -m 700 "${_dir}/home"; then
    rm -rf "${_dir}"
    return 3
  fi
  { "${_MS_GPG_BIN:-gpg}" --dearmor < "${_key}" > "${_dir}/k.gpg"; } 2> /dev/null
  _gpg_rc=$?
  if [[ ${_gpg_rc} -ne 0 ]]; then
    _rc=2
  else
    _keyring_has_pinned_fpr "${_dir}/k.gpg" "${_fpr}" "${_dir}/home"
    _rc=$?
  fi
  if [[ ${_rc} -eq 0 ]]; then
    if ! { sudo install -m 0644 "${_dir}/k.gpg" "${_ring}.new" && sudo mv -f "${_ring}.new" "${_ring}"; }; then
      sudo rm -f "${_ring}.new"
      _rc=3
    fi
  fi
  rm -rf "${_dir}"
  return "${_rc}"
}

# Fetch a key to a file, convert it in a throwaway dir as the invoking user (a
# root-run gpg writes a umask-dependent 0600 file apt cannot read), then install
# it 0644 to <keyring>.new and rename over <keyring>. A piped fetch cannot be
# checked (the consumer's status masks curl's), and a stale .new from an
# interrupted run would pass the non-empty check, so it is removed first. Any
# failure leaves the existing <keyring> untouched and no .new behind.
# Usage: _install_apt_keyring <url> <keyring> <armored|binary>
# Returns 0 installed; 1 on bad arguments or any failed stage (named in a warning).
# gpg is _APT_KEY_GPG_BIN (default gpg). No EXIT/RETURN trap, for the reason
# given above _build_pinned_keyring.
_install_apt_keyring() {
  local _url="$1" _ring="$2" _kind="$3" _dir _src _stage=""
  [[ -n ${_url} && -n ${_ring} ]] || return 1
  [[ ${_kind} == "armored" || ${_kind} == "binary" ]] || return 1
  _dir="$(mktemp -d "${_APT_KEY_TMP_ROOT:-${TMPDIR:-/tmp}}/apt-key.XXXXXXXX")" || return 1
  if ! sudo rm -f "${_ring}.new"; then
    log_warn "${_ring}: stale .new could not be removed"
    rm -rf "${_dir}"
    return 1
  fi
  if ! curl -fsSL -o "${_dir}/key" "${_url}"; then
    log_warn "${_ring}: key download failed"
    rm -rf "${_dir}"
    return 1
  fi
  _src="${_dir}/key"
  if [[ ${_kind} == "armored" ]]; then
    _src="${_dir}/ring"
    "${_APT_KEY_GPG_BIN:-gpg}" --batch --yes --dearmor -o "${_src}" < "${_dir}/key" || _stage="conversion"
  fi
  if [[ -z ${_stage} && ! -s ${_src} ]]; then
    _stage="conversion"
  fi
  if [[ -z ${_stage} ]] && ! sudo install -m 0644 "${_src}" "${_ring}.new"; then
    _stage="install"
  fi
  if [[ -z ${_stage} ]] && ! sudo mv -f "${_ring}.new" "${_ring}"; then
    _stage="rename"
  fi
  if [[ -n ${_stage} ]]; then
    log_warn "${_ring}: key ${_stage} failed"
    sudo rm -f "${_ring}.new"
    rm -rf "${_dir}"
    return 1
  fi
  rm -rf "${_dir}"
  return 0
}

# Fetch a binary into a throwaway dir, install it last, and stamp the URL only
# after the install succeeds, so an interrupted run leaves the destination
# untouched and the next run fetches again. The stamp is the idempotency check:
# a stamp equal to the (resolved) URL plus an executable destination is a skip.
# Usage: _install_fetched_binary <name> <url> <bin|zip|tar> <member> [<dest-name>] [--resolve]
# <member> is the path inside a zip/tar (ignored for bin); <dest-name> defaults
# to <name>. --resolve follows redirects first and uses the final URL as the
# identity (for "latest" links); a failed resolution keeps a stamped, non-empty,
# executable copy and otherwise fails.
# Returns 0 installed, up to date, or kept; 1 on bad arguments or a failed stage
# (named in a warning). A stamp that cannot be written warns and still returns 0.
# Seams, read at call time: _DL_STAMP_DIR, _DL_TMP_ROOT, _DL_BIN_DIR,
# _DL_UNZIP_BIN, _DL_TAR_BIN. No EXIT/RETURN trap (check-lib-exit-traps.sh;
# shell.md): every path below reaches an explicit rm -rf.
_install_fetched_binary() {
  [[ $# -ge 4 ]] || return 1
  local _name="$1" _url="$2" _kind="$3" _member="$4"
  local _dest_name="" _resolve=0 _arg _stamp _bin _tmp _src _stage="" _resolved
  [[ -n ${_name} && -n ${_url} ]] || return 1
  [[ ${_kind} == "bin" || ${_kind} == "zip" || ${_kind} == "tar" ]] || return 1
  shift 4
  for _arg in "$@"; do
    if [[ ${_arg} == "--resolve" ]]; then
      _resolve=1
    else
      [[ -z ${_dest_name} ]] || return 1
      _dest_name="${_arg}"
    fi
  done
  _dest_name="${_dest_name:-${_name}}"
  _stamp="${_DL_STAMP_DIR:-${HOME}/.local/share/dotfiles/installed}/${_name}"
  _bin="${_DL_BIN_DIR:-/usr/local/bin}/${_dest_name}"

  if [[ ${_resolve} -eq 1 ]]; then
    _resolved="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "${_url}")" || _resolved=""
    if [[ -z ${_resolved} || ${_resolved} == "${_url}" ]]; then
      if [[ -f ${_stamp} && -x ${_bin} && -s ${_bin} ]]; then
        log_warn "${_name}: could not resolve ${_url}; keeping installed copy"
        return 0
      fi
      log_warn "${_name}: resolve failed"
      return 1
    fi
    _url="${_resolved}"
  fi

  if [[ -f ${_stamp} && -x ${_bin} && "$(< "${_stamp}")" == "${_url}" ]]; then
    printf '%s: up to date (stamp %s); rm it to force a re-install\n' "${_name}" "${_stamp}"
    return 0
  fi

  mkdir -p "${_DL_TMP_ROOT:-${HOME}/software_downloads}" || {
    log_warn "${_name}: workdir failed"
    return 1
  }
  _tmp="$(mktemp -d "${_DL_TMP_ROOT:-${HOME}/software_downloads}/.dl.XXXXXXXX")" || {
    log_warn "${_name}: workdir failed"
    return 1
  }

  if ! wget -O "${_tmp}/dl" "${_url}"; then
    _stage="download"
  elif [[ ${_kind} == "bin" ]]; then
    _src="${_tmp}/dl"
  else
    mkdir -p "${_tmp}/x"
    if [[ ${_kind} == "zip" ]]; then
      "${_DL_UNZIP_BIN:-unzip}" -o -q "${_tmp}/dl" -d "${_tmp}/x" || _stage="extract"
    else
      "${_DL_TAR_BIN:-tar}" -xzf "${_tmp}/dl" -C "${_tmp}/x" || _stage="extract"
    fi
    _src="${_tmp}/x/${_member}"
  fi
  # -s alone passes a directory and follows a symlink to any non-empty file.
  if [[ -z ${_stage} ]] && ! [[ -f ${_src} && ! -L ${_src} && -s ${_src} ]]; then
    _stage="extract"
  fi
  if [[ -z ${_stage} ]] && ! sudo install -m 0755 "${_src}" "${_bin}"; then
    _stage="install"
  fi
  rm -rf "${_tmp}"
  if [[ -n ${_stage} ]]; then
    log_warn "${_name}: ${_stage} failed"
    return 1
  fi

  if ! { mkdir -p "$(dirname "${_stamp}")" && printf '%s\n' "${_url}" > "${_stamp}"; } 2> /dev/null; then
    log_warn "${_name}: could not write stamp ${_stamp}; it will be re-installed next run"
  fi
  return 0
}

# Own function so tests can drive the edge source logic without also running the
# albert writes that share _install_ubuntu_gui_tools.
_install_ubuntu_edge_source() {
  # The package owns microsoft-edge.sources, but do-release-upgrade can leave it
  # disabled, so existence is not enough: a live one has a URIs: line (an empty or
  # stanza-less file is not a source) and every Enabled: line in it is affirmative.
  # apt reads many spellings of "off" (no, false, 0, off, disable, without), so the
  # rule lists the affirmative values and treats anything else as inert; the
  # harmless direction to err in is a duplicate source. Only a live one retires the
  # bootstrap .list and keyring.
  local _edge_dir="${_EDGE_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local _edge_src="${_edge_dir}/microsoft-edge.sources"
  local _edge_list="${_edge_dir}/microsoft-edge.list"
  local _edge_keyring="${_EDGE_BOOTSTRAP_KEYRING:-/usr/share/keyrings/microsoft-edge-bootstrap.gpg}"
  if grep -q '^URIs:' "${_edge_src}" 2> /dev/null \
    && ! grep -iE '^Enabled:' "${_edge_src}" | grep -qviE '^Enabled:[[:space:]]*(yes|true|with|on|enable|1)[[:space:]]*$'; then
    sudo rm -f "${_edge_list}" "${_edge_keyring}"
  else
    local _edge_key="${_MS_KEY_PATH:-${DOTFILES_REPO_ROOT}/keys/microsoft.asc}"
    if _build_pinned_keyring "${_edge_key}" "${_edge_keyring}" "${MS_GPG_FPR}"; then
      # Microsoft Edge has no ARM64 Linux build — amd64 only
      printf 'deb [arch=amd64 signed-by=%s] https://packages.microsoft.com/repos/edge stable main\n' "${_edge_keyring}" | sudo tee "${_edge_list}" > /dev/null
    else
      log_warn "edge: could not build ${_edge_keyring} (gpg missing or failed on ${_edge_key}, the keyring lacks the pinned fingerprint, or it is not writable); writing no Edge source"
      sudo rm -f "${_edge_list}" "${_edge_keyring}"
      return 1
    fi
  fi
}

# Albert's apt source, pinned to ALBERT_GPG_FPR. The key is fetched (OBS extends
# its expiry without changing the fingerprint, so the pin follows an extension)
# and the source is https + signed-by a dedicated keyring rather than a global
# trusted.gpg.d key. Returns 0 installed; 2 anything else. On a fetch failure,
# an unreadable key, or a local keyring failure the last verified source is kept,
# so a network blip does not drop a working source; on a fingerprint mismatch
# both are removed. No EXIT/RETURN trap (check-lib-exit-traps.sh; shell.md): every
# path below reaches the one rm -rf.
_install_ubuntu_albert() {
  local _sources="${_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local _keyrings="${_APT_KEYRINGS_DIR:-/usr/share/keyrings}"
  local _trusted="${_APT_TRUSTED_DIR:-/etc/apt/trusted.gpg.d}"
  local _list="${_sources}/albert.list"
  local _ring="${_keyrings}/albert-obs.gpg"
  local _release _url _dir _brc _keep_note _fprs _npub _f
  _keep_note="keeping last verified source"

  _release="$(lsb_release -rs)"
  printf "Installing Albert Ubuntu %s\\n" "${_release}"
  # Legacy cleanup runs first, before any fetch, so it happens on every path.
  sudo rm -f "${_trusted}/home_manuelschneid3r.gpg" "${_sources}/home:manuelschneid3r.list"
  [[ -e ${_list} ]] || _keep_note="no verified albert source is present yet"

  _url="${_ALBERT_KEY_URL:-https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_${_release}/Release.key}"
  _dir="$(mktemp -d "${_APT_KEY_TMP_ROOT:-${TMPDIR:-/tmp}}/albert-key.XXXXXXXX")" || {
    log_warn "albert: could not create a temp dir for the key from ${_url}"
    return 2
  }

  if ! curl -fsSL -o "${_dir}/albert-key.asc" "${_url}"; then
    rm -rf "${_dir}"
    log_warn "albert key fetch failed (${_url}); ${_keep_note}"
    return 2
  fi

  _build_pinned_keyring "${_dir}/albert-key.asc" "${_ring}" "${ALBERT_GPG_FPR}"
  _brc=$?
  case ${_brc} in
    0) ;;
    1)
      # Throwaway homedir: never read or write the operator's GNUPGHOME.
      _fprs=""
      _npub=0
      if mkdir -m 700 "${_dir}/gh"; then
        _fprs="$("${_MS_GPG_BIN:-gpg}" --homedir "${_dir}/gh" --batch --show-keys --with-colons "${_dir}/albert-key.asc" 2> /dev/null \
          | awk -F: '$1 == "pub" {want = 1; next} $1 == "fpr" && want {printf "%s ", $10; want = 0}')"
      fi
      for _f in ${_fprs}; do _npub=$((_npub + 1)); done
      [[ -n ${_fprs} ]] || _fprs="(unreadable)"
      if [[ ${_npub} -gt 1 ]]; then
        log_warn "albert key from ${_url} holds ${_npub} primary keys (${_fprs}), not exactly one; expected ALBERT_GPG_FPR ${ALBERT_GPG_FPR}. Removing the albert source and keyring. Verify the key out of band, then edit ALBERT_GPG_FPR in lib/constants.sh"
      else
        log_warn "albert key from ${_url} is not the pinned key: fetched primary fingerprint ${_fprs} but ALBERT_GPG_FPR is ${ALBERT_GPG_FPR}; removing the albert source and keyring. Verify the new key out of band, then edit ALBERT_GPG_FPR in lib/constants.sh"
      fi
      rm -rf "${_dir}"
      sudo rm -f "${_list}" "${_ring}"
      return 2
      ;;
    2)
      rm -rf "${_dir}"
      log_warn "albert: no key could be read from ${_url}; ${_keep_note}"
      return 2
      ;;
    *)
      rm -rf "${_dir}"
      log_warn "albert: could not install the keyring ${_ring}; ${_keep_note}"
      return 2
      ;;
  esac
  rm -rf "${_dir}"

  if ! printf 'deb [signed-by=%s] https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_%s/ /\n' "${_ring}" "${_release}" | sudo tee "${_list}" > /dev/null; then
    log_warn "albert: could not write ${_list}"
    return 2
  fi
  sudo -H DEBIAN_FRONTEND=noninteractive apt update
  if ! sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" albert -y; then
    log_warn "albert: apt install albert failed"
    return 2
  fi
  if [[ -x $(command -v albert) ]]; then
    printf "Albert is installed Ubuntu %s\\n" "${_release}"
  fi
  return 0
}

_install_ubuntu_gui_tools() {
  # Returns albert's own rc when it is non-zero (as before); otherwise 1 when any
  # other sub-install failed, each named in a warning, else 0. Every sub-install
  # is attempted regardless of an earlier failure.
  local _gui_rc=0 _albert_rc=0 _ring _snap
  local _sources="${_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local _keyrings="${_APT_KEYRINGS_DIR:-/usr/share/keyrings}"
  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing Virtualbox\\n"
    _ring="${_keyrings}/oracle-virtualbox-2016.gpg"
    _install_apt_keyring "https://www.virtualbox.org/download/oracle_vbox_2016.asc" "${_ring}" armored || {
      log_warn "gui_tools: virtualbox: keyring install failed"
      _gui_rc=1
    }
    # VirtualBox has no ARM64 Linux build — amd64 only
    _write_apt_source_list gui_tools virtualbox "${_ring}" "${_sources}/virtualbox.list" \
      "deb [arch=amd64 signed-by=${_ring}] http://download.virtualbox.org/virtualbox/debian $(. /etc/os-release && echo "$VERSION_CODENAME") contrib" || _gui_rc=1
    # base owns the update warning; a failed refresh must not mask the install result.
    sudo -H apt update || :
    # shellcheck disable=SC2086 # package-name slot: apt install takes a list, and VIRTUALBOX_VER may hold more than one package
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" ${VIRTUALBOX_VER} -y || {
      log_warn "gui_tools: virtualbox: install failed"
      _gui_rc=1
    }
    if [[ -x $(command -v vboxmanage) ]]; then
      printf "Virtualbox is installed\\n"
    fi
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    _install_ubuntu_albert || _albert_rc=$?
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing microsoft edge\\n"
    _install_ubuntu_edge_source || {
      log_warn "gui_tools: edge: source setup failed"
      _gui_rc=1
    }
    # base owns the update warning; a failed refresh must not mask the install result.
    sudo -H apt update || :
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" microsoft-edge-stable -y || {
      log_warn "gui_tools: edge: install failed"
      _gui_rc=1
    }
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "snap software with classic option, the other snap packages are installed in ubuntu_workstation_snap_packages.txt\\n"
    for _snap in code slack certbot; do
      sudo snap install "${_snap}" --classic || {
        log_warn "gui_tools: snap ${_snap}: install failed"
        _gui_rc=1
      }
    done
    sudo snap set certbot trust-plugin-with-root=ok || {
      log_warn "gui_tools: snap certbot: trust-plugin-with-root failed"
      _gui_rc=1
    }
    sudo snap install certbot-dns-route53 || {
      log_warn "gui_tools: snap certbot-dns-route53: install failed"
      _gui_rc=1
    }
  fi

  if [[ -n ${HAS_FLATPAK} ]]; then
    printf "Installing Steam via Flatpak\\n"
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || {
      log_warn "gui_tools: steam: flathub remote-add failed"
      _gui_rc=1
    }
    sudo flatpak install flathub com.valvesoftware.Steam -y || {
      log_warn "gui_tools: steam: install failed"
      _gui_rc=1
    }
    # Advisory probe: the message below is informational, not a status.
    if sudo flatpak list | grep -q com.valvesoftware.Steam; then
      printf "Steam is installed\\n"
    fi
  fi
  [[ ${_albert_rc} -ne 0 ]] && return "${_albert_rc}"
  ((_gui_rc == 0)) || return 1
  return 0
}

# Installs a checksum-verified release binary, skipping when the copy already
# in place reports the pinned version. tflint and tfsec share an identical
# pinned-version / per-arch-sha256 / download / verify / extract / install
# sequence -- exactly where a hand copy drops the verify step, so two
# consumers are enough to justify one helper.
#
# Reads ${_RELEASE_BIN_DIR:-/usr/local/bin}/<name>'s own --version output,
# never the copy on PATH (shell.md: an absolute-path default is the only
# thing a PATH mock cannot defeat, and here a PATH stub must not satisfy the
# skip check when the target directory is genuinely empty). <version-line-
# regex> is matched as given -- it carries its own ^...$ anchors, because a
# substring match would let an "out of date, latest is X" notice look like
# X is already installed.
#
# sha256sum is never mocked, mirroring _install_rustup_rs above: mocking it
# would make every mismatch case vacuous.
_install_pinned_release_binary() {
  local _name="$1" _version="$2" _url="$3" _sha256="$4" _kind="$5" _version_regex="$6"
  local _dir="${_RELEASE_BIN_DIR:-/usr/local/bin}"

  if [[ -x "${_dir}/${_name}" ]]; then
    local _current
    _current="$("${_dir}/${_name}" --version 2>&1)"
    if printf '%s\n' "${_current}" | grep -qE "${_version_regex}"; then
      printf "%s %s already installed\\n" "${_name}" "${_version}"
      return 0
    fi
  fi

  # No trap here, deliberately: scripts/check-lib-exit-traps.sh ratchets every
  # `trap ... EXIT` in lib/*.sh against a hand-maintained allowlist, so this
  # mirrors _install_rustup_rs above instead -- an explicit `rm -rf "${_tmp}"`
  # before every return, rather than a subshell-scoped trap.
  #
  # _RELEASE_TMP_ROOT is a seam, not a convenience: BSD mktemp -d with no
  # template ignores TMPDIR entirely, so a TMPDIR-based assertion is inert on
  # the Studio, where this suite runs. Precedent: _OVERRIDE_RUN_TMPDIR_ROOT in
  # lib/workflows.sh.
  local _tmp
  _tmp="$(mktemp -d "${_RELEASE_TMP_ROOT:-${TMPDIR:-/tmp}}/release-bin.XXXXXXXX")" || return 1

  # A malformed or empty pin must fail closed rather than let sha256sum decide.
  # Measured: macOS /sbin/sha256sum exits 0 on a malformed checksum line (only
  # warning on stderr, which the redirect below discards), while GNU exits 1 --
  # so without this, the Studio's suite is structurally unable to fail for an
  # empty or typo'd pin.
  if [[ ! "${_sha256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    log_error "${_name}: pinned sha256 is not 64 hex chars"
    rm -rf "${_tmp}"
    return 1
  fi

  local _artifact="${_tmp}/${_name}.download"
  if ! curl -fsSL -o "${_artifact}" "${_url}"; then
    log_error "${_name} download failed"
    rm -rf "${_tmp}"
    return 1
  fi

  if ! printf '%s  %s\n' "${_sha256}" "${_artifact}" | sha256sum -c - > /dev/null 2>&1; then
    log_error "${_name} sha256 mismatch — refusing to install"
    rm -rf "${_tmp}"
    return 1
  fi

  local _extracted
  case "${_kind}" in
    zip)
      if ! unzip -o -q "${_artifact}" "${_name}" -d "${_tmp}"; then
        log_error "${_name} unzip failed"
        rm -rf "${_tmp}"
        return 1
      fi
      _extracted="${_tmp}/${_name}"
      ;;
    tarxz)
      # Extract the whole archive and then locate the binary by name, rather
      # than naming a member path: shellcheck ships its binary one level down
      # (shellcheck-v0.11.0/shellcheck) and that prefix carries the version, so
      # a hardcoded member path would need editing on every bump. The artifact
      # itself is ${_name}.download, which `-name "${_name}"` cannot match.
      if ! tar -xJf "${_artifact}" -C "${_tmp}"; then
        log_error "${_name} tar extraction failed"
        rm -rf "${_tmp}"
        return 1
      fi
      _extracted="$(find "${_tmp}" -type f -name "${_name}" | head -1)"
      if [[ -z "${_extracted}" ]]; then
        log_error "${_name} not found in the extracted archive"
        rm -rf "${_tmp}"
        return 1
      fi
      ;;
    raw)
      _extracted="${_artifact}"
      ;;
    *)
      log_error "unknown release-binary kind for ${_name}: ${_kind}"
      rm -rf "${_tmp}"
      return 1
      ;;
  esac

  if [[ -w "${_dir}" ]]; then
    if ! install -m 0755 "${_extracted}" "${_dir}/${_name}"; then
      log_error "${_name} install into ${_dir} failed"
      rm -rf "${_tmp}"
      return 1
    fi
  else
    if ! sudo install -m 0755 "${_extracted}" "${_dir}/${_name}"; then
      log_error "${_name} install into ${_dir} failed"
      rm -rf "${_tmp}"
      return 1
    fi
  fi

  rm -rf "${_tmp}"
  printf "%s %s installed\\n" "${_name}" "${_version}"
}

_install_ubuntu_shellcheck() {
  [[ -n ${HAS_DEVTOOLS} ]] || return 0
  local _sha _arch
  # NOTE: shellcheck publishes x86_64/aarch64, not the amd64/arm64 spelling
  # _LINUX_ARCH carries, so the two names are mapped rather than interpolated.
  case "${_LINUX_ARCH}" in
    amd64) _sha="${SHELLCHECK_SHA256_AMD64}"; _arch="x86_64" ;;
    arm64) _sha="${SHELLCHECK_SHA256_ARM64}"; _arch="aarch64" ;;
    *)
      log_warn "no pinned shellcheck sha256 for ${_LINUX_ARCH}; skipping"
      return 0
      ;;
  esac
  _install_pinned_release_binary shellcheck "${SHELLCHECK_VER}" \
    "${_SHELLCHECK_URL:-https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VER}/shellcheck-v${SHELLCHECK_VER}.linux.${_arch}.tar.xz}" \
    "${_SHELLCHECK_SHA256:-${_sha}}" tarxz "^version: ${SHELLCHECK_VER//./\\.}$"
}

_install_ubuntu_tflint() {
  [[ -n ${HAS_DEVTOOLS} ]] || return 0
  local _sha
  case "${_LINUX_ARCH}" in
    amd64) _sha="${TFLINT_SHA256_AMD64}" ;;
    arm64) _sha="${TFLINT_SHA256_ARM64}" ;;
    *)
      log_warn "no pinned tflint sha256 for ${_LINUX_ARCH}; skipping"
      return 0
      ;;
  esac
  _install_pinned_release_binary tflint "${TFLINT_VER}" \
    "${_TFLINT_URL:-https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VER}/tflint_linux_${_LINUX_ARCH}.zip}" \
    "${_TFLINT_SHA256:-${_sha}}" zip "^TFLint version ${TFLINT_VER//./\\.}$"
}

_install_ubuntu_tfsec() {
  [[ -n ${HAS_DEVTOOLS} ]] || return 0
  local _sha
  case "${_LINUX_ARCH}" in
    amd64) _sha="${TFSEC_SHA256_AMD64}" ;;
    arm64) _sha="${TFSEC_SHA256_ARM64}" ;;
    *)
      log_warn "no pinned tfsec sha256 for ${_LINUX_ARCH}; skipping"
      return 0
      ;;
  esac
  _install_pinned_release_binary tfsec "${TFSEC_VER}" \
    "${_TFSEC_URL:-https://github.com/aquasecurity/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-${_LINUX_ARCH}}" \
    "${_TFSEC_SHA256:-${_sha}}" raw "^v${TFSEC_VER//./\\.}$"
}

# terraform on the Mac and on `workstation` comes from tfenv, not a static
# binary: /usr/local/bin/terraform is a symlink into ~/.tfenv/bin, and
# run_update already `git pull`s ~/.tfenv. _install_pinned_release_binary is
# NOT used here -- installing a standalone terraform binary would silently
# replace that symlink with a regular file and orphan tfenv underneath it.
#
# tfenv-install verifies its download against HashiCorp's SHA256SUMS, which is
# a same-origin check only: it skips PGP verification unless gpg or keybase is
# configured (measured on workstation, libexec/tfenv-install:318-376). That is
# weaker than the in-repo sha256 pins _install_pinned_release_binary uses for
# tflint/tfsec above, and is accepted because it matches how terraform already
# arrives on the Mac and on workstation.
_install_ubuntu_tfenv() {
  [[ -n ${HAS_DEVTOOLS} ]] || return 0

  local _root="${_TFENV_ROOT:-${HOME}/.tfenv}"
  local _links="${_TFENV_LINK_DIR:-/usr/local/bin}"
  local _repo="${_TFENV_REPO_URL:-https://github.com/tfutils/tfenv.git}"

  if [[ ! -d "${_root}" ]]; then
    if ! git clone "${_repo}" "${_root}"; then
      log_warn "tfenv clone into ${_root} failed; skipping"
      return 0
    fi
  elif [[ ! -x "${_root}/bin/tfenv" ]]; then
    # ${_root} exists but is not a usable checkout -- an interrupted clone
    # (git self-cleans on an ordinary error exit but not on
    # SIGINT/SIGTERM/timeout/OOM), a stray mkdir, or a damaged checkout. Do
    # NOT re-clone: `git clone` into a non-empty directory fails, so it
    # would not self-heal, and do not auto-delete the directory either --
    # destroying an operator's directory is their call, not ours. Warning
    # and returning before the symlink loop below is what keeps this state
    # from becoming permanent: the loop's own `-L` branch treats an
    # already-correct dangling symlink as done and repairs nothing on every
    # subsequent run, which is what running this while ${_root} is broken
    # would otherwise plant.
    log_warn "${_root} exists but has no usable tfenv entry point; run 'rm -rf ${_root}' and retry"
    return 0
  fi

  local _name _target _link
  for _name in tfenv terraform; do
    _target="${_root}/bin/${_name}"
    _link="${_links}/${_name}"
    if [[ -L "${_link}" ]]; then
      if [[ "$(readlink "${_link}")" != "${_target}" ]]; then
        log_warn "${_link} is a symlink to $(readlink "${_link}"), not ${_target}; leaving it"
      fi
      continue
    fi
    if [[ -e "${_link}" ]]; then
      log_warn "${_link} already exists and is not a tfenv symlink; leaving it"
      continue
    fi
    if [[ -w "${_links}" ]]; then
      ln -s "${_target}" "${_link}" || log_warn "linking ${_link} failed; skipping"
    else
      sudo ln -s "${_target}" "${_link}" || log_warn "linking ${_link} failed; skipping"
    fi
  done

  if [[ ! -f "${_root}/version" ]]; then
    if ! "${_root}/bin/tfenv" install "${TERRAFORM_VER}"; then
      log_warn "tfenv install ${TERRAFORM_VER} failed; skipping"
      return 0
    fi
    if ! "${_root}/bin/tfenv" use "${TERRAFORM_VER}"; then
      log_warn "tfenv use ${TERRAFORM_VER} failed; skipping"
      return 0
    fi
  fi

  return 0
}

_install_ubuntu_misc() {
  # rc 1 when docker-compose, yq or opentofu failed; each is named in a warning
  # and the rest are still attempted. dotnet, tflint, tfsec, tfenv and the nala
  # cleanup are advisory.
  local _misc_rc=0
  printf "Installing docker-compose Ubuntu\\n"
  _install_fetched_binary docker-compose "${DOCKER_COMPOSE_URL}" bin docker-compose || {
    log_warn "misc: docker-compose: install failed"
    _misc_rc=1
  }

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing yq\\n"
    _install_fetched_binary yq "${YQ_URL}" bin yq || {
      log_warn "misc: yq: install failed"
      _misc_rc=1
    }
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    printf "Installing .net10 sdk\\n"
    # 8.0 was dropped entirely on 26.04 resolute -- `apt-cache policy dotnet-sdk-8.0`
    # returns nothing there -- so every provision of that box warned and skipped.
    # 10.0 is stock on both live releases: noble 10.0.112-0ubuntu1~24.04.1 and
    # resolute 10.0.112-0ubuntu1~26.04.1, measured 2026-09-13. The guard stays for
    # whichever release drops 10.0 next.
    sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" dotnet-sdk-10.0 -y || log_warn "dotnet-sdk-10.0 not available on this Ubuntu release; skipping"
  fi

  if [[ -n ${HAS_DEVTOOLS} ]]; then
    # _FORCE_OPENTOFU_INSTALL is a test seam: forces the install path even when
    # tofu is already on PATH, so tests don't depend on host tofu presence.
    # Unset in normal operation — identical to `! command -v tofu`.
    if [[ -n ${_FORCE_OPENTOFU_INSTALL:-} ]] || ! command -v tofu &>/dev/null; then
      printf "Installing opentofu\\n"
      local _tofu_keyrings="${_APT_KEYRINGS_DIR:-/etc/apt/keyrings}"
      local _tofu_ring="${_tofu_keyrings}/opentofu-archive-keyring.gpg"
      # Advisory: if the directory cannot be made, the keyring install below
      # fails and names the cause.
      sudo mkdir -p "${_tofu_keyrings}" || :
      _install_apt_keyring https://packages.opentofu.org/opentofu/tofu/gpgkey "${_tofu_ring}" armored || {
        log_warn "misc: opentofu: keyring install failed"
        _misc_rc=1
      }
      _write_apt_source_list misc opentofu "${_tofu_ring}" "${_APT_SOURCES_DIR:-/etc/apt/sources.list.d}/opentofu.list" \
        "deb [signed-by=${_tofu_ring}] https://packages.opentofu.org/opentofu/tofu/any/ any main" || _misc_rc=1
      # base owns the update warning; a failed refresh must not mask the install result.
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq || :
      # The package in packages.opentofu.org/opentofu/tofu/any is named `tofu`,
      # not `opentofu` -- its amd64 index carries exactly that one package.
      # Installing `opentofu` failed with "Unable to locate package" on every
      # Ubuntu release, silently, because the `command -v tofu` check below
      # simply never fired. Measured on claude 2026-09-12.
      sudo DEBIAN_FRONTEND=noninteractive apt-get install "${APT_CONFFILE_OPTS[@]}" -y tofu || {
        log_warn "misc: opentofu: install failed"
        _misc_rc=1
      }
      if command -v tofu &>/dev/null; then
        printf "opentofu is installed\\n"
      fi
    else
      printf "opentofu already installed\\n"
    fi
  fi

  # Each is self-gated on HAS_DEVTOOLS and advisory, as the dotnet install above.
  _install_ubuntu_shellcheck || log_warn "shellcheck install failed; skipping"
  _install_ubuntu_tflint || log_warn "tflint install failed; skipping"
  _install_ubuntu_tfsec || log_warn "tfsec install failed; skipping"
  # _install_ubuntu_tfenv always returns 0 (every failure warns internally
  # and returns 0, unlike tflint/tfsec's helper), so this `||` cannot fire
  # today. Kept for parity with the two lines above and as a guard if that
  # contract ever changes.
  _install_ubuntu_tfenv || log_warn "tfenv install failed; skipping"

  check_and_install_nala
  # </dev/null: same job-control hang as update_apt_packages in lib/linux_shared.sh.
  sudo -H DEBIAN_FRONTEND=noninteractive nala autoremove -y < /dev/null || log_warn "misc: nala autoremove failed"
  return "${_misc_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
