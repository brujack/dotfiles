#!/usr/bin/env zsh

# setup some functions
quiet_which() {
  which "$1" &>/dev/null
}

export AWS_HOME=${HOME}/.aws

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }
[ $# -eq 0 ] &&usage

# get command line options
while getopts ":ha:" arg; do
  case $arg in
    a) # Specify a of either 'home', 'leonovus'.
      [ ${OPTARG} = "home" ] && export AWS_CREDS_HOME=1
      [ ${OPTARG} = "leonovus" ] && export AWS_CREDS_LEONOVUS=1
      ;;
    h | *) # Display help.
      usage
      exit 0
      ;;
  esac
done

echo "home is ${AWS_CREDS_HOME}"
echo "leonovus is ${AWS_CREDS_LEONOVUS}"

if [[ ${AWS_CREDS_HOME} ]]
then
  if [[ -f ${AWS_HOME}/.aws_creds_home ]]
  then
    #export TF_VAR_aws_access_key=""
    #export TF_VAR_aws_secret_key=""
    source ${AWS_HOME}/.aws_creds_home
    echo "Set aws creds to home"
    echo ${TF_VAR_aws_access_key}
    echo ${TF_VAR_aws_secret_key}
    #export TF_VAR_aws_access_key
    #export TF_VAR_aws_secret_key
  fi
fi

if [[ ${AWS_CREDS_LEONOVUS} ]]
then
  if [[ -f ${AWS_HOME}/.aws_creds_leonovus ]]
  then
    #export TF_VAR_aws_access_key=""
    #export TF_VAR_aws_secret_key=""
    source ${AWS_HOME}/.aws_creds_leonovus
    echo "Set aws creds to leonovus"
    echo ${TF_VAR_aws_access_key}
    echo ${TF_VAR_aws_secret_key}
    #export TF_VAR_aws_access_key
    #export TF_VAR_aws_secret_key
  fi
fi
