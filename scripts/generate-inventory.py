#!/usr/bin/env python3
"""
generate-inventory.py — Lab.yml til Ansible-inventory

Leser config/lab.yml og produserer ansible/inventory/hosts.yml med
riktige host-grupper basert pa 'roles' i hver server.

Kjor med:
    python3 scripts/generate-inventory.py

Output: ansible/inventory/hosts.yml (overskriver eksisterende)
"""

import yaml
from pathlib import Path
import sys

# -----------------------------------------------------------------------------
# Stier
# -----------------------------------------------------------------------------
ROOT = Path(__file__).parent.parent
LAB_CONFIG = ROOT / "config" / "lab.yml"
OUTPUT = ROOT / "ansible" / "inventory" / "hosts.yml"


def load_lab() -> dict:
    """Leser lab.yml inn som dict."""
    if not LAB_CONFIG.exists():
        print(f"FEIL: {LAB_CONFIG} mangler", file=sys.stderr)
        sys.exit(1)
    with open(LAB_CONFIG, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def build_inventory(lab: dict) -> dict:
    """
    Bygger Ansible-inventory-struktur fra lab-config.

    Mapping av roller -> Ansible-grupper:
        domain-controller  -> domain_controllers
        domain-member      -> member_servers
        dhcp-server        -> dhcp_servers
        file-server        -> file_servers
    """

    role_to_group = {
        "domain-controller": "domain_controllers",
        "domain-member":     "member_servers",
        "dhcp-server":       "dhcp_servers",
        "file-server":       "file_servers",
    }

    # Initialiser tomme grupper
    groups = {grp: {"hosts": {}} for grp in role_to_group.values()}

    # Felles vars for alle Windows-hosts
    windows_vars = {
        "ansible_connection":               "winrm",
        "ansible_winrm_transport":          "basic",
        "ansible_winrm_server_cert_validation": "ignore",
        "ansible_port":                     5985,
        "ansible_user":                     lab["local_admin"]["username"],
        # NB: passordet hentes fra ansible-vault i produksjon.
        # For lab-bruk hardkoder vi referansen til en variabel.
        "ansible_password":                 "{{ vault_admin_password }}",
    }

    # Per host: fyll inn IP og legg i riktige grupper
    for server in lab["servers"]:
        hostname = server["hostname"].lower()
        host_entry = {
            "ansible_host": server["ip"],
        }

        # Server-roller -> Ansible groups
        for role in server.get("roles", []):
            grp = role_to_group.get(role)
            if grp:
                groups[grp]["hosts"][hostname] = host_entry

    # Bygg endelig struktur
    inventory = {
        "all": {
            "children": {
                "windows": {
                    "vars": windows_vars,
                    "children": {grp: groups[grp] for grp in groups if groups[grp]["hosts"]},
                }
            }
        }
    }

    return inventory


def main():
    lab = load_lab()
    inventory = build_inventory(lab)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write("---\n")
        f.write("# AUTO-GENERERT av scripts/generate-inventory.py\n")
        f.write("# Ikke rediger direkte — endre config/lab.yml og kjor scriptet pa nytt.\n\n")
        yaml.dump(inventory, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"OK: Skrev inventory til {OUTPUT}")
    print(f"    Servere: {len(lab['servers'])}")
    for s in lab["servers"]:
        print(f"      - {s['hostname']} ({s['ip']}) -> {', '.join(s.get('roles', []))}")


if __name__ == "__main__":
    main()
