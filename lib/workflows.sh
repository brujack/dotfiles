#!/usr/bin/env bash
# lib/workflows.sh — top-level workflow functions dispatched by setup_env.sh

setup_claude_mcp() {
  local _template="${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
  local _output="${HOME}/.claude/mcp.json"
  local _local_config="${PERSONAL_GITREPOS}/${DOTFILES}/config/local.sh"

  # Source config/local.sh to pick up GITHUB_PAT if not already in environment
  if [[ -f "${_local_config}" ]]; then
    # shellcheck disable=SC1090
    source "${_local_config}" || true
  fi

  if [[ -z "${GITHUB_PAT:-}" ]]; then
    log_warn "GITHUB_PAT not set — GitHub MCP not configured"
    log_warn "Add GITHUB_PAT to config/local.sh and re-run: setup_env.sh -t setup_user"
    return 0
  fi

  if ! command -v envsubst &>/dev/null; then
    log_error "envsubst not found — install gettext: brew install gettext or apt-get install gettext-base"
    return 1
  fi

  # Remove broken symlink from old setup if present
  if [[ -L "${_output}" ]] && [[ ! -e "${_output}" ]]; then
    rm -f "${_output}"
  fi

  mkdir -p "$(dirname "${_output}")"
  # shellcheck disable=SC2016 # single quotes intentional — envsubst variable list, not shell expansion
  if ! GITHUB_PAT="${GITHUB_PAT}" envsubst '${GITHUB_PAT}' < "${_template}" > "${_output}"; then
    log_error "Failed to generate ${_output} from template"
    return 1
  fi
  log_info "GitHub MCP configured (${_output})"
}

run_setup_user() {
  # need to make sure that some base packages are installed
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! [ -x "$(command -v dnf)" ]; then
      printf "Installing dnf\\n"
      sudo -H yum update -y
      sudo -H yum install dnf -y
      if ! [ -x "$(command -v dnf)" ]; then
        printf "Failed to install dnf\\n"
        return 1
      fi
      printf "Installed dnf\\n"
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    printf "Installing Rosetta if necessary\\n"
    install_rosetta || return 1
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${FEDORA} ]] || [[ -n ${CENTOS} ]]; then
    install_git || return 1
  fi

  mkdir -p ${HOME}/software_downloads

  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then
    install_zsh || return 1
  fi

  if [[ -n ${LINUX} ]]; then
    install_bats || return 1
  fi

  printf "Creating %s/bin\\n" "${HOME}"
  mkdir -p ${HOME}/bin

  printf "Creating %s\\n" "${PERSONAL_GITREPOS}"
  mkdir -p ${PERSONAL_GITREPOS}

  clone_or_update_dotfiles || return 1

  setup_dotfile_symlinks || return 1

  install_terraform_skill || return 1

  setup_zsh_as_default_shell || return 1

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

  setup_claude_mcp || return 1
}

run_setup_or_developer() {
  setup_credential_directories || return 1

  if [[ -n ${MACOS} ]]; then
    install_macos_packages || return 1
  fi

  if [[ -n ${UBUNTU} ]]; then
    install_ubuntu_packages || return 1
  fi

  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    install_rhel_packages || return 1
  fi

  if [[ -n ${CENTOS} ]]; then
    install_centos_packages || return 1
  fi

  if [[ -n ${LINUX} ]]; then
    install_linux_packages || return 1
  fi

  install_aws_tools || return 1
  setup_vim_plugins
}

run_developer_or_ansible() {
  printf "Installing json2yaml via npm\n"
  npm install json2yaml || return 1

  install_ruby_tools || return 1
  install_ruby || return 1
  if [[ -n ${LINUX} ]]; then
    install_github_cli_linux || return 1
  fi
  setup_kitchen || return 1
  setup_ansible || return 1
  clone_personal_repos
}

