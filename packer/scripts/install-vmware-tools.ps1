# =============================================================================
# install-vmware-tools.ps1
# =============================================================================
# Installerer VMware Tools fra ISO-en som Workstation automatisk monter
# nar du velger "Install VMware Tools" — eller fra Packer's tools_upload_path.
#
# Hvorfor VMware Tools?
# - Riktig grafikk-driver (slipper laggy konsoll)
# - Tidssync med host (samme tid pa alle lab-VM-er)
# - Quiesced snapshots
# - Bedre nettverksperformance (vmxnet3 driver fungerer skikkelig)
# - VM IP-adresse rapporteres til hypervisoren (nyttig for vmrun)
#
# Vi installer dette i base-imaget slik at klonede VM-er har det fra start.
# =============================================================================

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\install-vmware-tools.log" -Force

Write-Host "==================================================="
Write-Host " install-vmware-tools.ps1 starter"
Write-Host "==================================================="

# -----------------------------------------------------------------------------
# Finn VMware Tools-installer
# -----------------------------------------------------------------------------
# Packer's vmware-iso builder kan settes til a montere tools-isoen automatisk.
# Det er ogsa mulig at filen er tilgjengelig pa D: (CD-ROM) eller
# 'C:\Users\Administrator\windows.iso' (default fra Packer).

$searchPaths = @(
    "C:\Users\Administrator\windows.iso",
    "D:\setup64.exe",
    "E:\setup64.exe",
    "F:\setup64.exe"
)

$installer = $null
foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        Write-Host "Fant VMware Tools her: $path"
        $installer = $path
        break
    }
}

if (-not $installer) {
    Write-Warning "VMware Tools ikke funnet. Skipper installasjon."
    Write-Warning "Du ma installere manuelt eller justere Packer-templaten."
    Stop-Transcript
    exit 0
}

# -----------------------------------------------------------------------------
# Hvis det er en ISO-fil, mount den forst
# -----------------------------------------------------------------------------
if ($installer -like "*.iso") {
    Write-Host "Mounting ISO..."
    $mount = Mount-DiskImage -ImagePath $installer -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    $installer = "${driveLetter}:\setup64.exe"
    Write-Host "ISO mountet pa $driveLetter`:"
}

# -----------------------------------------------------------------------------
# Stille installasjon
# -----------------------------------------------------------------------------
# /S      = silent
# /v      = pass parameters til MSI
# /qn     = no UI
# REBOOT=R = ikke reboot (det styrer vi)
Write-Host ""
Write-Host "Installerer VMware Tools..."
$proc = Start-Process -FilePath $installer `
    -ArgumentList "/S", "/v", "/qn REBOOT=R" `
    -Wait `
    -PassThru

Write-Host "Exit code: $($proc.ExitCode)"

if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
    # 3010 = "success but reboot required" — ok for oss
    Write-Warning "VMware Tools install mulig feilet (exit $($proc.ExitCode))"
}

Write-Host ""
Write-Host "==================================================="
Write-Host " install-vmware-tools.ps1 ferdig"
Write-Host "==================================================="

Stop-Transcript
