#!/usr/bin/env python3
"""
AI Data Center Incast Results Parser
Aggregates iperf3 JSON outputs, ping tail latency distributions,
and tc qdisc drop/mark statistics into results/summary_metrics.csv.
"""

import os
import glob
import json
import re
import csv
import numpy as np

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RESULTS_DIR = os.path.join(REPO_ROOT, "results")
OUTPUT_CSV = os.path.join(RESULTS_DIR, "summary_metrics.csv")


def parse_ping_latencies(file_path):
    latencies = []
    if not os.path.exists(file_path):
        return [0.0]
    with open(file_path, "r") as f:
        for line in f:
            match = re.search(r"time=([\d\.]+)\s*ms", line)
            if match:
                latencies.append(float(match.group(1)))
    return latencies if latencies else [0.0]


def parse_qdisc_drops(post_file, pre_file):
    # Extract drops from 'dropped <N>' in tc -s qdisc show
    def get_drops(path):
        if not os.path.exists(path):
            return 0
        with open(path, "r") as f:
            content = f.read()
            m = re.search(r"dropped\s+(\d+)", content)
            return int(m.group(1)) if m else 0

    return max(0, get_drops(post_file) - get_drops(pre_file))


def parse_run(mode, scenario, run_idx):
    scen_dir = os.path.join(RESULTS_DIR, mode, scenario)
    json_pattern = os.path.join(scen_dir, f"*_run{run_idx}.json")
    json_files = glob.glob(json_pattern)

    total_throughput_gbps = 0.0
    total_retransmits = 0

    for jf in json_files:
        try:
            with open(jf, "r") as f:
                data = json.load(f)
                end = data.get("end", {})
                sum_sent = end.get("sum_sent", {})
                bps = sum_sent.get("bits_per_second", 0.0)
                retrans = sum_sent.get("retransmits", 0)
                total_throughput_gbps += bps / 1e9
                total_retransmits += retrans
        except Exception:
            pass

    ping_file = os.path.join(scen_dir, f"ping_run{run_idx}.txt")
    latencies = parse_ping_latencies(ping_file)

    p50 = float(np.percentile(latencies, 50))
    p99 = float(np.percentile(latencies, 99))
    p999 = float(np.percentile(latencies, 99.9))

    pre_qdisc = os.path.join(scen_dir, f"qdisc_pre_run{run_idx}.txt")
    post_qdisc = os.path.join(scen_dir, f"qdisc_post_run{run_idx}.txt")
    drops = parse_qdisc_drops(post_qdisc, pre_qdisc)

    return {
        "mode": mode,
        "scenario": scenario,
        "run": run_idx,
        "throughput_gbps": round(total_throughput_gbps, 3),
        "retransmits": total_retransmits,
        "drops": drops,
        "p50_ms": round(p50, 3),
        "p99_ms": round(p99, 3),
        "p999_ms": round(p999, 3)
    }


def main():
    records = []
    for mode in ["baseline", "ecn"]:
        for scenario in ["4to1", "7to1"]:
            scen_dir = os.path.join(RESULTS_DIR, mode, scenario)
            if not os.path.exists(scen_dir):
                continue
            # Find number of runs
            ping_files = glob.glob(os.path.join(scen_dir, "ping_run*.txt"))
            for pf in ping_files:
                m = re.search(r"ping_run(\d+)\.txt", pf)
                if m:
                    run_idx = int(m.group(1))
                    record = parse_run(mode, scenario, run_idx)
                    records.append(record)

    if not records:
        print("[WARN] No benchmark records found in results/. Run benchmarks/run_incast.sh first.")
        return

    records.sort(key=lambda r: (r["scenario"], r["mode"], r["run"]))
    fieldnames = ["scenario", "mode", "run", "throughput_gbps", "retransmits", "drops", "p50_ms", "p99_ms", "p999_ms"]

    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)

    print(f"[SUCCESS] Parsed {len(records)} runs into {OUTPUT_CSV}.")


if __name__ == "__main__":
    main()
