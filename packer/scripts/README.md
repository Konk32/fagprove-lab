# packer/scripts/

PowerShell-scripts som kjorer pa Windows-VM-en under Packer-builden.

Skal innholde i Fase 2:
- `setup-winrm.ps1` — aktiverer WinRM under autounattend specialize-fasen
- `install-updates.ps1` — kjorer Windows Update til alt er ferskt
- `install-vmware-tools.ps1` — installer VMware Tools (matter for IP-pickup)
- `sysprep.ps1` — generaliser imaget for cloning

Hver fil far et ansvar og kommenteres tett. Sammen produserer de en image som:
- Er fullt patchet
- Har VMware Tools installert
- Er sysprep'et og klar til kloning
- Har WinRM ferdig konfigurert i imaget (slik at klonene "bare funker")
