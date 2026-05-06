# Roadmap

What is built and what is planned next.

## Phase 1 - Skeleton

- [x] Repo-struktur
- [x] config/lab.yml som sentral konfig
- [x] Packer-template (HCL2) for Windows Server 2022 i Workstation
- [x] Ansible-playbook-skjelett (site.yml)
- [x] Ansible-inventory eksempel
- [x] build.ps1 entrypoint
- [x] .gitignore for sensitive filer

## Phase 2 - Working Packer build

- [ ] `packer/http/autounattend.xml` - Windows Setup answer-file
- [ ] `packer/scripts/setup-winrm.ps1` - enable WinRM during specialize
- [ ] `packer/scripts/install-updates.ps1`
- [ ] `packer/scripts/install-vmware-tools.ps1`
- [ ] `packer/scripts/sysprep.ps1`
- [ ] Test: `packer build .` produces a bootable VMX

## Phase 3 - VM cloning

- [ ] `scripts/clone-vms.ps1` - read `lab.yml`, run `vmrun clone` per server
- [ ] Per-VM unattend injection (unique hostname/IP at first boot)
- [ ] Test: 3 VMs boot with unique hostnames and join the LAN segment

## Phase 4 - Ansible roles

- [ ] `ansible/roles/ad-forest` - promote first DC
- [ ] `ansible/roles/dhcp-server` - create DHCP scope from `lab.yml`
- [ ] `ansible/roles/ou-structure` - build OUs recursively
- [ ] `ansible/roles/security-groups`
- [ ] `ansible/roles/users-from-config` - create users from `lab.yml`
- [ ] `ansible/roles/gpo-baseline` - baseline password policy
- [ ] Test: `ansible-playbook site.yml` runs idempotently

## Phase 5 - Hardening and reliability

- [ ] Idempotency test: run playbook twice with no changes on second run
- [ ] Generated inventory from `lab.yml` (Python script)
- [ ] Ansible Vault for password handling
- [ ] CSV-based user creation for larger labs
- [ ] Verification playbook for post-build health checks

## Phase 6 - Advanced features

- [ ] Internal CA with AD Certificate Services
- [ ] WinRM over HTTPS with valid certificates
- [ ] AWX in Docker for self-service deployment
- [ ] Backup role (Windows Server Backup + storage on pfSense/TrueNAS)
- [ ] Monitoring integration (Prometheus windows_exporter + Grafana)

## Approach

- Build bottom-up: image first, cloning second, configuration third.
- Keep each phase independently testable.
