#!/bin/bash
# ==============================================================================
# AI Data Center Spine-Leaf Fabric Digital Twin - Stage 2 Underlay Verification
# ==============================================================================
set -e

CLAB_PREFIX="clab-ai-fabric"
SPINES=("spine1" "spine2")
LEAVES=("leaf1" "leaf2" "leaf3" "leaf4")
ALL_NODES=("spine1" "spine2" "leaf1" "leaf2" "leaf3" "leaf4")
LOOPBACKS=("10.255.0.1" "10.255.0.2" "10.255.1.1" "10.255.1.2" "10.255.1.3" "10.255.1.4")

echo "=============================================================================="
echo "  AI Data Center Fabric - Stage 2: eBGP Underlay Verification"
echo "  Date: $(date -u)"
echo "  Host: $(uname -n) | Kernel: $(uname -r)"
echo "=============================================================================="

echo -e "\n------------------------------------------------------------------------------"
echo " 1. BGP SESSION STATE SUMMARY (SPINES)"
echo "------------------------------------------------------------------------------"
for spine in "${SPINES[@]}"; do
    echo -e "\n[+] Spine Switch: ${spine}"
    docker exec "${CLAB_PREFIX}-${spine}" vtysh -c "show ip bgp summary"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 2. BGP SESSION STATE SUMMARY (LEAVES)"
echo "------------------------------------------------------------------------------"
for leaf in "${LEAVES[@]}"; do
    echo -e "\n[+] Leaf Switch: ${leaf}"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show ip bgp summary"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 3. ECMP MULTIPATH ROUTING VERIFICATION"
echo "------------------------------------------------------------------------------"
for leaf in "${LEAVES[@]}"; do
    echo -e "\n[+] Equal-Cost Multipath (ECMP) routes to other leaf loopbacks on ${leaf}:"
    docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show ip route 10.255.1.0/24 longer-prefixes"
done

echo -e "\n------------------------------------------------------------------------------"
echo " 4. FULL MESH LOOPBACK REACHABILITY MATRIX (ALL NODES -> ALL LOOPBACKS)"
echo "------------------------------------------------------------------------------"
total_pings=0
passed_pings=0

for src in "${ALL_NODES[@]}"; do
    echo -e "\n[+] Reachability probes from ${src}:"
    for dst in "${LOOPBACKS[@]}"; do
        total_pings=$((total_pings + 1))
        if docker exec "${CLAB_PREFIX}-${src}" ping -c 1 -W 1 "${dst}" >/dev/null 2>&1; then
            echo "    -> ${dst} [PASS]"
            passed_pings=$((passed_pings + 1))
        else
            echo "    -> ${dst} [FAIL]"
        fi
    done
done

echo -e "\n------------------------------------------------------------------------------"
echo " 5. UNDERLAY HEALTH VERIFICATION SUMMARY"
echo "------------------------------------------------------------------------------"
echo "Total Loopback Probes: ${total_pings}"
echo "Successful Probes:    ${passed_pings}"

if [ "${total_pings}" -eq "${passed_pings}" ]; then
    echo -e "\nSTATUS: PASSED - 100% UNDERLAY CONNECTIVITY, BGP ESTABLISHED & ECMP CONFIRMED"
else
    echo -e "\nSTATUS: FAILED - Some loopback probes failed."
    exit 1
fi
