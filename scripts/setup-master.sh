#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (or with sudo)."
  exit 1
fi

echo ">>> Updating packages..."
DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

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
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo ">>> Installing Kubernetes components..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes.gpg

echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet

echo ">>> Initializing Kubernetes master..."
kubeadm init --pod-network-cidr=10.244.0.0/16

export KUBECONFIG=/etc/kubernetes/admin.conf

TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME="$(eval echo "~$TARGET_USER")"
mkdir -p "$TARGET_HOME/.kube" /root/.kube
cp -i /etc/kubernetes/admin.conf "$TARGET_HOME/.kube/config"
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.kube/config"

echo ">>> Installing Flannel CNI..."
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo ">>> Waiting for Flannel to deploy..."
kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=120s 2>/dev/null || true

echo ">>> Waiting for nodes to become Ready..."
for i in $(seq 1 36); do
  READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  echo "  Ready: $READY / $TOTAL"
  if [ "$READY" -ge 1 ] && [ "$READY" -eq "$TOTAL" ]; then
    break
  fi
  sleep 5
done

echo
echo "============================================================"
echo "  Worker join command (save this):"
echo "============================================================"
kubeadm token create --print-join-command
echo "============================================================"
echo
echo "On each worker node, run the join command above."
echo "Done."
