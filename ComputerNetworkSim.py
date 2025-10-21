#!/usr/bin/env python3
"""
generate_structured_network_notes.py

Generates a random computer network and creates one Markdown file per node,
organized into category folders inside your Obsidian vault:

    Network/
    ├── Router/
    ├── Connectors/
    └── Devices/

Each Markdown file contains:
- Device type and timestamp
- Linked connections to other nodes
- A small Mermaid diagram showing direct connections

Usage:
    python generate_structured_network_notes.py /path/to/ObsidianVault
"""

import os
import sys
import random
from datetime import datetime

# ---------------- Configuration ----------------
END_DEVICE_TYPES = ["Laptop", "Desktop", "Smartphone", "Printer", "Tablet", "SmartTV", "Camera"]
CONNECTOR_TYPES = ["Switch", "Hub", "Extender"]
ROUTER_TYPE = "Router"
# ------------------------------------------------


def generate_network():
    """Generate a random realistic network with categories and readable names."""
    num_devices = random.randint(5, 100)
    num_connectors = random.randint(1, 25)

    # Router
    router = {"name": ROUTER_TYPE, "type": "Router", "category": "Router"}

    # Connectors
    connectors = [
        {
            "name": f"{ctype} {i}",
            "type": ctype,
            "category": "Connectors"
        }
        for i, ctype in enumerate(random.choices(CONNECTOR_TYPES, k=num_connectors), 1)
    ]

    # End devices
    devices = [
        {
            "name": f"{dtype} {i}",
            "type": dtype,
            "category": "Devices"
        }
        for i, dtype in enumerate(random.choices(END_DEVICE_TYPES, k=num_devices), 1)
    ]

    all_nodes = [router] + connectors + devices
    connections = {n["name"]: set() for n in all_nodes}

    # Router connects to some connectors (or devices if none)
    first_targets = connectors if connectors else devices
    for target in random.sample(first_targets, k=min(len(first_targets), random.randint(1, 5))):
        connections[router["name"]].add(target["name"])
        connections[target["name"]].add(router["name"])

    # Connect connectors among each other randomly
    for c in connectors:
        others = [x for x in connectors if x != c]
        for o in random.sample(others, k=min(len(others), random.randint(0, 3))):
            connections[c["name"]].add(o["name"])
            connections[o["name"]].add(c["name"])

    # Connect devices to connectors (or router if none)
    for d in devices:
        target = random.choice(connectors) if connectors else router
        connections[d["name"]].add(target["name"])
        connections[target["name"]].add(d["name"])

    return all_nodes, connections


def make_mermaid_snippet(node_name, connections):
    """Create a small Mermaid graph for local connections."""
    lines = ["```mermaid", "graph LR"]
    lines.append(f'    "{node_name}"')
    for peer in connections:
        lines.append(f'    "{node_name}" --> "{peer}"')
    lines.append("```")
    return "\n".join(lines)


def write_node_files(vault_path, nodes, connections):
    """Write Markdown files organized into category folders."""
    base_dir = os.path.join(vault_path, "Network")
    router_dir = os.path.join(base_dir, "Router")
    connectors_dir = os.path.join(base_dir, "Connectors")
    devices_dir = os.path.join(base_dir, "Devices")

    for d in (base_dir, router_dir, connectors_dir, devices_dir):
        os.makedirs(d, exist_ok=True)

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    for node in nodes:
        name = node["name"]
        node_type = node["type"]
        category = node["category"]
        peers = sorted(connections[name])

        mermaid_block = make_mermaid_snippet(name, peers)
        peer_links = "\n".join(f"- [[{p}]]" for p in peers) if peers else "*(No direct connections)*"

        content = f"""# {name}
*Type:* **{node_type}**  
*Category:* **{category}**  

## Connections
{peer_links}

## Local Topology
{mermaid_block}
"""

        # Choose correct folder
        if category == "Router":
            folder = router_dir
        elif category == "Connectors":
            folder = connectors_dir
        else:
            folder = devices_dir

        file_path = os.path.join(folder, f"{name}.md")
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)

    print(f"✅ Created {len(nodes)} node files organized into:")
    print(f"   {router_dir}\n   {connectors_dir}\n   {devices_dir}")


def main():
    if len(sys.argv) != 2:
        print("Usage: python generate_structured_network_notes.py /path/to/ObsidianVault")
        sys.exit(1)

    vault_path = os.path.abspath(sys.argv[1])
    if not os.path.isdir(vault_path):
        print("Error: The provided path is not a valid directory.")
        sys.exit(1)

    nodes, connections = generate_network()
    write_node_files(vault_path, nodes, connections)


if __name__ == "__main__":
    main()
