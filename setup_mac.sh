#!/bin/bash

# locations of directories
GITREPOS="$HOME/git-repos"
PERSONAL_GITREPOS="$GITREPOS/personal"
DOTFILES="dotfiles"
RANCHERSSH="~/.rancherssh"

# Xcode mas id 497799835
mas install 497799835
echo "Installing xcode-stuff"
xcode-select --install

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

# check hostname
HOSTNAME=`hostname -s`

# Check for Homebrew,
# Install if we don't have it
if test ! $(which brew); then
  echo "Installing homebrew..."
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Update homebrew recipes
echo "Updating homebrew..."
brew update

echo "Upgrading homebrew"
brew upgrade

echo "Installing other brew stuff..."

brew install chruby
brew install exa
brew install fd
brew install git
brew install glide
brew install go
brew install htop
brew install node
brew install rancher-cli
brew install fangli/dev/rancherssh
brew install mas
brew install openssl
brew install ruby-install
brew install the_silver_searcher
brew install tree
brew install vim
brew install wget
brew install zsh

echo "Cleaning up brew"
brew cleanup

echo "Installing homebrew cask"
brew tap caskroom/cask

echo "Installing common apps via mas"


# 443987910 1Password
# 414209656 Better Rename 9
# 425264550 Blackmagic Disk Speed Test
# 406056744 Evernote
# 682658836 GarageBand
# 1175706108 Geekbench 4
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
# 425424353 The Unarchiver
# 403388562 Transmit
# 747648890 Telegram
# 497799835 Xcode

mas install 443987910
mas install 414209656
mas install 425264550
mas install 406056744
mas install 682658836
mas install 1175706108
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
mas install 425424353
mas install 403388562
mas install 747648890

echo "Installing server apps via mas"
# 883878097 Server
if [[ $HOSTNAME == "mac" ]] || [[ $HOSTNAME == "server" ]]
then
  mas install 883878097
fi

echo "Installing developer apps via mas"
# 1025345625 SQLPro for Postgres
# 604825918 Valentina Studio
if [[ $HOSTNAME == "ratna" ]] || [[ $HOSTNAME == "Bruces-MacBook-Pro" ]] || [[ $HOSTNAME == "Bruces-MacBook-Air" ]]
then
  mas install 1025345625
  mas install 604825918
fi

echo "Updating app store apps via mas"
mas upgrade

echo "Installing apps via cask"
if [[ ! -d /Applications/Alfred\ 3.app ]]
then
  brew cask install alfred
fi

if [[ ! -d /Applications/Atom.app ]]
then
  brew cask install atom
fi

if [[ ! -d /Applications/DaisyDisk.app ]]
then
  brew cask install daisydisk
fi

if [[ ! -d /Applications/Dropbox.app ]]
then
  brew cask install dropbox
fi

if [[ ! -d /Applications/Google\ Chrome.app ]]
then
  brew cask install google-chrome
fi

if [[ ! -d /Applications/MySQLWorkbench.app ]]
then
  brew cask install mysqlworkbench
fi

if [[ ! -d /Applications/SourceTree.app ]]
then
  brew cask install sourcetree
fi

if [[ ! -d /Applications/SourceTree.app ]]
then
  brew cask install sourcetree
fi

if [[ ! -d /Applications/Spotify.app ]]
then
  brew cask install spotify
fi

if [[ ! -d /Applications/TeamViewer.app ]]
then
  brew cask install teamviewer
fi

if [[ ! -d /Applications/Telegram.app ]]
then
  brew cask install telegram
fi

echo "Installing pip"
sudo -H easy_install pip

echo "Installing ansible via pip"
# pip install ansible
sudo -H pip install ansible

echo "Installing boto via pip"
# pip install boto boto3 botocore
sudo -H pip install boto boto3 botocore --ignore-installed six

echo "Installing awscli via pip"
sudo -H pip install awscli

echo "Installing json2yaml via npm"
npm install json2yaml

echo "Installing Oh My ZSH..."
if [[ ! -d "$HOME"/.oh-my-zsh ]]
then
  sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
fi

echo "Creating $GITREPOS"
if [[ ! -d "$GITREPOS" ]]
then
  mkdir "$GITREPOS"
fi

