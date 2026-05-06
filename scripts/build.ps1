# Build entrypoint for the full lab deployment.

[CmdletBinding()]
param(
    [string]$Config = "$PSScriptRoot\..\config\lab.yml",
    [switch]$SkipPacker,
    [switch]$SkipClone,
    [switch]$SkipAnsible,
    [switch]$Destroy
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

Write-Section "Pre-flight checks"

$tools = @{
    "packer" = "Packer"
    "vmrun"  = "VMware Workstation"
    "wsl"    = "WSL (for Ansible)"
}

foreach ($tool in $tools.Keys) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Write-Host "[OK] $($tools[$tool]) found" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $($tools[$tool])" -ForegroundColor Red
        exit 1
    }
}

if ($Destroy) {
    Write-Section "Destroy mode - remove all lab VMs"
    Write-Warning "Not implemented yet. Remove generated VMs manually."
    exit 0
}

if (-not $SkipPacker) {
    Write-Section "Step 1/3 - Build Windows base image with Packer"

    Push-Location "$PSScriptRoot\..\packer"
    try {
        packer init .
        packer build .
    } finally {
        Pop-Location
    }
}

if (-not $SkipClone) {
    Write-Section "Step 2/3 - Clone VMs from base image"

    & "$PSScriptRoot\clone-vms.ps1" -Config $Config
}

if (-not $SkipAnsible) {
    Write-Section "Step 3/3 - Run Ansible configuration"

    # Run Ansible via WSL because Ansible is not native on Windows.
    $repoRoot = Resolve-Path "$PSScriptRoot\.."
    $wslPath  = (wsl wslpath $repoRoot.Path.Replace("\", "/")).Trim()

    wsl --cd $wslPath ansible-playbook `
        -i ansible/inventory/hosts.yml `
        ansible/playbooks/site.yml
}

Write-Section "Done"
Write-Host "Lab deployment finished. Run ansible/playbooks/verify.yml to validate." -ForegroundColor Green
