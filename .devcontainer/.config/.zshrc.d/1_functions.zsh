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

# show .oh_my_zsh plugins and their shortcuts
function options() {
  PLUGIN_PATH="$HOME/.oh-my-zsh/plugins/"
  for plugin in $plugins; do
    echo "\n\nPlugin: $plugin"; grep -r "^function \w*" $PLUGIN_PATH$plugin | awk '{print $2}' | sed 's/()//'| tr '\n' ', '; grep -r "^alias" $PLUGIN_PATH$plugin | awk '{print $2}' | sed 's/=.*//' |  tr '\n' ', '
  done
}
