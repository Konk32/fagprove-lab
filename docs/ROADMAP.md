# Roadmap

Hva som er bygget, og hva som er neste i kø.

## Fase 1 — Skjelett (DENNE COMMIT-EN)

- [x] Repo-struktur
- [x] config/lab.yml som sentral konfig
- [x] Packer-template (HCL2) for Windows Server 2022 i Workstation
- [x] Ansible-playbook-skjelett (site.yml)
- [x] Ansible-inventory eksempel
- [x] build.ps1 entrypoint
- [x] .gitignore for sensitive filer

## Fase 2 — Faktisk fungerende Packer-build

- [ ] `packer/http/autounattend.xml` — Windows Setup answer-file
- [ ] `packer/scripts/setup-winrm.ps1` — aktiver WinRM under specialize
- [ ] `packer/scripts/install-updates.ps1`
- [ ] `packer/scripts/install-vmware-tools.ps1`
- [ ] `packer/scripts/sysprep.ps1`
- [ ] Test: `packer build .` produserer en bootbar VMX

## Fase 3 — VM-cloning

- [ ] `scripts/clone-vms.ps1` — leser lab.yml, kjører `vmrun clone` per server
- [ ] Per-VM autounattend-injection (unik hostname/IP ved første boot)
- [ ] Test: 3 VM-er bootes med unike hostnames og kommer opp på LAN-segmentet

## Fase 4 — Ansible-roller

- [ ] `ansible/roles/ad-forest` — promoter første DC
- [ ] `ansible/roles/dhcp-server` — opprett DHCP-scope fra lab.yml
- [ ] `ansible/roles/ou-structure` — bygg OU-er rekursivt
- [ ] `ansible/roles/security-groups`
- [ ] `ansible/roles/users-from-config` — opprett brukere fra lab.yml
- [ ] `ansible/roles/gpo-baseline` — NSM-kompatibel passordpolicy
- [ ] Test: `ansible-playbook site.yml` kjører idempotent

## Fase 5 — Robustifisering

- [ ] Idempotenstest: kjør playbook 2x, ingenting endres på andre kjøring
- [ ] Generated inventory fra lab.yml (Python-script)
- [ ] Ansible Vault for passord-håndtering
- [ ] CSV-basert brukeropprettelse for store labs
- [ ] Verifikasjons-playbook (helsesjekk etter build)

## Fase 6 — Differensiering for fagprøven

- [ ] Intern CA via AD Certificate Services
- [ ] WinRM over HTTPS med ekte cert
- [ ] AWX i Docker for self-service deployment
- [ ] Backup-rolle (Windows Server Backup + lagring til pfSense/TrueNAS)
- [ ] Monitoring-hook (Prometheus windows_exporter + Grafana)

## Tanker

- Vi bygger nedenfra og opp. Først får vi ÉN VM bootet automatisk (Fase 2).
- Når det fungerer, klone (Fase 3).
- Når kloning fungerer, Ansible (Fase 4).
- Resten er polish.
