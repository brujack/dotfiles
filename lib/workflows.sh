#!/usr/bin/env bash
# lib/workflows.sh — top-level workflow functions dispatched by setup_env.sh

run_setup_user() {
  # need to make sure that some base packages are installed
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! [ -x "$(command -v dnf)" ]; then
      printf "Installing dnf\\n"
      sudo -H yum update -y
      sudo -H yum install dnf -y
      if ! [ -x "$(command -v dnf)" ]; then
        printf "Failed to install dnf\\n"
        exit 1
      fi
      printf "Installed dnf\\n"
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    printf "Installing Rosetta if necessary\\n"
    install_rosetta
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${FEDORA} ]] || [[ -n ${CENTOS} ]]; then
    install_git
  fi

  mkdir -p ${HOME}/software_downloads

  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then
    install_zsh
  fi

  if [[ -n ${LINUX} ]]; then
    install_bats
  fi

  printf "Creating %s/bin\\n" "${HOME}"
  mkdir -p ${HOME}/bin

  printf "Creating %s\\n" "${PERSONAL_GITREPOS}"
  mkdir -p ${PERSONAL_GITREPOS}

  clone_or_update_dotfiles

  setup_dotfile_symlinks

  setup_zsh_as_default_shell

  printf "Setting up cheat.sh\\n"
  if [[ -d ${HOME}/bin ]]; then
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
    fi
    if [[ -n ${CENTOS} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install curl -y
    fi
    if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H yum update
      sudo -H yum install curl -y
    fi
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 750 ${HOME}/bin/cht.sh
  fi
  if [[ -x $(command -v cht.sh) ]]; then
    printf "cht.sh is installed\\n"
  fi

  printf "Creating %s/.zsh.d\\n" "${HOME}"
  mkdir -p ${HOME}/.zsh.d
  if [[ ! -f ${HOME}/.zsh.d/_cht ]]; then
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi

  printf "Creating %s/go-work\\n" "${HOME}"
  mkdir -p ${HOME}/go-work
  if [[ -d ${HOME}/go-work ]]; then
    printf "Created %s/go-work\\n" "${HOME}"
  fi
}

run_setup_or_developer() {
  setup_credential_directories

  if [[ -n ${MACOS} ]]; then
    install_macos_packages
  fi

  if [[ -n ${UBUNTU} ]]; then
    install_ubuntu_packages
  fi

  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf update -y
    sudo -H dnf install bzip2 -y
    sudo -H dnf install bzip2-devel -y
    sudo -H dnf install cpan -y
    sudo -H dnf install curl -y
    sudo -H dnf install fzf -y
    sudo -H dnf install gcc -y
    sudo -H dnf install htop -y
    sudo -H dnf install iotop -y
    sudo -H dnf install iperf3 -y
    sudo -H dnf install libffi-devel -y
    sudo -H dnf install make -y
    sudo -H dnf install openssl-devel -y
    sudo -H dnf install python-setuptools -y
    sudo -H dnf install python3-setuptools -y
    sudo -H dnf install python3-devel -y
    sudo -H dnf install python3-pip -y
    sudo -H dnf install readline-devel -y
    sudo -H dnf install sqlite -y
    sudo -H dnf install sqlite-devel -y
    sudo -H dnf install the_silver_searcher -y
    sudo -H dnf install tmux -y
    sudo -H dnf install unzip -y
    sudo -H dnf install wget -y
    sudo -H dnf install xz -y
    sudo -H dnf install xa-devel -y
    sudo -H dnf install zlib-devel -y

    printf "Installing pyenv\\n"
    curl https://pyenv.run | bash
    if [[ -x $(command -v pyenv) ]]; then
      printf "pyenv is installed\\n"
    fi

    printf "Installing shellcheck RHEL\\n"
    if [[ ! -d ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER} ]]; then
      wget -O ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz https://shellcheck.storage.googleapis.com/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz
      xz --decompress ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar.xz
      cd ${HOME}/software_downloads || exit
      tar -xf ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}.linux.x86_64.tar
      sudo cp -a ${HOME}/software_downloads/shellcheck-v${SHELLCHECK_VER}/shellcheck /usr/local/bin/
      sudo chmod 755 /usr/local/bin/shellcheck
      sudo chown root:root /usr/local/bin/shellcheck
      if [[ -x $(command -v shellcheck) ]]; then
        printf "shellcheck is installed\\n"
      fi
    fi

    printf "Installing keychain RHEL\\n"
    sudo -H rpm --import http://wiki.psychotic.ninja/RPM-GPG-KEY-psychotic
    sudo -H rpm -ivh http://packages.psychotic.ninja/6/base/i386/RPMS/psychotic-release-1.0.0-1.el6.psychotic.noarch.rpm
    sudo -H yum --enablerepo=psychotic install keychain -y
    if [[ -x $(command -v keychain) ]]; then
      printf "keychain is installed\\n"
    fi

    printf "Installing azure-cli RHEL\\n"
    sudo -H rpm --import http://packages.microsoft.com/keys/microsoft.asc
    sudo -H sh -c 'echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=http://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=http://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
    sudo -H dnf update -y
    sudo -H dnf install azure-cli -y
    if [[ -x $(command -v az) ]]; then
      printf "az is installed\\n"
    fi

    printf "Installing git credential manager RHEL\\n"
    sudo -H dnf install http://github.com/Microsoft/Git-Credential-Manager-for-Mac-and-Linux/releases/download/git-credential-manager-2.0.4/git-credential-manager-2.0.4-1.noarch.rpm -y

    printf "Installing powershell RHEL\\n"
    curl http://packages.microsoft.com/config/rhel/7/prod.repo | sudo -H tee /etc/yum.repos.d/microsoft.repo
    sudo -H dnf update -y
    sudo -H dnf install powershell -y
    if [[ -x $(command -v pwsh) ]]; then
      printf "pwsh is installed\\n"
    fi

    printf "Installing npm RHEL\\n"
    curl -sL http://rpm.nodesource.com/setup_12.x | sudo -E bash -
    sudo -H dnf update -y
    sudo -H dnf install nodejs -y

    printf "Installing glances cpu monitor RHEL\\n"
    sudo -H python -m pip install glances
    if [[ -x $(command -v glances) ]]; then
      printf "glances is installed\\n"
    fi

    printf "Installing go RHEL\\n"
    if [[ ! -f ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz ]]; then
      wget -O ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz https://dl.google.com/go/go${GO_VER}.linux-amd64.tar.gz
      sudo tar -C /usr/local -xzf ${HOME}/software_downloads/go${GO_VER}.linux-amd64.tar.gz
      if [[ -x $(command -v go) ]]; then
        printf "go is installed\\n"
      fi
    fi

    printf "Installing google-cloud-sdk RHEL\\n"
    if [[ ! -f /etc/yum.repos.d/google-cloud-sdk.repo ]]; then
      sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=http://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://packages.cloud.google.com/yum/doc/yum-key.gpg
       http://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
    fi
    sudo -H dnf update -y
    sudo -H dnf install google-cloud-sdk -y
    sudo -H dnf install google-cloud-sdk-app-engine-python -y
    sudo -H dnf install google-cloud-sdk-app-engine-python-extras -y
    sudo -H dnf install google-cloud-sdk-app-engine-go -y

    printf "Installing kubectl RHEL\\n"
    if [[ ! -f /etc/yum.repos.d/kubernetes.repo ]]; then
      echo "${RHEL_KUBECTL_REPO}" | sudo tee /tmp/kubernetes.repo > /dev/null
      sudo chown root:root /tmp/kubernetes.repo
      sudo chmod 644 /tmp/kubernetes.repo
      sudo mv /tmp/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
    fi
    sudo -H dnf update -y
    sudo -H dnf install kubectl -y
    if [[ -x $(command -v kubectl) ]]; then
      printf "kubectl is installed\\n"
    fi

    printf "Installing Hashicorp Packer RHEL\\n"
    if [[ ! -d ${HOME}/software_downloads/packer_${PACKER_VER} ]]; then
      wget -O ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip ${HASHICORP_URL}/packer/${PACKER_VER}/packer_${PACKER_VER}_linux_amd64.zip
      unzip ${HOME}/software_downloads/packer_${PACKER_VER}_linux_amd64.zip -d ${HOME}/software_downloads/packer_${PACKER_VER}
      sudo cp -a ${HOME}/software_downloads/packer_${PACKER_VER}/packer /usr/local/bin/
      sudo chmod 755 /usr/local/bin/packer
      sudo chown root:root /usr/local/bin/packer
      if [[ -x $(command -v packer) ]]; then
        printf "packer is installed\\n"
      fi
    fi

  fi

  if [[ -n ${CENTOS} ]]; then
    sudo -H yum update -y
    sudo -H yum install curl -y
    sudo -H yum install gcc -y
    sudo -H yum install git -y
    sudo -H yum install htop -y
    sudo -H yum install iotop -y
    sudo -H yum install keychain -y
    sudo -H yum install make -y
    sudo -H yum install python-setuptools -y
    sudo -H yum install python3-setuptools -y
    sudo -H yum install python3-pip -y
    sudo -H yum install the_silver_searcher -y
    sudo -H yum install unzip -y
    sudo -H yum install wget -y
    sudo -H yum install zsh -y
  fi

  if [[ -n ${LINUX} ]]; then
    printf "Installing Hashicorp Terraform Linux with tfenv on Linux\\n"
    if [[ ! -d ${HOME}/.tfenv ]]; then
      git clone --recursive https://github.com/tfutils/tfenv.git ${HOME}/.tfenv
    fi

    printf "Linking terraform to /usr/local/bin\\n"
    sudo rm -f /usr/local/bin/terraform
    sudo ln -s ${HOME}/.tfenv/bin/terraform /usr/local/bin/terraform

    printf "Linking tfenv to /usr/local/bin\\n"
    sudo rm -f /usr/local/bin/tfenv
    sudo ln -s ${HOME}/.tfenv/bin/tfenv /usr/local/bin/tfenv

    if [[ -f ${HOME}/.tfenv/bin/tfenv ]]; then
      tfenv install ${TERRAFORM_VER}
    fi

    printf "Installing tflint\\n"
    if [[ -f ${HOME}/software_downloads/tflint_linux_amd64.zip ]]; then
      rm ${HOME}/software_downloads/tflint_linux_amd64.zip
      wget -O ${HOME}/software_downloads/tflint_linux_amd64.zip ${TFLINT_URL}
      sudo -H unzip ${HOME}/software_downloads/tflint_linux_amd64.zip -d /usr/local/bin
      sudo -H chmod 755 /usr/local/bin/tflint
    else
      wget -O ${HOME}/software_downloads/tflint_linux_amd64.zip ${TFLINT_URL}
      sudo -H unzip ${HOME}/software_downloads/tflint_linux_amd64.zip -d /usr/local/bin
      sudo -H chmod 755 /usr/local/bin/tflint
    fi
    if [[ -x $(command -v tflint) ]]; then
      printf "tflint is installed\\n"
    fi

    printf "Installing tfsec\\n"
    if [[ ! -f ${HOME}/software_downloads/tfsec-linux-amd64 ]]; then
      wget -O ${HOME}/software_downloads/tfsec-linux-amd64 ${TFSEC_URL}
      sudo -H mv ${HOME}/software_downloads/tfsec-linux-amd64 /usr/local/bin/tfsec
      sudo -H chmod 755 /usr/local/bin/tfsec
    fi
    if [[ -x $(command -v tfsec) ]]; then
      printf "tfsec is installed\\n"
    fi
  fi

  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on MacOS\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg ]]; then
      wget -O ${HOME}/software_downloads/awscli/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
      sudo installer -pkg ${HOME}/software_downloads/awscli/AWSCLIV2.pkg -target /
      rm -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed MacOS\\n"
      fi
    fi
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on Linux\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/awscliv2.zip ]]; then
      wget -O ${HOME}/software_downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
      unzip ${HOME}/software_downloads/awscli/awscliv2.zip -d ${HOME}/software_downloads/awscli
      sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
      rm -rf ${HOME}/software_downloads/awscli
      rm -f ${HOME}/software_downloads/awscli/awscliv2.zip
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed Linux\\n"
      fi
    fi
  fi

  printf "vim plugins setup\\n"
  mkdir -p ${HOME}/.vim/plugged
  if [[ -d ${HOME}/.vim/plugged ]]; then
    chmod 770 ${HOME}/.vim/plugged
  fi
  mkdir -p ${HOME}/.vim/autoload
  if [[ -d ${HOME}/.vim/autoload ]]; then
    chmod 770 ${HOME}/.vim/autoload
  fi
  if [[ ! -f ${HOME}/.vim/autoload/plug.vim ]]; then
    curl -fLo ${HOME}/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
}

