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
  if [ -z "$1" ]; then
    echo "No environment supplied"
  else
    if findStringInFile ~/.aws/config $1; then
      export AWS_PROFILE=${1}
      aws sts get-caller-identity --profile ${1} | grep "Arn: arn:aws:sts::" &> /dev/null
      if [ $? -eq 0 ]; then
        echo "AWS command line environment set to [${1}]"
      else
        if [ -t 1 ] ; then
          # is tty session
          echo "Found that this is an interactive terminal, will run the sso login"
          aws sso login
          if [ "$?" -ne 0 ]; then
            echo "You didnt login, exiting!"
            exit 1;
          else
            echo "AWS command line environment set to [${1}]"
          fi
        else
          # is cron
          echo "Not in a tty, gracefully exiting due to no active SSO login. Check that your logged in via SSO, or have perms via IAM already setup";
          exit 1;
        fi
      fi
    else
      echo "AWS profile [${1}] not found."
      echo "Please choose from an existing profile:"
      grep "\[profile" ~/.aws/config
      echo "Or create a new one."
    fi
  fi
}
