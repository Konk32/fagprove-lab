# Build a 1.44 MB FAT12 floppy image from a source directory.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SourceDir,
    [Parameter(Mandatory)] [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function ConvertTo-WslPath {
    param([string]$WindowsPath)
    $abs = (Resolve-Path -Path $WindowsPath -ErrorAction SilentlyContinue).Path
    if (-not $abs) {
        $parent = Split-Path $WindowsPath -Parent
        $leaf   = Split-Path $WindowsPath -Leaf
        $absParent = (Resolve-Path -Path $parent).Path
        $abs = Join-Path $absParent $leaf
    }
    $drive = $abs.Substring(0, 1).ToLower()
    $rest  = $abs.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host "[ERROR] WSL not found. Install it with: wsl --install -d Ubuntu" -ForegroundColor Red
    exit 1
}

$mtoolsCheck = wsl which mformat 2>$null
if (-not $mtoolsCheck) {
    Write-Host "[INFO] mtools not found in WSL. Installing (sudo required)..."
    wsl sudo apt-get update
    wsl sudo apt-get install -y mtools
}

$wslOutput = ConvertTo-WslPath $OutputPath
$wslSource = ConvertTo-WslPath $SourceDir

Write-Host "[DEBUG] Output (Win):  $OutputPath"
Write-Host "[DEBUG] Output (WSL):  $wslOutput"
Write-Host "[DEBUG] Source (Win):  $SourceDir"
Write-Host "[DEBUG] Source (WSL):  $wslSource"

if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

Write-Host "[STEP 1] Creating empty 1.44 MB image..."
wsl bash -c "dd if=/dev/zero of='$wslOutput' bs=512 count=2880 2>&1 | tail -1"
if (-not (Test-Path $OutputPath)) {
    throw "Could not create floppy image at $OutputPath"
}

Write-Host "[STEP 2] Formatting as FAT12..."
$formatResult = wsl bash -c "mformat -i '$wslOutput' -f 1440 :: 2>&1"
Write-Host "  $formatResult"

Write-Host "[STEP 3] Copying files from $SourceDir..."
$files = Get-ChildItem -Path $SourceDir -File
if ($files.Count -eq 0) {
    throw "Source directory is empty: $SourceDir"
}

foreach ($file in $files) {
    $wslFile = ConvertTo-WslPath $file.FullName
    Write-Host "  Copying: $($file.Name)"
    Write-Host "    Win path: $($file.FullName)"
    Write-Host "    WSL path: $wslFile"
    
    $copyResult = wsl bash -c "mcopy -i '$wslOutput' -v '$wslFile' '::$($file.Name)' 2>&1"
    Write-Host "    Result: $copyResult"
}

Write-Host "[STEP 4] Verifying floppy contents..."
$listResult = wsl bash -c "mdir -i '$wslOutput' :: 2>&1"
Write-Host $listResult

if ($listResult -match "No files") {
    Write-Host "[ERROR] Floppy is empty after copy!" -ForegroundColor Red
    Write-Host "        Check the WSL paths above for errors." -ForegroundColor Yellow
    exit 1
}

$fileSize = (Get-Item $OutputPath).Length
Write-Host "[OK] Floppy created: $OutputPath ($([math]::Round($fileSize / 1KB, 0)) KB)" -ForegroundColor Green
