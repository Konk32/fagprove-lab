# =============================================================================
# make-floppy.ps1
# =============================================================================
# Lager en virtuell floppy (.flp / .img) fra en mappe med filer.
# VMware Workstation aksepterer .flp-filer som disketter.
#
# Bruker innebygd diskpart + format for a opprette ekte FAT12-floppy.
# Fallback: hvis det feiler, bruker vi WSL og 'mkfs.fat' / mtools.
#
# Kjor med:
#   .\make-floppy.ps1 -SourceDir "path\to\files" -OutputPath "config.flp"
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SourceDir,
    [Parameter(Mandatory)] [string]$OutputPath
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Forsok 1: WSL + mtools (mest palitelig)
# -----------------------------------------------------------------------------
$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if ($wsl) {
    Write-Host "[INFO] Bruker WSL + mtools til a bygge floppy"

    # Sjekk at mtools er installert i WSL
    $mtoolsCheck = wsl which mformat 2>$null
    if (-not $mtoolsCheck) {
        Write-Host "[INFO] mtools ikke funnet i WSL. Installerer (krever sudo-passord)..."
        wsl sudo apt-get update
        wsl sudo apt-get install -y mtools
    }

    # Konverter Windows-stier til WSL-stier
    $wslOutput = wsl wslpath ($OutputPath -replace '\\', '/')
    $wslOutput = $wslOutput.Trim()

    # Slett eksisterende output
    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    # 1. Lag tom 1.44 MB fil
    wsl dd if=/dev/zero of=$wslOutput bs=512 count=2880 2>$null

    # 2. Formater som FAT12
    wsl mformat -i $wslOutput -f 1440 ::

    # 3. Kopier filer fra source-mappa
    foreach ($file in Get-ChildItem -Path $SourceDir -File) {
        $wslSource = wsl wslpath ($file.FullName -replace '\\', '/')
        $wslSource = $wslSource.Trim()
        Write-Host "  Kopierer: $($file.Name)"
        wsl mcopy -i $wslOutput $wslSource ::$($file.Name)
    }

    if (Test-Path $OutputPath) {
        Write-Host "[OK] Floppy laget: $OutputPath ($([math]::Round((Get-Item $OutputPath).Length / 1KB, 0)) KB)" -ForegroundColor Green
        return
    }
}

# -----------------------------------------------------------------------------
# Forsok 2: Hvis WSL ikke er tilgjengelig, gi tydelig feilmelding
# -----------------------------------------------------------------------------
Write-Host "[FEIL] Kunne ikke lage floppy. Mulige losninger:" -ForegroundColor Red
Write-Host "  1. Installer WSL og kjor: wsl --install -d Ubuntu" -ForegroundColor Yellow
Write-Host "  2. Etter WSL er klar: wsl sudo apt install mtools" -ForegroundColor Yellow
Write-Host "  3. Alternativt: bruk en ferdig 1.44MB FAT12-floppy som mal" -ForegroundColor Yellow
exit 1
