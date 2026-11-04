#!/bin/sh
set -e

# AI Data Center Spine Switch Dataplane Setup
echo "[INFO] Configuring dataplane on spine2..."

# Enable IP forwarding and L4 multipath hash policy for true ECMP
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.fib_multipath_hash_policy=1 >/dev/null 2>&1 || true

# Set Jumbo MTU on fabric interfaces
ip link set dev eth1 mtu 9000 up || true
ip link set dev eth2 mtu 9000 up || true
ip link set dev eth3 mtu 9000 up || true
ip link set dev eth4 mtu 9000 up || true

# Ensure loopback is up
ip link set dev lo up || true
touch /etc/frr/vtysh.conf 2>/dev/null || true

echo "[SUCCESS] spine2 dataplane configured."