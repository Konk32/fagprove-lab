# =============================================================================
# make-floppy.ps1
# =============================================================================
# Lager en virtuell floppy (1.44 MB FAT12) fra en mappe med filer.
# Bruker WSL + mtools for palitelig FAT12-formatering.
#
# Konverterer Windows-stier til WSL-stier MANUELT for a unnga
# encoding-issues i wsl wslpath (spesielt med ae/oe/aa).
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SourceDir,
    [Parameter(Mandatory)] [string]$OutputPath
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Helper: Konverter Windows-path til WSL-path
# -----------------------------------------------------------------------------
# C:\Users\Andreas\fagprove\... -> /mnt/c/Users/Andreas/fagprove/...
# Manuell konvertering = ingen rare tegn i wsl wslpath kan rote til.
function ConvertTo-WslPath {
    param([string]$WindowsPath)
    $abs = (Resolve-Path -Path $WindowsPath -ErrorAction SilentlyContinue).Path
    if (-not $abs) {
        # Hvis pathen ikke finnes ennaa (vi skal lage den), bruk parent
        $parent = Split-Path $WindowsPath -Parent
        $leaf   = Split-Path $WindowsPath -Leaf
        $absParent = (Resolve-Path -Path $parent).Path
        $abs = Join-Path $absParent $leaf
    }
    # C: -> /mnt/c, backslash -> forward slash
    $drive = $abs.Substring(0, 1).ToLower()
    $rest  = $abs.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

# -----------------------------------------------------------------------------
# Sjekk WSL og mtools
# -----------------------------------------------------------------------------
$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host "[FEIL] WSL ikke funnet. Installer med: wsl --install -d Ubuntu" -ForegroundColor Red
    exit 1
}

$mtoolsCheck = wsl which mformat 2>$null
if (-not $mtoolsCheck) {
    Write-Host "[INFO] mtools ikke i WSL. Installerer (krever sudo-passord)..."
    wsl sudo apt-get update
    wsl sudo apt-get install -y mtools
}

# -----------------------------------------------------------------------------
# Bygg floppy
# -----------------------------------------------------------------------------
$wslOutput = ConvertTo-WslPath $OutputPath
$wslSource = ConvertTo-WslPath $SourceDir

Write-Host "[DEBUG] Output (Win):  $OutputPath"
Write-Host "[DEBUG] Output (WSL):  $wslOutput"
Write-Host "[DEBUG] Source (Win):  $SourceDir"
Write-Host "[DEBUG] Source (WSL):  $wslSource"

# Slett eksisterende output
if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

# 1. Lag tom 1.44 MB fil
Write-Host "[STEG 1] Lager tom 1.44 MB fil..."
wsl bash -c "dd if=/dev/zero of='$wslOutput' bs=512 count=2880 2>&1 | tail -1"
if (-not (Test-Path $OutputPath)) {
    throw "Kunne ikke lage floppy-fil pa $OutputPath"
}

# 2. Formater som FAT12
Write-Host "[STEG 2] Formaterer som FAT12..."
$formatResult = wsl bash -c "mformat -i '$wslOutput' -f 1440 :: 2>&1"
Write-Host "  $formatResult"

# 3. Kopier hver fil med mcopy
Write-Host "[STEG 3] Kopierer filer fra $SourceDir..."
$files = Get-ChildItem -Path $SourceDir -File
if ($files.Count -eq 0) {
    throw "Source-mappa er tom: $SourceDir"
}

foreach ($file in $files) {
    $wslFile = ConvertTo-WslPath $file.FullName
    Write-Host "  Kopierer: $($file.Name)"
    Write-Host "    Win path: $($file.FullName)"
    Write-Host "    WSL path: $wslFile"
    
    # mcopy med eksplisitt sti og verbose
    $copyResult = wsl bash -c "mcopy -i '$wslOutput' -v '$wslFile' '::$($file.Name)' 2>&1"
    Write-Host "    Result: $copyResult"
}

# 4. Verifiser innhold
Write-Host "[STEG 4] Verifiserer floppy-innhold..."
$listResult = wsl bash -c "mdir -i '$wslOutput' :: 2>&1"
Write-Host $listResult

if ($listResult -match "No files") {
    Write-Host "[FEIL] Floppy er TOM etter kopiering!" -ForegroundColor Red
    Write-Host "       Sjekk WSL paths over for feilmeldinger" -ForegroundColor Yellow
    exit 1
}

$fileSize = (Get-Item $OutputPath).Length
Write-Host "[OK] Floppy laget: $OutputPath ($([math]::Round($fileSize / 1KB, 0)) KB)" -ForegroundColor Green
