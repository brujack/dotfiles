#!/bin/bash

# locations of directories
GITREPOS="$HOME/git-repos"
PERSONAL_GITREPOS="$GITREPOS/personal"
DOTFILES="dotfiles"

echo "Installing xcode-stuff"
xcode-select --install

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
brew install tree
brew install wget
brew install htop-osx
brew install the_silver_searcher
#brew install ansible
brew install zsh
brew install vim
brew install thefuck
brew install chruby
brew install ruby-install

echo "Cleaning up brew"
brew cleanup

echo "Installing homebrew cask"
brew tap caskroom/cask

echo "Installing ansible via pip"
pip install ansible
# sudo -H pip install ansible

echo "Installing boto via pip"
pip install boto boto3 botocore
# sudo -H pip install boto boto3 botocore --ignore-installed six

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

exit 0
