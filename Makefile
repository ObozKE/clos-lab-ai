# AI Data Center Spine-Leaf Fabric Digital Twin Makefile
SHELL := /bin/bash
PYTHON ?= $(shell which python3 2>/dev/null || which py 2>/dev/null || echo python)
CLAB ?= containerlab
TOPO := topology/fabric.clab.yml
SPEC := topology/topology.yml

.PHONY: all generate up down status verify benchmark clean setup-rhel help

all: help

help:
	@echo "AI Data Center Spine-Leaf Fabric Digital Twin (Containerlab + FRR)"
	@echo "----------------------------------------------------------------"
	@echo "make setup-rhel  - Bootstrap fresh RHEL 9 VM (Docker CE, clab, kernel modules)"
	@echo "make generate    - Generate configs and clab topology from topology/topology.yml"
	@echo "make up          - Deploy the 14-node spine-leaf fabric in Containerlab"
	@echo "make down        - Tear down the fabric and clean up veth/network namespaces"
	@echo "make status      - Display status and details of running lab nodes"
	@echo "make verify      - Run automated health, underlay BGP, and EVPN overlay checks"
	@echo "make benchmark   - Execute baseline and ECN incast benchmarks"
	@echo "make clean       - Remove generated configuration artifacts"

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

verify:
	@echo "[*] Running fabric verification tests..."
	@bash scripts/verify_fabric.sh

benchmark:
	@echo "[*] Running incast congestion benchmark..."
	@bash benchmarks/run_incast.sh

clean:
	@echo "[*] Cleaning generated configurations..."
	@rm -rf configs/leaf* configs/spine* configs/h* topology/fabric.clab.yml
	@echo "[*] Clean complete."
