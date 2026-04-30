# =============================================================================
# build.ps1 — Hoved-entrypoint for hele lab-byggingen
# =============================================================================
# Kjor med:
#   .\scripts\build.ps1
#
# Eller for delvis kjoring:
#   .\scripts\build.ps1 -SkipPacker          # hvis basen finnes fra for
#   .\scripts\build.ps1 -SkipAnsible         # bare bygg/klone, ikke konfigurer
#   .\scripts\build.ps1 -Destroy             # riv ned alle lab-VM-er
# =============================================================================

[CmdletBinding()]
param(
    [string]$Config = "$PSScriptRoot\..\config\lab.yml",
    [switch]$SkipPacker,
    [switch]$SkipClone,
    [switch]$SkipAnsible,
    [switch]$Destroy
)

# -----------------------------------------------------------------------------
# Stopp pa forste feil — bedre enn a fortsette og rote til state
# -----------------------------------------------------------------------------
$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Helper: skrive seksjons-bannere (lett a finne i logg)
# -----------------------------------------------------------------------------
function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

# -----------------------------------------------------------------------------
# Pre-flight: sjekk at verktoyene finnes
# -----------------------------------------------------------------------------
Write-Section "Pre-flight checks"

$tools = @{
    "packer" = "Packer"
    "vmrun"  = "VMware Workstation"
    "wsl"    = "WSL (for Ansible)"
}

foreach ($tool in $tools.Keys) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Write-Host "[OK] $($tools[$tool]) funnet" -ForegroundColor Green
    } else {
        Write-Host "[MANGLER] $($tools[$tool])" -ForegroundColor Red
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Destroy-modus: riv ned alle lab-VM-er
# -----------------------------------------------------------------------------
if ($Destroy) {
    Write-Section "Destroy mode — fjerner alle lab-VM-er"
    # TODO: les serverliste fra lab.yml og kjor 'vmrun stop' + 'vmrun deleteVM'
    Write-Warning "Ikke implementert enda. Manuelt: VM-er ligger under output/"
    exit 0
}

# -----------------------------------------------------------------------------
# Steg 1: Packer — bygg gylden base-image
# -----------------------------------------------------------------------------
if (-not $SkipPacker) {
    Write-Section "Steg 1/3 — Packer build (gylden Win2022-image)"

    Push-Location "$PSScriptRoot\..\packer"
    try {
        # init laster ned plugin-er definert i .pkr.hcl
        packer init .
        # build kjorer hele autounattend-installasjonen
        packer build .
    } finally {
        Pop-Location
    }
}

# -----------------------------------------------------------------------------
# Steg 2: Klone basen til alle servere
# -----------------------------------------------------------------------------
if (-not $SkipClone) {
    Write-Section "Steg 2/3 — Klone VM-er fra base"

    & "$PSScriptRoot\clone-vms.ps1" -Config $Config
}

# -----------------------------------------------------------------------------
# Steg 3: Ansible — konfigurer alt
# -----------------------------------------------------------------------------
if (-not $SkipAnsible) {
    Write-Section "Steg 3/3 — Ansible-konfigurasjon"

    # Ansible kjorer i WSL siden den ikke stottes nativt p Windows.
    # Vi kaller WSL og kjorer playbook derfra.
    $repoRoot = Resolve-Path "$PSScriptRoot\.."
    $wslPath  = (wsl wslpath $repoRoot.Path.Replace("\", "/")).Trim()

    wsl --cd $wslPath ansible-playbook `
        -i ansible/inventory/hosts.yml `
        ansible/playbooks/site.yml
}

Write-Section "Ferdig!"
Write-Host "Lab-miljoet er klart. Sjekk docs/post-build.md for verifikasjon." -ForegroundColor Green
