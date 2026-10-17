#!/usr/bin/env bash
# lib/linux_shared.sh — Ubuntu Linux install functions (git, zsh, bats, updates)

_apt_pkg_installed() {
  dpkg-query -f '${db:Status-Abbrev}' -W "${1}" 2>/dev/null | grep -q '^ii'
}

install_git_linux() {
  # This guard answers "is git installed", not "is the PPA's newer git installed" —
  # it returns true for the distro package and skips the ppa:git-core/ppa step below.
  # Harmless while this function is unreachable (run_setup_user calls install_git only
  # under [[ -n ${MACOS} ]]). Adding a production Linux caller requires replacing this
  # with a version comparison first.
  if _apt_pkg_installed git; then
    log_info "git already installed"
    return 0
  fi

  log_info "Installing git via apt"
  sudo -H add-apt-repository ppa:git-core/ppa -y \
    || log_warn "PPA add failed — continuing with distro git"
  sudo -H apt update \
    || log_warn "apt update failed — package index may be stale"
  sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" git -y \
    || { log_error "Failed to install git"; return 1; }
  log_info "Installed git"
}

install_zsh_linux() {
  if _apt_pkg_installed zsh && _apt_pkg_installed zsh-doc; then
    log_info "zsh already installed"
    return 0
  fi

  log_info "Installing zsh via apt"
  sudo -H apt update \
    || log_warn "apt update failed — package index may be stale"
  sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" zsh zsh-doc -y \
    || { log_error "Failed to install zsh"; return 1; }
  log_info "Installed zsh"
}

install_bats_linux() {
  if quiet_which bats; then
    log_info "bats already installed"
    return 0
  fi

  log_info "Installing bats"
  sudo -H DEBIAN_FRONTEND=noninteractive apt-get install "${APT_CONFFILE_OPTS[@]}" -y bats
}

update_apt_packages() {
  sudo -H apt update || { log_error "apt update failed"; return 1; }
  check_and_install_nala || { log_error "nala install failed"; return 1; }
  # </dev/null is load-bearing. With stdout not a terminal (run_update tees it)
  # nala uses raw dpkg mode and forks apt into its own process group; if that
  # child still holds the terminal as stdin, job control stops it and the run
  # hangs after "Downloading". DEBIAN_FRONTEND=noninteractive alone does not
  # prevent it. Reproduced on Ubuntu 26.04 / nala 0.16.0, 2026-09-16.
  #
  # With stdin closed dpkg cannot answer a conffile prompt: it fails "end of file
  # on stdin at conffile prompt" and leaves the package unpacked but unconfigured.
  # APT_CONFFILE_OPTS (confdef+confold) keeps the local edit and writes the package copy as
  # .dpkg-dist, the same choice unattended-upgrades makes. Measured 2026-09-16.
  #
  # DEBIAN_FRONTEND is set as well, for a different hang: apt's needrestart
  # Post-Invoke hook raises a debconf dialog when stdout is not a tty, and sudo
  # does not pass the caller's value through, so it must sit on this command line.
  # --no-update after the verb: apt update has just refreshed the lists, and nala's own refresh would print a second copy of every signer error.
  sudo -H DEBIAN_FRONTEND=noninteractive nala full-upgrade --no-update "${APT_CONFFILE_OPTS[@]}" -y \
    < /dev/null || { log_error "nala full-upgrade failed"; return 1; }
  sudo -H DEBIAN_FRONTEND=noninteractive nala autoremove -y < /dev/null || { log_error "nala autoremove failed"; return 1; }
  log_info "Updated apt packages"
}

# Whether this host can refresh snaps. A named function rather than an inline
# `command -v snap`, so a test can override it directly.
#
# Tests must NOT try to hide snap by stripping PATH. On Ubuntu 24.04 — which is
# what ubuntu-latest runs — snap lives in /usr/bin alongside bash, grep, sed,
# awk, mktemp, cp and rm, so removing "the directory containing snap" removes
# the whole toolchain. That passed on macOS, where no /usr/bin/snap exists, and
# failed three tests in CI. Removing a directory to drop one binary is the same
# defect this branch already fixed once for tests/mocks; this seam removes the
# class rather than the instance.
_snap_available() {
  command -v snap > /dev/null 2>&1
}

