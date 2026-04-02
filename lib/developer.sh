#!/usr/bin/env bash
# lib/developer.sh — cross-platform developer tooling (Ruby, Python, Ansible, AWS CLI, Rust, etc.)

clone_or_update_dotfiles() {
  printf "Copying %s from Github\\n" "${DOTFILES}"
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
  if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
    if [[ -n ${MACOS} ]]; then
      printf "Updating MACOS awscli\n"
      cd ${HOME}/software_downloads/awscli || exit
      curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
      sudo -H installer -pkg AWSCLIV2.pkg -target /
      rm AWSCLIV2.pkg
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
  fi
  if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
    printf "Updating Linux awscli\n"
    mkdir -p ${HOME}/software_downloads/awscli
    cd ${HOME}/software_downloads/awscli || exit
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -u -o awscliv2.zip
    sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
}

update_rust() {
  if [[ -n ${UBUNTU} ]] && { [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; }; then
    printf "Updating Rust Ubuntu\n"
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      ${HOME}/.cargo/bin/rustup self update
      ${HOME}/.cargo/bin/rustup update
    elif command -v rustup >/dev/null 2>&1; then
      rustup self update
      rustup update
    else
      printf "rustup not found; skipping Rust update\n"
    fi
  fi
}
