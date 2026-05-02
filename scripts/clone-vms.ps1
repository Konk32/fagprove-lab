# =============================================================================
# clone-vms.ps1
# =============================================================================
# Kloner sysprep'd Windows-base til N VM-er definert i config/lab.yml.
# =============================================================================

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
        Write-Host "[INFO] Installerer powershell-yaml-modul..."
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
    throw "Kunne ikke finne vmrun.exe. Er VMware Workstation installert?"
}

# -----------------------------------------------------------------------------
# Pre-flight
# -----------------------------------------------------------------------------
Write-Section "Pre-flight checks"

if (-not (Test-Path $BaseVmx)) {
    Write-Host "[FEIL] Base-image ikke funnet: $BaseVmx" -ForegroundColor Red
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
Write-Host "[OK] VM-rotmappe: $VmRootDir" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Les lab-konfig
# -----------------------------------------------------------------------------
Write-Section "Leser konfigurasjon"
$lab = Get-LabConfig -YamlPath $Config
Write-Host "Domene:      $($lab.domain.fqdn)"
Write-Host "Nettverk:    $($lab.network.subnet) ($($lab.network.lan_segment))"
Write-Host "Servere:     $($lab.servers.Count) stk"
$lab.servers | ForEach-Object { Write-Host "  - $($_.hostname) @ $($_.ip)" }

$unattendTemplate = "$PSScriptRoot\..\templates\clone-unattend.xml.template"
$winrmBat         = "$PSScriptRoot\..\packer\http\winrmConfig.bat"

if (-not (Test-Path $unattendTemplate)) {
    throw "Mangler unattend-template: $unattendTemplate"
}
if (-not (Test-Path $winrmBat)) {
    throw "Mangler winrmConfig.bat: $winrmBat"
}

$prefix       = Get-CidrPrefix -Subnet $lab.network.subnet
$gateway      = $lab.network.gateway
$dnsServer    = ($lab.servers | Where-Object { $_.roles -contains "domain-controller" } | Select-Object -First 1).ip
$adminPass    = $lab.local_admin.password
$lanSegment   = $lab.network.lan_segment

Write-Host ""
Write-Host "DNS-server (DC):    $dnsServer"
Write-Host "Subnet prefix:      /$prefix"
Write-Host "Gateway:            $gateway"
Write-Host "LAN segment:        $lanSegment"

# -----------------------------------------------------------------------------
# Klone for hver server
# -----------------------------------------------------------------------------
foreach ($server in $lab.servers) {
    $hostname     = $server.hostname
    $ip           = $server.ip
    # FIX: bruk $serverDir istedenfor $vmDir (kollisjon med ytre scope)
    $serverDir    = Join-Path $VmRootDir $hostname
    $vmxPath      = Join-Path $serverDir "$hostname.vmx"

    Write-Section "Kloner $hostname ($ip)"
    Write-Host "Server-mappe: $serverDir"

    # Ryd opp eksisterende klone hvis -Force
    if (Test-Path $serverDir) {
        if ($Force) {
            Write-Host "[INFO] Sletter eksisterende: $serverDir" -ForegroundColor Yellow
            & $vmrun -T ws stop $vmxPath hard 2>$null
            Start-Sleep -Seconds 2
            Remove-Item -Path $serverDir -Recurse -Force
        } else {
            Write-Host "[SKIP] $hostname finnes allerede. Bruk -Force for a overskrive." -ForegroundColor Yellow
            continue
        }
    }

    # Steg 1: vmrun clone
    Write-Host "[STEG 1/4] Kloner base til $vmxPath..."
    & $vmrun -T ws clone $BaseVmx $vmxPath full -cloneName=$hostname
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FEIL] Cloning feilet" -ForegroundColor Red
        continue
    }

    # Steg 2: Generer per-VM unattend.xml
    Write-Host "[STEG 2/4] Genererer unattend.xml..."
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

    # Skriv unattend som UTF-8 UTEN BOM (Windows Setup er kresen)
    $unattendPath = Join-Path $stagingDir "unattend.xml"
    [System.IO.File]::WriteAllText($unattendPath, $unattend, (New-Object System.Text.UTF8Encoding $false))

    Copy-Item -Path $winrmBat -Destination (Join-Path $stagingDir "winrmConfig.bat")

    # Steg 3: Lag floppy-image
    Write-Host "[STEG 3/4] Bygger floppy-image..."
    $floppyPath = Join-Path $serverDir "config.flp"
    & "$PSScriptRoot\make-floppy.ps1" -SourceDir $stagingDir -OutputPath $floppyPath
    if (-not (Test-Path $floppyPath)) {
        Write-Host "[FEIL] Kunne ikke lage floppy" -ForegroundColor Red
        continue
    }

    # Verifiser at floppy faktisk inneholder filene
    Write-Host "[STEG 3.5/4] Verifiserer at floppy inneholder unattend.xml..."
    $wslFloppyPath = ($floppyPath -replace '\\', '/' -replace '^C:', '/mnt/c')
    $floppyContents = wsl mdir -i $wslFloppyPath :: 2>&1 | Out-String
    if ($floppyContents -match "UNATTEND") {
        Write-Host "[OK] Floppy inneholder unattend.xml" -ForegroundColor Green
    } else {
        Write-Host "[FEIL] Floppy mangler unattend.xml!" -ForegroundColor Red
        Write-Host $floppyContents
        Write-Host "Aborterer for $hostname"
        continue
    }

    # Steg 4: Modifiser .vmx
    Write-Host "[STEG 4/4] Modifiserer .vmx..."

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

    Write-Host "[OK] $hostname klar" -ForegroundColor Green

    if (-not $SkipStart) {
        Write-Host "[STEG 5/5] Starter $hostname..."
        & $vmrun -T ws start $vmxPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $hostname startet" -ForegroundColor Green
        }
    }
}

Write-Section "Cloning ferdig"
Write-Host "Vent ~5-10 min mens klonene fullforer specialize-pass."
Write-Host ""
Write-Host "Sjekk fremgang med:"
Write-Host "   Test-NetConnection -ComputerName $dnsServer -Port 5985"
