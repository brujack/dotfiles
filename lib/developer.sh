#!/usr/bin/env bash
# lib/developer.sh — cross-platform developer tooling (Ruby, Python, Ansible, AWS CLI, Rust, etc.)

clone_or_update_dotfiles() {
  log_info "Copying ${DOTFILES} from Github"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]; then
    cd ${HOME} || return
    git clone --recursive git@github.com:brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
    # for regular https github used on machines that will not push changes
    # git clone --recursive https://github.com/brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    git pull
  fi
}

update_aws_cli() {
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    log_info "Updating MACOS awscli"
    cd ${HOME}/software_downloads/awscli || exit
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
    sudo -H installer -pkg AWSCLIV2.pkg -target /
    rm AWSCLIV2.pkg
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    log_info "Updating Linux awscli"
    mkdir -p ${HOME}/software_downloads/awscli
    cd ${HOME}/software_downloads/awscli || exit
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -u -o awscliv2.zip
    sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
}

update_rust() {
  if [[ -n ${UBUNTU} ]] && [[ -n ${HAS_RUST} ]]; then
    log_info "Updating Rust Ubuntu"
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      ${HOME}/.cargo/bin/rustup self update
      ${HOME}/.cargo/bin/rustup update
    elif command -v rustup >/dev/null 2>&1; then
      rustup self update
      rustup update
    else
      log_warn "rustup not found; skipping Rust update"
    fi
  fi
}

install_aws_tools() {
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
}

setup_vim_plugins() {
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

install_ruby_tools() {
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
}

install_ruby() {
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
}
