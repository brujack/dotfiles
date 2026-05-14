# pyenv setup
[[ $(hostname -s) = "laptop" ]] && export LAPTOP=1
[[ $(hostname -s) = "laptop-1" ]] && export LAPTOP=1
[[ $(hostname -s) = "studio" ]] && export STUDIO=1
[[ $(hostname -s) = "studio-1" ]] && export STUDIO=1
[[ $(hostname -s) = "reception" ]] && export RECEPTION=1
[[ $(hostname -s) = "reception-1" ]] && export RECEPTION=1
[[ $(hostname -s) = "office" ]] && export OFFICE=1
[[ $(hostname -s) = "office-1" ]] && export OFFICE=1
[[ $(hostname -s) = "homes" ]] && export HOMES=1
[[ $(hostname -s) = "homes-1" ]] && export HOMES=1
[[ $(hostname -s) = "workstation" ]] && export WORKSTATION=1
[[ $(hostname -s) = "workstation" ]] && export WORKSTATION=1
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
