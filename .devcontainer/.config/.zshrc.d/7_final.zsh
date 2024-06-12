if [[ ${LINUX} ]]; then
  # find out which distribution we are running on
  distro=$(awk '/^ID=/' /etc/*-release | awk -F'=' '{ print tolower($2) }')

  # set an icon based on the distro
  case $distro in
      *kali*)                  ICON="ﴣ";;
      *arch*)                  ICON="";;
      *debian*)                ICON="";;
      *raspbian*)              ICON="";;
      *ubuntu*)                ICON="";;
      *elementary*)            ICON="";;
      *fedora*)                ICON="";;
      *coreos*)                ICON="";;
      *gentoo*)                ICON="";;
      *mageia*)                ICON="";;
      *centos*)                ICON="";;
      *opensuse*|*tumbleweed*) ICON="";;
      *sabayon*)               ICON="";;
      *slackware*)             ICON="";;
      *linuxmint*)             ICON="";;
      *alpine*)                ICON="";;
      *aosc*)                  ICON="";;
      *nixos*)                 ICON="";;
      *devuan*)                ICON="";;
      *manjaro*)               ICON="";;
      *rhel*)                  ICON="";;
      *)                       ICON="";;
  esac
fi
if [[ ${MACOS} ]]; then
  ICON=""
fi

# for go

if [[ -d /usr/local/go ]]; then
  export GOROOT=/usr/local/go
fi
if [[ -d ${HOME}/go-work ]]; then
  export GOPATH="${HOME}/go-work"
fi

# for zoxide
if quiet_which zoxide
then
  eval "$(zoxide init zsh)"
fi

# for pyenv
if command -v pyenv &> /dev/null; then
  export PYENV_VIRTUALENV_DISABLE_PROMPT=1
  export PYENV_ROOT="$HOME/.pyenv"

  if ! command -v pyenv &> /dev/null; then
    export PATH="$PYENV_ROOT/bin:$PATH"
  fi

  eval "$(pyenv virtualenv-init -)"
  if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]] || [[ -n ${RATNA} ]]; then
    if [[ "$(pyenv version-name)" != "ansible" ]]; then
      pyenv activate ansible
    fi
  fi

fi

# Load Starship
export STARSHIP_DISTRO="$ICON "
eval "$(starship init zsh)"
