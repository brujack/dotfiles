#!/usr/bin/env bash
# lib/helpers.sh — install guards, brew helpers, symlink utilities, argument parsing

# ── logging helpers ───────────────────────────────────────────────────────────
readonly _RED='\033[0;31m'
readonly _YELLOW='\033[0;33m'
readonly _GREEN='\033[0;32m'
readonly _NC='\033[0m'

log_info()  { printf "${_GREEN}[INFO]${_NC}  %s\n" "$*"; }
log_warn()  { printf "${_YELLOW}[WARN]${_NC}  %s\n" "$*" >&2; }
log_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }

# ── symlink helpers ───────────────────────────────────────────────────────────
safe_link() {
  local src="$1" dest="$2"
  if [[ -L "${dest}" ]]; then
    return 0
  fi
  if [[ -e "${dest}" ]]; then
    log_warn "Backing up existing file: ${dest} → ${dest}.bak"
    mv "${dest}" "${dest}.bak"
  fi
  ln -s "${src}" "${dest}"
  log_info "Linked ${dest} → ${src}"
}

quiet_which() {
  which "$1" &>/dev/null
}

rhel_installed_package() {
  if ! command -v yum &>/dev/null; then
    log_error "yum command not found! Please install yum or run on a supported system."
    return 1
  fi
  yum list installed "$@" >/dev/null 2>&1
}

brew_update() {
  if ! ensure_not_root; then
    return 1
  fi
  if ! command -v brew &>/dev/null; then
    log_info "Homebrew not found, installing Homebrew..."
    install_homebrew
  fi

  log_info "Updating Homebrew..."
  if ! brew update; then
    log_error "Failed to update Homebrew. Aborting."
    return 1
  fi

  log_info "Upgrading installed formulae..."
  if ! brew upgrade; then
    log_error "Failed to upgrade formulae. Aborting."
    return 1
  fi

  log_info "Upgrading installed casks..."
  if ! brew upgrade --cask --greedy; then
    log_error "Failed to upgrade casks. Aborting."
    return 1
  fi

  log_info "Cleaning Homebrew up..."
  if ! brew cleanup; then
    log_error "Failed to clean up. Aborting."
    return 1
  fi

  log_info "Homebrew update process completed successfully."
  return 0
}

ensure_not_root() {
  if [[ $(id -u) -eq 0 ]]; then
    log_error "Homebrew cannot run as root. Re-run without sudo."
    return 1
  fi
  return 0
}

brew_formula_installed() {
  local formula="$1"
  if ! ensure_not_root; then
    return 1
  fi
  if [[ "$formula" == */* ]]; then
    brew list --formula --full-name | grep -q "^${formula}$"
  else
    brew list --formula | grep -q "^${formula}$"
  fi
}

brew_cask_installed() {
  local cask="$1"
  if ! ensure_not_root; then
    return 1
  fi
  if [[ "$cask" == */* ]]; then
    brew list --cask --full-name | grep -q "^${cask}$"
  else
    brew list --cask | grep -q "^${cask}$"
  fi
}

brew_install_formula() {
  local formula="$1"
  if ! ensure_not_root; then
    return 1
  fi
  if ! brew_formula_installed "$formula"; then
    brew install "$formula"
  fi
}

brew_install_cask() {
  local cask="$1"
  if ! ensure_not_root; then
    return 1
  fi
  if ! brew_cask_installed "$cask"; then
    brew install --cask --force --overwrite "$cask"
  fi
}

brew_tap_installed() {
  local tap="$1"
  if ! ensure_not_root; then
    return 1
  fi
  brew tap | grep -q "^${tap}$"
}

brew_tap_if_missing() {
  local tap="$1"
  if ! ensure_not_root; then
    return 1
  fi
  if ! brew_tap_installed "$tap"; then
    brew tap "$tap"
  fi
}

app_dir_exists() {
  local path="$1"
  local normalized="${path//\\ / }"
  [[ -d "$normalized" ]]
}

check_and_install_nala() {
  log_info "Installing nala"
  if [[ "$(uname -s)" = "Linux" ]]; then
    if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') = "Ubuntu" ]]; then
      if ! [ -x "$(command -v nala)" ]; then
        log_info "Installing nala via apt"
        wget -O ${HOME}/software_downloads/volian-archive-keyring_0.2.0_all.deb https://gitlab.com/-/project/39215670/uploads/d9473098bc12525687dc9aca43d50159/volian-archive-keyring_0.2.0_all.deb
        sudo -H dpkg --install ${HOME}/software_downloads/volian-archive-keyring_0.2.0_all.deb
        wget -O ${HOME}/software_downloads/volian-archive-nala_0.2.0_all.deb https://gitlab.com/-/project/39215670/uploads/d00e44faaf2cc8aad526ca520165a0af/volian-archive-nala_0.2.0_all.deb
        sudo -H dpkg --install ${HOME}/software_downloads/volian-archive-nala_0.2.0_all.deb
        sudo -H apt update
        sudo -H apt install nala -y
      fi
    fi
  fi
}

