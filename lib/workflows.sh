#!/usr/bin/env bash
# lib/workflows.sh — top-level workflow functions dispatched by setup_env.sh

setup_claude_mcp() {
  local _ai_config_dir="${_OVERRIDE_AI_CONFIG_DIR:-${AI_CONFIG_DIR}}"
  local _template="${_ai_config_dir}/.claude/mcp.json.template"
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

  # Skip if mcp.json is a valid symlink — writing through it would inject credentials into the symlink target (e.g. a tracked git file)
  if [[ -L "${_output}" ]] && [[ -e "${_output}" ]]; then
    log_warn "${_output} is a symlink — skipping template generation to avoid writing credentials into the target"
    log_warn "To use template-generated mcp.json, remove the symlink first: rm ${_output}"
    return 0
  fi

  mkdir -p "$(dirname "${_output}")"
  # shellcheck disable=SC2016 # single quotes intentional — envsubst variable list, not shell expansion
  if ! GITHUB_PAT="${GITHUB_PAT}" envsubst '${GITHUB_PAT}' < "${_template}" > "${_output}"; then
    log_error "Failed to generate ${_output} from template"
    return 1
  fi
  log_info "GitHub MCP configured (${_output})"
}

setup_claude_plugins() {
  if ! command -v claude &>/dev/null; then
    log_warn "claude not installed — skipping plugin setup"
    return 0
  fi

  local _plugins=(
    "superpowers@claude-plugins-official"
    "code-review@claude-plugins-official"
    "context7@claude-plugins-official"
    "context-mode@context-mode"
    "rust-analyzer-lsp@claude-plugins-official"
    "pyright-lsp@claude-plugins-official"
    "caveman@caveman"
    "firecrawl@firecrawl"
    "skill-creator@claude-plugins-official"
    "frontend-design@claude-plugins-official"
    "security-guidance@claude-plugins-official"
    "ansible-good-practices@claude-ansible-skills"
    "terraform-skill@antonbabenko"
    "warp@claude-code-warp"
  )

  local _installed
  _installed="$(claude plugins list 2>/dev/null)" || true

  for _plugin in "${_plugins[@]}"; do
    if printf '%s' "${_installed}" | grep -qF "${_plugin}"; then
      log_info "Claude plugin already installed: ${_plugin}"
    else
      log_info "Installing Claude plugin: ${_plugin}"
      claude plugins install "${_plugin}" || log_warn "Failed to install Claude plugin: ${_plugin}"
    fi
  done
}

setup_ai_config() {
  local _dir="${_OVERRIDE_AI_CONFIG_DIR:-${AI_CONFIG_DIR}}"
  if [[ ! -d "${_dir}" ]]; then
    log_info "ai-config not found — cloning..."
    git clone git@github.com:brujack/ai-config "${_dir}" || return 1
  else
    log_info "Updating ai-config..."
    git -C "${_dir}" pull --rebase --autostash || return 1
  fi
}

_dotfiles_run_tmpdir_setup() {
  _DOTFILES_RUN_TMPDIR=$(mktemp -d)
  export _DOTFILES_RUN_TMPDIR
  trap 'rm -rf "${_DOTFILES_RUN_TMPDIR}"; unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
  date -u +%Y-%m-%dT%H:%M:%SZ > "${_DOTFILES_RUN_TMPDIR}/started_at"
  date +%s > "${_DOTFILES_RUN_TMPDIR}/start_epoch"
  python3 -c "import uuid; print(str(uuid.uuid4()))" \
    > "${_DOTFILES_RUN_TMPDIR}/run_id" 2>/dev/null || true
  git -C "${PERSONAL_GITREPOS}/${DOTFILES}" rev-parse HEAD \
    > "${_DOTFILES_RUN_TMPDIR}/git_sha" 2>/dev/null || true
}

run_setup_user() {
  _dotfiles_run_tmpdir_setup
  if [[ -n ${MACOS} ]]; then
    printf "Installing Rosetta if necessary\\n"
    install_rosetta || return 1
  fi

  if [[ -n ${MACOS} ]]; then
    install_git || return 1
  fi

  mkdir -p ${HOME}/software_downloads

  if [[ ${MACOS} || ${UBUNTU} ]]; then
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
  setup_ai_config || return 1

  setup_dotfile_symlinks || return 1

  install_terraform_skill || return 1

  setup_zsh_as_default_shell || return 1

  printf "Setting up cheat.sh\\n"
  if [[ -d ${HOME}/bin ]]; then
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
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
  setup_claude_plugins || return 1
  _ledger_write_run_entry "setup_user" 0 || true
}

