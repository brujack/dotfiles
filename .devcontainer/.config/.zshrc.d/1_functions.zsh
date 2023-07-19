function Make() {
  if [ -f Taskfile.yml ]; then
    task "$@"
  elif [ -f Taskfile.yaml ]; then
    task "$@"
  else
    if [[ ${MACOS} ]]; then
      if [[ ${RATNA} ]]; then
        alias make='/usr/local/bin/gmake'
      fi
      if [[ ${LAPTOP} ]] || [[ ${BRUCEWORK} ]] || [[ ${STUDIO} ]]; then
        alias make='/opt/homebrew/bin/gmake'
      fi
    fi
    make "$@"
  fi
}

function quiet_which() {
  which "$1" &>/dev/null
}

# rancherssh will do fuzzy find for your query between %%
# rssh container-keyword
function rssh () {
  cd ${HOME}/.rancherssh || return
  rancherssh %"$1"%
  cd ${HOME} || return
}

function tssh() {
  tsh ssh bruce@$1
}

function sh() {
  ssh bruce@$1
}

function sshb() {
  ssh build@$1
}

function sshu() {
  ssh build@$1
}

# show .oh_my_zsh plugins and their shortcuts
function options() {
  PLUGIN_PATH="$HOME/.oh-my-zsh/plugins/"
  for plugin in $plugins; do
    echo "\n\nPlugin: $plugin"; grep -r "^function \w*" $PLUGIN_PATH$plugin | awk '{print $2}' | sed 's/()//'| tr '\n' ', '; grep -r "^alias" $PLUGIN_PATH$plugin | awk '{print $2}' | sed 's/=.*//' |  tr '\n' ', '
  done
}

function findStringInFile() {
  if [ -z "$1" ]; then
    echo "No file supplied"
  else
    if [ -z "$2" ]; then
      echo "No string supplied"
    else
      if grep -q "$2" $1; then
        echo "Found $2 in $1"
        return 0
      else
        echo "Did not find $2 in $1"
        return 1
      fi
    fi
  fi
}

function awsuse() {
  if [ $# -eq 0 ]
    then
      echo "No arguments supplied. Please provide the AWS profile name."
      return 1
  fi

  local profile=$1

  # Check if in a TTY environment
  if ! tty -s
  then
    echo "This function must be run in a TTY environment."
    return 1
  fi

  # Check if profile exists
  if ! aws configure list-profiles | grep -q ${profile}
  then
    echo "The specified profile [${profile}] does not exist."
    return 1
  fi

  # Check if already logged in
  if aws sts get-caller-identity --profile ${profile} &> /dev/null
  then
    echo "Already logged in to AWS SSO with profile [${profile}]"
  else
    echo "Logging in to AWS SSO with profile [${profile}]"
    aws sso login --profile ${profile}
  fi
}
