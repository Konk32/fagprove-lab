# Forste Packer-build — walkthrough

Dette er hva du gjor *forste gang* du proverer a bygge basen.

## 1. Last ned Windows Server 2022 ISO

Microsoft Eval Center:
https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022

Velg **ISO downloads → 64-bit edition → English (United States)**.
Du far en filnavn som `SERVER_EVAL_x64FRE_en-us.iso`.

Lagre den et sted med fornuftig sti, f.eks. `C:\iso\windows-server-2022.iso`.

## 2. Beregn SHA256-sum av ISO-en

```powershell
Get-FileHash C:\iso\windows-server-2022.iso -Algorithm SHA256
```

Kopier hash-en. Den skal inn i `variables.auto.pkrvars.hcl`.

## 3. Lag variables.auto.pkrvars.hcl

Kopier eksempelet:

```powershell
cd packer
copy variables.auto.pkrvars.hcl.example variables.auto.pkrvars.hcl
notepad variables.auto.pkrvars.hcl
```

Fyll inn:

```hcl
iso_url      = "C:/iso/windows-server-2022.iso"
iso_checksum = "sha256:DIN_HASH_HER"
winrm_username = "Administrator"
```

**IKKE** legg passord her — settes som env-variabel:

```powershell
$env:PKR_VAR_winrm_password = "Packer2024!"
```

NB: Passordet MA matche `<AdministratorPassword>` i `http/autounattend.xml`.

## 4. Installer Packer hvis du ikke har det

```powershell
choco install packer -y
packer version
```

## 5. Init og validate

```powershell
cd packer
packer init .
packer validate .
```

`init` laster ned vmware-pluginen.
`validate` sjekker at HCL-filen er gyldig — fanger syntax-feil for du sloser tid.

## 6. Forste build (lang!)

```powershell
packer build .
```

**Hva skal du forvente:**

| Tid    | Hva skjer                                         |
|--------|---------------------------------------------------|
| 0:00   | Packer printer "==> vmware-iso.win2022: ..."      |
| 0:05   | VMware Workstation apnes med ny VM                |
| 0:08   | "Press any key to boot from CD" — Packer sender mellomrom |
| 0:10   | Windows Setup starter (bla bakgrunn)              |
| 5:00   | Forste reboot, Windows logger inn som Administrator |
| 5:30   | setup-winrm.ps1 kjorer i terminal-vindu pa VM     |
| 6:00   | Packer rapporterer "Connected to WinRM"           |
| 6:30   | install-updates.ps1 starter                       |
| 30-60  | Windows Update kjorer (variabel)                  |
| ~70    | install-vmware-tools.ps1                          |
| ~75    | sysprep.ps1 kjorer                                |
| ~76    | VM slas av, Packer ferdig                         |

Output: `packer/output/win2022-base/win2022-base.vmx`

## Det forste som typisk feiler

### "Waiting for WinRM..." timer ut

Vanligvis fordi:
1. setup-winrm.ps1 feilet — apne VM-konsollen og se loggen
2. Brannmuren blokkerer fortsatt — sjekk `Get-NetFirewallRule -DisplayGroup "Windows Remote Management"`
3. Nettverksprofilen er Public istedenfor Private

Fix: Apne VM-konsollen, logg inn som Administrator (passord: `Lab123`)
og se `C:\Windows\Temp\setup-winrm.log`.

### Boot-loop pa "Press any key..."

Hvis Packer sender mellomrom for sent kommer du forbi prompten. Hvis for raskt
har VM-en ikke kommet dit enda. Juster `boot_wait` i `.pkr.hcl`:

```hcl
boot_wait = "15s"   # eller 5s, prov begge retninger
```

### "Cannot find ISO at path..."

Stien i `iso_url` ma vaere absolutt og bruke FORWARD slash:
```hcl
iso_url = "C:/iso/windows-server-2022.iso"
```
IKKE backslash, IKKE relativ sti.

### Windows Update tar 4 timer

Det er normalt for ferst Server 2022 ISO. Etter forste build kan du
disable update-steget for raskere iterasjon — bare commit ut provisioneren.

## Etter vellykket build

VM-en er slatt av. **IKKE start den manuelt.** Hvis du gjor det aktiveres
sysprep og du mister generalisering. Hvis du ved et uhell starter den —
tom output-folderen og kjor `packer build .` igjen.

Neste fase (Fase 3): vmrun cloning av basen til DC01, FS01 osv.