run_developer_or_ansible() {
  printf "Installing json2yaml via npm\\n"
  npm install json2yaml

  printf "Installing ruby-install on linux\\n"
  if [[ -n ${LINUX} ]]; then
    if [[ ! -d ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER} ]]; then
      wget -O ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz https://github.com/postmodern/ruby-install/archive/v${RUBY_INSTALL_VER}.tar.gz
      tar -xzvf ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz -C ${HOME}/software_downloads/
      cd ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}/ || exit
      sudo make install
    fi
  fi

  printf "Installing chruby on linux\\n"
  if [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      if [[ ! -d ${HOME}/software_downloads/chruby-${CHRUBY_VER} ]]; then
        wget -O ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz https://github.com/postmodern/chruby/archive/v${CHRUBY_VER}.tar.gz
        tar -xzvf ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz -C ${HOME}/software_downloads/
        cd ${HOME}/software_downloads/chruby-${CHRUBY_VER}/ || exit
        sudo make install
      fi
    fi
  fi

  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    printf "Install ruby %s\\n" "${RUBY_VER}"
    if [[ -n ${MACOS} ]]; then
      # shellcheck disable=SC2046
      ruby-install ${RUBY_VER} -- --with-openssl-dir=$(brew --prefix openssl@3)
    fi
    if [[ -n ${LINUX} ]]; then
      if [[ -n ${FOCAL} ]]; then
        ruby-install ${RUBY_VER}
      elif [[ -n ${JAMMY} ]]; then
        # Ruby 4.0 requires OpenSSL 3; Jammy ships OpenSSL 3 at /usr by default
        OPENSSL_DIR="$(pkg-config --variable=prefix openssl 2>/dev/null)"
        ruby-install ${RUBY_VER} -- --with-openssl-dir="${OPENSSL_DIR:-/usr}"
      elif [[ -n ${NOBLE} ]]; then
        if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
          # Optional but often helpful: point Ruby at Ubuntu's OpenSSL
          OPENSSL_DIR="$(pkg-config --variable=libdir openssl 2>/dev/null | sed 's#/lib$##')"
          RUBY_CONFIGURE_OPTS="--with-openssl-dir=${OPENSSL_DIR:-/usr}" rbenv install ${RUBY_VER}
          rbenv global ${RUBY_VER}
          rbenv rehash
        fi
      fi
    fi
    INSTALLED_RUBY_VERSION=$(ruby --version | awk '{print $2}')
    if [[ ${INSTALLED_RUBY_VERSION} == "${RUBY_VER}" ]]; then
      printf "ruby %s is installed\\n" "${RUBY_VER}"
    fi
  fi

  if [[ -n ${LINUX} ]]; then
    printf "installing github cli on linux\\n"
    if [[ -n ${UBUNTU} ]]; then
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo -H apt update
      sudo -H apt install gh
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed Ubuntu\\n"
      fi
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H dnf install 'dnf-command(config-manager)'
      sudo -H dnf config-manager --add-repo http://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install gh --repo gh-cli
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed RHEL\\n"
      fi
    fi
  fi

  printf "Setup kitchen\\n"
  if [[ -n ${MACOS} ]]; then
    source ${CHRUBY_LOC}/chruby/chruby.sh
    source ${CHRUBY_LOC}/chruby/auto.sh
    chruby ruby-${RUBY_VER}
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      source ${CHRUBY_LOC}/chruby/chruby.sh
      source ${CHRUBY_LOC}/chruby/auto.sh
      chruby ruby-${RUBY_VER}
    elif [[ -n ${NOBLE} ]]; then
      if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
        rbenv install ${RUBY_VER}
      fi
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    gem install test-kitchen
    gem install kitchen-ansible
    gem install kitchen-docker
    gem install kitchen-inspec
    gem install kitchen-terraform
    gem install kitchen-verifier-serverspec
    gem install bundle
    gem install bundler
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      gem install test-kitchen
      gem install kitchen-ansible
      gem install kitchen-docker
      gem install kitchen-inspec
      gem install kitchen-terraform
      gem install kitchen-verifier-serverspec
      gem install bundle
      gem install bundler
    elif [[ -n ${NOBLE} ]]; then
      rbenv shell ${RUBY_VER}
      gem install test-kitchen
      gem install kitchen-ansible
      gem install kitchen-docker
      gem install kitchen-inspec
      gem install kitchen-terraform
      gem install kitchen-verifier-serverspec
      gem install bundle
      gem install bundler
    fi
  fi

  printf "Install terraspace\\n"
  gem install terraspace
  if [[ -x $(command -v terraspace) ]]; then
    printf "terraspace is installed\\n"
  fi

  printf "ANSIBLE setup\\n"
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    if [[ -n "${LINUX:-}" ]]; then
      # Keep pyenv's build definitions current (optional but useful)
      pyenv update

      # zsh-safe cleanup (avoids: zsh: no matches found)
      rm -rf "/tmp/python-build.*" 2>/dev/null || true

      # Force bundled libmpdec + keep Homebrew out of the build environment
      # shellcheck disable=SC2016 # vars expand inside bash -lc at runtime, not here
      env -i \
        HOME="$HOME" USER="$USER" SHELL="${SHELL:-/bin/bash}" TERM="$TERM" \
        PYTHON_VER="${PYTHON_VER}" \
        PYENV_ROOT="$HOME/.pyenv" \
        PYENV_VIRTUALENV_DISABLE_PROMPT=1 \
        PYTHON_CONFIGURE_OPTS="--with-system-libmpdec=no" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        bash -lc '
          set -euo pipefail
          export PATH="$PYENV_ROOT/bin:$PATH"
          eval "$(pyenv init -)"
          pyenv install -s -v "${PYTHON_VER}"
        '

    elif [[ -n "${MACOS:-}" ]]; then
      # macOS: normal pyenv install, use system/brew deps as you already have them
      pyenv install -s "${PYTHON_VER}"
    fi
  fi

  if ! [[ $(readlink "${HOME}/.pyenv/versions/ansible") == "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" ]]; then
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PYENV_VIRTUALENV_DISABLE_PROMPT=1
      if quiet_which pyenv; then
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
      fi
      pyenv virtualenv-delete -f ansible
      pyenv virtualenv "${PYTHON_VER}" ansible
      pyenv activate ansible
      printf "Installing Ansible dependencies...\\n"
      python -m pip install ansible ansible-lint certbot certbot-dns-cloudflare boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt
    fi
  fi

  printf "personal git repos cloning\\n"
  if ! [[ -d ${PERSONAL_GITREPOS}/dotfiles ]]; then
    git clone git@github.com:brujack/dotfiles.git ${PERSONAL_GITREPOS}/dotfiles
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform ]]; then
    git clone git@github.com:brujack/docker_container_terraform.git ${PERSONAL_GITREPOS}/docker_container_terraform
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible ]]; then
    git clone git@github.com:brujack/docker_container_terraform_packer_ansible.git ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/kubernetes ]]; then
    git clone git@github.com:brujack/kubernetes.git ${PERSONAL_GITREPOS}/kubernetes
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/pfsense_config ]]; then
    git clone git@github.com:brujack/pfsense_config.git ${PERSONAL_GITREPOS}/pfsense_config
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/python-learning ]]; then
    git clone git@github.com:brujack/python-learning.git ${PERSONAL_GITREPOS}/python-learning
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraform_ansible ]]; then
    git clone git@github.com:brujack/terraform_ansible.git ${PERSONAL_GITREPOS}/terraform_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraspace_env ]]; then
    git clone git@github.com:brujack/terraspace_env.git ${PERSONAL_GITREPOS}/terraspace_env
  fi

}

