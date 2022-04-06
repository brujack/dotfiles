# pyenv setup
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "fg-bjackson" ]] && export BRUCEWORK=1
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if [[ ${LAPTOP} ]] || [[ ${STUDIO} ]] || [[  ${BRUCEWORK} ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
eval "$(pyenv init --path)"
