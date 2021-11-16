# pyenv setup
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if [[ ${LAPTOP} ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
eval "$(pyenv init --path)"