run_brew_install() {
  mkdir -p "${BREWFILE_LOC}"
  rm -f "${BREWFILE_LOC}/Brewfile"
  ln -s "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile" "${BREWFILE_LOC}/Brewfile"

  if ! quiet_which brew; then
    install_homebrew || return 1
  fi
  brew_update
  brew_tap_if_missing homebrew/bundle
  if [[ -n ${MACOS} ]]; then
    install_macos_casks
  fi
  brew cleanup
}

run_mas_install() {
  if [[ -z ${MACOS} ]]; then
    log_info "Skipping mas install — macOS only"
    return 0
  fi
  if ! quiet_which mas; then
    log_error "mas not found — run --brew-install first"
    return 1
  fi
  log_info "Installing/updating Mac App Store apps"
  mas upgrade
}

run_update() {
  local _run_all=0
  _any_update_flag || _run_all=1

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
      brew_update
      printf "Updating app store apps softwareupdate\\n"
      sudo -H softwareupdate --install --all --verbose
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    if command -v claude &>/dev/null; then
      printf "Updating Claude plugins\\n"
      claude plugins update superpowers && claude plugins update code-simplifier && claude plugins update context7
      printf "Updated Claude plugins\\n"
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    update_system_packages
    if [[ -n ${MACOS} ]]; then
      log_info "Updating mas packages"
      mas upgrade
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PIP:-} ]]; then
    printf "Updating pip3 packages\n"
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

      if command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
      fi

      pyenv shell ansible 2>/dev/null || true
      PYTHON="$(pyenv which python 2>/dev/null || command -v python3)"

      "$PYTHON" -m pip install -U pip setuptools wheel

      "$PYTHON" - <<'PY'
