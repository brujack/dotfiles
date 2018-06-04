#!/bin/bash

GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"

sudo -H apt-get update
sudo -H apt-get dist-upgrade -y
sudo -H apt-get install apt-transport-https ca-certificates curl software-properties-common -y
sudo -H apt-get autoremove -y

sudo -H apt-get install docker.io -y

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
sudo -H snap install --classic go

# install crictl from go
sudo -H apt update
sudo -H apt-get install gcc -y
go get github.com/kubernetes-incubator/cri-tools/cmd/crictl

# disable swap as kubernetes expects it to be off
sudo -H sed -i '/ swap / s/^/#/' /etc/fstab
sudo -H swapoff -a

# fix the kubelet startup script to use the correct cgroup driver that matches what docker uses
KUBELET_CGROUP_ARGS=$(sudo -H docker info | grep -i cgroup | awk -F ':' '{print $2}' | sed -e 's/^[[:space:]]*//')
echo Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=${KUBELET_CGROUP_ARGS}" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo -H systemctl daemon-reload && sudo -H systemctl restart kubelet

# initialize a kubernetes cluster
sudo -H kubeadm init --pod-network-cidr=192.168.10.0/24

sleep 120
# setup .kube environment
sudo -H chmod 644 /etc/kubernetes/admin.conf
mkdir -p ~/.kube
sudo -H cp -i /etc/kubernetes/admin.conf ~/.kube/config
sudo -H chown -R $(id -u):$(id -g) ~/.kube

sleep 60

export KUBECONFIG=/etc/kubernetes/admin.conf && sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml

# Allow workloads to be scheduled to the master node
sudo -H kubectl taint nodes `hostname` node-role.kubernetes.io/master:NoSchedule-

# Deploy the monitoring stack based on Heapster, Influxdb and Grafana
sudo -H apt-get update
sudo -H apt-get install git -y
cd ${PERSONAL_GITREPOS}
git clone https://github.com/kubernetes/heapster.git
cd ${PERSONAL_GITREPOS}/heapster

# Change the default Grafana config to use NodePort so we can reach the Grafana UI over the Public/Floating IP
sed -i 's/# type: NodePort/type: NodePort/' deploy/kube-config/influxdb/grafana.yaml

sudo -H kubectl create -f deploy/kube-config/influxdb/
sudo -H kubectl create -f deploy/kube-config/rbac/heapster-rbac.yaml

# install the Kubernetes dashboard
cd ~
wget https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
echo '  type: NodePort' >> kubernetes-dashboard.yaml
sudo -H kubectl create -f kubernetes-dashboard.yaml

# Create an admin user that will be needed in order to access the Kubernetes Dashboard
bash -c 'cat << EOF > admin-user.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF'

sudo -H kubectl create -f admin-user.yaml

# Create an admin role that will be needed in order to access the Kubernetes Dashboard
bash -c 'cat << EOF > role-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF'

sudo -H kubectl create -f role-binding.yaml

# This command will create a token and print the command needed to join slave workers
sudo -H kubeadm token create --print-join-command --ttl 24h

# This command will print the port exposed by the Grafana service. We need to connect to the floating IP:PORT later
sudo -H kubectl get svc -n kube-system | grep grafana

# This command will print the port exposed by the Kubernetes dashboard service. We need to connect to the floating IP:PORT later
sudo -H kubectl -n kube-system get service kubernetes-dashboard

# This command will print a token that can be used to authenticate in the Kubernetes dashboard
sudo -H kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}') | grep "token:"
