#!/usr/bin/env bash
# lib/developer.sh — cross-platform developer tooling (Ruby, Python, Ansible, AWS CLI, Rust, etc.)

clone_or_update_dotfiles() {
  log_info "Copying ${DOTFILES} from Github"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]; then
    cd ${HOME} || return 1
    git clone --recursive git@github.com:brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
    # for regular https github used on machines that will not push changes
    # git clone --recursive https://github.com/brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
    git pull
  fi
}

update_aws_cli() {
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    log_info "Updating MACOS awscli"
    cd "${HOME}/software_downloads/awscli" || return 1
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
    sudo -H installer -pkg AWSCLIV2.pkg -target /
    rm AWSCLIV2.pkg
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    log_info "Updating Linux awscli"
    mkdir -p ${HOME}/software_downloads/awscli
    cd "${HOME}/software_downloads/awscli" || return 1
    curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip"
    unzip -u -o awscliv2.zip
    sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  fi
}

update_rust() {
  if [[ -n ${UBUNTU} ]] && [[ -n ${HAS_RUST} ]]; then
    log_info "Updating Rust Ubuntu"
    local _rustup_found=0
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      ${HOME}/.cargo/bin/rustup self update
      ${HOME}/.cargo/bin/rustup update
      ${HOME}/.cargo/bin/rustup component add rust-analyzer
      _rustup_found=1
    elif command -v rustup >/dev/null 2>&1; then
      rustup self update
      rustup update
      rustup component add rust-analyzer
      _rustup_found=1
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
      wget -O ${HOME}/software_downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip"
      unzip ${HOME}/software_downloads/awscli/awscliv2.zip -d ${HOME}/software_downloads/awscli
      sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
      rm -f ${HOME}/software_downloads/awscli/awscliv2.zip
      rm -rf ${HOME}/software_downloads/awscli
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
      cd ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}/ || return 1
      sudo make install
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
      if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
        # Refresh ruby-build definitions from git so a newly released Ruby
        # (e.g. 4.0.5 on Ubuntu 26.04) installs even when the Homebrew
        # ruby-build bottle lags upstream. An rbenv plugin copy of ruby-build
        # takes precedence over the brew-managed definitions.
        local _ruby_build="${HOME}/.rbenv/plugins/ruby-build"
        if [[ -d ${_ruby_build}/.git ]]; then
          git -C "${_ruby_build}" pull --quiet 2>/dev/null || true
        else
          git clone --quiet https://github.com/rbenv/ruby-build.git "${_ruby_build}" 2>/dev/null || true
        fi
        if command -v brew &>/dev/null; then
          brew upgrade ruby-build 2>/dev/null || true
        fi
        # Build Ruby's openssl extension against the SYSTEM OpenSSL — the
        # libcrypto the rbenv-managed ruby loads at runtime. Do NOT derive the
        # dir from `pkg-config`: on machines with Homebrew (linuxbrew) on PATH,
        # `brew shellenv` puts the keg-only openssl@3 on PKG_CONFIG_PATH, so the
        # build would link the extension against Homebrew OpenSSL (e.g. 3.6.3)
        # whose versioned symbols (OPENSSL_3.4.0) are absent from the older
        # system libcrypto (Ubuntu 24.04 ships 3.0.13) — producing a runtime
        # LoadError, "OpenSSL is not available", on every gem HTTPS operation.
        # Passing --with-openssl-dir makes the openssl gem's extconf skip
        # pkg-config entirely (it consults pkg-config only when no dir is
        # given), mirroring the "keep Homebrew out of the build" approach used
        # for pyenv in setup_ansible().
        # Attempt the install directly: ruby-build fails fast if the definition
        # is genuinely missing, so a fragile pre-flight --list grep (which is
        # curated and false-negatives on point releases) is not needed.
        # --skip-existing keeps it idempotent.
        if ! RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr" rbenv install --skip-existing ${RUBY_VER}; then
          log_warn "rbenv install ${RUBY_VER} failed — ruby-build may lack the definition"
          log_warn "Run 'rbenv install ${RUBY_VER}' manually once ruby-build is updated"
          return 0
        fi
        rbenv global ${RUBY_VER}
        rbenv rehash
      fi
    fi
    INSTALLED_RUBY_VERSION=$(ruby --version | awk '{print $2}')
    if [[ ${INSTALLED_RUBY_VERSION} == "${RUBY_VER}" ]]; then
      printf "ruby %s is installed\\n" "${RUBY_VER}"
    fi
  fi
}

