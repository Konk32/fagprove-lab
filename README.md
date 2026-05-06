# fagprove-lab

Reproducible Windows Server lab environment for exam preparation.

## What this repository does

Given one config file (`config/lab.yml`), the repository can:

1. Build a reusable Windows Server 2022 base image with Packer.
2. Clone lab VMs from that base image in VMware Workstation.
3. Configure the environment with Ansible (AD, DHCP, users, groups, and baseline policies).

## Deployment flow

This is the canonical flow used by this project:

1. Fill out `config/lab.yml`.
2. Generate inventory from config.
3. Build the Windows base image.
4. Run the full Ansible deployment.

Use the commands below from the repository root unless stated otherwise.

### 1) Configure lab settings

Edit:

- `config/lab.yml`
- `packer/variables.auto.pkrvars.hcl` (create from `.example` if missing)

### 2) Generate Ansible inventory

```bash
python scripts/generate-inventory.py
```

### 3) Build the Windows image and clone VMs

```powershell
.\scripts\build.ps1 -SkipAnsible
```

### 4) Run Ansible

Run from WSL (or another Linux environment with Ansible installed):

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml
```

### 5) Verify deployment

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/verify.yml
```

## Prerequisites

- Windows host with VMware Workstation Pro
- Packer
- Python 3 with `PyYAML`
- WSL2 (or Linux) with Ansible
- Windows Server 2022 ISO

## Notes

- Network setup guidance is documented in `docs/network-setup.md`.
- The all-in-one script `scripts/build.ps1` is useful for local iteration, but the documented flow above is the source of truth for publication.

## License

DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
