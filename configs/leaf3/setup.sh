#!/bin/sh
set -e

echo "[INFO] Configuring dataplane on leaf3..."

# Sysctl settings
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.fib_multipath_hash_policy=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.arp_ignore=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.arp_announce=2 >/dev/null 2>&1 || true

# Set fabric uplink MTUs
ip link set dev eth1 mtu 9000 up || true
ip link set dev eth2 mtu 9000 up || true
ip link set dev lo up || true

# 1. Create Tenant VRF
ip link add dev TENANT-A type vrf table 1001 2>/dev/null || true
ip link set dev TENANT-A up

# 2. Create VLAN-aware Linux Bridge
ip link add dev br0 type bridge vlan_filtering 1 vlan_default_pvid 0 2>/dev/null || true
ip link set dev br0 mtu 9000 up

# 3. Create L2VNI VXLAN tunnel interface (VNI 10100 -> VLAN 100)
ip link add dev vxlan10100 type vxlan id 10100 local 10.255.1.3 dstport 4789 nolearning 2>/dev/null || true
ip link set dev vxlan10100 mtu 9000 up
ip link set dev vxlan10100 master br0
bridge vlan add dev vxlan10100 vid 100 2>/dev/null || true

# 4. Create L3VNI VXLAN tunnel interface (VNI 50001 -> VLAN 501 for VRF TENANT-A)
ip link add dev vxlan50001 type vxlan id 50001 local 10.255.1.3 dstport 4789 nolearning 2>/dev/null || true
ip link set dev vxlan50001 mtu 9000 up
ip link set dev vxlan50001 master br0
bridge vlan add dev vxlan50001 vid 501 2>/dev/null || true

# 5. Create L3VNI SVI interface and bind to VRF
ip link add link br0 name vlan501 type vlan id 501 2>/dev/null || true
ip link set dev vlan501 master TENANT-A
ip link set dev vlan501 mtu 9000 up
bridge vlan add dev br0 vid 501 self 2>/dev/null || true

# 6. Create Anycast Gateway SVI for compute VLAN 100
ip link add link br0 name vlan100 address 00:00:5e:00:01:01 type vlan id 100 2>/dev/null || true
ip addr add 10.100.0.1/24 dev vlan100 2>/dev/null || true
ip link set dev vlan100 master TENANT-A
ip link set dev vlan100 mtu 1500 up
bridge vlan add dev br0 vid 100 self 2>/dev/null || true

# 7. Bind host-facing access ports to bridge with untagged VLAN 100
ip link set dev eth3 master br0
bridge vlan add dev eth3 vid 100 pvid untagged 2>/dev/null || true
ip link set dev eth3 mtu 1500 up
ip link set dev eth4 master br0
bridge vlan add dev eth4 vid 100 pvid untagged 2>/dev/null || true
ip link set dev eth4 mtu 1500 up

echo "[SUCCESS] leaf3 dataplane configured."