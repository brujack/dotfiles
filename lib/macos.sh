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

      # Check for Rosetta "oahd" process. If not found, perform a non-interactive install of Rosetta.
      if pgrep oahd >/dev/null 2>&1; then
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
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Check if the installation was successful
  if [[ $? -ne 0 ]]; then
    log_error "Failed to install Homebrew. Aborting."
    return 1
  fi

  log_info "Homebrew has been successfully installed."
  return 0
}

install_git() {
  log_info "Installing git"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if brew list | grep '^git$' &> /dev/null; then
      log_info "Git (from Homebrew) is already installed."
      return 0
    fi
    log_info "Installing git via Homebrew."
    if [[ -n ${MACOS} ]]; then
      if ! command -v brew &> /dev/null; then
        install_homebrew
      fi
      if command -v brew &> /dev/null; then
        brew_install_formula git
      else
        log_error "Failed to install Homebrew. Cannot install Git."
        return 1
      fi
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
      log_info "Installing git via apt"
      sudo -H add-apt-repository ppa:git-core/ppa -y
      sudo -H apt update
      sudo -H apt dist-upgrade -y
      sudo -H apt install git -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
      log_info "Installing git via yum"
      sudo -H yum update -y
      sudo -H yum install git -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
      log_info "Installing git via dnf"
      sudo -H dnf update -y
      sudo -H dnf install git -y
    fi
    # because the version of git is so old on redhat, we need to install a newer version by compiling it
    if [[ -n ${REDHAT} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install asciidoc -y
      sudo -H dnf install autoconf -y
      sudo -H dnf install cpan -y
      sudo -H dnf install docbook2X -y
      sudo -H dnf install make -y
      sudo -H dnf install perl-App-cpanminus -y
      sudo -H dnf install perl-ExtUtils-MakeMaker -y
      sudo -H dnf install perl-IO-Socket-SSL -y
      sudo -H dnf install wget -y
      sudo -H dnf install xmlto -y
      #cpan to properly compile git on redhat
      cpan App::cpanminus
      cpanm Test::Simple
      cpanm Fatal
      cpanm XML::SAX
      if [[ ! -f ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ]]; then
        log_info "Installing Redhat git"
        wget -O ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ${GIT_URL}/git-${GIT_VER}.tar.gz
        tar -zxvf ${HOME}/software_downloads/git-${GIT_VER}.tar.gz -C ${HOME}/software_downloads
        cd ${HOME}/software_downloads/git-${GIT_VER} || exit
        make configure
        ./configure --prefix=/usr
        make -j "$(nproc)" all doc info
        sudo -H make install install-doc install-info
        if ! [[ -x "$(command -v git)" ]]; then
          log_error "Git is not installed Redhat"
          exit 1
        fi
        INSTALLED_GIT_VERSION=$(git --version | awk '{print $3}')
        if [[ "${INSTALLED_GIT_VERSION}" == "${GIT_VER}" ]]; then
          log_info "Git ${GIT_VER} is installed Redhat"
        else
          log_error "Git ${GIT_VER} is not installed Redhat"
          exit 1
        fi
      fi
    fi
  fi
  log_info "Installed git"
}

install_zsh() {
  log_info "Installing zsh"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if brew list | grep '^zsh$' &> /dev/null; then
      log_info "zsh (from Homebrew) is already installed."
      return 0
    fi
    log_info "Installing zsh via Homebrew."
    if [[ -n ${MACOS} ]]; then
      if ! command -v brew &> /dev/null; then
        install_homebrew
      fi
      if command -v brew &> /dev/null; then
        brew_install_formula zsh
      else
        log_error "Failed to install Homebrew. Cannot install zsh."
        return 1
      fi
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
      log_info "Installing zsh via apt"
      sudo -H apt update
      sudo -H apt dist-upgrade -y
      sudo -H apt install zsh zsh-doc -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
      log_info "Installing zsh via yum"
      sudo -H yum update -y
      sudo -H yum install zsh -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
      log_info "Installing zsh via dnf"
      sudo -H dnf update -y
      sudo -H dnf install zsh -y
    fi
    # because the version of zsh is so old on redhat, we need to install a newer version by compiling it
    if [[ -n ${REDHAT} ]]; then
      if rhel_installed_package zsh; then
        sudo -H yum remove zsh -y
      fi
      sudo -H yum update
      sudo -H yum install gcc -y
      sudo -H yum install make -y
      sudo -H yum install ncurses-devel -y
      if [[ ! -f ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz ]]; then
        log_info "Installing Redhat zsh"
        wget -O ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz http://www.zsh.org/pub/zsh-${ZSH_VER}.tar.xz
        tar -xvf ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz -C ${HOME}/software_downloads
        cd ${HOME}/software_downloads/zsh-${ZSH_VER} || exit
        ./configure --prefix=/usr/local --bindir=/usr/local/bin --sysconfdir=/etc/zsh --enable-etcdir=/etc/zsh
        make
        sudo -H make install
        # shellcheck disable=SC2143 # grep -Fxq has no output; checking if line absent
        if [[ ! $(grep -Fxq "/usr/local/bin/zsh" /etc/shells) ]]; then
          sudo -H sh -c 'echo /usr/local/bin/zsh >> /etc/shells'
        fi
        # shellcheck disable=SC2143 # grep -Fxq has no output; checking if line absent
        if [[ ! $(grep -Fxq "/bin/zsh" /etc/shells) ]]; then
          sudo -H sh -c 'echo /bin/zsh >> /etc/shells'
        fi
      fi
      if [[ -f /bin/zsh ]]; then
        sudo -H rm -f /bin/zsh
      fi
      if [[ ! -L /bin/zsh ]]; then
        if [[ -f /usr/local/bin/zsh ]]; then
          sudo -H ln -s /usr/local/bin/zsh /bin/zsh
        fi
      fi
      if ! [[ -x "$(command -v zsh)" ]]; then
          log_error "zsh is not installed Redhat"
          exit 1
        fi
        INSTALLED_ZSH_VERSION=$(zsh --version | awk '{print $2}')
        if [[ "${INSTALLED_ZSH_VERSION}" == "${ZSH_VER}" ]]; then
          log_info "zsh ${ZSH_VER} is installed Redhat"
        else
          log_error "zsh ${ZSH_VER} is not installed Redhat"
          exit 1
        fi
      fi
    fi
  log_info "Installed zsh"
}

setup_zsh_as_default_shell() {
  log_info "Setting ZSH as shell..."

  # Set the ZSH path based on the value of REDHAT
  ZSH_PATH=${REDHAT:+"/usr/local/bin/zsh"}
  ZSH_PATH=${ZSH_PATH:-"/bin/zsh"}

  if [[ ${SHELL} != "${ZSH_PATH}" ]]; then
    if [[ -x "${ZSH_PATH}" ]]; then
      chsh -s "${ZSH_PATH}"
      log_info "Changed default shell to ${ZSH_PATH}"
    else
      log_error "Error: ${ZSH_PATH} does not exist"
    fi
  fi
}

install_macos_casks() {
  brew bundle --file "${BREWFILE_LOC}/Brewfile"
  [[ -n ${HAS_GUI} ]]      && brew bundle --file "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  [[ -n ${HAS_DEVTOOLS} ]] && brew bundle --file "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
}
