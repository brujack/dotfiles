!/bin/bash

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
brew install caskroom/cask/brew-cask

echo "Installing Oh My ZSH..."
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

echo "Copying dotfiles from Github"
cd ~
git clone --recursive git@github.com:brujack/dotfiles.git dotfiles

echo "Linking dotfiles to their home"
ln -s ~/dotfiles/.zshrc ~/.zshrc
ln -s ~/dotfiles/bruce.zsh-theme ~/.oh-my-zsh/themes/bruce.zsh-theme

echo "Setting ZSH as shell..."
chsh -s /bin/zsh

echo "Downloading keychain"
wget http://www.funtoo.org/distfiles/keychain/keychain-2.8.2.tar.bz2 ~/Downloads/keychain-2.8.2.tar.bz2
