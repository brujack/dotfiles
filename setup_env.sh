#!/bin/bash

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }
[ $# -eq 0 ] &&usage

# get command line options
while getopts ":ht:" arg; do
  case $arg in
    t) # Specify t of either 'setup' or 'update'.
      [ ${OPTARG} = "setup" ] && export SETUP=1
      [ ${OPTARG} = "update" ] && export UPDATE=1
      ;;
    h | *) # Display help.
      usage
      exit 0
      ;;
  esac
done

# choose which env we are running on
[ $(uname -s) = "Darwin" ] && export MACOS=1
[ $(uname -s) = "Linux" ] && export LINUX=1
[[ $(uname -r) =~ Microsoft$ ]] && export WINDOWS=1
[ $(hostname -s) = "kube-0" ] && export KUBE=1
[ $(hostname -s) = "kube-1" ] && export KUBE=1
[ $(hostname -s) = "kube-2" ] && export KUBE=1

# locations of directories
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
DOTFILES="dotfiles"
RANCHERSSH="${HOME}/.rancherssh"
BREWFILE_LOC="${HOME}/brew"
HOSTNAME=$(hostname -s)
WSL_HOME="/mnt/c/Users/${USER}"

# setup variables based off of environment
if [[ ${MACOS} ]]
then
  VSCODE="${HOME}/Library/Application Support/Code/User"
elif [[ ${WINDOWS} ]]
then
  #%APPDATA%\Code\User\ in windows parlance
  VSCODE="${WSL_HOME}/AppData/Roaming/Code/User"
fi

