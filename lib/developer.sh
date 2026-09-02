#!/usr/bin/env bash
# lib/developer.sh — cross-platform developer tooling (Ruby, Python, Ansible, AWS CLI, Rust, etc.)

clone_or_update_dotfiles() {
  log_info "Copying ${DOTFILES} from Github"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]; then
    cd "${HOME}" || return 1
    git clone --recursive git@github.com:brujack/"${DOTFILES}".git "${PERSONAL_GITREPOS}"/"${DOTFILES}"
    # for regular https github used on machines that will not push changes
    # git clone --recursive https://github.com/brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
    git pull
  fi
}

# _aws_gpg_fail <errfile> <message>
#
# Prints the caller's message plus the tail of gpg's captured stderr. That
# stderr is the only stream separating "no valid OpenPGP data found" (a
# truncated or HTML .sig) from a genuine bad signature -- discarding it would
# reproduce, on the verify side, the misattribution ci.md records costing 200
# consecutive daily runs on the fetch side.
_aws_gpg_fail() {
  local _errfile="$1" _msg="$2"
  log_error "${_msg}"
  if [[ -s "${_errfile}" ]]; then
    tail -n 10 "${_errfile}" >&2
  fi
}

# _aws_verify_zip <zip> <sig>
#
# Verifies the Linux awscli zip against the vendored AWS signing key, using a
# throwaway keyring holding only that key. Returns 0 when the signature is
# genuinely from the vendored key and neither expired nor revoked; 1 otherwise.
#
# The whole body runs in a `( )` subshell with an EXIT trap -- NOT
# `trap ... RETURN` at function scope. `trap ... RETURN` is not function-scoped
# in bash: it stays armed in the calling shell and fires again on every later
# return up the call chain, with `_ring` out of scope (empty) by then, which
# resolves `gpgconf --homedir ""` to the operator's REAL ~/.gnupg -- silently
# killing their live gpg-agent/dirmngr/scdaemon. Reproduced on bash 5.3.15 and
# 3.2.57. A subshell's EXIT trap fires exactly once, with `_ring` guaranteed
# in scope.
_aws_verify_zip() {
  local _zip="$1" _sig="$2"

  # _AWS_GPG_BIN: read unconditionally, defaults to `gpg`. Without this seam
  # the verifier-absent branch is unreachable -- a PATH strip that removes
  # /opt/homebrew/bin takes git and make with it.
  command -v "${_AWS_GPG_BIN:-gpg}" >/dev/null 2>&1 || {
    log_error "gpg not found; cannot verify the awscli signature"
    log_error "install: brew install gnupg  /  apt-get install gnupg"
    return 1
  }

  # _AWS_KEY_PATH: read unconditionally, defaults to the repo's vendored key.
  # Without this seam only the vendored key could ever be exercised and the
  # fingerprint-mismatch branch would be unreachable.
  local _key
  _key="${_AWS_KEY_PATH:-}"
  if [[ -z "${_key}" ]]; then
    _key="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/keys/aws-cli-team.asc"
  fi

  (
    _ring="$(mktemp -d)" || exit 1
    # gpg 2.x spawns gpg-agent AND scdaemon bound to the homedir; both survive
    # its deletion. Measured: 3 verifications leave 3 of each orphaned. EXIT
    # in a subshell fires exactly once, with _ring guaranteed in scope.
    trap 'gpgconf --homedir "${_ring}" --kill all >/dev/null 2>&1; rm -rf "${_ring}"' EXIT

    # _status and _err live INSIDE _ring so the same trap removes them.
    _status="${_ring}/status"
    _err="${_ring}/err"

    "${_AWS_GPG_BIN:-gpg}" --homedir "${_ring}" --batch --import "${_key}" \
      >/dev/null 2>"${_err}" || { _aws_gpg_fail "${_err}" "could not import the vendored key"; exit 1; }

    "${_AWS_GPG_BIN:-gpg}" --homedir "${_ring}" --batch --status-fd 1 \
      --verify "${_sig}" "${_zip}" >"${_status}" 2>"${_err}"

    # Reject BEFORE accepting, and split the two causes: they demand opposite
    # operator responses. VALIDSIG is emitted for both, and gpg exits 0 for
    # both -- an accept-only guard would let a revoked or expired key through.
    if grep -qE '^\[GNUPG:\] (REVKEYSIG|KEYREVOKED)' "${_status}"; then
      log_error "AWS signing key REVOKED — do not install; investigate"
      exit 1
    fi
    if grep -qE '^\[GNUPG:\] (EXPSIG|EXPKEYSIG|KEYEXPIRED)' "${_status}"; then
      log_error "vendored key or signature expired — refresh keys/aws-cli-team.asc"
      exit 1
    fi
    if ! grep -q "^\[GNUPG:\] VALIDSIG ${AWSCLI_GPG_FPR} " "${_status}"; then
      _aws_gpg_fail "${_err}" "signature did not verify against the vendored key"
      exit 1
    fi
    exit 0
  )
}

