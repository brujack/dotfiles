!/bin/bash

# locations of directories
GITREPOS="~/git-repos"
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
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

echo "Creating $GITREPOS"
if [ ! -d "$GITREPOS" ]; then
  mkdir "$GITREPOS"
fi

echo "Creating $PERSONAL_GITREPOS"
if [ ! -d "$PERSONAL_GITREPOS" ]; then
  mkdir "$PERSONAL_GITREPOS"
fi

echo "Copying $DOTFILES from Github"
if [ ! -d "$PERSONAL_GITREPOS"/"$DOTFILES" ]; then
  cd ~
  git clone --recursive git@github.com:brujack/"$DOTFILES".git "$PERSONAL_GITREPOS"/"$DOTFILES"
else
  cd "$PERSONAL_GITREPOS"/"$DOTFILES"
  git pull
fi

echo "Downloading git-prompt via full git repo"
if [ ! -d "$PERSONAL_GITREPOS"/git ]; then
  cd ~
  git clone --recursive https://github.com/git/git.git "$PERSONAL_GITREPOS"/git
else
  cd "$PERSONAL_GITREPOS"/git
  git pull
fi

echo "creating link for git-prompt"   -L "$file" && -d "$file"
if [ ! -L ~/.bash_git && -d  ~/.bash_git ]; then
  ln -s "$PERSONAL_GITREPOS"/git/contrib/completion/git-prompt.sh ~/.bash_git
else
  rm ~/.bash_git
  ln -s "$PERSONAL_GITREPOS"/git/contrib/completion/git-prompt.sh ~/.bash_git
fi

echo "Linking $DOTFILES to their home"
if [ ! -L ~/.bash_profile && -d ~/.bash_profile ]; then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.bash_profile ~/.bash_profile
else
  rm ~/.bash_profile
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.bash_profile ~/.bash_profile
fi
if [ ! -L ~/.zshrc && -d ~/.zshrc ]; then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.zshrc ~/.zshrc
else
  rm ~/.zshrc
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.zshrc ~/.zshrc
fi
if [ ! -L ~/.oh-my-zsh/themes/bruce.zsh-theme && -d ~/.oh-my-zsh/themes/bruce.zsh-theme ]; then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/bruce.zsh-theme ~/.oh-my-zsh/themes/bruce.zsh-theme
else
  rm ~/.oh-my-zsh/themes/bruce.zsh-theme
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/bruce.zsh-theme ~/.oh-my-zsh/themes/bruce.zsh-theme
if [ ! -L ~/.ssh/config && -d ~/.ssh/config ]; then
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.ssh/config ~/.ssh/config
else
  rm ~/.ssh/config
  ln -s "$PERSONAL_GITREPOS"/"$DOTFILES"/.ssh/config ~/.ssh/config
fi

echo "Setting ZSH as shell..."
chsh -s /bin/zsh

echo "Downloading keychain"
wget -O ~/Downloads/keychain-2.8.3.tar.bz2 http://www.funtoo.org/distfiles/keychain/keychain-2.8.3.tar.bz2

echo "Deploying keychain"
bunzip2 ~/Downloads/keychain-2.8.3.tar.bz2
cd ~
tar xvf ~/Downloads/keychain-2.8.3.tar
if [ ! -L ~/keychain && -d ~/keychain ]; then
  ln -s ~/keychain-2.8.3 ~/keychain
else
  rm -f ~/keychain
  ln -s ~/keychain-2.8.3 ~/keychain
fi