# Setup is run rarely as it should be run when setting up a new device or when doing a controlled change after changing items in setup
if [[ ${SETUP} ]]
then
  echo "Creating home bin"
  if [[ ! -d ${HOME}/bin ]]
  then
    mkdir ${HOME}/bin
  fi

  echo "Creating home aws"
  if [[ ! -d ${HOME}/.aws ]]
  then
    mkdir ${HOME}/.aws
  fi

  echo "Creating ${GITREPOS}"
  if [[ ! -d ${GITREPOS} ]]
  then
    mkdir ${GITREPOS}
  fi

  echo "Creating ${PERSONAL_GITREPOS}"
  if [[ ! -d ${PERSONAL_GITREPOS} ]]
  then
    mkdir ${PERSONAL_GITREPOS}
  fi

  echo "Copying ${DOTFILES} from Github"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]
  then
    cd ${HOME}
    git clone --recursive git@github.com:brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd ${PERSONAL_GITREPOS}/${DOTFILES}
    git pull
  fi

  echo "Linking ${DOTFILES} to their home"

  if [[ ! -L ${HOME}/.zshrc ]]
  then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  else
    rm ${HOME}/.zshrc
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  fi
  if [[ ! -L ${HOME}/.gitconfig ]]
  then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig ${HOME}/.gitconfig
  else
    rm ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig ${HOME}/.gitconfig
  fi
  if [[ ! -L ${HOME}/.vimrc ]]
  then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  else
    rm ${HOME}/.vimrc
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  fi
  if [[ ${MACOS} ]]
  then
    if [[ ! -L "$VSCODE"/settings.json ]]
    then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
    else
      rm "$VSCODE"/settings.json
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
    fi
  fi
  if [[ ${WINDOWS} ]]
  then
    if [[ ! -e "$VSCODE"/settings.json ]]
    then
      cp -a ${WSL_HOME}/git-repos/personal/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
    else
      rm "$VSCODE"/settings.json
      cp -a ${WSL_HOME}/git-repos/personal/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
    fi
  fi

  echo "Installing Oh My ZSH..."
  if [[ ! -d ${HOME}/.oh-my-zsh ]]
  then
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
  fi

  echo "Linking custom bruce.zsh-theme"
  if [[ ! -L ${HOME}/.oh-my-zsh/custom/bruce.zsh-theme && -d ${HOME}/.oh-my-zsh/custom/bruce.zsh-theme ]]
  then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/bruce.zsh-theme
  else
    rm ${HOME}/.oh-my-zsh/custom/bruce.zsh-theme
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/bruce.zsh-theme
  fi

  if [[ ! -d ${HOME}/.ssh ]]
  then
    mkdir ${HOME}/.ssh
    chmod 755 ${HOME}/.ssh
  fi
  if [[ ! -L ${HOME}/.ssh/config && -d ${HOME}/.ssh/config ]]
  then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  else
    rm ${HOME}/.ssh/config
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  fi

  echo "Setting ZSH as shell..."
  if [[ ! ${SHELL} = "/bin/zsh" ]]
  then
    chsh -s /bin/zsh
  fi

  if [[ ${MACOS} ]]
  then
    echo "Creating $BREWFILE_LOC"
    if [[ ! -d ${BREWFILE_LOC} ]]
    then
      mkdir ${BREWFILE_LOC}
    fi

    if [[ ! -L ${BREWFILE_LOC}/Brewfile ]]
    then
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile $BREWFILE_LOC/Brewfile
    else
      rm $BREWFILE_LOC/Brewfile
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile $BREWFILE_LOC/Brewfile
    fi

    # Xcode mas id 497799835
    # needed early in order to install other stuff
    mas install 497799835
    echo "Installing xcode-stuff"
    xcode-select --install

    # Check for Homebrew,
    # Install if we don't have it
    if test ! $(which brew); then
      echo "Installing homebrew..."
      ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    echo "Updating homebrew..."
    brew update
    echo "Upgrading brew's"
    brew upgrade
    echo "Upgrading brew casks"
    brew cask upgrade

    echo "Installing other brew stuff..."
    brew tap homebrew/bundle
    brew tap caskroom/cask
    cd ${BREWFILE_LOC} && brew bundle
    cd ${PERSONAL_GITREPOS}/${DOTFILES}

    if [[ ! -d "/Applications/Alfred 3.app" ]]
    then
      brew cask install alfred
    fi
    if [[ ! -d "/Applications/AppCleaner.app" ]]
    then
      brew cask install appcleaner
    fi
    if [[ ! -d "/Applications/Atom.app" ]]
    then
      brew cask install atom
    fi
    if [[ ! -d "/Applications/DaisyDisk.app" ]]
    then
      brew cask install daisydisk
    fi
    if [[ ! -d "/Applications/Beyond Compare.app" ]]
    then
      brew cask install beyond-compare
    fi
    if [[ ! -d "/Applications/Carbon Copy Cloner.app" ]]
    then
      brew cask install carbon-copy-cloner
    fi
    if [[ ! ${HOSTNAME} == "server" ]]
    then
      if [[ ! -d "/Applications/Docker.app" ]]
      then
        brew cask install caskroom/versions/docker-edge
      fi
    fi
    if [[ ! -d "/Applications/Dropbox.app" ]]
    then
      brew cask install dropbox
    fi
    if [[ ! -d "/Applications/Firefox.app" ]]
    then
      brew cask install firefox
    fi
    if [[ ! ${HOSTNAME} == "server" ]] || [[ ! ${HOSTNAME} == "mac" ]]
    then
      if [[ ! -d "/Applications/Franz.app" ]]
      then
        brew cask install franz
      fi
    fi
    if [[ ! -d "/Applications/Funter.app" ]]
    then
      brew cask install funter
    fi
    if [[ ! -d "/Applications/Google Chrome.app" ]]
    then
      brew cask install google-chrome
    fi
    if [[ ! -d "/usr/local/Caskroom/google-cloud-sdk" ]]
    then
      brew cask install google-cloud-sdk
    fi
    if [[ ! -d "/Applications/iTerm.app" ]]
    then
      brew cask install iterm2
    fi
    if [[ ! -d "/Applications/Malwarebytes.app" ]]
    then
      brew cask install malwarebytes
    fi
    if [[ ! -d "/Applications/MySQLWorkbench.app" ]]
    then
      brew cask install mysqlworkbench
    fi
    if [[ ! -d "/Applications/Postman.app" ]]
    then
      brew cask install postman
    fi
    if [[ ! -d "/Applications/SourceTree.app" ]]
    then
      brew cask install sourcetree
    fi
    if [[ ! -d "/Applications/Spotify.app" ]]
    then
      brew cask install spotify
    fi
    if [[ ! -d "/Applications/TeamViewer.app" ]]
    then
      brew cask install teamviewer
    fi
    if [[ ! -d "/Applications/Visual Studio Code.app" ]]
    then
      brew cask install visual-studio-code
    fi

    echo "Cleaning up brew"
    brew cleanup

    echo "Updating app store apps via mas"
    mas upgrade

    echo "Installing common apps via mas"
    if [[ ! -d "/Applications/1Password 7.app" ]]
    then
      mas install 1333542190
    fi
    if [[ ! -d "/Applications/Better Rename 9.app" ]]
    then
      mas install 414209656
    fi
    if [[ ! -d "/Applications/Blackmagic Disk Speed Test.app" ]]
    then
      mas install 425264550
    fi
    if [[ ! -d "/Applications/Geekbench 4.app" ]]
    then
      mas install 1175706108
    fi
    if [[ ! -d "/Applications/Evernote.app" ]]
    then
      mas install 406056744
    fi
    if [[ ! -d "/Applications/iMovie.app" ]]
    then
      mas install 408981434
    fi
    if [[ ! -d "/Applications/iNet Network Scanner.app" ]]
    then
      mas install 403304796
    fi
    if [[ ! -d "/Applications/Keynote.app" ]]
    then
      mas install 409183694
    fi
    if [[ ! -d "/Applications/Mactracker.app" ]]
    then
      mas install 430255202
    fi
    if [[ ! -d "/Applications/Microsoft Remote Desktop.app" ]]
    then
      mas install 715768417
    fi
    if [[ ! -d "/Applications/Numbers.app" ]]
    then
      mas install 409203825
    fi
    if [[ ! -d "/Applications/Pages.app" ]]
    then
      mas install 409201541
    fi
    if [[ ! -d "/Applications/Pixelmator.app" ]]
    then
      mas install 407963104
    fi
    if [[ ! -d "/Applications/Read CHM.app" ]]
    then
      mas install 594432954
    fi
    if [[ ! -d "/Applications/Remote Desktop.app" ]]
    then
      mas install 409907375
    fi
    if [[ ! -d "/Applications/Simplenote.app" ]]
    then
      mas install 692867256
    fi
    if [[ ! -d "/Applications/Slack.app" ]]
    then
      mas install 803453959
    fi
    if [[ ! -d "/Applications/Speedtest.app" ]]
    then
      mas install 1153157709
    fi
    if [[ ! -d "/Applications/SQLPro for Postgres.app" ]]
    then
      mas install 1025345625
    fi
    if [[ ! -d "/Applications/The Unarchiver.app" ]]
    then
      mas install 425424353
    fi
    if [[ ! -d "/Applications/Transmit.app" ]]
    then
      mas install 403388562
    fi
    if [[ ! -d "/Applications/Telegram.app" ]]
    then
      mas install 747648890
    fi
    if [[ ! -d "/Applications/Valentina Studio.app" ]]
    then
      mas install 604825918
    fi

    echo "Installing server apps via mas"
    # 883878097 Server
    if [[ ${HOSTNAME} == "mac" ]] || [[ ${HOSTNAME} == "server" ]]
    then
      if [[ ! -d "/Applications/Server.app" ]]
      then
        mas install 883878097
      fi
    fi

    echo "setup ruby 2.3.5"
    if [[ ! -d ${HOME}/.rubies/ruby-2.3.5/bin ]]
    then
      ruby-install ruby 2.3.5
    fi

    # setup for test-kitchen and ruby-2.3.5 for fullscript
    echo "Setup kitchen"
    source /usr/local/opt/chruby/share/chruby/chruby.sh
    source /usr/local/opt/chruby/share/chruby/auto.sh
    chruby ruby-2.3.5
    gem install test-kitchen
    gem install kitchen-ansible
    gem install kitchen-docker
    gem install kitchen-verifier-serverspec

    echo "Creating ${RANCHERSSH}"
    if [[ ! -d ${RANCHERSSH} ]]
    then
      mkdir ${RANCHERSSH}
    fi
  fi

  if [ ${LINUX} ]
  then
    sudo -H apt-get update
    sudo -H apt-get install zsh -y
    sudo -H apt-get install zsh-doc -y
    sudo -H apt-get install git -y
    sudo -H apt-get install gcc -y
    sudo -H apt-get install htop -y
    sudo -H apt-get install iotop -y
    sudo -H apt-get install keychain -y
    sudo -H apt-get install make -y
    sudo -H apt-get install python-setuptools -y
    sudo -H apt-get install npm -y
      # install go 1.10
    sudo add-apt-repository ppa:gophers/archive
    sudo apt-get update
    sudo apt-get install golang-1.10-go -y
    # on KUBE systems:
    if [ ${KUBE} ]
    then
      # install for bonded links
      sudo -H apt-get install ifenslave bridge-utils -y
      # for docker setup for rancher kubernetes setup
      sudo -H apt-get install apt-transport-https -y
      sudo -H apt-get install ca-certificates -y
      sudo -H apt-get install curl -y
      sudo -H apt-get install software-properties-common -y
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo -H apt-key add -
      sudo -H add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"
      sudo -H apt-get update
      sudo -H apt-get install docker-ce=17.03.2~ce-0~ubuntu-xenial -y
      sudo -H apt-mark hold docker-ce
    fi
  fi

  echo "Installing pip"
  sudo -H easy_install pip

  echo "Installing virtualenv for python"
  sudo -H pip install virtualenv virtualenvwrapper

  # setup virtualenv for python if virtualenv there
  if ! [ -d ${HOME}/.virtualenvs ]
  then
    mkdir ${HOME}/.virtualenvs
  fi

  cd ${HOME}/.virtualenvs
  source /usr/local/bin/virtualenvwrapper.sh

  if ! [[ -f ${HOME}/.virtualenvs/ansible ]]
  then
    if [[ -f /usr/local/bin/virtualenv ]]
    then
      mkvirtualenv ansible -p python3
      # mkvirtualenv ansible
    fi
  fi

  echo "Installing ansible via pip"
  pip3 install ansible

  echo "Installing boto via pip"
  pip3 install boto boto3 botocore

  # override boto provided endpoints with a more correct version that has all of the regions
  if [[ -f ${HOME}/git-repos/fullscript/aws-terraform ]]
  then
    if [[ -f ${HOME}/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json ]]
    then
      mv ${HOME}/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json ${HOME}/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json.orig
      ln -s ${HOME}/git-repos/fullscript/aws-terraform/docker/ansible/boto.json ${HOME}/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json
    fi
  fi

  echo "Installing awscli via pip"
  pip3 install awscli

  echo "Installing json2yaml via npm"
  npm install json2yaml
fi

# update is run more often to keep the device up to date with patches
if [[ ${UPDATE} ]]
then
  if [[ ${MACOS} ]]
  then
    echo "Updating homebrew..."
    brew update
    echo "Upgrading brew's"
    brew upgrade
    echo "Upgrading brew casks"
    brew cask upgrade
    echo "Cleaning up brew"
    brew cleanup
    echo "Updating app store apps via mas"
    mas upgrade
  fi
  if [[ ${LINUX} ]]
  then
    sudo -H apt-get update
    sudo -H apt-get dist-upgrade -y
  fi
  if [[ ${WINDOWS} ]]
  then
    if [[ ! -e "$VSCODE"/settings.json ]]
    then
      cp -a ${WSL_HOME}/git-repos/personal/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
    else
      rm "$VSCODE"/settings.json
      cp -a ${WSL_HOME}/git-repos/personal/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
    fi
  fi
fi

source ${HOME}/.zshrc

exit 0
