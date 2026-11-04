#!/bin/bash
# AI Data Center East-West Incast Congestion Benchmark
# Supports Baseline (CUBIC + Tail-drop) and ECN (DCTCP + RED/ECN Marking)
set -e

MODE=${1:-baseline}       # baseline | ecn
RUNS=${2:-10}             # repetitions per scenario
RECEIVER="clab-ai-fabric-h8"
RECEIVER_IP="10.100.0.18"
RECEIVER_LEAF="clab-ai-fabric-leaf4"
RECEIVER_PORT="eth4"      # Leaf4 port facing h8
RESULTS_DIR="results/${MODE}"

mkdir -p "${RESULTS_DIR}/4to1" "${RESULTS_DIR}/7to1" "${RESULTS_DIR}/logs"

echo "============================================================"
echo "  AI Data Center Incast Congestion Benchmark"
echo "  Mode: $MODE | Repetitions: $RUNS"
echo "  Receiver: $RECEIVER ($RECEIVER_IP)"
echo "============================================================"

# Configure Congestion Control & Bottleneck Qdisc
configure_scenario() {
    echo "[*] Configuring host congestion control and leaf egress bottleneck..."
    if [ "$MODE" == "baseline" ]; then
        # Default Tail-Drop with CUBIC
        for h in $(docker ps --filter "name=clab-ai-fabric-h" --format "{{.Names}}"); do
            docker exec "$h" sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
            docker exec "$h" sysctl -w net.ipv4.tcp_ecn=0 >/dev/null
        done
        # Rate limit leaf port to 1Gbit with a standard FIFO tail-drop queue (limit 100 packets)
        docker exec "$RECEIVER_LEAF" tc qdisc del dev "$RECEIVER_PORT" root 2>/dev/null || true
        docker exec "$RECEIVER_LEAF" tc qdisc add dev "$RECEIVER_PORT" root handle 1: tbf rate 1000mbit burst 32kbit limit 100kb
        echo "[+] Bottleneck set: 1 Gbps TBF Tail-Drop buffer"
    elif [ "$MODE" == "ecn" ]; then
        # ECN enabled with DCTCP (or fallback to CUBIC+ECN if DCTCP not loaded)
        for h in $(docker ps --filter "name=clab-ai-fabric-h" --format "{{.Names}}"); do
            docker exec "$h" sysctl -w net.ipv4.tcp_ecn=1 >/dev/null
            docker exec "$h" sysctl -w net.ipv4.tcp_congestion_control=dctcp 2>/dev/null || \
            docker exec "$h" sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
        done
        # RED with ECN marking enabled at low queue depth
        docker exec "$RECEIVER_LEAF" tc qdisc del dev "$RECEIVER_PORT" root 2>/dev/null || true
        docker exec "$RECEIVER_LEAF" tc qdisc add dev "$RECEIVER_PORT" root handle 1: red limit 100000 min 20000 max 50000 avpkt 1000 burst 30 ecn
        echo "[+] Bottleneck set: RED Qdisc with ECN marking"
    fi
}

start_receiver() {
    echo "[*] Starting iperf3 server on $RECEIVER..."
    docker exec -d "$RECEIVER" iperf3 -s -p 5201 --one-off >/dev/null 2>&1 || true
    sleep 1
}

run_incast_test() {
    local scenario=$1
    local senders=()
    if [ "$scenario" == "4to1" ]; then
        senders=("clab-ai-fabric-h1" "clab-ai-fabric-h3" "clab-ai-fabric-h5" "clab-ai-fabric-h7")
    elif [ "$scenario" == "7to1" ]; then
        senders=("clab-ai-fabric-h1" "clab-ai-fabric-h2" "clab-ai-fabric-h3" "clab-ai-fabric-h4" "clab-ai-fabric-h5" "clab-ai-fabric-h6" "clab-ai-fabric-h7")
    fi

    echo -e "\n[*] Running Scenario: $scenario (${#senders[@]} Senders -> 1 Receiver) - $RUNS iterations"

    for r in $(seq 1 $RUNS); do
        echo -n "  Iteration $r/$RUNS... "
        start_receiver

        # Reset qdisc stats before run
        docker exec "$RECEIVER_LEAF" tc -s qdisc show dev "$RECEIVER_PORT" > "${RESULTS_DIR}/${scenario}/qdisc_pre_run${r}.txt" 2>&1

        # Background ping from h1 to measure tail latency under congestion
        docker exec clab-ai-fabric-h1 ping -c 30 -i 0.1 "$RECEIVER_IP" > "${RESULTS_DIR}/${scenario}/ping_run${r}.txt" 2>&1 &
        PING_PID=$!

        # Launch concurrent iperf3 clients
        local pids=()
        for idx in "${!senders[@]}"; do
            local s="${senders[$idx]}"
            docker exec "$s" iperf3 -c "$RECEIVER_IP" -p 5201 -t 3 -J > "${RESULTS_DIR}/${scenario}/${s}_run${r}.json" 2>&1 &
            pids+=($!)
        done

        # Wait for senders and ping
        for pid in "${pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        wait "$PING_PID" 2>/dev/null || true

        # Capture post-run qdisc drops/marks
        docker exec "$RECEIVER_LEAF" tc -s qdisc show dev "$RECEIVER_PORT" > "${RESULTS_DIR}/${scenario}/qdisc_post_run${r}.txt" 2>&1
        echo "Done."
    done
}

configure_scenario
run_incast_test "4to1"
run_incast_test "7to1"

echo -e "\n[SUCCESS] Benchmark runs complete! Results saved in ${RESULTS_DIR}/."
