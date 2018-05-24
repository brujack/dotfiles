#!/bin/bash

# choose which env we are running on
[ $(uname -s) = "Darwin" ] && export MACOS=1
[ $(uname -s) = "Linux" ] && export LINUX=1

# locations of directories
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
DOTFILES="dotfiles"
RANCHERSSH="${HOME}/.rancherssh"
BREWFILE_LOC="${HOME}/brew"
HOSTNAME=$(hostname -s)

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

# get hostname
HOSTNAME=`hostname -s`

# setup variables based off of environment
if [[ ${MACOS} ]]
then
  VSCODE="${HOME}/Library/Application Support/Code/User"
elif [[ ${LINUX} ]]
then
  VSCODE="${HOME}/.config/Code/User"
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
if [[ -e ${HOME}/.zshrc ]]
then
  rm ${HOME}/.zshrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
fi
if [[ -e ${HOME}/.gitconfig ]]
then
  rm ${HOME}/.gitconfig
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig ${HOME}/.gitconfig
fi
if [[ -e ${HOME}/.vimrc ]]
then
  rm ${HOME}/.vimrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
fi
if [[ ${MACOS} ]]
then
  if [[ -e "$VSCODE"/settings.json ]]
  then
    rm "$VSCODE"/settings.json
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/vscode-settings.json "$VSCODE"/settings.json
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
  if [[ ! -d "/Applications/Carbon Copy Cloner.app" ]]
  then
    brew cask install carbon-copy-cloner
  fi
  if [[ ! -d "/Applications/Dropbox.app" ]]
  then
    brew cask install dropbox
  fi
  if [[ ! -d "/Applications/Google Chrome.app" ]]
  then
    brew cask install google-chrome
  fi
  if [[ ! -d "/Applications/Malwarebytes.app" ]]
  then
    brew cask install malwarebytes
  fi
  if [[ ! -d "/Applications/MySQLWorkbench.app" ]]
  then
    brew cask install mysqlworkbench
  fi
  if [[ ! -d "/Applications/SourceTree.app" ]]
  then
    brew cask install sourcetree
  fi
  if [[ ! -d "/Applications/SourceTree.app" ]]
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

  echo "Installing common apps via mas"
  # This is the key values of the mas id to a commom name:
  # 443987910 1Password
  # 414209656 Better Rename 9
  # 425264550 Blackmagic Disk Speed Test
  # 1175706108 Geekbench 4
  # 406056744 Evernote
  # 408981434 iMovie
  # 403304796 iNet Network Scanner
  # 409183694 Keynote
  # 430255202 Mactracker
  # 715768417 Microsoft Remote Desktop
  # 409203825 Numbers
  # 409201541 Pages
  # 407963104 Pixelmator
  # 594432954 Read CHM
  # 409907375 Remote Desktop
  # 692867256 Simplenote
  # 803453959 Slack
  # 1153157709 Speedtest
  # 1025345625 SQLPro for Postgres
  # 425424353 The Unarchiver
  # 403388562 Transmit
  # 747648890 Telegram
  # 604825918 Valentina Studio
  # 497799835 Xcode

  mas install 443987910
  mas install 414209656
  mas install 425264550
  mas install 1175706108
  mas install 406056744
  mas install 408981434
  mas install 403304796
  mas install 409183694
  mas install 430255202
  mas install 715768417
  mas install 409203825
  mas install 409201541
  mas install 407963104
  mas install 594432954
  mas install 409907375
  mas install 692867256
  mas install 803453959
  mas install 1153157709
  mas install 1025345625
  mas install 425424353
  mas install 403388562
  mas install 747648890
  mas install 604825918

  echo "Installing server apps via mas"
  # 883878097 Server
  if [[ ${HOSTNAME} == "mac" ]] || [[ $HOSTNAME == "server" ]]
  then
    mas install 883878097
  fi

  echo "Updating app store apps via mas"
  mas upgrade

  echo "setup ruby 2.3.5"
  if [[ ! -d ~/.rubies/ruby-2.3.5/bin ]]
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
  sudo -H apt-get install docker.io -y
  sudo -H apt-get install gcc -y
  sudo -H apt-get install htop -y
  sudo -H apt-get install iotop -y
  sudo -H apt-get install keychain -y
  sudo -H apt-get install make -y
  sudo -H apt-get install python-setuptools -y
  sudo -H apt-get install zsh -y
  # install go 1.10
  sudo add-apt-repository ppa:gophers/archive
  sudo apt-get update
  sudo apt-get install golang-1.10-go
fi

echo "Installing pip"
sudo -H easy_install pip

echo "Installing virtualenv for python"
sudo -H pip install virtualenv virtualenvwrapper

# setup virtualenv for python if virtualenv there
if ! [ -d ~/.virtualenvs ]
then
  mkdir ${HOME}/.virtualenvs
fi

cd ~/.virtualenvs
source /usr/local/bin/virtualenvwrapper.sh

if ! [[ -f ~/.virtualenvs/ansible ]]
then
  if [[ -f /usr/local/bin/virtualenv ]]
  then
    mkvirtualenv ansible -p python3
    # mkvirtualenv ansible
  fi
fi

echo "Installing ansible via pip"
# pip install ansible
pip3 install ansible

echo "Installing boto via pip"
# pip install boto boto3 botocore
pip3 install boto boto3 botocore

# override boto provided endpoints with a more correct version that has all of the regions
if [[ -f ~/git-repos/fullscript/aws-terraform ]]
then
  if [[ -f ~/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json ]]
  then
    mv ~/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json ~/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json.orig
    ln -s ~/git-repos/fullscript/aws-terraform/docker/ansible/boto.json ~/.virtualenvs/ansible/lib/python3.6/site-packages/boto/endpoints.json
  fi
fi

echo "Installing awscli via pip"
pip3 install awscli

echo "Installing json2yaml via npm"
npm install json2yaml

source ~/.zshrc

exit 0