recreate_ruby() {
  if [[ -n ${MACOS} ]]; then
    if ! quiet_which ruby-install; then
      log_error "ruby-install not found — cannot recreate ruby"
      return 1
    fi
    printf "Deleting ruby %s\\n" "${RUBY_VER}"
    rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"
  fi
  if [[ -n ${LINUX} ]]; then
    if ! quiet_which rbenv; then
      log_error "rbenv not found — cannot recreate ruby"
      return 1
    fi
    export PATH="${HOME}/.rbenv/bin:${PATH}"
    eval "$(rbenv init -)"
    printf "Deleting ruby %s\\n" "${RUBY_VER}"
    rbenv uninstall -f "${RUBY_VER}" 2>/dev/null || true
  fi
  install_ruby || return 1
}

install_github_cli_linux() {
  if [[ -n ${UBUNTU} ]]; then
    printf "installing github cli on Ubuntu\\n"
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo -H apt update
    sudo -H apt install gh
    if [[ -x $(command -v gh) ]]; then
      printf "gh is installed Ubuntu\\n"
    fi
  fi
}

setup_ansible() {
  printf "ANSIBLE setup\\n"
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    if [[ -n "${LINUX:-}" ]]; then
      # Belt-and-suspenders: install Python build deps before compiling.
      # ubuntu_common_packages.txt has these, but they may be absent when
      # running -t ansible without -t developer, or if nala failed on a new
      # Ubuntu release (e.g. 26.04 resolute where zlib1g-dev caused BUILD FAILED).
      sudo apt-get install -y \
        zlib1g-dev libssl-dev libbz2-dev libffi-dev \
        libreadline-dev libsqlite3-dev liblzma-dev tk-dev \
        uuid-dev libdb-dev libgdbm-dev libgdbm-compat-dev libnss3-dev \
        2>/dev/null || true

      # Keep pyenv's build definitions current (optional but useful)
      pyenv update

      # zsh-safe cleanup (avoids: zsh: no matches found)
      rm -rf "/tmp/python-build.*" 2>/dev/null || true

      # brew install pyenv puts the binary in the brew prefix, not ~/.pyenv/bin/pyenv.
      # The env -i subprocess below resolves pyenv only via $PYENV_ROOT/bin, so create
      # a symlink when the expected path is absent (e.g. fresh machine, brew install).
      if command -v pyenv &>/dev/null && [[ ! -x "${HOME}/.pyenv/bin/pyenv" ]]; then
        mkdir -p "${HOME}/.pyenv/bin"
        ln -sf "$(command -v pyenv)" "${HOME}/.pyenv/bin/pyenv"
      fi

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
      local _pip_pkgs=(ansible ansible-lint molecule "molecule-plugins[docker]" certbot certbot-dns-cloudflare checkov boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt pyright cosmic-ray hypothesis passlib scikit-learn scipy bandit pip-audit ruff pytest pytest-cov pytest-xdist mypy pandas matplotlib seaborn ipython jupyterlab pre-commit radon vulture)
      [[ -n ${MACOS:-} ]] && _pip_pkgs+=(mlx)
      python -m pip install "${_pip_pkgs[@]}"
      pyenv rehash
    fi
  fi
}

recreate_python_venv() {
  local _venv_name="${1:-ansible}"
  export PYENV_ROOT="$HOME/.pyenv"
  export PYENV_VIRTUALENV_DISABLE_PROMPT=1
  if ! quiet_which pyenv; then
    log_error "pyenv not found — cannot recreate virtualenv"
    return 1
  fi
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"

  printf "Deleting virtualenv '%s'\\n" "${_venv_name}"
  pyenv virtualenv-delete -f "${_venv_name}" 2>/dev/null || true

  printf "Creating virtualenv '%s' with Python %s\\n" "${_venv_name}" "${PYTHON_VER}"
  pyenv virtualenv "${PYTHON_VER}" "${_venv_name}" || return 1
  pyenv activate "${_venv_name}" || return 1

  if [[ "${_venv_name}" == "ansible" ]]; then
    local _python
    _python="$(pyenv which python 2>/dev/null || command -v python3)"
    printf "Installing Ansible dependencies...\\n"
    local _pip_pkgs=(ansible ansible-lint molecule "molecule-plugins[docker]" certbot certbot-dns-cloudflare checkov boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt pyright cosmic-ray hypothesis passlib scikit-learn scipy bandit pip-audit ruff pytest pytest-cov pytest-xdist mypy pandas matplotlib seaborn ipython jupyterlab pre-commit radon vulture)
    [[ -n ${MACOS:-} ]] && _pip_pkgs+=(mlx)
    "${_python}" -m pip install "${_pip_pkgs[@]}" || return 1
    pyenv rehash
  fi
}

clone_personal_repos() {
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