update_snap_packages() {
  sudo snap refresh || { log_error "snap refresh failed"; return 1; }
  log_info "Updated snap packages"
}

# A function so tests can redefine it rather than edit PATH: removing
# tests/mocks from PATH would expose the real /usr/bin/flatpak on claude and
# workstation (tdd.md E2).
_flatpak_available() {
  command -v flatpak > /dev/null 2>&1
}

# flatpak names NVIDIA GL extensions after the loaded module's version with dots
# turned into dashes, read from this same file (flatpak 1.16.6 common/flatpak-utils.c).
_nvidia_loaded_version() {
  local _f="${_NVIDIA_MODULE_VERSION_FILE:-/sys/module/nvidia/version}" _v=""
  [[ -r "${_f}" ]] || return 1
  IFS= read -r _v < "${_f}" || [[ -n "${_v}" ]] || return 1
  [[ "${_v}" =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1
  printf '%s\n' "${_v//./-}"
}

# System installation only, by design (spec N1).
_flatpak_nvidia_gl_refs() {
  local _list
  _list="$(flatpak list --system --runtime --columns=application,arch,branch)" || return 1
  awk -F'\t' '$1 ~ /^org\.freedesktop\.Platform\.GL(32)?\.nvidia-/ { print $1 "/" $2 "/" $3 }' <<<"${_list}"
}

# System installation only, by design (spec N1).
# 0 apps installed, 1 none, 2 the list failed.
_flatpak_has_apps() {
  local _list
  _list="$(flatpak list --system --app --columns=application)" || return 2
  [[ -n "${_list//[[:space:]]/}" ]]
}

# Spec: docs/superpowers/specs/2026-10-12-flatpak-update-design.md
# Removes nothing by name: a plain `flatpak update` already auto-prunes GL
# extensions for inactive drivers (autoprune-unless = active-gl-driver).
update_flatpak_packages() {
  local _loaded _refs _apps_rc
  sudo flatpak update -y --noninteractive --system || { log_error "flatpak update failed"; return 1; }
  sudo flatpak uninstall -y --noninteractive --system --unused || { log_error "flatpak uninstall --unused failed"; return 1; }
  if ! _loaded="$(_nvidia_loaded_version)"; then
    log_info "Updated flatpak runtimes"
    return 0
  fi
  _refs="$(_flatpak_nvidia_gl_refs)" || { log_error "flatpak: cannot list runtimes"; return 1; }
  _apps_rc=0
  _flatpak_has_apps || _apps_rc=$?
  [[ ${_apps_rc} -ne 2 ]] || { log_error "flatpak: cannot list apps"; return 1; }
  if [[ ${_apps_rc} -eq 0 ]] && ! grep -q "^org\.freedesktop\.Platform\.GL\.nvidia-${_loaded}/" <<<"${_refs}"; then
    printf 'flatpak: no GL.nvidia-%s installed for loaded driver %s; flatpak apps get no NVIDIA GL. Flathub may not publish it yet: re-run -t update later.\n' \
      "${_loaded}" "${_loaded//-/.}"
    return 2
  fi
  log_info "Updated flatpak runtimes"
}

# Wrapper retained so existing callers/tests that invoke the combined
# operation keep working. Runs both halves unconditionally — snap should
# still refresh even when apt fails — and reports failure if either did.
#
# It has NO production caller: run_update calls update_apt_packages and
# update_snap_packages directly so each gets its own summary row. The snap
# gate is duplicated here rather than left to the caller because this
# function's name makes it the obvious entry point for a future caller, and
# an ungated snap refresh on a host without snapd is the permanently-red
# summary row the split was written to remove. Both paths must agree.
update_system_packages() {
  local _rc=0
  update_apt_packages || _rc=1
  if _snap_available; then
    update_snap_packages || _rc=1
  else
    log_info "snap not installed on this host — skipping snap refresh"
  fi
  return "${_rc}"
}

# Joins its arguments with "|" for an awk -v value: BWK awk (macOS) rejects a
# literal newline in -v, and no prefix or token contains "|".
_apt_signer_awk_list() {
  local IFS='|'
  printf '%s' "$*"
}

# Reads apt output on stdin; prints "host<TAB>token" once per distinct host
# (lowercased, no userinfo or port) named on a signature-failure line, so
# callers need not re-parse apt's wording.
_apt_stale_signer_hosts() {
  local _prefixes _tokens
  # Empty lists would skip every line and read as "no stale signer"; refuse instead.
  ((${#APT_SIGNER_PREFIXES[@]} && ${#APT_SIGNER_TOKENS[@]})) \
    || { log_error "_apt_stale_signer_hosts: signer lists undefined (lib/constants.sh not sourced)"; return 1; }
  _prefixes="$(_apt_signer_awk_list "${APT_SIGNER_PREFIXES[@]}")" || return 1
  _tokens="$(_apt_signer_awk_list "${APT_SIGNER_TOKENS[@]}")" || return 1
  awk -v prefixes="${_prefixes}" -v tokens="${_tokens}" '
    BEGIN {
      np = split(prefixes, pre, "|")
      nt = split(tokens, tok, "|")
    }
    {
      sub(/\r$/, "")
      ok = 0
      for (i = 1; i <= np; i++) {
        if (substr($0, 1, length(pre[i])) == pre[i]) { ok = 1; break }
      }
      if (!ok) next
      found = ""
      for (i = 1; i <= nt; i++) {
        if (index($0, tok[i]) > 0) { found = tok[i]; break }
      }
      if (found == "") next
      rest = $0
      # authority = text after the scheme up to the first / quote or space
      while (match(rest, /https?:\/\/[^\/\047 ]+/)) {
        url = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/^https?:\/\//, "", url)
        sub(/^[^@]*@/, "", url)
        sub(/:[0-9]*$/, "", url)
        url = tolower(url)
        if (!(url in seen)) { seen[url] = 1; printf "%s\t%s\n", url, found }
      }
    }
  '
}

# Maps a host named by a signature failure to its one-line remedy, so the
# update summary can tell the operator what to do instead of just that it broke.
# The nvidia, gcloud and opentofu arms track their install-time key-fetch guards in
# _install_ubuntu_nvidia, _install_ubuntu_cloud_tools and _install_ubuntu_misc. The
# first arm (re-run -t developer) assumes those fetches stay unconditional. The
# microsoft and albert arms depend on the MS_GPG_FPR and ALBERT_GPG_FPR pins. Change
# any of those and the matching arm changes with it.
_apt_signer_remedy() {
  case "$1" in
    download.docker.com | pkgs.k8s.io | prod-cdn.packages.k8s.io | deb.releases.teleport.dev | pkg.cloudflareclient.com | download.virtualbox.org | cli.github.com)
      printf '%s\n' "re-run ./setup_env.sh -t developer (it re-fetches this key); if this line persists after that run, the publisher's own key is at fault, so refresh it by hand"
      ;;
    nvidia.github.io)
      printf '%s\n' 'sudo rm /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg, then re-run ./setup_env.sh -t developer'
      ;;
    packages.cloud.google.com)
      printf '%s\n' 'sudo rm /etc/apt/sources.list.d/google-cloud-sdk.list, then re-run ./setup_env.sh -t developer'
      ;;
    packages.opentofu.org)
      # Two steps because the installer re-fetches only when tofu is absent; staging
      # keeps a failed or non-key download away from the live keyring.
      # shellcheck disable=SC2016 # the text is shown to the operator to paste; $d must stay literal
      printf '%s\n' 'Stage and show: `d=$(mktemp -d) && curl -fsSL -o "$d/key" https://packages.opentofu.org/opentofu/tofu/gpgkey && gpg --batch --dearmor -o "$d/ring" "$d/key" && gpg --show-keys "$d/ring" && echo "$d"`. Compare the printed fingerprint with OpenTofu'"'"'s published key. Then install: `sudo install -m 0644 "$d/ring" /etc/apt/keyrings/opentofu-archive-keyring.gpg.new && sudo mv -f /etc/apt/keyrings/opentofu-archive-keyring.gpg.new /etc/apt/keyrings/opentofu-archive-keyring.gpg && rm -rf "$d"`'
      ;;
    packages.microsoft.com)
      printf '%s\n' "verify Microsoft's new key, replace keys/microsoft.asc and bump MS_GPG_FPR in lib/constants.sh"
      ;;
    download.opensuse.org)
      printf '%s\n' "verify the albert OBS key's new fingerprint and bump ALBERT_GPG_FPR in lib/constants.sh"
      ;;
    *)
      printf '%s\n' 'dotfiles has no remedy for this host; refresh its key by hand'
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
