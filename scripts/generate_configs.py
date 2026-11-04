#!/usr/bin/env python3
"""
AI Data Center Spine-Leaf Fabric Digital Twin
Configuration Generator
Consumes topology/topology.yml and renders:
  - topology/fabric.clab.yml (Containerlab topology)
  - configs/<node>/frr.conf
  - configs/<node>/daemons
  - configs/<node>/setup.sh
"""

import os
import sys
import yaml
import ipaddress
from jinja2 import Environment, FileSystemLoader

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TOPOLOGY_FILE = os.path.join(REPO_ROOT, "topology", "topology.yml")
TEMPLATES_DIR = os.path.join(REPO_ROOT, "templates")
CONFIGS_DIR = os.path.join(REPO_ROOT, "configs")
OUTPUT_CLAB_FILE = os.path.join(REPO_ROOT, "topology", "fabric.clab.yml")


def load_yaml(file_path):
    with open(file_path, "r") as f:
        return yaml.safe_load(f)


def build_fabric_model(topo):
    spines = topo.get("spines", [])
    leaves = topo.get("leaves", [])
    hosts = topo.get("hosts", [])
    fabric = topo.get("fabric", {})
    images = topo.get("images", {})

    p2p_base = ipaddress.ip_network(fabric.get("p2p_subnet_base", "10.0.0.0/16"))
    subnets_31 = list(p2p_base.subnets(new_prefix=31))

    fabric_links = []
    spine_models = {s["name"]: dict(s, peers=[], router_id=s["loopback"].split("/")[0]) for s in spines}
    leaf_models = {l["name"]: dict(l, peers=[], router_id=l["loopback"].split("/")[0]) for l in leaves}

    subnet_idx = 0
    for s_idx, spine in enumerate(spines, start=1):
        s_name = spine["name"]
        for l_idx, leaf in enumerate(leaves, start=1):
            l_name = leaf["name"]
            p2p_sub = subnets_31[subnet_idx]
            subnet_idx += 1

            spine_ip = str(list(p2p_sub.hosts())[0]) if p2p_sub.prefixlen == 31 else str(p2p_sub[0])
            # For RFC 3021 /31 subnets in Python: p2p_sub.network_address and p2p_sub.broadcast_address are the two host addresses
            ip_pair = [str(p2p_sub.network_address), str(p2p_sub.broadcast_address)]
            s_ip, l_ip = ip_pair[0], ip_pair[1]

            spine_port = f"eth{l_idx}"
            leaf_port = f"eth{s_idx}"

            link = {
                "spine": s_name,
                "spine_port": spine_port,
                "spine_ip": s_ip,
                "leaf": l_name,
                "leaf_port": leaf_port,
                "leaf_ip": l_ip,
                "subnet": str(p2p_sub)
            }
            fabric_links.append(link)

            # Record peer on spine
            spine_models[s_name]["peers"].append({
                "spine_port": spine_port,
                "spine_ip": s_ip,
                "leaf_name": l_name,
                "leaf_port": leaf_port,
                "leaf_ip": l_ip,
                "leaf_asn": leaf["asn"]
            })

            # Record peer on leaf
            peer_info = {
                "leaf_port": leaf_port,
                "leaf_ip": l_ip,
                "spine_name": s_name,
                "spine_port": spine_port,
                "spine_ip": s_ip,
                "spine_asn": spine["asn"]
            }
            leaf_models[l_name]["peers"].append(peer_info)
            if s_name == "spine1":
                leaf_models[l_name]["spine1_ip"] = l_ip
                leaf_models[l_name]["peer_spine1_ip"] = s_ip
            elif s_name == "spine2":
                leaf_models[l_name]["spine2_ip"] = l_ip
                leaf_models[l_name]["peer_spine2_ip"] = s_ip

    # Map hosts per leaf
    hosts_by_leaf = {l["name"]: [] for l in leaves}
    for h in hosts:
        leaf_name = h.get("leaf")
        if leaf_name in hosts_by_leaf:
            hosts_by_leaf[leaf_name].append(h)

    return {
        "fabric": fabric,
        "images": images,
        "spines": list(spine_models.values()),
        "leaves": list(leaf_models.values()),
        "hosts": hosts,
        "fabric_links": fabric_links,
        "hosts_by_leaf": hosts_by_leaf
    }


def render_file(env, template_name, context, dest_path):
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    template = env.get_template(template_name)
    rendered = template.render(context)
    with open(dest_path, "w", newline="\n") as f:
        f.write(rendered)
    # Ensure bash scripts are executable
    if dest_path.endswith(".sh"):
        try:
            os.chmod(dest_path, 0o755)
        except Exception:
            pass


def main():
    print(f"[INFO] Loading topology from {TOPOLOGY_FILE}...")
    topo = load_yaml(TOPOLOGY_FILE)
    model = build_fabric_model(topo)

    env = Environment(loader=FileSystemLoader(TEMPLATES_DIR), trim_blocks=True, lstrip_blocks=True)

    # 1. Render Containerlab Topology File
    print(f"[INFO] Rendering Containerlab topology to {OUTPUT_CLAB_FILE}...")
    render_file(env, "clab_topology.yml.j2", model, OUTPUT_CLAB_FILE)

    # 2. Render Spine configurations
    for spine in model["spines"]:
        spine_dir = os.path.join(CONFIGS_DIR, spine["name"])
        ctx = {"spine": spine, "fabric": model["fabric"], "images": model["images"]}
        render_file(env, "daemons.j2", ctx, os.path.join(spine_dir, "daemons"))
        render_file(env, "frr_spine.conf.j2", ctx, os.path.join(spine_dir, "frr.conf"))
        render_file(env, "spine_setup.sh.j2", ctx, os.path.join(spine_dir, "setup.sh"))
        print(f"[INFO] Generated configs for {spine['name']}")

    # 3. Render Leaf configurations
    for leaf in model["leaves"]:
        leaf_dir = os.path.join(CONFIGS_DIR, leaf["name"])
        hosts_on_leaf = model["hosts_by_leaf"].get(leaf["name"], [])
        ctx = {
            "leaf": leaf,
            "fabric": model["fabric"],
            "images": model["images"],
            "hosts_on_this_leaf": hosts_on_leaf
        }
        render_file(env, "daemons.j2", ctx, os.path.join(leaf_dir, "daemons"))
        render_file(env, "frr_leaf.conf.j2", ctx, os.path.join(leaf_dir, "frr.conf"))
        render_file(env, "leaf_setup.sh.j2", ctx, os.path.join(leaf_dir, "setup.sh"))
        print(f"[INFO] Generated configs for {leaf['name']}")

    # 4. Render Host configurations
    for host in model["hosts"]:
        host_dir = os.path.join(CONFIGS_DIR, host["name"])
        ctx = {"host": host, "fabric": model["fabric"]}
        render_file(env, "host_setup.sh.j2", ctx, os.path.join(host_dir, "setup.sh"))
        print(f"[INFO] Generated configs for {host['name']}")

    print("\n[SUCCESS] All fabric configurations successfully rendered!")


if __name__ == "__main__":
    main()
