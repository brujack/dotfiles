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

# ── command wrapper ───────────────────────────────────────────────────────────
run_cmd() {
  if [[ -n ${DRY_RUN:-} ]]; then
    printf "[DRY RUN] %s\n" "$*"
  else
    "$@"
  fi
}

# ── doctor check primitives ───────────────────────────────────────────────────
_DOCTOR_PASS=0
_DOCTOR_FAIL=0
_DOCTOR_FAILED=0

doctor_pass() {
  _DOCTOR_PASS=$(( _DOCTOR_PASS + 1 ))
  printf "  ${_GREEN}[PASS]${_NC} %s\n" "$1"
}

doctor_fail() {
  _DOCTOR_FAIL=$(( _DOCTOR_FAIL + 1 ))
  _DOCTOR_FAILED=1
  printf "  ${_RED}[FAIL]${_NC} %s: %s\n" "$1" "${2:-}"
}

# ── symlink helpers ───────────────────────────────────────────────────────────
safe_link() {
  local src="$1" dest="$2"
  if [[ -L "${dest}" ]]; then
    return 0
  fi
  if [[ -e "${dest}" ]]; then
    log_warn "Backing up existing file: ${dest} → ${dest}.bak"
    run_cmd mv "${dest}" "${dest}.bak"
  fi
  run_cmd ln -s "${src}" "${dest}"
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
    log_warn "Some casks failed to upgrade; continuing."
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

_any_update_flag() {
  [[ -n ${UPDATE_BREW:-}   ]] || [[ -n ${UPDATE_PIP:-}    ]] || \
  [[ -n ${UPDATE_GEMS:-}   ]] || [[ -n ${UPDATE_MAS:-}    ]] || \
  [[ -n ${UPDATE_CLAUDE:-} ]]
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
Usage: $0 -t <type> [--dry-run] [-w]
Types:
  setup_user : Sets up a basic user environment for the current user
  setup      : Runs a full machine and developer setup
  developer  : Runs a developer setup with packages and python virtual environment for running ansible
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update     : Does a system update of packages including brew packages
               Flags: --brew-only, --pip-only, --gems-only, --mas-only, --claude-only
  doctor     : Active health checks: symlinks, tools, credential dir permissions, version drift. Exits non-zero on failure
  check-versions : Compare pinned tool versions in lib/constants.sh against latest GitHub releases
Options:
  --dry-run     : Log mutating operations (symlinks, installs, mkdir) without executing them
  --brew-only   : (update only) Update Homebrew formulae and casks only
  --pip-only    : (update only) Update pip packages only
  --gems-only   : (update only) Update Ruby gems only
  --mas-only    : (update only) Update Mac App Store apps only
  --claude-only : (update only) Update Claude plugins only
  -w            : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}

# ── cross-platform install dispatchers ───────────────────────────────────────

install_git() {
  if [[ -n ${MACOS} ]]; then
    install_git_macos
  elif [[ -n ${LINUX} ]]; then
    install_git_linux
  fi
}

install_zsh() {
  if [[ -n ${MACOS} ]]; then
    install_zsh_macos
  elif [[ -n ${LINUX} ]]; then
    install_zsh_linux
  fi
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

run_doctor() {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0

  printf "=== Doctor Report ===\n"
  printf "\nOS Detection:\n"
  printf "  MACOS=%s  LINUX=%s\n" "${MACOS:-<unset>}" "${LINUX:-<unset>}"
  printf "  UBUNTU=%s  REDHAT=%s  FEDORA=%s  CENTOS=%s\n" \
    "${UBUNTU:-<unset>}" "${REDHAT:-<unset>}" "${FEDORA:-<unset>}" "${CENTOS:-<unset>}"
  printf "  FOCAL=%s  JAMMY=%s  NOBLE=%s\n" \
    "${FOCAL:-<unset>}" "${JAMMY:-<unset>}" "${NOBLE:-<unset>}"
  printf "\nProfile:\n"
  printf "  PROFILE=%s\n" "${PROFILE:-unknown}"
  printf "\nCapabilities:\n"
  printf "  HAS_GUI=%s\n"      "${HAS_GUI:-<unset>}"
  printf "  HAS_DEVTOOLS=%s\n" "${HAS_DEVTOOLS:-<unset>}"
  printf "  HAS_AWS=%s\n"      "${HAS_AWS:-<unset>}"
  printf "  HAS_K8S=%s\n"      "${HAS_K8S:-<unset>}"
  printf "  HAS_DOCKER=%s\n"   "${HAS_DOCKER:-<unset>}"
  printf "  HAS_RUST=%s\n"     "${HAS_RUST:-<unset>}"
  printf "  HAS_SNAP=%s\n"     "${HAS_SNAP:-<unset>}"
  printf "  HAS_PRINTING=%s\n" "${HAS_PRINTING:-<unset>}"
  printf "\nKey Paths:\n"
  printf "  HOME=%s\n"              "${HOME}"
  printf "  PERSONAL_GITREPOS=%s\n" "${PERSONAL_GITREPOS:-<unset>}"
  printf "  DOTFILES=%s\n"          "${DOTFILES:-<unset>}"
  printf "  BREWFILE_LOC=%s\n"      "${BREWFILE_LOC:-<unset>}"
  printf "  CHRUBY_LOC=%s\n"        "${CHRUBY_LOC:-<unset>}"

  printf "\n=== Checks ===\n"

  _doctor_check_symlinks
  _doctor_check_tools
  _doctor_check_cred_dirs
  _doctor_check_versions

  printf "\n=== Summary ===\n"
  printf "%d checks passed, %d failed\n" "${_DOCTOR_PASS}" "${_DOCTOR_FAIL}"

  [[ ${_DOCTOR_FAILED} -eq 0 ]]
}

_doctor_check_symlinks() {
  printf "\nSymlinks:\n"
  local _label _link

  # shellcheck disable=SC2088 # tildes are display labels, not expanded paths
  local -a _checks=(
    "~/.zshrc          ${HOME}/.zshrc"
    "~/.zprofile       ${HOME}/.zprofile"
    "~/.vimrc          ${HOME}/.vimrc"
    "~/.tmux.conf      ${HOME}/.tmux.conf"
    "~/.p10k.zsh       ${HOME}/.p10k.zsh"
    "~/.ssh/config     ${HOME}/.ssh/config"
    "~/.config/starship.toml  ${HOME}/.config/starship.toml"
    "~/.config/.zshrc.d       ${HOME}/.config/.zshrc.d"
    "~/.gitconfig      ${HOME}/.gitconfig"
  )

  local _entry
  for _entry in "${_checks[@]}"; do
    _label="${_entry%%  *}"
    _link="${_entry##*  }"
    if [[ -L "${_link}" ]] && [[ -e "${_link}" ]]; then
      doctor_pass "${_label}"
    elif [[ -L "${_link}" ]]; then
      doctor_fail "${_label}" "broken symlink (target missing)"
    else
      doctor_fail "${_label}" "symlink missing"
    fi
  done
}
_doctor_check_tools() {
  printf "\nTools:\n"
  local _tool
  local -a _common_tools=(git zsh curl tmux bats)

  for _tool in "${_common_tools[@]}"; do
    if command -v "${_tool}" &>/dev/null; then
      doctor_pass "${_tool}"
    else
      doctor_fail "${_tool}" "not found"
    fi
  done

  if [[ -n ${MACOS} ]]; then
    if command -v brew &>/dev/null; then
      doctor_pass "brew"
    else
      doctor_fail "brew" "not found"
    fi
  fi

  if [[ -n ${LINUX} ]]; then
    if [[ -n ${UBUNTU} ]]; then
      if command -v apt-get &>/dev/null; then
        doctor_pass "apt-get"
      else
        doctor_fail "apt-get" "not found"
      fi
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        doctor_pass "dnf/yum"
      else
        doctor_fail "dnf/yum" "not found"
      fi
    fi
  fi
}
_doctor_check_cred_dirs() {
  printf "\nCredential directories:\n"
  local -a _dirs=("${HOME}/.aws" "${HOME}/.tf_creds" "${HOME}/.ssh" "${HOME}/.tsh")
  local _label _perms

  local _dir
  for _dir in "${_dirs[@]}"; do
    # shellcheck disable=SC2088 # display label, not a path
    _label="~/${_dir##"${HOME}/"}"
    if [[ ! -d "${_dir}" ]]; then
      doctor_fail "${_label}" "missing"
      continue
    fi
    if [[ -n ${MACOS} ]]; then
      _perms=$(stat -f '%OLp' "${_dir}")
    else
      _perms=$(stat -c '%a' "${_dir}")
    fi
    if [[ "${_perms}" == "700" ]]; then
      doctor_pass "${_label} (700)"
    else
      doctor_fail "${_label}" "expected 700, got ${_perms}"
    fi
  done
}
_doctor_check_versions() {
  printf "\nVersions:\n"

  _doctor_check_one_version() {
    local _tool="$1" _pinned="$2" _cmd="$3" _regex="$4"
    if ! command -v "${_tool}" &>/dev/null; then
      log_warn "${_tool}: not installed (skipping version check)"
      return
    fi
    local _raw _installed
    _raw=$(${_cmd} 2>&1)
    _installed=$(printf '%s' "${_raw}" | grep -oE "${_regex}" | head -1)
    if [[ -z "${_installed}" ]]; then
      log_warn "${_tool}: could not parse version from '${_raw}'"
      return
    fi
    if [[ "${_installed}" == "${_pinned}"* ]]; then
      doctor_pass "${_tool} (${_installed})"
    else
      doctor_fail "${_tool}" "installed ${_installed}, pinned ${_pinned}"
    fi
  }

  _doctor_check_one_version "go"      "${GO_VER}"     "go version"        "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _doctor_check_one_version "python3" "${PYTHON_VER}" "python3 --version" "[0-9]+\.[0-9]+\.[0-9]+"
  _doctor_check_one_version "ruby"    "${RUBY_VER}"   "ruby --version"    "[0-9]+\.[0-9]+\.[0-9]+"
  _doctor_check_one_version "zsh"     "${ZSH_VER}"    "zsh --version"     "[0-9]+\.[0-9]+(\.[0-9]+)?"
}

process_args() {
  # Pre-process long options before getopts (getopts only handles short options)
  local _short_args=()
  for _arg in "$@"; do
    case "${_arg}" in
      --dry-run)     readonly DRY_RUN=1 ;;
      --brew-only)   readonly UPDATE_BREW=1 ;;
      --pip-only)    readonly UPDATE_PIP=1 ;;
      --gems-only)   readonly UPDATE_GEMS=1 ;;
      --mas-only)    readonly UPDATE_MAS=1 ;;
      --claude-only) readonly UPDATE_CLAUDE=1 ;;
      *) _short_args+=("${_arg}") ;;
    esac
  done
  set -- "${_short_args[@]}"

  local arg OPTARG
  while getopts ":ht:w" arg; do
    # shellcheck disable=SC2317 # exit after usage() is intentional redundancy
    case ${arg} in
      t)
        # shellcheck disable=SC2317 # exit after usage() is intentional redundancy
        case ${OPTARG} in
          setup_user)     readonly SETUP_USER=1 ;;
          setup)          readonly SETUP=1 ;;
          developer)      readonly DEVELOPER=1 ;;
          ansible)        readonly ANSIBLE=1 ;;
          update)         readonly UPDATE=1 ;;
          doctor)         readonly DOCTOR=1 ;;
          check-versions) readonly CHECK_VERSIONS=1 ;;
          *) printf "Invalid option for -t\n"; usage; exit 1 ;;
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
    safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac" "${HOME}/.gitconfig"
    if [[ -d ${HOME}/git-repos/gitlab ]]; then
      safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac_gitlab" "${HOME}/git-repos/gitlab/.gitconfig"
    fi
  fi
  if [[ -n ${LINUX} ]]; then
    safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux" "${HOME}/.gitconfig"
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      if [[ -d ${HOME}/git-repos/gitlab ]]; then
        safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux_gitlab" "${HOME}/git-repos/gitlab/.gitconfig"
      fi
    fi
  fi

  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc" "${HOME}/.vimrc"
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.p10k.zsh" "${HOME}/.p10k.zsh"
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.tmux.conf" "${HOME}/.tmux.conf"
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/scripts" "${HOME}/scripts"

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "Creating ${HOME}/.config"
    mkdir -p ${HOME}/.config
    log_info "Created ${HOME}/.config"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "Creating ${HOME}/.tf_creds"
    mkdir -p ${HOME}/.tf_creds
    if [[ -d ${HOME}/.tf_creds ]]; then
      chmod 700 ${HOME}/.tf_creds
      log_info "Created ${HOME}/.tf_creds"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    log_info "powershell profile and custom oh-my-posh theme"
    mkdir -p ${HOME}/.config/powershell
    safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/profile.ps1" "${HOME}/.config/powershell/profile.ps1"
    safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/bruce.omp.json" "${HOME}/.config/powershell/bruce.omp.json"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/starship.toml" "${HOME}/.config/starship.toml"
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

  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc" "${HOME}/.zshrc"
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.config/.zshrc.d" "${HOME}/.config/.zshrc.d"

  mkdir -p ${HOME}/.config
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.config/ccstatusline" "${HOME}/.config/ccstatusline"

  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.zprofile" "${HOME}/.zprofile"
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme" "${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme"

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
    log_info "Created ${HOME}/.warp"
  fi
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.warp/themes" "${HOME}/.warp/themes"
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.warp/launch_configurations" "${HOME}/.warp/launch_configurations"

  log_info "Creating ${HOME}/.ssh"
  mkdir -p ${HOME}/.ssh
  if [[ -d ${HOME}/.ssh ]]; then
    chmod 700 ${HOME}/.ssh
    log_info "Created ${HOME}/.ssh"
  fi

  log_info "Creating ${HOME}/.claude"
  mkdir -p ${HOME}/.claude
  if [[ -d ${HOME}/.claude ]]; then
    log_info "Created ${HOME}/.claude"
  fi
  for _claude_item in "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/"*; do
    [[ -e "${_claude_item}" ]] || continue
    # Skip projects/ — handled below with per-project symlinks into a real ~/.claude/projects/
    [[ "$(basename "${_claude_item}")" == "projects" ]] && continue
    _claude_target="${HOME}/.claude/$(basename "${_claude_item}")"
    safe_link "${_claude_item}" "${_claude_target}"
  done
  mkdir -p "${HOME}/.claude/projects"
  for _claude_proj in "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/projects/"*; do
    [[ -e "${_claude_proj}" ]] || continue
    _claude_proj_target="${HOME}/.claude/projects/$(basename "${_claude_proj}")"
    safe_link "${_claude_proj}" "${_claude_proj_target}"
  done

  log_info "Creating ${HOME}/.cursor"
  mkdir -p "${HOME}/.cursor"
  # glob * excludes dotfiles (e.g. .gitignore) — intentional
  for _cursor_item in "${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/"*; do
    [[ -e "${_cursor_item}" ]] || continue
    # Skip User/ — handled separately via CURSOR_USER_DIR symlinks
    [[ "$(basename "${_cursor_item}")" == "User" ]] && continue
    _cursor_target="${HOME}/.cursor/$(basename "${_cursor_item}")"
    safe_link "${_cursor_item}" "${_cursor_target}"
  done

  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config" "${HOME}/.ssh/config"

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
        # v2: settings live in a separate Cursor/settings/ subdir
        # v3: settings live directly in Cursor/User/; check User dir exists
        if [[ ! -f "${CURSOR_APP_SETTINGS_DIR}/settings.json" ]] || \
           [[ ! -f "${CURSOR_APP_SETTINGS_DIR}/keybindings.json" ]]; then
          if [[ ! -d "${CURSOR_USER_DIR}" ]]; then
            CURSOR_APP_SETTINGS_OK=0
          fi
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
        safe_link "${CURSOR_DOTFILES_USER_DIR}/settings.json" "${CURSOR_USER_DIR}/settings.json"
        safe_link "${CURSOR_DOTFILES_USER_DIR}/keybindings.json" "${CURSOR_USER_DIR}/keybindings.json"
        safe_link "${CURSOR_DOTFILES_USER_DIR}/snippets" "${CURSOR_USER_DIR}/snippets"
      else
        log_warn "Skipping Cursor symlinks; Cursor app settings or dotfiles Cursor user files are missing"
      fi
    else
      log_warn "Skipping Cursor symlinks; Cursor is not installed"
    fi
  fi

  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/teleport.cfg" "${HOME}/.ssh/teleport.cfg"

  log_info "Creating ${HOME}/.tsh"
  mkdir -p ${HOME}/.tsh
  if [[ -d ${HOME}/.tsh ]]; then
    chmod 700 ${HOME}/.tsh
    log_info "Created ${HOME}/.tsh"
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