update_aws_cli() {
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    log_info "Updating MACOS awscli"
    mkdir -p "${HOME}"/software_downloads/awscli || return 1
    cd "${HOME}/software_downloads/awscli" || return 1
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" || return 1
    # Cleanup runs regardless of the installer's result: a stale or partial pkg
    # means the next run installs it. tdd.md's cleanup exception.
    if ! sudo -H installer -pkg AWSCLIV2.pkg -target /; then
      rm -f AWSCLIV2.pkg
      return 1
    fi
    # Not `|| return 1`: this is the same cleanup as the failure arm above, and
    # cleanup must not gate propagation (tdd.md). `rm -f` on an absent file exits
    # 0; a genuine filesystem fault here would otherwise report the aws section
    # FAIL after the install had already succeeded.
    rm -f AWSCLIV2.pkg
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    log_info "Updating Linux awscli"
    mkdir -p "${HOME}"/software_downloads/awscli || return 1
    cd "${HOME}/software_downloads/awscli" || return 1
    curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" || return 1
    unzip -u -o awscliv2.zip || return 1
    sudo -H "${HOME}"/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update || return 1
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  fi
}

update_rust() {
  if [[ -n ${UBUNTU} ]] && [[ -n ${HAS_RUST} ]]; then
    log_info "Updating Rust Ubuntu"
    local _rustup
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      _rustup="${HOME}/.cargo/bin/rustup"
    elif command -v rustup >/dev/null 2>&1; then
      _rustup="rustup"
    else
      log_warn "rustup not found; skipping Rust update"
      return 0
    fi
    "${_rustup}" self update || return 1
    "${_rustup}" update || return 1
    "${_rustup}" component add rust-analyzer || return 1
  fi
}

install_aws_tools() {
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    mkdir -p "${HOME}"/software_downloads/awscli
    printf "Installing aws-cli on MacOS\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg ]]; then
      wget -O "${HOME}"/software_downloads/awscli/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
      sudo installer -pkg "${HOME}"/software_downloads/awscli/AWSCLIV2.pkg -target /
      rm -f "${HOME}"/software_downloads/awscli/AWSCLIV2.pkg
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed MacOS\\n"
      fi
    fi
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    mkdir -p "${HOME}"/software_downloads/awscli
    printf "Installing aws-cli on Linux\\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/awscliv2.zip ]]; then
      wget -O "${HOME}"/software_downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip"
      unzip "${HOME}"/software_downloads/awscli/awscliv2.zip -d "${HOME}"/software_downloads/awscli
      sudo -H "${HOME}"/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
      rm -f "${HOME}"/software_downloads/awscli/awscliv2.zip
      rm -rf "${HOME}"/software_downloads/awscli
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed Linux\\n"
      fi
    fi
  fi
}

setup_vim_plugins() {
  printf "vim plugins setup\\n"
  mkdir -p "${HOME}"/.vim/plugged
  if [[ -d ${HOME}/.vim/plugged ]]; then
    chmod 770 "${HOME}"/.vim/plugged
  fi
  mkdir -p "${HOME}"/.vim/autoload
  if [[ -d ${HOME}/.vim/autoload ]]; then
    chmod 770 "${HOME}"/.vim/autoload
  fi
  if [[ ! -f ${HOME}/.vim/autoload/plug.vim ]]; then
    curl -fLo "${HOME}"/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
}

