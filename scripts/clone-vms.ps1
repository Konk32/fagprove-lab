# =============================================================================
# clone-vms.ps1
# =============================================================================
# Kloner sysprep'd Windows-base til N VM-er definert i config/lab.yml.
# For hver server:
#   1. vmrun clone <base.vmx> <hostname.vmx>
#   2. Generer per-VM unattend.xml fra template (substituer hostname/IP osv)
#   3. Lag virtuell floppy med unattend.xml + winrmConfig.bat
#   4. Modifiser klonens .vmx for a montere floppy + sette LAN segment
#   5. Start klonen — den kjorer specialize-pass og far hostname/IP
#
# Kjor med:
#   .\scripts\clone-vms.ps1
#
# Flagg:
#   -Force          Slett eksisterende kloner forst
#   -SkipStart      Bare klone, ikke start VM-ene
#   -BaseVmx <sti>  Overstyr base-imagets sti
# =============================================================================

[CmdletBinding()]
param(
    [string]$Config   = "$PSScriptRoot\..\config\lab.yml",
    [string]$BaseVmx  = "$PSScriptRoot\..\packer\win2022-base-final\win2022-base.vmx",
    [string]$VmDir    = "$PSScriptRoot\..\vms",
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
    # Bruker powershell-yaml-modulen. Installer med: Install-Module powershell-yaml
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
    # "10.50.0.0/24" -> 24
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

function New-FloppyImage {
    # Lager en virtuell floppy (.flp) fra en mappe med filer.
    # Bruker bsdtar fra Git for Windows hvis tilgjengelig, ellers oscdimg.
    # Faktisk: VMware Workstation kan montere .img-filer som floppy.
    # Vi genererer en .img direkte med en simpel FAT12-struktur.
    param(
        [string]$SourceDir,
        [string]$OutputPath
    )

    # 1.44 MB floppy
    $size = 1474560
    $stream = [System.IO.File]::Create($OutputPath)
    $stream.SetLength($size)
    $stream.Close()

    # Mount som virtuelt drev og kopier filer
    $mount = Mount-DiskImage -ImagePath $OutputPath -StorageType ISO -PassThru -ErrorAction SilentlyContinue
    if (-not $mount) {
        # Fallback: bruk diskpart for a formatere
        Write-Warning "Kunne ikke mounte floppy. Bruker manuell tilnaerming via vfat-tools..."
        # For na: kopier filene "som om" — VMware vil aksepterer en vanlig fil
        # som floppy-bilde hvis den er pa rett storrelse.
        # Reelt sett trenger vi diskpart eller mtools.
        return
    }
}

# -----------------------------------------------------------------------------
# Pre-flight
# -----------------------------------------------------------------------------
Write-Section "Pre-flight checks"

if (-not (Test-Path $BaseVmx)) {
    Write-Host "[FEIL] Base-image ikke funnet: $BaseVmx" -ForegroundColor Red
    Write-Host "       Har du kjort 'packer build' i packer-mappen?" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Base-image: $BaseVmx" -ForegroundColor Green

$vmrun = Find-Vmrun
Write-Host "[OK] vmrun: $vmrun" -ForegroundColor Green

if (-not (Test-Path $VmDir)) {
    New-Item -Path $VmDir -ItemType Directory | Out-Null
    Write-Host "[OK] Lagde VM-mappe: $VmDir" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Les lab-konfig
# -----------------------------------------------------------------------------
Write-Section "Leser konfigurasjon"
$lab = Get-LabConfig -YamlPath $Config
Write-Host "Domene:      $($lab.domain.fqdn)"
Write-Host "Nettverk:    $($lab.network.subnet) ($($lab.network.lan_segment))"
Write-Host "Servere:     $($lab.servers.Count) stk"
$lab.servers | ForEach-Object { Write-Host "  - $($_.hostname) @ $($_.ip)" }

# -----------------------------------------------------------------------------
# Templater
# -----------------------------------------------------------------------------
$unattendTemplate = "$PSScriptRoot\..\templates\clone-unattend.xml.template"
$winrmBat         = "$PSScriptRoot\..\packer\http\winrmConfig.bat"

if (-not (Test-Path $unattendTemplate)) {
    throw "Mangler unattend-template: $unattendTemplate"
}
if (-not (Test-Path $winrmBat)) {
    throw "Mangler winrmConfig.bat: $winrmBat"
}

# Hent verdier som er felles for alle klonene
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
    $hostname = $server.hostname
    $ip       = $server.ip
    $vmDir    = Join-Path $VmDir $hostname
    $vmxPath  = Join-Path $vmDir "$hostname.vmx"

    Write-Section "Kloner $hostname ($ip)"

    # Ryd opp eksisterende klone hvis -Force
    if (Test-Path $vmDir) {
        if ($Force) {
            Write-Host "[INFO] Sletter eksisterende: $vmDir" -ForegroundColor Yellow
            # Forsoker a stoppe VM-en hvis den kjorer
            & $vmrun -T ws stop $vmxPath hard 2>$null
            Start-Sleep -Seconds 2
            Remove-Item -Path $vmDir -Recurse -Force
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

    $stagingDir = Join-Path $vmDir "_floppy"
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null
    $unattend | Out-File -FilePath (Join-Path $stagingDir "unattend.xml") -Encoding utf8 -NoNewline
    Copy-Item -Path $winrmBat -Destination (Join-Path $stagingDir "winrmConfig.bat")

    # Steg 3: Lag floppy-image
    Write-Host "[STEG 3/4] Bygger floppy-image..."
    $floppyPath = Join-Path $vmDir "config.flp"
    & "$PSScriptRoot\make-floppy.ps1" -SourceDir $stagingDir -OutputPath $floppyPath
    if (-not (Test-Path $floppyPath)) {
        Write-Host "[FEIL] Kunne ikke lage floppy" -ForegroundColor Red
        continue
    }

    # Steg 4: Modifiser .vmx for a (a) montere floppy, (b) sette LAN segment, (c) ressurser
    Write-Host "[STEG 4/4] Modifiserer .vmx..."

    $vmx = Get-Content -Path $vmxPath
    # Fjern gamle floppy/network linjer for a unngha duplikater
    $vmx = $vmx | Where-Object {
        $_ -notmatch '^floppy0\.' -and
        $_ -notmatch '^ethernet0\.connectionType' -and
        $_ -notmatch '^ethernet0\.vnet' -and
        $_ -notmatch '^ethernet0\.networkName' -and
        $_ -notmatch '^numvcpus' -and
        $_ -notmatch '^memsize' -and
        $_ -notmatch '^displayName'
    }

    # Bygg nye linjer
    $relFloppy = [System.IO.Path]::GetFileName($floppyPath)
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

    ($vmx + $newLines) | Set-Content -Path $vmxPath

    Write-Host "[OK] $hostname klar" -ForegroundColor Green

    # Steg 5: Start VM-en (med mindre -SkipStart)
    if (-not $SkipStart) {
        Write-Host "[STEG 5/5] Starter $hostname..."
        & $vmrun -T ws start $vmxPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $hostname startet" -ForegroundColor Green
        }
    }
}

Write-Section "Cloning ferdig"
Write-Host "Neste steg: vent ~5-10 min mens klonene fullforer specialize-pass"
Write-Host "             og setter sin statiske IP. Sjekk med:"
Write-Host ""
Write-Host "   Test-NetConnection -ComputerName $dnsServer -Port 5985"
Write-Host ""
Write-Host "Nar alle svarer: kjor Ansible-playbook for AD-promovering."
