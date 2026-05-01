# =============================================================================
# sysprep.ps1
# =============================================================================
# Det SISTE som kjorer i Packer-builden. Generaliserer Windows-imaget slik at
# det kan klones til mange identiske VM-er uten konflikter.
#
# Hva sysprep gjor:
# - Sletter SID (Security Identifier) — hver klone far ny unik SID
# - Sletter computer name — hver klone kan fa eget navn ved forste boot
# - Sletter event-log
# - Resetter aktivering
# - Forbereder OOBE-fasen pa nytt
#
# ETTER sysprep ma imaget IKKE bootes manuelt — bare klones.
# Hvis du booter sysprep'd image, vil sysprep-tellern ga ned og du
# mister ett av de 3 generaliserings-rounds Microsoft tillater per image.
# =============================================================================

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\sysprep.log" -Force

Write-Host "==================================================="
Write-Host " sysprep.ps1 starter"
Write-Host "==================================================="

# -----------------------------------------------------------------------------
# Steg 1: Cleanup — slett ting vi ikke vil ha med i imaget
# -----------------------------------------------------------------------------
# Hver MB vi sletter na blir hver MB mindre per klone senere.

Write-Host ""
Write-Host "Steg 1: Cleanup"
Write-Host "-----------------------------------"

# Tom temp-mapper
$tempPaths = @(
    "$env:windir\Temp\*",
    "$env:LOCALAPPDATA\Temp\*",
    "C:\Users\Administrator\AppData\Local\Temp\*"
)
foreach ($path in $tempPaths) {
    Write-Host "Sletter: $path"
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

# Cleanup Windows Update-cache (kan vaere flere GB)
Write-Host "Stopper wuauserv for cleanup..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

# DISM cleanup — fjerner gamle component-versjoner som ikke trengs
Write-Host "DISM /Cleanup-Image (kan ta noen minutter)..."
& dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet

# -----------------------------------------------------------------------------
# Steg 2: Defrag og zero-fill (mindre VMDK-fil)
# -----------------------------------------------------------------------------
# Optional men hjelper pa disk-storrelse. Kan skipes for raskere build.
Write-Host ""
Write-Host "Steg 2: Optimaliser disk"
Write-Host "-----------------------------------"
Optimize-Volume -DriveLetter C -Defrag -Verbose -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# Steg 3: Disable WinRM brannmur (vil reaktiveres ved klone-boot)
# -----------------------------------------------------------------------------
# Hvis vi lar WinRM staende apent her, og en klone bootes for sysprep
# rekker a kjore, kan Packer/Vagrant tro VM-en er klar for tidlig.
# Vi blokkerer pa imaget — autounattend ved klone-boot apner igjen.
Write-Host ""
Write-Host "Steg 3: Disable WinRM-brannmur (reaktiveres pa klone-boot)"
Write-Host "-----------------------------------"
Disable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# Steg 4: Sysprep selv
# -----------------------------------------------------------------------------
# /generalize  = slett SID/computer name/aktivering
# /oobe        = reset til OOBE neste boot
# /shutdown    = sla av etter sysprep (ikke restart!)
# /quiet       = ingen UI
# /unattend    = bruk vart svar-fil ved neste boot
#
# MERK: Vi peker pa autounattend.xml som Packer plassert i C:\Windows\Panther\
# under installasjon. Den brukes ogsa av sysprep ved neste boot.
Write-Host ""
Write-Host "Steg 4: Kjorer sysprep — VM slas av etter dette"
Write-Host "-----------------------------------"

# Forst kopier en sysprep-spesifikk unattend hvis vi har en
# (For na: bruk samme som ble brukt under install)
$sysprepUnattend = "C:\Windows\Panther\unattend.xml"
$sysprepExe = "C:\Windows\System32\Sysprep\sysprep.exe"

if (Test-Path $sysprepUnattend) {
    Write-Host "Bruker eksisterende unattend.xml"
    Start-Process -FilePath $sysprepExe -ArgumentList "/generalize", "/oobe", "/shutdown", "/quiet", "/unattend:$sysprepUnattend" -Wait
} else {
    Write-Host "Ingen unattend.xml funnet"
    Start-Process -FilePath $sysprepExe -ArgumentList "/generalize", "/oobe", "/shutdown", "/quiet" -Wait
}

Stop-Transcript

Stop-Transcript
