# aliases for home
alias prox-0='tsh ssh root@prox-0'
alias prox-1='tsh ssh root@prox-1'
alias prox-2='tsh ssh root@prox-2'

# aliases for work servers

# command aliases
alias au='sudo apt-get update'
alias ad='sudo apt-get dist-upgrade -y'
alias aa='sudo apt-get autoremove -y'
alias dot='cd ~/git-repos/personal/dotfiles && git pl && source ~/.zshrc'
alias update='cd ~/git-repos/personal/dotfiles && git co master && git pl && ./setup_env.sh -t update'
alias zu='cd ~/git-repos/z && git pl'
alias oh='cd ~/.oh-my-zsh && git pl'
alias tp='terraform plan -out terraform-plan'
alias ta='terraform apply "terraform-plan"'
alias tiu='terraform init --upgrade'
alias ti='terraform init'
alias tv='terraform validate'
alias td='terraform destroy'
alias make='Make'
alias m='Make'
alias mp='make plan'
alias ma='make apply'
alias mi='make init'
alias tw='~/scripts/tmux-workstation.sh'
alias kgp='kubectl get pods --all-namespaces'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deploy'
alias kgr='kubectl get rs'
alias kgs='kubectl get services --all-namespaces'
alias kcv='kubectl config view'
alias kcc='kubectl config current-context'
alias kcu='kubectl config use-context $@'
alias lzd='lazydocker'
alias tlogin='tsh login --proxy=teleport.home.conecrazy.ca --user=teleport-admin --insecure'
alias talogin='export ANSIBLE_SSH_ARGS="-F ${HOME}/.ssh/teleport.cfg" && export ANSIBLE_SCP_IF_SSH=False && export ANSIBLE_HOST_KEY_CHECKING=False && tsh login --proxy=teleport.home.conecrazy.ca --user=teleport-admin --insecure'
alias tlogout='tsh logout'
alias tstatus='tsh status'
alias tlist='tsh ls'
# tssh and sh are functions defined above
alias ts='tssh $@'
alias ss='sh $@'
alias ssu='sshu $@'

if quiet_which z
then
  alias cd="z"
  alias zz="z -"
fi

if quiet_which nvim
then
  alias vim="nvim"
fi

if quiet_which bat
then
  alias cat="bat"
elif quiet_which batcat
then
  alias cat="batcat"
fi

# alias for ls to exa removed due to breaking globbing for ansible aws integration
if quiet_which exa
then
  alias gs="exa -lg --git"
  alias tree="exa --tree"
  alias ll="ls -la"
  alias ls="ls -l"
else
  alias ll="ls -la"
  alias ls="ls -l"
fi

# for aws info at the cli
# add a "--region xxx" to change regions
alias idesc="aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Placement.AvailabilityZone, State.Name, InstanceId,InstanceType,Tags]' --output text"
