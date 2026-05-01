# fagprove-lab

Reproduserbart Windows Server-lab for fagprøveforberedelse. Én config-fil
inn, ferdig oppsatt domene-miljø ut.

## Hva dette gjør

Tar en YAML-fil med ønsket miljø (domene, servere, DHCP-scope, brukere)
og bygger hele infrastrukturen i VMware Workstation Pro:

1. **Packer** bygger en gylden Windows Server 2022-image
2. **vmrun** kloner basen til N servere/klienter
3. **Ansible** konfigurerer AD, DHCP, GPO, OU-struktur og brukere

Total tid fra `build.ps1` til ferdig miljø: ~30 minutter
(etter førstegangs Packer-build på ~60 min).

## Hvorfor

Fagprøvedemo er sårbar for menneskelige feil: VM-klokker som driver,
sertifikater som mangler, hjemmeområder med ÆØÅ i pathen, kontoer
opprettet inkonsistent mellom dokumentasjon og demo.

Dette repoet gjør miljøet til kode. Riv det ned, bygg det opp på 30 min,
samme resultat hver gang.

## Forutsetninger

- Windows 10/11 host
- VMware Workstation Pro 17+
- Packer 1.10+ (`choco install packer`)
- Ansible på WSL2 (Ubuntu/Fedora)
- Windows Server 2022 ISO (Eval fra Microsoft)
- Minimum 32 GB RAM på hosten for et realistisk lab

## Kom i gang

```powershell
# 1. Klon
git clone https://github.com/Konk32/fagprove-lab.git
cd fagprove-lab

# 2. Tilpass miljøet
notepad config\lab.yml

# 3. Bygg
.\scripts\build.ps1
```

## Status

Tidlig fase. Se `docs/ROADMAP.md` for hva som er på vei.

## Lisens

DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
