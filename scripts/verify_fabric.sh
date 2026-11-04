#!/bin/bash
# AI Data Center Spine-Leaf Fabric Automated Verification Script
set -e

MODE=${1:-all}
CLAB_PREFIX="clab-ai-fabric"

echo "============================================================"
echo "  AI Data Center Fabric Verification ($MODE)"
echo "============================================================"

check_underlay() {
    echo -e "\n[*] --- Underlay eBGP Verification ---"
    for spine in spine1 spine2; do
        echo -e "\n[+] BGP summary on $spine:"
        docker exec "${CLAB_PREFIX}-${spine}" vtysh -c "show ip bgp summary" || true
    done

    for leaf in leaf1 leaf2 leaf3 leaf4; do
        echo -e "\n[+] BGP summary on $leaf:"
        docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show ip bgp summary" || true
        echo -e "\n[+] ECMP Multipath routes to other leaf loopbacks on $leaf:"
        docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show ip route 10.255.1.0/24 longer-prefixes" || true
    done
}

check_overlay() {
    echo -e "\n[*] --- Overlay EVPN Verification ---"
    for leaf in leaf1 leaf2 leaf3 leaf4; do
        echo -e "\n[+] EVPN VNIs on $leaf:"
        docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show evpn vni" || true
        echo -e "\n[+] EVPN Type-2 (MAC/IP) routes on $leaf:"
        docker exec "${CLAB_PREFIX}-${leaf}" vtysh -c "show bgp l2vpn evpn route type macip" || true
    done

    echo -e "\n[*] --- End-to-End Host Connectivity Tests ---"
    # Test East-West connectivity between hosts on different leaves
    echo -n "[+] Ping h1 (leaf1) -> h3 (leaf2): "
    docker exec "${CLAB_PREFIX}-h1" ping -c 2 -W 1 10.100.0.13 >/dev/null 2>&1 && echo "SUCCESS" || echo "FAILED"

    echo -n "[+] Ping h1 (leaf1) -> h5 (leaf3): "
    docker exec "${CLAB_PREFIX}-h1" ping -c 2 -W 1 10.100.0.15 >/dev/null 2>&1 && echo "SUCCESS" || echo "FAILED"

    echo -n "[+] Ping h1 (leaf1) -> h7 (leaf4): "
    docker exec "${CLAB_PREFIX}-h1" ping -c 2 -W 1 10.100.0.17 >/dev/null 2>&1 && echo "SUCCESS" || echo "FAILED"

    echo -n "[+] Ping h8 (leaf4) -> h2 (leaf1): "
    docker exec "${CLAB_PREFIX}-h8" ping -c 2 -W 1 10.100.0.12 >/dev/null 2>&1 && echo "SUCCESS" || echo "FAILED"
}

case "$MODE" in
    underlay)
        check_underlay
        ;;
    overlay)
        check_overlay
        ;;
    all)
        check_underlay
        check_overlay
        ;;
    *)
        echo "Usage: $0 [underlay|overlay|all]"
        exit 1
        ;;
esac

echo -e "\n============================================================"
echo "  Verification Complete"
echo "============================================================"
