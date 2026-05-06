# Clone a sysprepped Windows base image to VMs defined in config/lab.yml.

[CmdletBinding()]
param(
    [string]$Config       = "$PSScriptRoot\..\config\lab.yml",
    [string]$BaseVmx      = "$PSScriptRoot\..\packer\win2022-base-final\win2022-base.vmx",
    [string]$VmRootDir    = "$PSScriptRoot\..\vms",
    [switch]$Force,
    [switch]$SkipStart
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Get-LabConfig {
    param([string]$YamlPath)
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-Host "[INFO] Installing powershell-yaml module..."
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber
    }
    Import-Module powershell-yaml
    $content = Get-Content -Path $YamlPath -Raw
    return ConvertFrom-Yaml $content
}

function Get-CidrPrefix {
    param([string]$Subnet)
    return [int]($Subnet -split "/")[1]
}

function Find-Vmrun {
    $candidates = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    throw "Could not find vmrun.exe. Is VMware Workstation installed?"
}

Write-Section "Pre-flight checks"

if (-not (Test-Path $BaseVmx)) {
    Write-Host "[ERROR] Base image not found: $BaseVmx" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Base-image: $BaseVmx" -ForegroundColor Green

$vmrun = Find-Vmrun
Write-Host "[OK] vmrun: $vmrun" -ForegroundColor Green

# Resolve absolute path FOR loop (unngar relative-path bugs)
$VmRootDir = (Resolve-Path -Path $VmRootDir -ErrorAction SilentlyContinue)
if (-not $VmRootDir) {
    $VmRootDir = "$PSScriptRoot\..\vms"
    New-Item -Path $VmRootDir -ItemType Directory -Force | Out-Null
    $VmRootDir = (Resolve-Path -Path $VmRootDir).Path
}
Write-Host "[OK] VM root directory: $VmRootDir" -ForegroundColor Green

Write-Section "Reading configuration"
$lab = Get-LabConfig -YamlPath $Config
Write-Host "Domain:      $($lab.domain.fqdn)"
Write-Host "Network:     $($lab.network.subnet) ($($lab.network.lan_segment))"
Write-Host "Servers:     $($lab.servers.Count)"
$lab.servers | ForEach-Object { Write-Host "  - $($_.hostname) @ $($_.ip)" }

$unattendTemplate = "$PSScriptRoot\..\templates\clone-unattend.xml.template"
$winrmBat         = "$PSScriptRoot\..\packer\http\winrmConfig.bat"

if (-not (Test-Path $unattendTemplate)) {
    throw "Missing unattend template: $unattendTemplate"
}
if (-not (Test-Path $winrmBat)) {
    throw "Missing winrmConfig.bat: $winrmBat"
}

$prefix       = Get-CidrPrefix -Subnet $lab.network.subnet
$gateway      = $lab.network.gateway
$dnsServer    = ($lab.servers | Where-Object { $_.roles -contains "domain-controller" } | Select-Object -First 1).ip
$adminPass    = $lab.local_admin.password
$lanSegment   = $lab.network.lan_segment

Write-Host ""
Write-Host "DNS server (DC):    $dnsServer"
Write-Host "Subnet prefix:      /$prefix"
Write-Host "Gateway:            $gateway"
Write-Host "LAN segment:        $lanSegment"

foreach ($server in $lab.servers) {
    $hostname     = $server.hostname
    $ip           = $server.ip
    $serverDir    = Join-Path $VmRootDir $hostname
    $vmxPath      = Join-Path $serverDir "$hostname.vmx"

    Write-Section "Cloning $hostname ($ip)"
    Write-Host "Server directory: $serverDir"

    if (Test-Path $serverDir) {
        if ($Force) {
            Write-Host "[INFO] Removing existing clone: $serverDir" -ForegroundColor Yellow
            & $vmrun -T ws stop $vmxPath hard 2>$null
            Start-Sleep -Seconds 2
            Remove-Item -Path $serverDir -Recurse -Force
        } else {
            Write-Host "[SKIP] $hostname already exists. Use -Force to overwrite." -ForegroundColor Yellow
            continue
        }
    }

    Write-Host "[STEP 1/4] Cloning base image to $vmxPath..."
    & $vmrun -T ws clone $BaseVmx $vmxPath full -cloneName=$hostname
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Clone failed" -ForegroundColor Red
        continue
    }

    Write-Host "[STEP 2/4] Generating unattend.xml..."
    $template = Get-Content -Path $unattendTemplate -Raw
    $unattend = $template `
        -replace '\{\{HOSTNAME\}\}',       $hostname `
        -replace '\{\{IP_ADDRESS\}\}',     $ip `
        -replace '\{\{SUBNET_PREFIX\}\}',  $prefix `
        -replace '\{\{GATEWAY\}\}',        $gateway `
        -replace '\{\{DNS_SERVER\}\}',     $dnsServer `
        -replace '\{\{ADMIN_PASSWORD\}\}', $adminPass

    $stagingDir = Join-Path $serverDir "_floppy"
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

    # Write UTF-8 without BOM for Windows Setup compatibility.
    $unattendPath = Join-Path $stagingDir "unattend.xml"
    [System.IO.File]::WriteAllText($unattendPath, $unattend, (New-Object System.Text.UTF8Encoding $false))

    Copy-Item -Path $winrmBat -Destination (Join-Path $stagingDir "winrmConfig.bat")

    Write-Host "[STEP 3/4] Building floppy image..."
    $floppyPath = Join-Path $serverDir "config.flp"
    & "$PSScriptRoot\make-floppy.ps1" -SourceDir $stagingDir -OutputPath $floppyPath
    if (-not (Test-Path $floppyPath)) {
        Write-Host "[ERROR] Could not build floppy image" -ForegroundColor Red
        continue
    }

    Write-Host "[STEP 3.5/4] Verifying floppy contains unattend.xml..."
    $wslFloppyPath = ($floppyPath -replace '\\', '/' -replace '^C:', '/mnt/c')
    $floppyContents = wsl mdir -i $wslFloppyPath :: 2>&1 | Out-String
    if ($floppyContents -match "UNATTEND") {
        Write-Host "[OK] Floppy contains unattend.xml" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Floppy is missing unattend.xml!" -ForegroundColor Red
        Write-Host $floppyContents
        Write-Host "Aborting for $hostname"
        continue
    }

    Write-Host "[STEP 4/4] Updating .vmx..."

    $vmxContent = Get-Content -Path $vmxPath
    $vmxContent = $vmxContent | Where-Object {
        $_ -notmatch '^floppy0\.' -and
        $_ -notmatch '^ethernet0\.connectionType' -and
        $_ -notmatch '^ethernet0\.vnet' -and
        $_ -notmatch '^ethernet0\.networkName' -and
        $_ -notmatch '^numvcpus' -and
        $_ -notmatch '^memsize' -and
        $_ -notmatch '^displayName'
    }

    $relFloppy = "config.flp"
    $newLines = @(
        "displayName = `"$hostname`"",
        "numvcpus = `"$($server.cpus)`"",
        "memsize = `"$($server.memory_mb)`"",
        "floppy0.present = `"TRUE`"",
        "floppy0.fileType = `"file`"",
        "floppy0.fileName = `"$relFloppy`"",
        "floppy0.startConnected = `"TRUE`"",
        "ethernet0.connectionType = `"custom`"",
        "ethernet0.vnet = `"$lanSegment`""
    )

    ($vmxContent + $newLines) | Set-Content -Path $vmxPath

    Write-Host "[OK] $hostname ready" -ForegroundColor Green

    if (-not $SkipStart) {
        Write-Host "[STEP 5/5] Starting $hostname..."
        & $vmrun -T ws start $vmxPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $hostname started" -ForegroundColor Green
        }
    }
}

Write-Section "Cloning complete"
Write-Host "Wait ~5-10 minutes while clones complete the specialize phase."
Write-Host ""
Write-Host "Check progress with:"
Write-Host "   Test-NetConnection -ComputerName $dnsServer -Port 5985"