import json, subprocess, sys

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out)]

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY

      "$PYTHON" -m pip check || true
      printf "Updated pip packages\n"
    fi
  fi

  if [[ ${_run_all} -eq 1 ]]; then
    update_aws_cli
    update_rust
    if [[ -d ${HOME}/.tfenv ]]; then
      printf "Updating tfenv\\n"
      cd ${HOME}/.tfenv || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      printf "Updating oh-my-zsh\\n"
      cd ${HOME}/.oh-my-zsh || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      printf "Updating powerlevel10k\\n"
      cd ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      printf "Updating tpm\\n"
      cd ${HOME}/.tmux/plugins/tpm || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      printf "Updating cheat.sh\\n"
      curl https://cht.sh/:cht.sh > ~/bin/cht.sh
      chmod 754 ${HOME}/bin/cht.sh
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      printf "Updating cheat.sh tab completion\\n"
      curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
      printf "Updating zsh-autosuggestions\\n"
      cd ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    printf "updating ruby gems\\n"
    gem update
  fi
}

_fetch_github_latest() {
  local _repo="$1"
  local -a _curl_args=(-sf)
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    _curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${_curl_args[@]}" \
    "https://api.github.com/repos/${_repo}/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
    | sed 's/^v//'
}

_check_one_version() {
  local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5"

  if ! command -v "${_tool}" &>/dev/null; then
    printf "  [SKIP]     %-12s not installed\n" "${_tool}"
    return 0
  fi

  local _latest
  _latest=$(_fetch_github_latest "${_repo}")
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-12s could not fetch latest version\n" "${_tool}"
    return 0
  fi

  local _raw _installed
  _raw=$(${_cmd} 2>&1)
  _installed=$(printf '%s' "${_raw}" | grep -oE "${_regex}" | head -1)

  if [[ -z "${_installed}" ]]; then
    printf "  [WARN]     %-12s could not parse installed version\n" "${_tool}"
    return 0
  fi

  _installed="${_installed#v}"
  # Strip any leading non-numeric prefix (handles golang's "go1.x.y" tag format)
  _latest="${_latest#"${_latest%%[0-9]*}"}"

  if [[ "${_installed}" == "${_latest}" ]]; then
    printf "  [OK]       %-12s pinned=%-10s latest=%s\n" "${_tool}" "${_pinned}" "${_latest}"
    return 0
  else
    printf "  [OUTDATED] %-12s pinned=%-10s latest=%s  installed=%s\n" \
      "${_tool}" "${_pinned}" "${_latest}" "${_installed}"
    return 1
  fi
}

