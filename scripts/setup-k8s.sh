#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 {master|worker [join-command]}"
  echo
  echo "  master               - Set up this node as the Kubernetes master"
  echo "  worker <join-cmd>    - Set up this node as a worker (pass the full kubeadm join ... command in quotes)"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

ROLE="$1"
JOIN_CMD="${2:-}"

if [ "$ROLE" = "worker" ] && [ -z "$JOIN_CMD" ]; then
  echo "Error: worker mode requires the full 'kubeadm join ...' command as the second argument."
  echo
  usage
fi

# ---------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_VERSION_ID="$VERSION_ID"
  else
    echo "Cannot detect OS"
    exit 1
  fi
}

# ---------------------------------------------------------------
# Common: update packages
# ---------------------------------------------------------------
update_packages() {
  echo ">>> Updating packages..."
  case "$OS_ID" in
    ubuntu)
      apt-get update && apt-get upgrade -y
      ;;
    amzn)
      yum update -y
      ;;
    *)
      echo "Unsupported OS: $OS_ID"
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------
# Common: disable swap
# ---------------------------------------------------------------
disable_swap() {
  echo ">>> Disabling swap..."
  swapoff -a
  sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}

# ---------------------------------------------------------------
# Common: load kernel modules & set sysctl
# ---------------------------------------------------------------
configure_kernel() {
  echo ">>> Configuring kernel parameters..."
  modprobe br_netfilter
  echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf

  cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

  sysctl --system
}

# ---------------------------------------------------------------
# Common: install & configure containerd
# ---------------------------------------------------------------
install_containerd() {
  echo ">>> Installing containerd..."
  case "$OS_ID" in
    ubuntu)
      apt-get install -y containerd
      ;;
    amzn)
      yum install -y containerd
      ;;
  esac

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml

  # Set SystemdCgroup = true
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  systemctl restart containerd
  systemctl enable containerd
}

# ---------------------------------------------------------------
# Common: install kubelet / kubeadm / kubectl
# ---------------------------------------------------------------
install_kubernetes() {
  echo ">>> Installing Kubernetes components..."

  case "$OS_ID" in
    ubuntu)
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
        gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes.gpg
      echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
        > /etc/apt/sources.list.d/kubernetes.list
      apt-get update
      apt-get install -y kubelet kubeadm kubectl
      apt-mark hold kubelet kubeadm kubectl
      ;;
    amzn)
      cat > /etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF
      yum install -y kubelet kubeadm kubectl
      yum versionlock kubelet kubeadm kubectl
      ;;
  esac

  systemctl enable --now kubelet
}

# ---------------------------------------------------------------
# Common: Amazon Linux DNS workaround
# ---------------------------------------------------------------
fix_amazon_dns() {
  if [ "$OS_ID" = "amzn" ]; then
    echo ">>> Applying Amazon Linux DNS workaround..."
    mkdir -p /run/systemd/resolve
    ln -sf /etc/resolv.conf /run/systemd/resolve/resolv.conf
  fi
}

# ---------------------------------------------------------------
# Common: full node setup (run on master AND worker)
# ---------------------------------------------------------------
setup_node() {
  update_packages
  disable_swap
  configure_kernel
  install_containerd
  install_kubernetes
  fix_amazon_dns
}

# ---------------------------------------------------------------
# Master: initialize control-plane
# ---------------------------------------------------------------
setup_master() {
  echo ">>> Initializing Kubernetes master..."
  kubeadm init --pod-network-cidr=10.244.0.0/16

  # Configure kubectl for the current user
  mkdir -p "$HOME/.kube"
  cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
  chown "$(id -u):$(id -g)" "$HOME/.kube/config"

  # Install Flannel CNI
  echo ">>> Installing Flannel CNI..."
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

  # Print join command
  echo
  echo "============================================================"
  echo "  Worker join command (save this):"
  echo "============================================================"
  kubeadm token create --print-join-command
  echo "============================================================"
  echo
  echo "On each worker node, run:"
  echo "  sudo $0 worker \"<join-command-from-above>\""
  echo
}

# ---------------------------------------------------------------
# Worker: join cluster
# ---------------------------------------------------------------
setup_worker() {
  echo ">>> Joining worker node to the cluster..."
  eval "$JOIN_CMD"
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
main() {
  detect_os

  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (or with sudo)."
    exit 1
  fi

  setup_node

  case "$ROLE" in
    master)
      setup_master
      ;;
    worker)
      setup_worker
      ;;
    *)
      usage
      ;;
  esac

  echo
  echo "Done. Check node status with: kubectl get nodes"
}

main
