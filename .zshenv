# Non-interactive shells (ssh host cmd, zsh -c from editors and scripts) read only this
# file, and on macOS their default PATH resolves python3 to Apple's 3.9.6. Put Homebrew's
# current python3 first, unless an inherited PATH already resolves python3 elsewhere
# (pyenv, a venv). Interactive shells are left to pyenv.
if [[ ! -o interactive ]]; then
  if [[ -z ${commands[python3]} || ${commands[python3]} == /usr/bin/python3 ]]; then
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

# Machine-local additions (installer-written lines such as rustup's) live here, never in
# this tracked file.
[[ -r "${HOME}/.zshenv.local" ]] && source "${HOME}/.zshenv.local"
