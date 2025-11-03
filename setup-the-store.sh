#!/bin/bash

# Private EC2 User Data Script
# Installs Docker, kind, kubectl, and clones the repository

set -e

echo "==============================================="
echo "Private EC2 Setup"
echo "Installing Docker, kind, kubectl, and cloning repository"
echo "==============================================="

# Update system packages
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install git and other prerequisites
echo "Installing prerequisites..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git \
  ca-certificates \
  curl \
  || true

# Install Docker from official Docker repository
echo "Installing Docker..."
# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Enable and start Docker
systemctl enable --now docker

# Install kind
echo "Installing kind..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
elif [ "$ARCH" = "aarch64" ]; then
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-arm64
else
  echo "ERROR: Unsupported architecture: $ARCH"
  exit 1
fi

chmod +x ./kind
mv ./kind /usr/local/bin/kind

# Install kubectl
echo "Installing kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

# Determine kubectl architecture based on system architecture
if [ "$ARCH" = "aarch64" ]; then
  KUBECTL_ARCH="arm64"
else
  KUBECTL_ARCH="amd64"  # Default to amd64 for x86_64
fi

curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256"

echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Clean up temporary files
rm -f kubectl kubectl.sha256

# Clone the repository
echo "Cloning repository..."
cd /home/ubuntu
sudo -u ubuntu git clone https://github.com/stonefeld/tpe_redes_2025_tf.git || true

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/the-store

echo "==============================================="
echo "✓ Setup complete!"
echo "✓ Docker installed and running"
echo "✓ kind installed"
echo "✓ kubectl installed"
echo "✓ Repository cloned to /home/ubuntu/the-store"
echo "==============================================="

# Create a message in MOTD
cat > /etc/motd << 'MOTD_EOF'
===============================================
Private EC2 Setup Complete
===============================================
✓ Docker installed and configured
✓ kind installed
✓ kubectl installed
✓ Repository cloned: /home/ubuntu/the-store

To create a Kubernetes cluster:
  kind create cluster --config /home/ubuntu/the-store/kind-config.yaml

Note: Configure kind to listen on 0.0.0.0:6443 for remote access
===============================================
MOTD_EOF

echo "✓ Setup complete. All tools installed and ready."