install_ruby_tools() {
  printf "Installing ruby-install on linux\\n"
  if [[ -n ${LINUX} ]]; then
    if [[ ! -d ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER} ]]; then
      wget -O "${HOME}"/software_downloads/ruby-install-"${RUBY_INSTALL_VER}".tar.gz https://github.com/postmodern/ruby-install/archive/v"${RUBY_INSTALL_VER}".tar.gz
      tar -xzvf "${HOME}"/software_downloads/ruby-install-"${RUBY_INSTALL_VER}".tar.gz -C "${HOME}"/software_downloads/
      cd "${HOME}"/software_downloads/ruby-install-"${RUBY_INSTALL_VER}"/ || return 1
      sudo make install
    fi
  fi

}

install_ruby() {
  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    printf "Install ruby %s\\n" "${RUBY_VER}"
    if [[ -n ${MACOS} ]]; then
      # shellcheck disable=SC2046 # brew --prefix emits exactly one path with no whitespace/globs; word-splitting is inert here, so quoting the substitution would not change behavior
      ruby-install "${RUBY_VER}" -- --with-openssl-dir=$(brew --prefix openssl@3)
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
        if ! RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr" rbenv install --skip-existing "${RUBY_VER}"; then
          log_warn "rbenv install ${RUBY_VER} failed — ruby-build may lack the definition"
          log_warn "Run 'rbenv install ${RUBY_VER}' manually once ruby-build is updated"
          return 0
        fi
        rbenv global "${RUBY_VER}"
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
  # install_ruby soft-fails on rbenv/ruby-install errors (returns 0 with a warning) so
  # that initial setup continues. recreate_ruby has already deleted the old installation,
  # so a silent failure here leaves the machine with no Ruby at all — verify explicitly.
  if [[ -n ${LINUX} ]] && [[ ! -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
    log_error "Ruby ${RUBY_VER} not found after install — rbenv install may have failed (see warnings above)"
    return 1
  fi
  if [[ -n ${MACOS} ]] && [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    log_error "Ruby ${RUBY_VER} not found after install — ruby-install may have failed (see output above)"
    return 1
  fi
  update_gems || { log_error "gem update failed after ruby recreate"; return 1; }
}

update_gems() {
  local _ruby_gem_dir=""
  if [[ -n ${MACOS} ]]; then
    _ruby_gem_dir="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  elif [[ -n ${LINUX} ]]; then
    _ruby_gem_dir="${HOME}/.rbenv/shims"
  fi
  local _extra_gem_path=""
  [[ -d "${_ruby_gem_dir}" ]] && _extra_gem_path="${_ruby_gem_dir}:"
  PATH="${_extra_gem_path}${PATH}" gem update
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
      local _uv
      _uv="$(resolve_uv)" || return 1
      uv_sync_venv "${_uv}" "${PYENV_ROOT}/versions/ansible/bin/python" "${PYENV_ROOT}/versions/ansible" || return 1
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
    local _uv
    _uv="$(resolve_uv)" || return 1
    uv_sync_venv "${_uv}" "${_python}" "${PYENV_ROOT}/versions/${_venv_name}" || return 1
    pyenv rehash
  fi
}

clone_personal_repos() {
  printf "personal git repos cloning\\n"
  if ! [[ -d ${PERSONAL_GITREPOS}/dotfiles ]]; then
    git clone git@github.com:brujack/dotfiles.git "${PERSONAL_GITREPOS}"/dotfiles
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform ]]; then
    git clone git@github.com:brujack/docker_container_terraform.git "${PERSONAL_GITREPOS}"/docker_container_terraform
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible ]]; then
    git clone git@github.com:brujack/docker_container_terraform_packer_ansible.git "${PERSONAL_GITREPOS}"/docker_container_terraform_packer_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/kubernetes ]]; then
    git clone git@github.com:brujack/kubernetes.git "${PERSONAL_GITREPOS}"/kubernetes
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/pfsense_config ]]; then
    git clone git@github.com:brujack/pfsense_config.git "${PERSONAL_GITREPOS}"/pfsense_config
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/python-learning ]]; then
    git clone git@github.com:brujack/python-learning.git "${PERSONAL_GITREPOS}"/python-learning
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraform_ansible ]]; then
    git clone git@github.com:brujack/terraform_ansible.git "${PERSONAL_GITREPOS}"/terraform_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraspace_env ]]; then
    git clone git@github.com:brujack/terraspace_env.git "${PERSONAL_GITREPOS}"/terraspace_env
  fi
}