_update_url_pins() {
  local _tool="$1" _old="$2" _new="$3" _constants="$4"

  case "${_tool}" in
    go)
      local _old_filename _new_filename
      _old_filename=$(grep '^GO_DOWNLOAD_FILENAME=' "${_constants}" | cut -d'"' -f2)
      # Replace the full semver prefix (e.g. go1.26.1 → go1.27.x)
      _new_filename=$(printf '%s' "${_old_filename}" | \
        sed 's|^go[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.|go'"${_new}"'.|')
      if [[ "${_old_filename}" != "${_new_filename}" ]]; then
        sed -i.bak "s|^GO_DOWNLOAD_FILENAME=\"${_old_filename}\"|GO_DOWNLOAD_FILENAME=\"${_new_filename}\"|" "${_constants}"
        rm -f "${_constants}.bak"
        # GO_DOWNLOAD_URL embeds the filename — replace old filename with new throughout
        sed -i.bak "s|${_old_filename}|${_new_filename}|g" "${_constants}"
        rm -f "${_constants}.bak"
      fi
      ;;
    yq)
      # YQ_URL may contain a literal version or a ${YQ_VER} variable reference — update both
      # shellcheck disable=SC2016 # single-quoted ${YQ_VER} is intentional — matches literal text in constants.sh
      sed -i.bak -e "s|/v${_old}/|/v${_new}/|g" \
                 -e 's|/v\${YQ_VER}/|/v'"${_new}"'/|g' "${_constants}"
      rm -f "${_constants}.bak"
      ;;
    *)
      # vagrant, python3, ruby, zsh, shellcheck — no URL vars to update
      ;;
  esac
}