run_brew_install() {
  mkdir -p "${BREWFILE_LOC}"
  rm -f "${BREWFILE_LOC}/Brewfile"
  ln -s "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile" "${BREWFILE_LOC}/Brewfile"

  if ! quiet_which brew; then
    install_homebrew || return 1
  fi
  brew_update || return 1
  brew_tap_if_missing homebrew/bundle || return 1
  if [[ -n ${MACOS} ]]; then
    install_macos_casks || return 1
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

  _UPDATE_TMPDIR=$(mktemp -d)
  export _UPDATE_TMPDIR
  trap 'rm -rf "${_UPDATE_TMPDIR}"; unset _UPDATE_TMPDIR' EXIT INT TERM

  # ── brew + softwareupdate ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
      _update_record_start "brew"
      brew_update
      _update_record_end "brew" $?

      if [[ -n ${MACOS} ]]; then
        _update_record_start "softwareupdate"
        printf "Updating app store apps softwareupdate\\n"
        sudo -H softwareupdate --install --all --verbose
        _update_record_end "softwareupdate" $?
      else
        _update_skip "softwareupdate" "not macOS"
      fi
    else
      _update_skip "brew" "not macOS or Linux"
      _update_skip "softwareupdate" "not macOS or Linux"
    fi
  else
    _update_skip "brew" "flag not set"
    _update_skip "softwareupdate" "flag not set"
  fi

  # ── claude plugins ────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    if command -v claude &>/dev/null; then
      _update_record_start "claude"
      printf "Updating Claude plugins\\n"
      # CLI matches installed plugins by plugin@marketplace (see `claude plugins list`), not short names.
      claude plugins update superpowers@claude-plugins-official \
        && claude plugins update code-simplifier@claude-plugins-official \
        && claude plugins update code-review@claude-plugins-official \
        && claude plugins update context7@claude-plugins-official
      _update_record_end "claude" $?
    else
      _update_skip "claude" "claude not installed"
    fi
  else
    _update_skip "claude" "flag not set"
  fi

  # ── terraform-skill (Cursor git checkout; Claude Code uses plugin) ───────────
  # Same trigger as Claude plugins: full update or --claude-only (no claude CLI required).
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    _update_record_start "terraform-skill"
    install_terraform_skill
    _update_record_end "terraform-skill" $?
  else
    _update_skip "terraform-skill" "flag not set"
  fi

  # ── Linux system packages ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PKGS:-} ]]; then
    if [[ -n ${LINUX} ]]; then
      _update_record_start "apt"
      _update_record_start "snap"
      _update_record_start "dnf"
      _update_record_start "yum"
      update_system_packages
      local _pkg_ec=$?
      _update_record_end "apt"  "${_pkg_ec}"
      _update_record_end "snap" "${_pkg_ec}"
      _update_record_end "dnf"  "${_pkg_ec}"
      _update_record_end "yum"  "${_pkg_ec}"
    else
      _update_skip "apt"  "not applicable"
      _update_skip "snap" "not applicable"
      _update_skip "dnf"  "not applicable"
      _update_skip "yum"  "not applicable"
    fi
  else
    _update_skip "apt"  "flag not set"
    _update_skip "snap" "flag not set"
    _update_skip "dnf"  "flag not set"
    _update_skip "yum"  "flag not set"
  fi

  # ── mas ───────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    _update_record_start "mas"
    local _mas_ec=0
    if [[ -n ${MACOS} ]]; then
      log_info "Updating mas packages"
      mas upgrade 2>&1 | tee "${_UPDATE_TMPDIR}/mas_upgrade_output"
      _mas_ec="${PIPESTATUS[0]}"
    fi
    _update_record_end "mas" "${_mas_ec}"
  else
    _update_skip "mas" "flag not set"
  fi

  # ── pip ───────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PIP:-} ]]; then
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      _update_record_start "pip"
      printf "Updating pip3 packages\n"
      export PYENV_ROOT="$HOME/.pyenv"
      export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

      if command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
      fi

      pyenv shell ansible 2>/dev/null || true
      PYTHON="$(pyenv which python 2>/dev/null || command -v python3)"

      "$PYTHON" -m pip install -U pip setuptools wheel

      # _UPDATE_TMPDIR is read by the Python block via os.environ to write pip_outdated
      "$PYTHON" - <<PY
import json, subprocess, sys, os

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out)]

# Write outdated package names for the update summary
tmpdir = os.environ.get("_UPDATE_TMPDIR", "/tmp")
with open(os.path.join(tmpdir, "pip_outdated"), "w") as f:
    f.write("\\n".join(pkgs))

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY
      local _pip_rc=$?

      "$PYTHON" -m pip check || true
      printf "Updated pip packages\n"
      _update_record_end "pip" ${_pip_rc}
    else
      _update_skip "pip" "HAS_DEVTOOLS not set"
    fi
  else
    _update_skip "pip" "flag not set"
  fi

  # ── git-based tools + misc (run_all only) ─────────────────────────────────
  if [[ ${_run_all} -eq 1 ]]; then
    update_aws_cli
    update_rust
    if [[ -d ${HOME}/.tfenv ]]; then
      _update_record_start "tfenv"
      printf "Updating tfenv\\n"
      cd "${HOME}/.tfenv" || return 1
      git pull
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "tfenv" $?
    else
      _update_skip "tfenv" "not installed"
    fi
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      _update_record_start "oh-my-zsh"
      printf "Updating oh-my-zsh\\n"
      cd "${HOME}/.oh-my-zsh" || return 1
      git pull
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "oh-my-zsh" $?
    else
      _update_skip "oh-my-zsh" "not installed"
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      _update_record_start "p10k"
      printf "Updating powerlevel10k\\n"
      cd "${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" || return 1
      git pull
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "p10k" $?
    else
      _update_skip "p10k" "not installed"
    fi
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      _update_record_start "tpm"
      printf "Updating tpm\\n"
      cd "${HOME}/.tmux/plugins/tpm" || return 1
      git pull
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "tpm" $?
    else
      _update_skip "tpm" "not installed"
    fi
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      _update_record_start "cheat.sh"
      printf "Updating cheat.sh\\n"
      curl https://cht.sh/:cht.sh > ~/bin/cht.sh
      chmod 754 ${HOME}/bin/cht.sh
      _update_record_end "cheat.sh" $?
    else
      _update_skip "cheat.sh" "not installed"
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      printf "Updating cheat.sh tab completion\\n"
      curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
      printf "Updating zsh-autosuggestions\\n"
      cd "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || return 1
      git pull
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
    fi
  else
    _update_skip "tfenv" "flag not set"
    _update_skip "oh-my-zsh" "flag not set"
    _update_skip "p10k" "flag not set"
    _update_skip "tpm" "flag not set"
    _update_skip "cheat.sh" "flag not set"
  fi

  # ── gems ──────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    _update_record_start "gems"
    printf "updating ruby gems\\n"
    gem update
    _update_record_end "gems" $?
  else
    _update_skip "gems" "flag not set"
  fi

  # ── drift check ───────────────────────────────────────────────────────────
  _update_check_brewfile_drift

  # ── summary ───────────────────────────────────────────────────────────────
  _update_summary
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
  _run_cv_check "gitleaks"  "${GITLEAKS_VER}"    "gitleaks/gitleaks"   "gitleaks version"     "[0-9]+\.[0-9]+\.[0-9]+"    "GITLEAKS_VER"

  printf "\n%d outdated, %d skipped, %d warnings, %d OK\n" \
    "${_outdated}" "${_skipped}" "${_warned}" "${_ok}"

  [[ ${_outdated} -eq 0 ]]
}