usage() {
  cat << EOF
Usage: $0 -t <type> [-w]
Types:
  setup_user : Sets up a basic user environment for the current user
  setup      : Runs a full machine and developer setup
  developer  : Runs a developer setup with packages and python virtual environment for running ansible
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update     : Does a system update of packages including brew packages
Options:
  -w : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}

process_args() {
  local arg OPTARG
  while getopts ":ht:w" arg; do
    case ${arg} in
      t)
        case ${OPTARG} in
          setup_user) readonly SETUP_USER=1 ;;
          setup) readonly SETUP=1 ;;
          developer) readonly DEVELOPER=1 ;;
          ansible) readonly ANSIBLE=1 ;;
          update) readonly UPDATE=1 ;;
          *) echo "Invalid option for -t"; usage; exit 1 ;;
        esac
        ;;
      w) readonly WORK=1 ;;
      h | *) usage; exit 0 ;;
    esac
  done
}

setup_dotfile_symlinks() {
  log_info "Linking ${DOTFILES} to their home"

  if [[ -n ${MACOS} ]]; then
    rm -f ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac ${HOME}/.gitconfig
    if [[ -d ${HOME}/git-repos/gitlab ]]; then
      rm -f ${HOME}/git-repos/gitlab/.gitconfig
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac_gitlab ${HOME}/git-repos/gitlab/.gitconfig
    fi
    if [[ -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
      log_info "gitlab/.gitconfig is linked"
    fi
  fi
  if [[ -n ${LINUX} ]]; then
    rm -f ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux ${HOME}/.gitconfig
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      if [[ -d ${HOME}/git-repos/gitlab ]]; then
        rm -f ${HOME}/git-repos/gitlab/.gitconfig
        ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux_gitlab ${HOME}/git-repos/gitlab/.gitconfig
      fi
      if [[ -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
        log_info "gitlab/.gitconfig is linked Linux"
      fi
    fi
  fi

  rm -f ${HOME}/.vimrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  if [[ -L ${HOME}/.vimrc ]]; then
    log_info ".vimrc is linked"
  fi

  rm -f ${HOME}/.p10k.zsh
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.p10k.zsh ${HOME}/.p10k.zsh
  if [[ -L ${HOME}/.p10k.zsh ]]; then
    log_info ".p10k.zsh is linked"
  fi

  rm -f ${HOME}/.tmux.conf
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.tmux.conf ${HOME}/.tmux.conf
  if [[ -L ${HOME}/.tmux.conf ]]; then
    log_info ".tmux.conf is linked"
  fi

  if [[ -d ${HOME}/scripts ]]; then
    rm -rf ${HOME}/scripts
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  elif [[ ! -L ${HOME}/scripts ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  fi
  if [[ -L ${HOME}/scripts ]]; then
    log_info "scripts is linked"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "Creating ${HOME}/.config"
    mkdir -p ${HOME}/.config
  fi
  if [[ -d ${HOME}/.config ]]; then
    log_info "Created ${HOME}/.config"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "Creating ${HOME}/.tf_creds"
    mkdir -p ${HOME}/.tf_creds
    if [[ -d ${HOME}/.tf_creds ]]; then
      chmod 700 ${HOME}/.tf_creds
    fi
    if [[ -d ${HOME}/.tf_creds ]]; then
      log_info "Created ${HOME}/.tf_creds"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "powershell profile and custom oh-my-posh theme"
    mkdir -p ${HOME}/.config/powershell
    rm -f ${HOME}/.config/powershell/profile.ps1
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/profile.ps1 ${HOME}/.config/powershell/profile.ps1
    rm -f ${HOME}/.config/powershell/bruce.omp.json
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.omp.json ${HOME}/.config/powershell/bruce.omp.json
    if [[ -L ${HOME}/.config/powershell/profile.ps1 ]]; then
      log_info "powershell profile is linked"
    fi
    if [[ -L ${HOME}/.config/powershell/bruce.omp.json ]]; then
      log_info "bruce.omp.json is linked"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "starship profile"
    rm -f ${HOME}/.config/starship.toml
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/starship.toml ${HOME}/.config/starship.toml
    if [[ -L ${HOME}/.config/starship.toml ]]; then
      log_info "starship.toml is linked"
    fi
  fi

  log_info "Installing Oh My ZSH..."
  if [[ ! -d ${HOME}/.oh-my-zsh ]]; then
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      log_info "Installed Oh My ZSH"
    fi
  fi

  log_info "Installing p10k"
  if [[ ! -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      log_info "Installed p10k"
    fi
  fi

  log_info "linking .zshrc"
  rm -f ${HOME}/.zshrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  if [[ -L ${HOME}/.zshrc ]]; then
    log_info ".zshrc is linked"
  fi

  log_info "linking .zshrc.d"
  rm -f ${HOME}/.config/.zshrc.d
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/.zshrc.d ${HOME}/.config/.zshrc.d
  if [[ -L ${HOME}/.config/.zshrc.d ]]; then
    log_info ".zshrc.d is linked"
  fi

  log_info "Linking ${HOME}/.config/ccstatusline"
  mkdir -p ${HOME}/.config
  rm -rf ${HOME}/.config/ccstatusline
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/ccstatusline ${HOME}/.config/ccstatusline
  if [[ -L ${HOME}/.config/ccstatusline ]]; then
    log_info ".config/ccstatusline is linked"
  fi

  log_info "linking .zprofile"
  rm -f ${HOME}/.zprofile
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zprofile ${HOME}/.zprofile
  if [[ -L ${HOME}/.zprofile ]]; then
    log_info ".zprofile is linked"
  fi

  log_info "Linking custom bruce.zsh-theme"
  rm -f ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  if [[ -L ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme ]]; then
    log_info "bruce.zsh-theme is linked"
  fi

  log_info "Creating ${HOME}/.tmux"
  mkdir -p ${HOME}/.tmux
  if [[ -d ${HOME}/.tmux ]]; then
    log_info "Created ${HOME}/.tmux"
  fi

  if [[ ! -d ${HOME}/.tmux/plugins/tpm ]]; then
    log_info "Installing TPM"
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      log_info "Installed TPM"
    fi
  fi

  log_info "Creating ${HOME}/.warp"
  mkdir -p ${HOME}/.warp
  if [[ -d ${HOME}/.warp ]]; then
    chmod 700 ${HOME}/.warp
    if [[ -d ${HOME}/.warp ]]; then
      log_info "Created ${HOME}/.warp"
    fi
  fi
  log_info "Linking ${HOME}/.warp/themes"
  rm -f ${HOME}/.warp/themes
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/themes ${HOME}/.warp/themes
  if [[ -L ${HOME}/.warp/themes ]]; then
    log_info ".warp/themes is linked"
  fi

  log_info "Linking ${HOME}/.warp/launch_configurations"
  rm -f ${HOME}/.warp/launch_configurations
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/launch_configurations ${HOME}/.warp/launch_configurations
  if [[ -L ${HOME}/.warp/launch_configurations ]]; then
    log_info ".warp/launch_configurations is linked"
  fi

  log_info "Creating ${HOME}/.ssh"
  mkdir -p ${HOME}/.ssh
  if [[ -d ${HOME}/.ssh ]]; then
    chmod 700 ${HOME}/.ssh
    if [[ -d ${HOME}/.ssh ]]; then
      log_info "Created ${HOME}/.ssh"
    fi
  fi

  log_info "Creating ${HOME}/.claude"
  mkdir -p ${HOME}/.claude
  if [[ -d ${HOME}/.claude ]]; then
    log_info "Created ${HOME}/.claude"
  fi
  for _claude_item in ${PERSONAL_GITREPOS}/${DOTFILES}/.claude/*; do
    _claude_target="${HOME}/.claude/$(basename ${_claude_item})"
    log_info "Linking ${_claude_target}"
    rm -rf ${_claude_target}
    ln -s ${_claude_item} ${_claude_target}
    if [[ -L ${_claude_target} ]]; then
      log_info "${_claude_target} is linked"
    fi
  done

  log_info "Linking ${HOME}/.ssh/config"
  rm -f ${HOME}/.ssh/config
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  if [[ -L ${HOME}/.ssh/config ]]; then
    log_info ".ssh/config is linked"
  fi

  if [[ -n ${MACOS} ]]; then
    CURSOR_USER_DIR="${HOME}/Library/Application Support/Cursor/User"
    CURSOR_APP_SETTINGS_DIR="${HOME}/Library/Application Support/Cursor/settings"
  elif [[ -n ${LINUX} ]]; then
    CURSOR_USER_DIR="${HOME}/.config/Cursor/User"
    CURSOR_APP_SETTINGS_DIR=""
  fi

  if [[ -n ${CURSOR_USER_DIR:-} ]]; then
    CURSOR_DOTFILES_USER_DIR="${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/User"

    # Only link Cursor settings if Cursor is installed, the app's settings files exist (on macOS),
    # and the dotfiles Cursor user files exist
    if app_dir_exists "/Applications/Cursor.app" || command -v cursor &>/dev/null; then
      CURSOR_APP_SETTINGS_OK=1
      if [[ -n ${MACOS:-} ]]; then
        if [[ ! -f "${CURSOR_APP_SETTINGS_DIR}/settings.json" ]] || \
           [[ ! -f "${CURSOR_APP_SETTINGS_DIR}/keybindings.json" ]]; then
          CURSOR_APP_SETTINGS_OK=0
        fi
      fi

      if [[ ${CURSOR_APP_SETTINGS_OK} -eq 1 ]] && \
         [[ -f "${CURSOR_DOTFILES_USER_DIR}/settings.json" ]] && \
         [[ -f "${CURSOR_DOTFILES_USER_DIR}/keybindings.json" ]] && \
         [[ -d "${CURSOR_DOTFILES_USER_DIR}/snippets" ]]; then

        log_info "Cursor User directory is ${CURSOR_USER_DIR}"
        log_info "Creating ${CURSOR_USER_DIR}"
        mkdir -p "${CURSOR_USER_DIR}"

        log_info "Linking Cursor settings"
        rm -f "${CURSOR_USER_DIR}/settings.json"
        ln -s "${CURSOR_DOTFILES_USER_DIR}/settings.json" "${CURSOR_USER_DIR}/settings.json"
        if [[ -L "${CURSOR_USER_DIR}/settings.json" ]]; then
          log_info "Cursor settings.json is linked"
        fi

        rm -f "${CURSOR_USER_DIR}/keybindings.json"
        ln -s "${CURSOR_DOTFILES_USER_DIR}/keybindings.json" "${CURSOR_USER_DIR}/keybindings.json"
        if [[ -L "${CURSOR_USER_DIR}/keybindings.json" ]]; then
          log_info "Cursor keybindings.json is linked"
        fi

        rm -rf "${CURSOR_USER_DIR}/snippets"
        ln -s "${CURSOR_DOTFILES_USER_DIR}/snippets" "${CURSOR_USER_DIR}/snippets"
        if [[ -L "${CURSOR_USER_DIR}/snippets" ]]; then
          log_info "Cursor snippets is linked"
        fi
      else
        log_warn "Skipping Cursor symlinks; Cursor app settings or dotfiles Cursor user files are missing"
      fi
    else
      log_warn "Skipping Cursor symlinks; Cursor is not installed"
    fi
  fi

  log_info "Linking ${HOME}/.ssh/teleport.cfg"
  rm -f ${HOME}/.ssh/teleport.cfg
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/teleport.cfg ${HOME}/.ssh/teleport.cfg
  if [[ -L ${HOME}/.ssh/teleport.cfg ]]; then
    log_info ".ssh/teleport.cfg is linked"
  fi

  log_info "Creating ${HOME}/.tsh"
  mkdir -p ${HOME}/.tsh
  if [[ -d ${HOME}/.tsh ]]; then
    chmod 700 ${HOME}/.tsh
    if [[ -d ${HOME}/.tsh ]]; then
      log_info "Created ${HOME}/.tsh"
    fi
  fi
}

setup_credential_directories() {
  log_info "Creating ${HOME}/.aws"
  mkdir -p ${HOME}/.aws
  if [[ -d ${HOME}/.aws ]]; then
    chmod 700 ${HOME}/.aws
    log_info "Created ${HOME}/.aws"
  fi

  log_info "Creating ${HOME}/.gcloud_creds"
  mkdir -p ${HOME}/.gcloud_creds
  if [[ -d ${HOME}/.gcloud_creds ]]; then
    chmod 700 ${HOME}/.gcloud_creds
    log_info "Created ${HOME}/.gcloud_creds"
  fi

  log_info "Creating ${HOME}/.azure_creds"
  mkdir -p ${HOME}/.azure_creds
  if [[ -d ${HOME}/.azure_creds ]]; then
    chmod 700 ${HOME}/.azure_creds
    log_info "Created ${HOME}/.azure_creds"
  fi
}
