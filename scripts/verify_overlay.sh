#!/bin/bash
# ==============================================================================
# AI Data Center Spine-Leaf Fabric Digital Twin - Stage 3 EVPN Overlay Verification
# ==============================================================================
set -e

CLAB_PREFIX="clab-ai-fabric"
SPINES=("spine1" "spine2")
LEAVES=("leaf1" "leaf2" "leaf3" "leaf4")
HOSTS=("h1" "h2" "h3" "h4" "h5" "h6" "h7" "h8")
HOST_IPS=(
    "10.100.0.11" "10.100.0.12" "10.100.0.13" "10.100.0.14"
    "10.100.0.15" "10.100.0.16" "10.100.0.17" "10.100.0.18"
)

echo "=============================================================================="
echo "  AI Data Center Fabric - Stage 3: VXLAN BGP-EVPN Overlay Verification"
echo "  Date: $(date -u)"
echo "  Host: $(uname -n) | Kernel: $(uname -r)"
echo "=============================================================================="

echo -e "\n------------------------------------------------------------------------------"
echo " 1. EVPN BGP SESSION STATE SUMMARY (SPINES)"
echo "------------------------------------------------------------------------------"
for spine in "${SPINES[@]}"; do
    echo -e "\n[+] Spine Switch: ${spine}"
    docker exec "${CLAB_PREFIX}-${spine}" vtysh -c "show bgp l2vpn evpn summary"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 2. EVPN BGP SESSION STATE SUMMARY (LEAVES)"
echo "------------------------------------------------------------------------------"
for leaf in "${LEAVES[@]}"; do
    echo -e "\n[+] Leaf Switch: ${leaf}"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show bgp l2vpn evpn summary"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 3. EVPN VNI CONFIGURATION & STATUS (ALL LEAVES)"
echo "------------------------------------------------------------------------------"
for leaf in "${LEAVES[@]}"; do
    echo -e "\n[+] Leaf Switch: ${leaf} (VNI Table)"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show evpn vni"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 4. EVPN ROUTE TABLE (SAMPLE: LEAF1 & LEAF3)"
echo "    Showing Type-2 (MAC/IP), Type-3 (Multicast), and Type-5 (IP Prefix) routes"
echo "------------------------------------------------------------------------------"
for leaf in "leaf1" "leaf3"; do
    echo -e "\n[+] BGP EVPN Routes on ${leaf}:"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show bgp l2vpn evpn route"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 5. TENANT VRF ROUTING TABLE (VRF TENANT-A ON LEAF1 & LEAF2)"
echo "------------------------------------------------------------------------------"
for leaf in "leaf1" "leaf2"; do
    echo -e "\n[+] IPv4 Routing Table for VRF TENANT-A on ${leaf}:"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show ip route vrf TENANT-A"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 6. DISTRIBUTED ANYCAST GATEWAY REACHABILITY (ALL HOSTS -> 10.100.0.1)"
echo "------------------------------------------------------------------------------"
gw_total=0
gw_passed=0
for host in "${HOSTS[@]}"; do
    gw_total=$((gw_total + 1))
    if docker exec "${CLAB_PREFIX}-${host}" ping -c 1 -W 1 10.100.0.1 >/dev/null 2>&1; then
        echo "    ${host} -> 10.100.0.1 (Anycast GW) [PASS]"
        gw_passed=$((gw_passed + 1))
    else
        echo "    ${host} -> 10.100.0.1 (Anycast GW) [FAIL]"
    fi
done
echo "Anycast Gateway Reachability: ${gw_passed}/${gw_total} passed"

echo -e "\n------------------------------------------------------------------------------"
echo " 7. CROSS-LEAF INTER-HOST PING MATRIX (FULL MESH: 8 HOSTS, 56 PAIRS)"
echo "------------------------------------------------------------------------------"
total_pings=0
passed_pings=0

for i in "${!HOSTS[@]}"; do
    src="${HOSTS[$i]}"
    for j in "${!HOSTS[@]}"; do
        if [ "$i" -eq "$j" ]; then
            continue
        fi
        dst_host="${HOSTS[$j]}"
        dst_ip="${HOST_IPS[$j]}"
        total_pings=$((total_pings + 1))
        if docker exec "${CLAB_PREFIX}-${src}" ping -c 1 -W 1 "${dst_ip}" >/dev/null 2>&1; then
            echo "    ${src} -> ${dst_host} (${dst_ip}) [PASS]"
            passed_pings=$((passed_pings + 1))
        else
            echo "    ${src} -> ${dst_host} (${dst_ip}) [FAIL]"
        fi
    done
done
echo "Overlay Ping Matrix: ${passed_pings}/${total_pings} passed"

echo -e "\n------------------------------------------------------------------------------"
echo " 8. ARP CACHE & ARP SUPPRESSION VERIFICATION"
echo "------------------------------------------------------------------------------"
for leaf in "leaf1" "leaf2"; do
    echo -e "\n[+] EVPN ARP Cache for L2VNI 10100 on ${leaf}:"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show evpn arp-cache vni 10100"
    echo -e "\n[+] Linux Bridge Link Settings (Neigh Suppress) on ${leaf}:"
    docker exec "${CLAB_PREFIX}-${leaf}" bridge link show dev vxlan10100
done

echo -e "\n=============================================================================="
if [ "${passed_pings}" -eq "${total_pings}" ] && [ "${gw_passed}" -eq "${gw_total}" ]; then
    echo "  STAGE 3 EVPN OVERLAY VERIFICATION PASSED: All ${total_pings} paths verified!"
    echo "=============================================================================="
    exit 0
else
    echo "  STAGE 3 EVPN OVERLAY VERIFICATION FAILED: Some paths unreachable."
    echo "=============================================================================="
    exit 1
fi
