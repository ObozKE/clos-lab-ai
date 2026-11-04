#!/bin/sh
set -e

echo "[INFO] Configuring host h1..."

# Ensure loopback is up
ip link set dev lo up || true

# Wait for eth1 to appear if needed
while ! ip link show eth1 >/dev/null 2>&1; do
    sleep 0.5
done

# Configure IP address and MTU on eth1
ip addr flush dev eth1 || true
ip addr add 10.100.0.11/24 dev eth1
ip link set dev eth1 mtu 1500 up

# Add default route via anycast gateway
ip route replace default via 10.100.0.1 dev eth1

echo "[SUCCESS] h1 configured with IP 10.100.0.11/24 via GW 10.100.0.1."