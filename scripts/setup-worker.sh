#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (or with sudo)."
  exit 1
fi

# Allow optional "worker" prefix for compatibility with the combined script syntax
if [ $# -lt 1 ]; then
  echo "Usage: $0 [worker] <kubeadm-join-command>"
  echo
  echo "  Pass the full join command from the master."
  echo
  echo "Examples:"
  echo "  $0 \"kubeadm join 10.0.0.10:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>\""
  echo "  $0 kubeadm join 10.0.0.10:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
  echo "  $0 worker kubeadm join 10.0.0.10:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
  exit 1
fi

if [ "$1" = "worker" ]; then
  shift
fi

echo ">>> Updating packages..."
yum update -y

echo ">>> Disabling swap..."
swapoff -a
sed -i '/ swap / s/^[[:space:]]*\([^#]\)/#\1/' /etc/fstab

echo ">>> Configuring kernel parameters..."
modprobe br_netfilter
echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

echo ">>> Installing containerd..."
yum install -y containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo ">>> Installing Kubernetes components..."
cat > /etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

yum install -y kubelet kubeadm kubectl yum-plugin-versionlock
yum versionlock kubelet kubeadm kubectl

systemctl enable --now kubelet

echo ">>> Applying Amazon Linux DNS workaround..."
mkdir -p /run/systemd/resolve
ln -sf /etc/resolv.conf /run/systemd/resolve/resolv.conf

echo ">>> Cleaning any previous Kubernetes state..."
kubeadm reset -f 2>/dev/null || true
rm -rf /etc/kubernetes/*

echo ">>> Joining worker node to the cluster..."
eval "$*"

echo
echo "Done. Check node status on the master with: kubectl get nodes"
