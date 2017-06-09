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
brew tap caskroom/cask

echo "Installing ansible via pip"
pip install ansible
# sudo -H pip install ansible

echo "Installing boto via pip"
pip install boto boto3 botocore
# sudo -H pip install boto boto3 botocore --ignore-installed six

echo "Installing Oh My ZSH..."
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

echo "Creating ~/git-repos"
if [ ! ~/git-repos ]; then
  mkdir ~/git-repos
fi

echo "Creating ~/git-repos/personal"
if [ ! ~/git-repos/personal ]; then
  mkdir ~/git-repos/personal
fi

echo "Copying dotfiles from Github"
if [ ! ~/git-repos/personal/dotfiles ]; then
  cd ~
  git clone --recursive git@github.com:brujack/dotfiles.git ~/git-repos/personal/dotfiles
else
  cd ~/git-repos/personal/dotfiles
  git pull
fi

echo "Downloading git-prompt via full git repo"
if [ ! ~/git-repos/personal/git ]; then
  cd ~
  git clone --recursive https://github.com/git/git.git ~/git-repos/personal/git
else
  cd ~/git-repos/personal/git
  git pull
fi

echo "creating link for git-prompt"
if [ ! ~/.bash_git ]; then
  ln -s ~/git-repos/personal/git/contrib/completion/git-prompt.sh ~/.bash_git
else
  rm ~/.bash_git
  ln -s ~/git-repos/personal/git/contrib/completion/git-prompt.sh ~/.bash_git
fi

echo "Linking dotfiles to their home"
if [ ! ~/.bash_profile ]; then
  ln -s ~/git-repos/personal/dotfiles/.bash_profile ~/.bash_profile
else
  rm ~/.bash_profile
  ln -s ~/git-repos/personal/dotfiles/.bash_profile ~/.bash_profile
fi
if [ ! ~/.zshrc ]; then
  ln -s ~/git-repos/personal/dotfiles/.zshrc ~/.zshrc
else
  rm ~/.zshrc
  ln -s ~/git-repos/personal/dotfiles/.zshrc ~/.zshrc
fi
if [ ! ~/.oh-my-zsh/themes/bruce.zsh-theme ]; then
  ln -s ~/git-repos/personal/dotfiles/bruce.zsh-theme ~/.oh-my-zsh/themes/bruce.zsh-theme
else
  rm ~/.oh-my-zsh/themes/bruce.zsh-theme
  ln -s ~/git-repos/personal/dotfiles/bruce.zsh-theme ~/.oh-my-zsh/themes/bruce.zsh-theme
if [ ! ~/.ssh/config ]; then
  ln -s ~/git-repos/personal/dotfiles/.ssh/config ~/.ssh/config
else
  rm ~/.ssh/config
  ln -s ~/git-repos/personal/dotfiles/.ssh/config ~/.ssh/config
fi

echo "Setting ZSH as shell..."
chsh -s /bin/zsh

echo "Downloading keychain"
wget -O ~/Downloads/keychain-2.8.3.tar.bz2 http://www.funtoo.org/distfiles/keychain/keychain-2.8.3.tar.bz2

echo "Deploying keychain"
bunzip2 ~/Downloads/keychain-2.8.3.tar.bz2
cd ~
tar xvf ~/Downloads/keychain-2.8.3.tar
if [ ! ~/keychain ]; then
  ln -s ~/keychain-2.8.3 ~/keychain
else
  rm -f ~/keychain
  ln -s ~/keychain-2.8.3 ~/keychain
fi