echo "Creating $PERSONAL_GITREPOS"
if [[ ! -d "$PERSONAL_GITREPOS" ]]
then
  mkdir "$PERSONAL_GITREPOS"
fi

echo "Copying $DOTFILES from Github"
if [[ ! -d "$PERSONAL_GITREPOS"/"$DOTFILES" ]]
then
  cd "$HOME"
  git clone --recursive git@github.com:brujack/"$DOTFILES".git "$PERSONAL_GITREPOS"/"$DOTFILES"
else
  cd "$PERSONAL_GITREPOS"/"$DOTFILES"
  git pull
fi

echo "Downloading git-prompt via full git repo"
if [[ ! -d "$PERSONAL_GITREPOS"/git ]]
then
  cd "$HOME"
  git clone --recursive https://github.com/git/git.git "$PERSONAL_GITREPOS"/git
else
  cd "$PERSONAL_GITREPOS"/git
  git pull
fi

echo "Creating link for git-prompt"
if [[ ! -L "$HOME"/.bash_git && -d "$HOME"/.bash_git ]]
then
  ln -s "$PERSONAL_GITREPOS"/git/contrib/completion/git-prompt.sh "$HOME"/.bash_git
else
  rm "$HOME/.bash_git"
  ln -s "$PERSONAL_GITREPOS"/git/contrib/completion/git-prompt.sh "$HOME"/.bash_git
fi

echo "Linking $DOTFILES to their home"
if [[ ! -L "$HOME"/.bash_profile && -d "$HOME"/.bash_profile ]]
then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.bash_profile "$HOME"/.bash_profile
else
  rm "$HOME"/.bash_profile
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.bash_profile "$HOME"/.bash_profile
fi
if [[ ! -L "$HOME"/.zshrc && -d "$HOME"/.zshrc ]]
then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.zshrc "$HOME"/.zshrc
else
  rm "$HOME"/.zshrc
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.zshrc "$HOME"/.zshrc
fi

if [[ ! -L "$HOME"/.oh-my-zsh/themes/bruce.zsh-theme && -d "$HOME"/.oh-my-zsh/themes/bruce.zsh-theme ]]
then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/bruce.zsh-theme "$HOME"/.oh-my-zsh/themes/bruce.zsh-theme
else
  rm "$HOME"/.oh-my-zsh/themes/bruce.zsh-theme
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/bruce.zsh-theme "$HOME"/.oh-my-zsh/themes/bruce.zsh-theme
fi
if [[ ! -L "$HOME"/.ssh/config && -d "$HOME"/.ssh/config ]]
then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.ssh/config "$HOME"/.ssh/config
else
  rm "$HOME"/.ssh/config
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.ssh/config "$HOME"/.ssh/config
fi

echo "Setting ZSH as shell..."
if [[ ! $SHELL = "/bin/zsh" ]]
then
  chsh -s /bin/zsh
fi

echo "Downloading keychain"
if [[ ! -f "$HOME"/Downloads/keychain-2.8.3.tar.bz2 ]]
then
  wget -O "$HOME"/Downloads/keychain-2.8.3.tar.bz2 http://www.funtoo.org/distfiles/keychain/keychain-2.8.3.tar.bz2
fi

echo "Deploying keychain"
if [[ ! -d "$HOME"/Downloads/keychain-2.8.3 ]]
then
  if [[ ! -f "$HOME"/Downloads/keychain-2.8.3.tar ]]
  then
    bunzip2 "$HOME"/Downloads/keychain-2.8.3.tar.bz2
  fi
  if [[ ! -d "$HOME"/keychain-2.8.3 ]]
  then
    cd "$HOME"
    tar xvf "$HOME"/Downloads/keychain-2.8.3.tar
  fi
fi

if [[ ! -L "$HOME"/keychain && -d "$HOME"/keychain ]]
then
  ln -s "$HOME"/keychain-2.8.3 "$HOME"/keychain
elif [[ -d "$HOME"/keychain ]]
then
  rm -rf "$HOME"/keychain
  ln -s "$HOME"/keychain-2.8.3 "$HOME"/keychain
else
  rm -f "$HOME"/keychain
  ln -s "$HOME"/keychain-2.8.3 "$HOME"/keychain
fi

echo "Creating $RANCHERSSH"
if [[ ! -d "$RANCHERSSH" ]]
then
  mkdir "$RANCHERSSH"
fi

exit 0
