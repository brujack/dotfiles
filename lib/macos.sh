#!/usr/bin/env bash
# lib/macos.sh — macOS-specific install functions

install_rosetta() {
  # Determine OS version
  # Save current IFS state
  OLDIFS=$IFS
  IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(sw_vers -productVersion)"

  # Restore IFS to previous state
  IFS=$OLDIFS
  exitcode=0

  # Check to see if the Mac is reporting itself as running macOS 11 or higher
  if [[ ${osvers_major} -ge 11 ]]; then

    # Check to see if the Mac needs Rosetta installed by testing the processor
    processor=$(sysctl -n machdep.cpu.brand_string)

    if [[ "$processor" == *"Intel"* ]]; then
      printf "%s processor installed. No need to install Rosetta.\\n" "${processor}"
    else

      # Check for Rosetta "oahd" process. If not found, perform a non-interactive install of Rosetta.
      if pgrep oahd >/dev/null 2>&1; then
          printf "Rosetta is already installed and running. Nothing to do.\\n"
      else
          softwareupdate --install-rosetta --agree-to-license

          if [[ $? -eq 0 ]]; then
            printf "Rosetta has been successfully installed.\\n"
          else
            printf "Rosetta installation failed!\\n"
            exitcode=1
          fi
      fi
    fi
  else
    printf "Mac is running macOS %s\\n" "$osvers_major.$osvers_minor.$osvers_dot_version."
    printf "No need to install Rosetta on this version of macOS.\\n"
  fi

  return $exitcode
}


install_homebrew() {
  if [[ "$(uname -s)" == "Darwin" ]]; then

    printf "Installing Xcode Command Line Tools...\\n"
    if ! xcode-select --print-path &>/dev/null; then
      printf "Installing Xcode Command Line Tools...\\n"
      xcode-select --install

      # Check if the installation was successful
      if [[ $? -ne 0 ]]; then
        printf "Failed to install Xcode Command Line Tools. Aborting.\\n"
        return 1
      fi

      # Accept Xcode license
      printf "Accepting Xcode license...\\n"
      sudo xcodebuild -license accept
      sudo xcodebuild -runFirstLaunch

      # Check if the license acceptance was successful
      if [[ $? -ne 0 ]]; then
        printf "Failed to accept Xcode license. Aborting.\\n"
        return 1
      fi
    fi
  fi

  printf "Installing Homebrew...\\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Check if the installation was successful
  if [[ $? -ne 0 ]]; then
    printf "Failed to install Homebrew. Aborting.\\n"
    return 1
  fi

  printf "Homebrew has been successfully installed.\\n"
  return 0
}

install_git() {
  printf "Installing git\\n"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if brew list | grep '^git$' &> /dev/null; then
      printf "Git (from Homebrew) is already installed.\\n"
      return 0
    fi
    printf "Installing git via Homebrew.\\n"
    if [[ -n ${MACOS} ]]; then
      if ! command -v brew &> /dev/null; then
        install_homebrew
      fi
      if command -v brew &> /dev/null; then
        brew_install_formula git
      else
        printf "Failed to install Homebrew. Cannot install Git.\\n"
        return 1
      fi
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
      printf "Installing git via apt\\n"
      sudo -H add-apt-repository ppa:git-core/ppa -y
      sudo -H apt update
      sudo -H apt dist-upgrade -y
      sudo -H apt install git -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
      printf "Installing git via yum\\n"
      sudo -H yum update -y
      sudo -H yum install git -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
      printf "Installing git via dnf\\n"
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
        printf "Installing Redhat git\\n"
        wget -O ${HOME}/software_downloads/git-${GIT_VER}.tar.gz ${GIT_URL}/git-${GIT_VER}.tar.gz
        tar -zxvf ${HOME}/software_downloads/git-${GIT_VER}.tar.gz -C ${HOME}/software_downloads
        cd ${HOME}/software_downloads/git-${GIT_VER} || exit
        make configure
        ./configure --prefix=/usr
        make -j $(nproc) all doc info
        sudo -H make install install-doc install-info
        if ! [[ -x "$(command -v git)" ]]; then
          printf "Git is not installed Redhat\\n"
          exit 1
        fi
        INSTALLED_GIT_VERSION=$(git --version | awk '{print $3}')
        if [[ "${INSTALLED_GIT_VERSION}" == "${GIT_VER}" ]]; then
          printf "Git %s is installed Redhat\\n" ${GIT_VER}
        else
          printf "Git %s is not installed Redhat\\n" ${GIT_VER}
          exit 1
        fi
      fi
    fi
  fi
  printf "Installed git\\n"
}

install_zsh() {
  printf "Installing zsh\\n"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if brew list | grep '^zsh$' &> /dev/null; then
      printf "zsh (from Homebrew) is already installed.\\n"
      return 0
    fi
    printf "Installing zsh via Homebrew.\\n"
    if [[ -n ${MACOS} ]]; then
      if ! command -v brew &> /dev/null; then
        install_homebrew
      fi
      if command -v brew &> /dev/null; then
        brew_install_formula zsh
      else
        printf "Failed to install Homebrew. Cannot install zsh.\\n"
        return 1
      fi
    fi
  elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Ubuntu" ]]; then
      printf "Installing zsh via apt\\n"
      sudo -H apt update
      sudo -H apt dist-upgrade -y
      sudo -H apt install zsh zsh-doc -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "CentOS Linux" ]]; then
      printf "Installing zsh via yum\\n"
      sudo -H yum update -y
      sudo -H yum install zsh -y
    elif [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') == "Fedora" ]]; then
      printf "Installing zsh via dnf\\n"
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
        printf "Installing Redhat zsh\\n"
        wget -O ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz http://www.zsh.org/pub/zsh-${ZSH_VER}.tar.xz
        tar -xvf ${HOME}/software_downloads/zsh-${ZSH_VER}.tar.xz -C ${HOME}/software_downloads
        cd ${HOME}/software_downloads/zsh-${ZSH_VER} || exit
        ./configure --prefix=/usr/local --bindir=/usr/local/bin --sysconfdir=/etc/zsh --enable-etcdir=/etc/zsh
        make
        sudo -H make install
        if [[ ! $(grep -Fxq "/usr/local/bin/zsh" /etc/shells) ]]; then
          sudo -H sh -c 'echo /usr/local/bin/zsh >> /etc/shells'
        fi
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
          printf "zsh is not installed Redhat\\n"
          exit 1
        fi
        INSTALLED_ZSH_VERSION=$(zsh --version | awk '{print $2}')
        if [[ "${INSTALLED_ZSH_VERSION}" == "${ZSH_VER}" ]]; then
          printf "zsh %s is installed Redhat\\n" ${ZSH_VER}
        else
          printf "zsh %s is not installed Redhat\\n" ${ZSH_VER}
          exit 1
        fi
      fi
    fi
  printf "Installed zsh\\n"
}

setup_zsh_as_default_shell() {
  printf "Setting ZSH as shell...\\n"

  # Set the ZSH path based on the value of REDHAT
  ZSH_PATH=${REDHAT:+"/usr/local/bin/zsh"}
  ZSH_PATH=${ZSH_PATH:-"/bin/zsh"}

  if [[ ${SHELL} != "${ZSH_PATH}" ]]; then
    if [[ -x "${ZSH_PATH}" ]]; then
      chsh -s "${ZSH_PATH}"
      printf "Changed default shell to %s\\n" "${ZSH_PATH}"
    else
      printf "Error: %s does not exist\\n" "${ZSH_PATH}"
    fi
  fi
}
