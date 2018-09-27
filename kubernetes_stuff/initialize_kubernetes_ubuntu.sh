#!/bin/bash
# There are 2 scripts to building a running kubernetes environment, this one and 'install_kubernetes_ubuntu.sh'
# 'install_kubernetes_ubuntu.sh' is run first to install all of the components necessary to run kubernetes
# 'initialize_kubernetes_ubuntu.sh' is run second to initialize a kubernetes master


set -e

usage() { echo "$0 usage:" && grep " .)\ #" $0; exit 0; }
[ $# -eq 0 ] &&usage

# get command line options
while getopts ":hn:" arg; do
  case $arg in
    n) # Specify the kubernetes cluster name to be initialized. Use only dashes in the name.
      CLUSTER_NAME=${OPTARG}
      ;;
    h | *) # Display help.
      usage
      exit 0
      ;;
  esac
done

GITREPOS="${HOME}/git-repos"

# initialize a master
sudo -H kubeadm init --node-name=${CLUSTER_NAME} --pod-network-cidr=10.244.0.0/16
echo "waiting for master node to initialize"
sleep 60

# setup .kube environment and copy over the config file
sudo -H chmod 644 /etc/kubernetes/admin.conf
mkdir -p ${HOME}/.kube/${CLUSTER_NAME}
sudo -H cp -i /etc/kubernetes/admin.conf ${HOME}/.kube/${CLUSTER_NAME}/config
sudo -H chown -R $(id -u):$(id -g) ${HOME}/.kube
# change the name of the cluster to not be the default
#sed -i '0,/name: kubernetes/{s/name: kubernetes/name: '${CLUSTER_NAME}'/}' ${HOME}/.kube/${CLUSTER_NAME}/config
#sed -i '0,/cluster: kubernetes/{s/cluster: kubernetes/cluster: '${CLUSTER_NAME}'/}' ${HOME}/.kube/${CLUSTER_NAME}/config
#sed -i '0,/name: kubernetes-admin@kubernetes/{s/name: kubernetes-admin@kubernetes/name: kubernetes-admin@'${CLUSTER_NAME}'/}' ${HOME}/.kube/${CLUSTER_NAME}/config
#sed -i '0,/current-context: kubernetes-admin@kubernetes/{s/current-context: kubernetes-admin@kubernetes/current-context: kubernetes-admin@'${CLUSTER_NAME}'/}' ${HOME}/.kube/${CLUSTER_NAME}/config
export KUBECONFIG=${HOME}/.kube/${CLUSTER_NAME}/config

# initialize a kubernetes master
#sudo -H kubeadm init --config=${HOME}/.kube/${CLUSTER_NAME}/config --pod-network-cidr=192.168.10.0/24

# setup flannel kubernetes internal network
# https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#pod-network
sudo -H sysctl net.bridge.bridge-nf-call-iptables=1
sudo -H kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml

# Allow workloads to be scheduled to the master node
#sudo -H kubectl taint nodes `hostname` node-role.kubernetes.io/master:NoSchedule-

# Deploy the monitoring stack based on Heapster, Influxdb and Grafana
sudo -H apt-get update
sudo -H apt-get install git -y
cd ${GITREPOS}
git clone https://github.com/kubernetes/heapster.git
cd ${GITREPOS}/heapster

# Change the default Grafana config to use NodePort so we can reach the Grafana UI over the Public/Floating IP
sed -i 's/# type: NodePort/type: NodePort/' deploy/kube-config/influxdb/grafana.yaml

sudo -H kubectl create -f deploy/kube-config/influxdb/
sudo -H kubectl create -f deploy/kube-config/rbac/heapster-rbac.yaml

# install the Kubernetes dashboard
cd ${HOME}
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
