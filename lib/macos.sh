#!/usr/bin/env bash
# lib/macos.sh — macOS-specific install functions

install_rosetta() {
  # Determine OS version
  # Save current IFS state
  OLDIFS=$IFS
  IFS='.' read -r osvers_major osvers_minor osvers_dot_version <<< "$(sw_vers -productVersion)"

  # Restore IFS to previous state
  IFS=$OLDIFS
  exitcode=0

  # Check to see if the Mac is reporting itself as running macOS 11 or higher
  if [[ ${osvers_major} -ge 11 ]]; then

    # Check to see if the Mac needs Rosetta installed by testing the processor
    processor=$(sysctl -n machdep.cpu.brand_string)

    if [[ "$processor" == *"Intel"* ]]; then
      log_info "${processor} processor installed. No need to install Rosetta."
    else

      # Prefer package check over process check; oahd may not be running even when Rosetta is installed.
      if pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
        log_info "Rosetta package is already installed. Nothing to do."
      # Keep the process check as a fallback signal used by existing environments/tests.
      elif pgrep oahd >/dev/null 2>&1; then
        log_info "Rosetta is already installed and running. Nothing to do."
      else
        softwareupdate --install-rosetta --agree-to-license

        if [[ $? -eq 0 ]]; then
          log_info "Rosetta has been successfully installed."
        else
          log_error "Rosetta installation failed!"
          exitcode=1
        fi
      fi
    fi
  else
    log_info "Mac is running macOS $osvers_major.$osvers_minor.$osvers_dot_version."
    log_info "No need to install Rosetta on this version of macOS."
  fi

  return $exitcode
}


install_homebrew() {
  if [[ "$(uname -s)" == "Darwin" ]]; then

    log_info "Installing Xcode Command Line Tools..."
    if ! xcode-select --print-path &>/dev/null; then
      log_info "Installing Xcode Command Line Tools..."
      xcode-select --install

      # Check if the installation was successful
      if [[ $? -ne 0 ]]; then
        log_error "Failed to install Xcode Command Line Tools. Aborting."
        return 1
      fi

      # Accept Xcode license
      log_info "Accepting Xcode license..."
      sudo xcodebuild -license accept
      sudo xcodebuild -runFirstLaunch

      # Check if the license acceptance was successful
      if [[ $? -ne 0 ]]; then
        log_error "Failed to accept Xcode license. Aborting."
        return 1
      fi
    fi
  fi

  log_info "Installing Homebrew..."
  local _brew_script
  _brew_script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    log_error "Failed to download Homebrew installer. Aborting."
    return 1
  }
  /bin/bash -c "${_brew_script}"

  # Check if the installation was successful
  if [[ $? -ne 0 ]]; then
    log_error "Failed to install Homebrew. Aborting."
    return 1
  fi

  log_info "Homebrew has been successfully installed."
  return 0
}

install_git_macos() {
  log_info "Installing git"
  if command -v brew &> /dev/null && brew list | grep '^git$' &> /dev/null; then
    log_info "Git (from Homebrew) is already installed."
    return 0
  fi
  log_info "Installing git via Homebrew."
  if ! command -v brew &> /dev/null; then
    install_homebrew
  fi
  if command -v brew &> /dev/null; then
    brew_install_formula git
  else
    log_error "Failed to install Homebrew. Cannot install Git."
    return 1
  fi
  log_info "Installed git"
}

install_zsh_macos() {
  log_info "Installing zsh"
  if command -v brew &> /dev/null && brew list | grep '^zsh$' &> /dev/null; then
    log_info "zsh (from Homebrew) is already installed."
    return 0
  fi
  log_info "Installing zsh via Homebrew."
  if ! command -v brew &> /dev/null; then
    install_homebrew
  fi
  if command -v brew &> /dev/null; then
    brew_install_formula zsh
  else
    log_error "Failed to install Homebrew. Cannot install zsh."
    return 1
  fi
  log_info "Installed zsh"
}


install_macos_casks() {
  brew bundle --file "${BREWFILE_LOC}/Brewfile" || return 1
  if [[ -n ${HAS_GUI} ]]; then
    brew bundle --file "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui" || return 1
  fi
  if [[ -n ${HAS_DEVTOOLS} ]]; then
    brew bundle --file "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools" || return 1
  fi
  # Trust third-party taps for Homebrew 6.0 (idempotent — no-op if already trusted or tap absent)
  brew trust cloudflare/cloudflare datawire/blackbird getagentseal/codeburn gitguardian/tap go-task/tap oven-sh/bun redpanda-data/tap snyk/tap teamookla/speedtest 2>/dev/null || true
}

install_macos_packages() {
  printf "Creating %s\n" "${BREWFILE_LOC}"
  mkdir -p ${BREWFILE_LOC}

  rm -f ${BREWFILE_LOC}/Brewfile
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile ${BREWFILE_LOC}/Brewfile
  if [[ -L ${BREWFILE_LOC}/Brewfile ]]; then
    printf "Brewfile is linked\n"
  fi

  if ! [[ -x "$(command -v brew)" ]]; then
    install_homebrew || return 1
  else
    brew_update || return 1
    printf "Installing other brew stuff...\n"
    brew_tap_if_missing homebrew/bundle || return 1
    install_macos_casks || return 1

    printf "Cleaning Homebrew up...\n"
    brew cleanup
  fi

  printf "Updating app store apps via softwareupdate\n"
  sudo -H softwareupdate --install --all --verbose

  printf "Setting up macOS defaults\n"
  ${HOME}/scripts/.osx.sh
}
