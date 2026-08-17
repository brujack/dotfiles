# pyenv setup
source "${0:A:h}/config/profiles.zsh"
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
eval "$(pyenv init --path)"
if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
  if [[ -f /home/linuxbrew/.linuxbrew/bin/rbenv ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/rbenv init - --no-rehash zsh)"
  fi
fi