_update_version_pin() {
  local _tool="$1" _var="$2" _old="$3" _new="$4"
  local _constants="${_OVERRIDE_CONSTANTS_PATH:-$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh}"
  sed -i.bak "s|^${_var}=\"${_old}\"|${_var}=\"${_new}\"|" "${_constants}"
  rm -f "${_constants}.bak"
  _update_url_pins "${_tool}" "${_old}" "${_new}" "${_constants}"
}

_prompt_version_update() {
  local _tool="$1" _var="$2" _pinned="$3" _latest="$4"
  local _reply
  printf "  Update %s from %s to %s? [y/N] " "${_tool}" "${_pinned}" "${_latest}"
  read -r _reply
  if [[ "${_reply}" =~ ^[Yy]$ ]]; then
    _update_version_pin "${_tool}" "${_var}" "${_pinned}" "${_latest}"
    printf "  Updated %s → %s\n" "${_var}" "${_latest}"
  fi
}

run_check_versions() {
  local _outdated=0 _skipped=0 _warned=0 _ok=0

  printf "=== Version Check ===\n\n"

  _run_cv_check() {
    local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5" _var="$6"
    local _out _latest
    _out=$(_check_one_version "${_tool}" "${_pinned}" "${_repo}" "${_cmd}" "${_regex}" 2>&1)
    printf '%s\n' "${_out}"
    if [[ "${_out}" == *"[SKIP]"* ]];       then _skipped=$(( _skipped + 1 ))
    elif [[ "${_out}" == *"[WARN]"* ]];     then _warned=$(( _warned + 1 ))
    elif [[ "${_out}" == *"[OK]"* ]];       then _ok=$(( _ok + 1 ))
    elif [[ "${_out}" == *"[OUTDATED]"* ]]; then
      _outdated=$(( _outdated + 1 ))
      if [[ -n ${UPDATE_VERSIONS:-} ]]; then
        _latest=$(printf '%s' "${_out}" | grep -oE 'latest=[^ ]+' | cut -d= -f2)
        _prompt_version_update "${_tool}" "${_var}" "${_pinned}" "${_latest}"
      fi
    fi
  }

  _run_cv_check "go"         "${GO_VER}"         "golang/go"           "go version"           "[0-9]+\.[0-9]+(\.[0-9]+)?" "GO_VER"
  _run_cv_check "python3"    "${PYTHON_VER}"      "python/cpython"      "python3 --version"    "[0-9]+\.[0-9]+\.[0-9]+"    "PYTHON_VER"
  _run_cv_check "ruby"       "${RUBY_VER}"        "ruby/ruby"           "ruby --version"       "[0-9]+\.[0-9]+\.[0-9]+"    "RUBY_VER"
  _run_cv_check "zsh"        "${ZSH_VER}"         "zsh-users/zsh"       "zsh --version"        "[0-9]+\.[0-9]+(\.[0-9]+)?" "ZSH_VER"
  _run_cv_check "yq"         "${YQ_VER}"          "mikefarah/yq"        "yq --version"         "[0-9]+\.[0-9]+\.[0-9]+"    "YQ_VER"
  _run_cv_check "shellcheck" "${SHELLCHECK_VER}"  "koalaman/shellcheck" "shellcheck --version" "[0-9]+\.[0-9]+\.[0-9]+"    "SHELLCHECK_VER"
  _run_cv_check "vagrant"    "${VAGRANT_VER}"     "hashicorp/vagrant"   "vagrant --version"    "[0-9]+\.[0-9]+\.[0-9]+"    "VAGRANT_VER"

  printf "\n%d outdated, %d skipped, %d warnings, %d OK\n" \
    "${_outdated}" "${_skipped}" "${_warned}" "${_ok}"

  [[ ${_outdated} -eq 0 ]]
}
