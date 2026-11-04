# AI Data Center Spine-Leaf Fabric Digital Twin Makefile
SHELL := /bin/bash
PYTHON ?= $(shell which python3 2>/dev/null || which py 2>/dev/null || echo python)
CLAB ?= containerlab
TOPO := topology/fabric.clab.yml
SPEC := topology/topology.yml

.PHONY: all generate up down status verify verify-underlay verify-overlay benchmark clean setup-rhel help

all: help

help:
	@echo "AI Data Center Spine-Leaf Fabric Digital Twin (Containerlab + FRR)"
	@echo "----------------------------------------------------------------"
	@echo "make setup-rhel      - Bootstrap fresh RHEL 9 VM (Docker CE, clab, kernel modules)"
	@echo "make generate        - Generate configs and clab topology from topology/topology.yml"
	@echo "make up              - Deploy the 14-node spine-leaf fabric in Containerlab"
	@echo "make down            - Tear down the fabric and clean up veth/network namespaces"
	@echo "make status          - Display status and details of running lab nodes"
	@echo "make verify          - Run full fabric verification (underlay and overlay)"
	@echo "make verify-underlay - Run eBGP underlay verification matrix"
	@echo "make verify-overlay  - Run VXLAN BGP-EVPN overlay & inter-host ping matrix"
	@echo "make benchmark       - Execute baseline and ECN incast benchmarks"
	@echo "make clean           - Remove generated configuration artifacts"

setup-rhel:
	@echo "[*] Provisioning RHEL 9 environment..."
	@bash scripts/rhel_bootstrap.sh

generate:
	@echo "[*] Generating configurations from $(SPEC)..."
	@$(PYTHON) scripts/generate_configs.py

up: generate
	@echo "[*] Deploying Containerlab fabric $(TOPO)..."
	@sudo $(CLAB) deploy -t $(TOPO) --reconfigure
	@echo "[*] Fabric deployed successfully. Checking node status..."
	@sudo $(CLAB) inspect -t $(TOPO)

down:
	@echo "[*] Destroying Containerlab fabric $(TOPO)..."
	@sudo $(CLAB) destroy -t $(TOPO) --cleanup

status:
	@echo "[*] Inspecting Containerlab fabric status..."
	@sudo $(CLAB) inspect -t $(TOPO)

verify-underlay:
	@echo "[*] Running eBGP underlay verification..."
	@bash scripts/verify_underlay.sh

verify-overlay:
	@echo "[*] Running VXLAN BGP-EVPN overlay verification..."
	@bash scripts/verify_overlay.sh

verify: verify-underlay verify-overlay

benchmark:
	@echo "[*] Running incast congestion benchmark..."
	@bash benchmarks/run_incast.sh

clean:
	@echo "[*] Cleaning generated configurations..."
	@rm -rf configs/leaf* configs/spine* configs/h* topology/fabric.clab.yml
	@echo "[*] Clean complete."