run_setup_or_developer() {
  _dotfiles_run_tmpdir_setup
  setup_credential_directories || return 1

  if [[ -n ${MACOS} ]]; then
    install_macos_packages || return 1
  fi

  if [[ -n ${UBUNTU} ]]; then
    install_ubuntu_packages || return 1
  fi

  install_aws_tools || return 1
  setup_vim_plugins
  _ledger_write_run_entry "setup" 0 || true
}

run_developer_or_ansible() {
  _dotfiles_run_tmpdir_setup
  printf "Installing json2yaml via npm\n"
  npm install json2yaml || return 1

  printf "Installing firecrawl-cli via npm\n"
  npm install -g firecrawl-cli || return 1

  printf "Installing exa-mcp-server via npm\n"
  npm install -g exa-mcp-server || return 1

  install_ruby_tools || return 1
  install_ruby || return 1
  if [[ -n ${LINUX} ]]; then
    install_github_cli_linux || return 1
  fi
  setup_ansible || return 1
  clone_personal_repos
  _ledger_write_run_entry "developer" 0 || true
}

run_recreate_venv() {
  _dotfiles_run_tmpdir_setup
  local _venv_name="${VENV_NAME:-ansible}"
  recreate_python_venv "${_venv_name}" || return 1
  _ledger_write_run_entry "recreate_venv" 0 || true
}

