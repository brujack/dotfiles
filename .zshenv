# Non-interactive shells (ssh host cmd, zsh -c from editors and scripts) read only this
# file, and on macOS their default PATH resolves python3 to Apple's 3.9.6. Put Homebrew's
# current python3 first, unless an inherited PATH already resolves python3 elsewhere
# (pyenv, a venv). Interactive shells are left to pyenv.
# The '-' default on commands[python3] keeps a nounset (zsh -u) shell alive when no
# python3 is on PATH.
if [[ ! -o interactive ]]; then
  if [[ -z ${commands[python3]-} || ${commands[python3]} == /usr/bin/python3 ]]; then
    for _py_prefix in "${_OVERRIDE_HOMEBREW_PREFIX_ARM:-/opt/homebrew}" "${_OVERRIDE_HOMEBREW_PREFIX_INTEL:-/usr/local}"; do
      if [[ -d "${_py_prefix}/opt/python@3/libexec/bin" ]]; then
        typeset -U path
        path=("${_py_prefix}/opt/python@3/libexec/bin" $path)
        break
      fi
    done
  fi
  unset _py_prefix
fi

# Claude Code loads each ':'-separated absolute path in CLAUDE_CODE_PLUGIN_DIRS as a
# --plugin-dir. The progress mod is linked from ai-config by setup_env.sh, so export it
# only where the link exists. Append to an inherited value rather than replace it, and
# skip the append when the dir is already an element: every nested zsh re-reads this file.
# Split into a real array: a one-element nested ${(s.:.)...} is a scalar, and (Ie) on a
# scalar is a substring search that counts a path like .../progress-old as a match.
# The '-' default keeps a nounset (zsh -u) shell from aborting this file before
# .zshenv.local is sourced.
_progress_mod="${HOME}/.claude/mods/progress"
_plugin_dirs=("${(@s.:.)CLAUDE_CODE_PLUGIN_DIRS-}")
if [[ -d "${_progress_mod}" ]] && (( ! ${_plugin_dirs[(Ie)${_progress_mod}]} )); then
  export CLAUDE_CODE_PLUGIN_DIRS="${CLAUDE_CODE_PLUGIN_DIRS:+${CLAUDE_CODE_PLUGIN_DIRS}:}${_progress_mod}"
fi
unset _progress_mod _plugin_dirs

# Machine-local additions (installer-written lines such as rustup's) live here, never in
# this tracked file.
[[ -r "${HOME}/.zshenv.local" ]] && source "${HOME}/.zshenv.local"
