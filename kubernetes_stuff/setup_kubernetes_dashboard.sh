#!/bin/bash

# A script to setup kubernetes dashboard after docker edge edition has been installed on macos
# Install docker edge edition from:  https://download.docker.com/mac/edge/Docker.dmg
# You will need to enable Kubernetes, by opening "Preferences/Kubernetes" and clicking on the "Enable Kubernetes"

# check if kubectl is installed
if ! [[ -x "$(command -v kubectl)" ]]; then
  echo 'Error: kubectl is not installed.' >&2
  exit 1
fi

# check if kubernetes is running


# configure a local kubernetes context
kubectl config current-context

# check if