run_recreate_ruby() {
  _dotfiles_run_tmpdir_setup
  recreate_ruby || return 1
  _ledger_write_run_entry "recreate_ruby" 0 || true
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

  _dotfiles_run_tmpdir_setup

  # ── brew + softwareupdate ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
      _update_record_start "brew"
      brew_update 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_brew"
      _update_record_end "brew" "${PIPESTATUS[0]}"

      if [[ -n ${MACOS} ]]; then
        _update_record_start "softwareupdate"
        printf "Updating app store apps softwareupdate\\n"
        sudo -H softwareupdate --install --all --verbose 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_softwareupdate"
        _update_record_end "softwareupdate" "${PIPESTATUS[0]}"
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
      # Run each independently so a single failure doesn't abort the rest, and failures are named.
      local _claude_failed=()
      local _plugin_rc=0
      for _plugin in \
        superpowers@claude-plugins-official \
        code-review@claude-plugins-official \
        context7@claude-plugins-official \
        context-mode@context-mode \
        rust-analyzer-lsp@claude-plugins-official \
        pyright-lsp@claude-plugins-official \
        caveman@caveman \
        firecrawl@firecrawl \
        skill-creator@claude-plugins-official \
        frontend-design@claude-plugins-official \
        security-guidance@claude-plugins-official \
        ansible-good-practices@claude-ansible-skills \
        terraform-skill@antonbabenko \
        warp@claude-code-warp; do
        claude plugins update "${_plugin}" 2>&1 | tee -a "${_DOTFILES_RUN_TMPDIR}/err_claude"
        _plugin_rc="${PIPESTATUS[0]}"
        [[ ${_plugin_rc} -ne 0 ]] && _claude_failed+=("${_plugin%%@*}")
      done
      local _claude_rc=0
      if [[ ${#_claude_failed[@]} -gt 0 ]]; then
        _claude_rc=1
        printf "%d plugin(s) failed (%s)\n" "${#_claude_failed[@]}" "${_claude_failed[*]}" \
          > "${_DOTFILES_RUN_TMPDIR}/fail_result_claude"
      fi
      _update_record_end "claude" "${_claude_rc}"
      # Post-update skill security scan — supply chain guard.
      # Advisory: never aborts the update. REVIEW/HOLD findings require human
      # review before using the flagged skill. Re-running does not clear REVIEW.
      if command -v python3 &>/dev/null && [[ -f "${HOME}/.claude/scripts/scan_skills.py" ]]; then
        printf "\n[skill-scan] Scanning updated plugins for malicious content...\n"
        local _scan_rc=0
        python3 "${HOME}/.claude/scripts/scan_skills.py" \
          --plugin-dir "${HOME}/.claude/plugins/cache/" \
          --write-ledger || _scan_rc=$?
        if [[ ${_scan_rc} -eq 2 ]]; then
          printf "\n[skill-scan] HOLD: one or more plugins contain red-flag patterns.\n"
          printf "             Do not use flagged skills until findings are resolved.\n"
        elif [[ ${_scan_rc} -eq 1 ]]; then
          printf "\n[skill-scan] REVIEW: one or more plugins could not be fully analyzed.\n"
          printf "             Human review required — re-running the scanner does not clear this.\n"
        fi
      fi
      # Post-update staleness audit — advisory only; never aborts update.
      # Detects attestations that pre-date the most recent plugin content hash.
      if command -v python3 &>/dev/null && [[ -f "${HOME}/.claude/scripts/plugin_verdicts.py" ]]; then
        python3 "${HOME}/.claude/scripts/plugin_verdicts.py" audit || {
          printf "\n[skill-scan] Stale attestations detected. Re-scan flagged plugins.\n"
        }
      fi
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
    install_terraform_skill 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_terraform-skill"
    _update_record_end "terraform-skill" "${PIPESTATUS[0]}"
  else
    _update_skip "terraform-skill" "flag not set"
  fi

  # ── npm global packages ───────────────────────────────────────────────────
  # Same trigger as Claude plugins: these packages support Claude tooling.
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    _update_record_start "npm"
    printf "Updating npm global packages\\n"
    npm install -g firecrawl-cli exa-mcp-server 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_npm"
    _update_record_end "npm" "${PIPESTATUS[0]}"
  else
    _update_skip "npm" "flag not set"
  fi

  # ── Linux system packages ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PKGS:-} ]]; then
    if [[ -n ${LINUX} ]]; then
      _update_record_start "apt"
      _update_record_start "snap"
      update_system_packages 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_apt"
      local _pkg_ec="${PIPESTATUS[0]}"
      cp "${_DOTFILES_RUN_TMPDIR}/err_apt" "${_DOTFILES_RUN_TMPDIR}/err_snap" 2>/dev/null || true
      _update_record_end "apt"  "${_pkg_ec}"
      _update_record_end "snap" "${_pkg_ec}"
    else
      _update_skip "apt"  "not applicable"
      _update_skip "snap" "not applicable"
    fi
  else
    _update_skip "apt"  "flag not set"
    _update_skip "snap" "flag not set"
  fi

  # ── mas ───────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    _update_record_start "mas"
    local _mas_ec=0
    if [[ -n ${MACOS} ]]; then
      log_info "Updating mas packages"
      mas upgrade 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_mas"
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

      {
        "$PYTHON" -m pip install -U pip setuptools

        # _DOTFILES_RUN_TMPDIR is read by the Python block via os.environ to write pip_outdated
        "$PYTHON" - <<PY
import json, subprocess, sys, os

# Packages with hard upper bounds from other installed tools — upgrading them
# independently breaks checkov, ansible-lint, shell-gpt, or bpytop. Let pip's
# dependency resolver manage these via top-level package installs only.
SKIP_UPGRADE = {"packaging", "pathspec", "rich", "psutil", "wheel"}

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out) if p["name"].lower() not in SKIP_UPGRADE]

# Write outdated package names for the update summary
tmpdir = os.environ.get("_DOTFILES_RUN_TMPDIR", "/tmp")
with open(os.path.join(tmpdir, "pip_outdated"), "w") as f:
    f.write("\\n".join(pkgs))

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY
      } 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_pip"
      local _pip_rc="${PIPESTATUS[0]}"

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
    _update_record_start "ai-config"
    setup_ai_config 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_ai-config"
    _update_record_end "ai-config" "${PIPESTATUS[0]}"
    update_aws_cli
    update_rust
    if [[ -d ${HOME}/.tfenv ]]; then
      _update_record_start "tfenv"
      printf "Updating tfenv\\n"
      { cd "${HOME}/.tfenv" && git pull; } 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_tfenv"
      local _tfenv_rc="${PIPESTATUS[0]}"
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "tfenv" "${_tfenv_rc}"
    else
      _update_skip "tfenv" "not installed"
    fi
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      _update_record_start "oh-my-zsh"
      printf "Updating oh-my-zsh\\n"
      { cd "${HOME}/.oh-my-zsh" && git pull; } 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_oh-my-zsh"
      local _omz_rc="${PIPESTATUS[0]}"
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "oh-my-zsh" "${_omz_rc}"
    else
      _update_skip "oh-my-zsh" "not installed"
    fi
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      _update_record_start "tpm"
      printf "Updating tpm\\n"
      { cd "${HOME}/.tmux/plugins/tpm" && git pull; } 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_tpm"
      local _tpm_rc="${PIPESTATUS[0]}"
      cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
      _update_record_end "tpm" "${_tpm_rc}"
    else
      _update_skip "tpm" "not installed"
    fi
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      _update_record_start "cheat.sh"
      printf "Updating cheat.sh\\n"
      { curl https://cht.sh/:cht.sh > ~/bin/cht.sh && chmod 754 "${HOME}/bin/cht.sh"; } \
        2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_cheat.sh"
      _update_record_end "cheat.sh" "${PIPESTATUS[0]}"
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
    _update_skip "tpm" "flag not set"
    _update_skip "cheat.sh" "flag not set"
  fi

  # ── gems ──────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    _update_record_start "gems"
    printf "updating ruby gems\\n"
    local _ruby_gem_dir="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
    local _extra_gem_path=""
    [[ -d "${_ruby_gem_dir}" ]] && _extra_gem_path="${_ruby_gem_dir}:"
    PATH="${_extra_gem_path}${PATH}" gem update 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_gems"
    _update_record_end "gems" "${PIPESTATUS[0]}"
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

_check_cv_oh_my_zsh() {
  local _latest _pinned="${OH_MY_ZSH_VER}"
  _latest=$(curl -fsSL "https://api.github.com/repos/ohmyzsh/ohmyzsh/releases/latest" \
    2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-14s could not fetch latest version\n" "oh-my-zsh"
    _warned=$(( _warned + 1 ))
    return 0
  fi
  if [[ "${_pinned}" == "${_latest}" ]]; then
    printf "  [OK]       %-14s pinned=%-10s latest=%s\n" "oh-my-zsh" "${_pinned}" "${_latest}"
    _ok=$(( _ok + 1 ))
  else
    printf "  [OUTDATED] %-14s pinned=%-10s latest=%s\n" "oh-my-zsh" "${_pinned}" "${_latest}"
    _outdated=$(( _outdated + 1 ))
    if [[ -n ${UPDATE_VERSIONS:-} ]]; then
      _prompt_version_update "oh-my-zsh" "OH_MY_ZSH_VER" "${_pinned}" "${_latest}"
    fi
  fi
}

_check_cv_homebrew_install() {
  local _latest _pinned="${HOMEBREW_INSTALL_SHA}"
  _latest=$(curl -fsSL "https://api.github.com/repos/Homebrew/install/commits/master" \
    2>/dev/null | grep '"sha"' | head -1 | cut -d'"' -f4)
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-14s could not fetch latest SHA\n" "homebrew-install"
    _warned=$(( _warned + 1 ))
    return 0
  fi
  local _pin_short="${_pinned:0:12}" _latest_short="${_latest:0:12}"
  if [[ "${_pinned}" == "${_latest}" ]]; then
    printf "  [OK]       %-14s pinned=%s latest=%s\n" "homebrew-install" "${_pin_short}" "${_latest_short}"
    _ok=$(( _ok + 1 ))
  else
    printf "  [OUTDATED] %-14s pinned=%s latest=%s\n" "homebrew-install" "${_pin_short}" "${_latest_short}"
    _outdated=$(( _outdated + 1 ))
    if [[ -n ${UPDATE_VERSIONS:-} ]]; then
      _prompt_version_update "homebrew-install" "HOMEBREW_INSTALL_SHA" "${_pinned}" "${_latest}"
    fi
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
  _check_cv_oh_my_zsh
  _check_cv_homebrew_install

  printf "\n%d outdated, %d skipped, %d warnings, %d OK\n" \
    "${_outdated}" "${_skipped}" "${_warned}" "${_ok}"

  [[ ${_outdated} -eq 0 ]]
}

# ── Ledger integration ─────────────────────────────────────────────────────────

ensure_machine_id() {
  local _id_path="${HOME}/.config/dotfiles/machine-id"
  if [[ -f "${_id_path}" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "${_id_path}")"
  python3 -c "import uuid; print(str(uuid.uuid4()))" > "${_id_path}" || return 1
  printf "machine-id created: %s\n" "${_id_path}"
}

ledger_write_entry() {
  local _json="${1:?ledger_write_entry: json payload required}"
  local _ledger_bin
  _ledger_bin="$(command -v ledger 2>/dev/null)"
  [[ -z "${_ledger_bin}" && -x "${HOME}/.local/bin/ledger" ]] && \
    _ledger_bin="${HOME}/.local/bin/ledger"
  if [[ -z "${_ledger_bin}" ]]; then
    printf "WARNING: ledger binary not found — skipping ledger write\n" >&2
    return 0
  fi
  local _rc
  printf '%s' "${_json}" | "${_ledger_bin}" write
  _rc=$?
  if [[ ${_rc} -eq 2 ]]; then
    printf "WARNING: ledger write spooled (unreachable)\n" >&2
    return 2
  fi
  return ${_rc}
}

ledger_flush_spool() {
  local _ledger_bin
  _ledger_bin="$(command -v ledger 2>/dev/null)"
  [[ -z "${_ledger_bin}" && -x "${HOME}/.local/bin/ledger" ]] && \
    _ledger_bin="${HOME}/.local/bin/ledger"
  if [[ -z "${_ledger_bin}" ]]; then
    return 0
  fi
  "${_ledger_bin}" flush
}
