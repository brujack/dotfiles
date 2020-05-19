#!/bin/bash
# There are 2 scripts to building a running kubernetes environment, this one and 'initialize_kubernetes_ubuntu.sh'
# 'install_kubernetes_ubuntu.sh' is run first to install all of the components necessary to run kubernetes
# 'initialize_kubernetes_ubuntu.sh' is run second to initialize a kubernetes master


set -e

GITREPOS="${HOME}/git-repos"

mkdir -p ${GITREPOS}

sudo -H apt-get update
sudo -H apt-get dist-upgrade -y
sudo -H apt-get install apt-transport-https ca-certificates curl software-properties-common -y
sudo -H apt-get autoremove -y

sudo -H apt-get install docker-ce -y

sudo -H bash -c 'cat << EOF > /etc/docker/daemon.json
{
   "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF'

# install kubernetes
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

sudo -H bash -c 'cat << EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF'

sudo -H apt-get update
sudo -H apt-get install -y kubelet kubeadm kubectl

# install latest version of go via snap
#sudo -H snap install --classic go
# changed to regular go
sudo -H add-apt-repository ppa:gophers/archive
sudo -H apt-get update
sudo -H apt-get install golang-1.14-go -y

# disable swap as kubernetes expects it to be off
sudo -H sed -i '/ swap / s/^/#/' /etc/fstab
sudo -H swapoff -a

# install crictl from go
sudo -H apt update
sudo -H apt-get install gcc -y
go get github.com/kubernetes-incubator/cri-tools/cmd/crictl

# fix the kubelet startup script to use the correct cgroup driver that matches what docker uses
KUBELET_CGROUP_ARGS=$(sudo -H docker info | grep -i cgroup | awk -F ':' '{print $2}' | sed -e 's/^[[:space:]]*//')
TEE_OUTPUT="Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=${KUBELET_CGROUP_ARGS}""
echo ${TEE_OUTPUT} | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo -H systemctl daemon-reload && sudo -H systemctl restart kubelet
