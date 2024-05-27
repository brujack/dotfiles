# pyenv setup
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "laptop-1" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "studio-1" ]] && export STUDIO=1
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
if [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[ ${RECEPTION} ]] || [[ ${OFFICE} ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
eval "$(pyenv init -)"
