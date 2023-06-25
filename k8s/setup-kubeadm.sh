#!/bin/bash

# refs:
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
# https://github.com/containerd/containerd/blob/main/docs/getting-started.md#installing-containerd

# TO DO:
# - none!

### FUNCTIONS ###
# Undo this script:
undo()
{
  echo "=== Uninstalling CNI plugins..."
  sudo rm -rf /opt/cni
  echo "=== Uninstalling runc..."
  sudo rm /usr/local/sbin/runc
  echo "=== Uninstalling containerd..."
  sudo systemctl disable --now containerd.service
  sudo rm -rf /usr/local/bin/containerd /usr/local/lib/systemd /etc/containerd /opt/containerd
  echo "=== Removing sysctl k8s settings..."
  sudo rm /etc/sysctl.d/k8s.conf
  sudo sysctl --system
  echo "=== Uninstalling dasel..."
  sudo rm /usr/local/bin/dasel
  echo "=== Uninstalling kube tools..."
  sudo apt purge -y --allow-change-held-packages kubeadm kubelet kubectl
  sudo rm /etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg /etc/apt/sources.list.d/kubernetes.list
  sudo apt autoremove -y
  echo "=== Cleaning up /tmp install dir..."
  sudo rm -rf /tmp/setup-kubeadm
  echo "=== Reversed all script functions."
}

### Handling Opts ###
while getopts ":u" i; do
  case $i in
    u) # reverse all script steps
      undo
      exit;;
    \?) # Invalid options
      echo "=== Invalid option: $1"
      exit 1;;
  esac
done

################### MAIN #################################

# Install prereqs:
sudo apt update
sudo apt install -y gpg curl apt-transport-https ca-certificates 

# Forwarding IPv4 and letting iptables see bridged traffic:
echo "=== Forwarding IPv4 and letting iptables see bridged traffic..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# Verify that the br_netfilter, overlay modules are loaded:
echo "=== Verify that the br_netfilter, overlay modules are loaded..."
lsmod | grep br_netfilter
lsmod | grep overlay

# Verify sysctl config:
sudo sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# Get my bearings:
mkdir -p /tmp/setup-kubeadm
cd /tmp/setup-kubeadm

# Install containerd:
echo "=== Installing containerd..."
for i in $(curl -fsSL https://api.github.com/repos/containerd/containerd/releases/latest | grep browser_download_url | grep -P "/containerd-\d.*linux-amd64" | cut -d\" -f 4); do curl -fsSL "$i" -L -O; done
sha256sum -c --ignore-missing ./containerd-*.sha256sum
# If previous checksum failed, exit script:
[ $? -ne "0" ] && exit 1
sudo tar Cxvzf /usr/local ./containerd-*.tar.gz
sudo mkdir -p /usr/local/lib/systemd/system
sudo wget -P /usr/local/lib/systemd/system https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo systemctl daemon-reload && sudo systemctl enable --now containerd

# Install runc:
echo "=== Installing runc..."
curl -fsSL "$(curl -fsSL https://api.github.com/repos/opencontainers/runc/releases/latest | grep browser_download_url | grep "runc.amd64\"" | cut -d\" -f 4)" -O
curl -fsSL "$(curl -fsSL https://api.github.com/repos/opencontainers/runc/releases/latest | grep browser_download_url | grep "runc.sha256sum\"" | cut -d\" -f 4)" -O
sha256sum -c --ignore-missing ./runc.sha256sum
# If previous checksum failed, exit script:
[ $? -ne "0" ] && exit 1
sudo install -m 755 ./runc.amd64 /usr/local/sbin/runc

# Install CNI plugins:
echo "=== Installing CNI plugins..."
curl -fsSL "$(curl -fsSL https://api.github.com/repos/containernetworking/plugins/releases/latest | grep browser_download_url | grep -P "linux.*amd64.*tgz\"" | cut -d\" -f 4)" -O
curl -fsSL "$(curl -fsSL https://api.github.com/repos/containernetworking/plugins/releases/latest | grep browser_download_url | grep -P "linux.*amd64.*sha256\"" | cut -d\" -f 4)" -O
sha256sum -c --ignore-missing ./cni-plugins-linux-amd64*sha256
# If previous checksum failed, exit script:
[ $? -ne "0" ] && exit 1
sudo mkdir -p /opt/cni/bin
sudo tar Cxvzf /opt/cni/bin ./cni-plugins-linux-amd64-*.tgz

# Generate default containerd config:
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Modify containerd config to use the systemd cgroup:
# Install last version of 'dasel' for modifying toml files:
curl -sSLf "$(curl -sSLf https://api.github.com/repos/tomwright/dasel/releases/latest | grep browser_download_url | grep linux_amd64 | grep -v .gz | cut -d\" -f 4)" -L -o ./dasel && chmod +x ./dasel
sudo mv ./dasel /usr/local/bin/dasel
sudo dasel put -t bool -f /etc/containerd/config.toml -v true '.plugins.io\.containerd\.grpc\.v1\.cri.containerd.runtimes.runc.options.SystemdCgroup'
sudo systemctl restart containerd

# Install kubeadm, kubelet, and kubectl tools:
# Download Google Cloud gpg key:
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg
# Add Kubernetes repo to apt sources:
echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
# Install packages & prevent updates to prevent version skew issues:
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Configure containerd to use same version of 'pause' image that kubeadm uses:
PAUSE_VER=$(sudo kubeadm config images pull | grep -oP "registry.*?pause.*$")
sudo dasel put -t string -f /etc/containerd/config.toml -v $PAUSE_VER '.plugins.io\.containerd\.grpc\.v1\.cri.sandbox_image'
sudo systemctl restart containerd
