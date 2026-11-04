#!/bin/bash
# ==============================================================================
# AI Data Center Fabric Digital Twin - RHEL 9 Environment Bootstrap Script
# ==============================================================================
# This script provisions a fresh Red Hat Enterprise Linux 9 / Rocky / AlmaLinux 9
# VM with Docker CE, Containerlab, Python tooling, and required kernel modules
# (sch_red, tcp_dctcp, rdma_rxe) for full RoCEv2 and ECN incast benchmarking.
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=============================================================================="
echo "  Provisioning RHEL 9 for AI Data Center Fabric & RoCEv2 Digital Twin"
echo "=============================================================================="

# 1. OS Verification
log_info "Verifying Operating System..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "Detected OS: $NAME ($VERSION_ID)"
else
    log_error "/etc/os-release not found. This script requires RHEL / Rocky / AlmaLinux 9."
    exit 1
fi

# 2. Base Utilities & EPEL
log_info "Installing EPEL, development tools, and network diagnostics..."
sudo dnf install -y dnf-plugins-core epel-release || true
sudo dnf config-manager --set-enabled crb 2>/dev/null || true

sudo dnf install -y \
    curl \
    wget \
    git \
    make \
    tar \
    python3 \
    python3-pip \
    python3-jinja2 \
    python3-pyyaml \
    iproute \
    iptables \
    iptables-nft \
    ethtool \
    tcpdump \
    iperf3 \
    kernel-modules-extra \
    rdma-core \
    infiniband-diags \
    libibverbs-utils

# 3. Docker CE Installation (Containerlab Recommended Engine)
log_info "Configuring Docker CE repository..."
if ! command -v docker &>/dev/null; then
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER" || true
    log_success "Docker CE installed and started."
else
    log_info "Docker is already installed."
    sudo systemctl enable --now docker || true
fi

# 4. Containerlab Installation
log_info "Installing Containerlab..."
if ! command -v containerlab &>/dev/null; then
    curl -sL https://containerlab.dev/setup | sudo bash
    log_success "Containerlab installed successfully."
else
    log_info "Containerlab is already installed: $(containerlab version | head -n 1)"
fi

# 5. Linux Kernel Modules (sch_red, tcp_dctcp, rdma_rxe)
log_info "Loading required high-performance networking kernel modules..."

modules=("sch_red" "tcp_dctcp" "rdma_rxe")
for mod in "${modules[@]}"; do
    if sudo modprobe "$mod" 2>/dev/null; then
        log_success "Module $mod loaded successfully."
        echo "$mod" | sudo tee "/etc/modules-load.d/${mod}.conf" >/dev/null
    else
        log_warn "Failed to modprobe $mod. Checking if module is available..."
        modinfo "$mod" 2>/dev/null || log_warn "$mod not found in current kernel tree."
    fi
done

# 6. Kernel Sysctl Optimization for Clos Fabric Dataplane
log_info "Applying Linux networking sysctls..."
cat << 'EOF' | sudo tee /etc/sysctl.d/99-clos-fabric.conf >/dev/null
# Enable IPv4 forwarding for transit routing
net.ipv4.ip_forward = 1

# L4 hashing for true Equal-Cost Multi-Path (ECMP) routing across spines
net.ipv4.fib_multipath_hash_policy = 1

# Bridge netfilter forwarding
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Incast congestion tuning
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
EOF

sudo modprobe br_netfilter 2>/dev/null || true
echo "br_netfilter" | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null || true
sudo sysctl --system >/dev/null

# 7. Firewalld Adjustment for Containerlab Dataplane
if systemctl is-active --quiet firewalld; then
    log_info "Adjusting firewalld for Containerlab bridge and veth forwarding..."
    sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0 2>/dev/null || true
    sudo firewall-cmd --permanent --add-masquerade 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
    log_success "Firewalld configured."
fi

# 8. Diagnostic Health Check
echo "=============================================================================="
echo "  RHEL 9 Environment Feasibility Diagnostics"
echo "=============================================================================="
echo -n "Docker daemon: "
sudo docker info >/dev/null 2>&1 && echo -e "${GREEN}ACTIVE${NC}" || echo -e "${RED}INACTIVE${NC}"

echo -n "Containerlab: "
command -v containerlab >/dev/null 2>&1 && echo -e "${GREEN}READY ($(containerlab version | head -n 1))${NC}" || echo -e "${RED}MISSING${NC}"

echo -n "Kernel Module sch_red (RED/ECN marking): "
lsmod | grep -q sch_red && echo -e "${GREEN}LOADED${NC}" || echo -e "${YELLOW}NOT LOADED${NC}"

echo -n "Kernel Module tcp_dctcp (DCTCP Congestion Control): "
lsmod | grep -q tcp_dctcp && echo -e "${GREEN}LOADED${NC}" || echo -e "${YELLOW}NOT LOADED${NC}"

echo -n "Kernel Module rdma_rxe (Soft-RoCE RDMA): "
lsmod | grep -q rdma_rxe && echo -e "${GREEN}LOADED${NC}" || echo -e "${YELLOW}NOT LOADED${NC}"

echo "=============================================================================="
log_success "RHEL 9 node preparation complete! You may now run 'make up'."
