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

echo "Installing ansible via pip"
pip install ansible

echo "Installing boto via pip"
pip install boto

echo "Installing Oh My ZSH..."
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

echo "Creating ~/git-repos
if [ ! ~/git-repos ]; then
  mkdir ~/git-repos
fi

echo "Creating ~/git-repos/personal
if [ ! ~/git-repos/personal ]; then
  mkdir ~/git-repos/personal
fi

echo "Downloading git-prompt via full git repo"
cd ~
git clone --recursive https://github.com/git/git.git ~/git-repos/personal/git

echo "Copying dotfiles from Github"
cd ~
git clone --recursive git@github.com:brujack/dotfiles.git ~/git-repos/personal/dotfiles

#echo "creating link for git-prompt
ln -s ~/git-repos/personal/git/contrib/completion/git-prompt.sh ~/.bash_git

echo "Linking dotfiles to their home"
ln -s ~/git-repos/personal/dotfiles/.bash_profile ~/.bash_profile
ln -s ~/git-repos/personal/dotfiles/.zshrc ~/.zshrc
ln -s ~/git-repos/personal/dotfiles/bruce.zsh-theme ~/.oh-my-zsh/themes/bruce.zsh-theme

echo "Setting ZSH as shell..."
chsh -s /bin/zsh

echo "Downloading keychain"
wget http://www.funtoo.org/distfiles/keychain/keychain-2.8.3.tar.bz2 ~/Downloads/keychain-2.8.3.tar.bz2
