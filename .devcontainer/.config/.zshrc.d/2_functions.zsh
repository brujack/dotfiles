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
      if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]]; then
        alias make='/opt/homebrew/bin/gmake'
      fi
    fi
    make "$@"
  fi
}

function quiet_which() {
  if [ $# -eq 0 ]; then
    echo "Usage: quiet_which <command> [command...]"
    return 1
  fi

  for cmd in "$@"; do
    if ! which "$cmd" &>/dev/null; then
      return 1
    fi
  done
}

# rancherssh will do fuzzy find for your query between %%
# rssh container-keyword
function rssh () {
  cd ${HOME}/.rancherssh || return
  rancherssh %"$1"%
  cd ${HOME} || return
}

function tssh() {
  if [ $# -eq 0 ]; then
    echo "No arguments supplied. Please provide the hostname/ip to ssh to"
    return 1
  fi
  tsh ssh bruce@$1
}

function sh() {
  if [ $# -eq 0 ]; then
    echo "No arguments supplied. Please provide the hostname/ip to ssh to"
    return 1
  fi
  ssh bruce@$1
}

function sshu() {
  if [ $# -eq 0 ]; then
    echo "No arguments supplied. Please provide the hostname/ip to ssh to"
    return 1
  fi
  ssh ubuntu@$1
}

search_pkg() {
  if [ $# -eq 0 ]; then
    echo "No arguments supplied. Please provide the package to search for"
    return 1
  fi
  dpkg -l | grep "$1"
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
  if [ $# -eq 0 ]; then
    echo "No arguments supplied. Please provide the AWS profile name."
    return 1
  fi

  local profile=$1

  # Check if in a TTY environment
  if ! tty -s; then
    echo "This function must be run in a TTY environment."
    return 1
  fi

  # Check if profile exists
  if ! aws configure list-profiles | grep -q ${profile}; then
    echo "The specified profile [${profile}] does not exist."
    return 1
  fi

  # Check if profile is "bruce" and set AWS_PROFILE if so
  if [ $profile = "bruce" ]; then
    echo "Setting AWS_PROFILE to [${profile}]"
    export AWS_PROFILE=bruce
    return 0
  fi

  # Check if already logged in
  if aws sts get-caller-identity --profile ${profile} &> /dev/null; then
    echo "Already logged in to AWS SSO with profile [${profile}]"
    export AWS_PROFILE=${profile}
  else
    echo "Logging in to AWS SSO with profile [${profile}]"
    aws sso login --profile ${profile}
    export AWS_PROFILE=${profile}
  fi
}

function mkill() {
  if [ $# -eq 0 ]; then
    echo "Please provide the name of the process to kill as an argument."
    exit 1
  fi

  process_name="$1"
  process_name_lowercase=$(echo "$process_name" | tr '[:upper:]' '[:lower:]')

  if pgrep -ix "$process_name_lowercase" > /dev/null; then
    pkill -ix "$process_name_lowercase"
    echo "Process '$process_name' has been killed."
  else
    echo "Process '$process_name' is not running."
  fi
}
