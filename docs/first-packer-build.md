# First Packer Build

Use this guide for the initial base-image build.

## 1) Download Windows Server 2022 ISO

Download from Microsoft Eval Center:
[https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022](https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022)

## 2) Compute SHA256

```powershell
Get-FileHash "<path-to-iso>" -Algorithm SHA256
```

## 3) Create Packer variables file

```powershell
cd packer
copy variables.auto.pkrvars.hcl.example variables.auto.pkrvars.hcl
```

Set required values, for example:

```hcl
iso_url        = "C:/iso/windows-server-2022.iso"
iso_checksum   = "sha256:<your-sha256>"
winrm_username = "Administrator"
```

Set password as environment variable:

```powershell
$env:PKR_VAR_winrm_password = "<password>"
```

## 4) Initialize and validate

```powershell
cd packer
packer init .
packer validate .
```

## 5) Run first build

```powershell
packer build .
```

The first build can take a long time depending on updates and host performance.

## Common failures

### `Waiting for WinRM...` timeout

- Check VM console logs and `C:\Windows\Temp\setup-winrm.log`.
- Ensure WinRM firewall rules are enabled.
- Ensure the VM network profile is not blocking remoting.

### ISO path errors

Use an absolute path with forward slashes in `iso_url`.

### Build accidentally booted after sysprep

If the resulting base VM was started manually, rebuild the image from scratch.
