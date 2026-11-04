#!/usr/bin/env python3
"""
AI Data Center Incast Performance Visualization
Plots:
  1. results/figures/drops_and_retransmits.png (Packet drops and TCP retransmissions)
  2. results/figures/tail_latency_p99.png (P99 / P99.9 latency under congestion)
  3. results/figures/throughput_comparison.png (Throughput with std error bars)
"""

import os
import csv
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CSV_FILE = os.path.join(REPO_ROOT, "results", "summary_metrics.csv")
FIGURES_DIR = os.path.join(REPO_ROOT, "results", "figures")


def load_data():
    if not os.path.exists(CSV_FILE):
        return None
    data = defaultdict(lambda: defaultdict(list))
    with open(CSV_FILE, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["scenario"], row["mode"])
            data[key]["throughput"].append(float(row["throughput_gbps"]))
            data[key]["retransmits"].append(float(row["retransmits"]))
            data[key]["drops"].append(float(row["drops"]))
            data[key]["p99"].append(float(row["p99_ms"]))
            data[key]["p999"].append(float(row["p999_ms"]))
    return data


def plot_drops_retransmits(data):
    scenarios = ["4to1", "7to1"]
    modes = ["baseline", "ecn"]

    fig, ax = plt.subplots(figsize=(8, 5))
    x = np.arange(len(scenarios))
    width = 0.35

    base_drops = [np.mean(data[(s, "baseline")]["drops"]) if (s, "baseline") in data else 0 for s in scenarios]
    ecn_drops = [np.mean(data[(s, "ecn")]["drops"]) if (s, "ecn") in data else 0 for s in scenarios]

    rects1 = ax.bar(x - width/2, base_drops, width, label="Baseline (Tail-Drop / CUBIC)", color="#d9534f")
    rects2 = ax.bar(x + width/2, ecn_drops, width, label="ECN Mode (RED / DCTCP)", color="#5cb85c")

    ax.set_ylabel("Average Packet Drops at Bottleneck")
    ax.set_title("Buffer Drops Under Incast Congestion (Baseline vs ECN)")
    ax.set_xticks(x)
    ax.set_xticklabels(["4:1 Incast", "7:1 Incast"])
    ax.legend()
    ax.grid(axis="y", linestyle="--", alpha=0.7)

    plt.tight_layout()
    plt.savefig(os.path.join(FIGURES_DIR, "drops_and_retransmits.png"), dpi=200)
    plt.close()


def plot_tail_latency(data):
    scenarios = ["4to1", "7to1"]

    fig, ax = plt.subplots(figsize=(8, 5))
    x = np.arange(len(scenarios))
    width = 0.35

    base_p99 = [np.mean(data[(s, "baseline")]["p99"]) if (s, "baseline") in data else 0 for s in scenarios]
    ecn_p99 = [np.mean(data[(s, "ecn")]["p99"]) if (s, "ecn") in data else 0 for s in scenarios]

    rects1 = ax.bar(x - width/2, base_p99, width, label="Baseline (Tail-Drop / CUBIC)", color="#f0ad4e")
    rects2 = ax.bar(x + width/2, ecn_p99, width, label="ECN Mode (RED / DCTCP)", color="#0275d8")

    ax.set_ylabel("P99 Latency (ms)")
    ax.set_title("P99 Tail Latency Under Incast Load (Baseline vs ECN)")
    ax.set_xticks(x)
    ax.set_xticklabels(["4:1 Incast", "7:1 Incast"])
    ax.legend()
    ax.grid(axis="y", linestyle="--", alpha=0.7)

    plt.tight_layout()
    plt.savefig(os.path.join(FIGURES_DIR, "tail_latency_p99.png"), dpi=200)
    plt.close()


def plot_throughput(data):
    scenarios = ["4to1", "7to1"]

    fig, ax = plt.subplots(figsize=(8, 5))
    x = np.arange(len(scenarios))
    width = 0.35

    base_tput = [np.mean(data[(s, "baseline")]["throughput"]) if (s, "baseline") in data else 0 for s in scenarios]
    base_err = [np.std(data[(s, "baseline")]["throughput"]) if (s, "baseline") in data else 0 for s in scenarios]

    ecn_tput = [np.mean(data[(s, "ecn")]["throughput"]) if (s, "ecn") in data else 0 for s in scenarios]
    ecn_err = [np.std(data[(s, "ecn")]["throughput"]) if (s, "ecn") in data else 0 for s in scenarios]

    ax.bar(x - width/2, base_tput, width, yerr=base_err, capsize=5, label="Baseline (Tail-Drop / CUBIC)", color="#6c757d")
    ax.bar(x + width/2, ecn_tput, width, yerr=ecn_err, capsize=5, label="ECN Mode (RED / DCTCP)", color="#20c997")

    ax.set_ylabel("Aggregate Goodput (Gbps)")
    ax.set_title("Fabric Goodput Under Incast with Error Bars")
    ax.set_xticks(x)
    ax.set_xticklabels(["4:1 Incast", "7:1 Incast"])
    ax.legend()
    ax.grid(axis="y", linestyle="--", alpha=0.7)

    plt.tight_layout()
    plt.savefig(os.path.join(FIGURES_DIR, "throughput_comparison.png"), dpi=200)
    plt.close()


def main():
    os.makedirs(FIGURES_DIR, exist_ok=True)
    data = load_data()
    if not data:
        print("[WARN] No summary data found. Run parse_results.py after benchmarks.")
        return

    plot_drops_retransmits(data)
    plot_tail_latency(data)
    plot_throughput(data)
    print(f"[SUCCESS] Charts saved to {FIGURES_DIR}/")


if __name__ == "__main__":
    main()
