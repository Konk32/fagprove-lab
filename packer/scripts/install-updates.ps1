# =============================================================================
# install-updates.ps1
# =============================================================================
# Kjores av Packer som provisioner ETTER WinRM er klart.
# Installerer alle pending Windows Updates og venter til ferdig.
#
# Dette er det mest tidkrevende steget i hele builden — typisk 30-60 min
# for et fersk Server 2022 ISO. Fordi vi installerer det i basen *en gang*,
# slipper alle klonede VM-er a oppdatere selv.
# =============================================================================

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\install-updates.log" -Force

Write-Host "==================================================="
Write-Host " install-updates.ps1 starter"
Write-Host "==================================================="

# -----------------------------------------------------------------------------
# Steg 1: Sorg for at NuGet og PSGallery er tilgjengelig
# -----------------------------------------------------------------------------
# PSWindowsUpdate-modulen lastes fra PowerShell Gallery. Forste gang krever
# det at NuGet-providern er installert og PSGallery er trusted.
Write-Host ""
Write-Host "Steg 1: Klargjor PowerShell-modulkilder"
Write-Host "-----------------------------------"

# Bruk TLS 1.2 — gamle Server-images defaulter til 1.0 som Microsoft har droppet
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Get-PackageProvider -Name NuGet -ForceBootstrap | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# -----------------------------------------------------------------------------
# Steg 2: Installer PSWindowsUpdate-modulen
# -----------------------------------------------------------------------------
# Microsoft har ingen offisiell "kjor alle updates fra script"-cmdlet. PSWindowsUpdate
# er community-modulen som alle bruker — godt vedlikeholdt, ~7M downloads.
Write-Host ""
Write-Host "Steg 2: Installer PSWindowsUpdate-modul"
Write-Host "-----------------------------------"
Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
Import-Module PSWindowsUpdate

# -----------------------------------------------------------------------------
# Steg 3: Kjor oppdateringer
# -----------------------------------------------------------------------------
# -AcceptAll       = ikke spor om bekreftelse
# -IgnoreReboot    = kollect alle, reboot styres av oss etter
# -MicrosoftUpdate = inkluder Office, Defender osv. (ikke bare OS)
#
# Vi kjorer 2 ganger — forste runde frigjor ofte 'replacement updates'
# som fortst blir synlige etter forste install.
Write-Host ""
Write-Host "Steg 3: Forste runde Windows Update"
Write-Host "-----------------------------------"
Get-WindowsUpdate `
    -AcceptAll `
    -Install `
    -IgnoreReboot `
    -MicrosoftUpdate `
    -Verbose `
    | Out-File -FilePath "C:\Windows\Temp\windows-update-1.log"

Write-Host ""
Write-Host "Steg 4: Andre runde Windows Update"
Write-Host "-----------------------------------"
Get-WindowsUpdate `
    -AcceptAll `
    -Install `
    -IgnoreReboot `
    -MicrosoftUpdate `
    -Verbose `
    | Out-File -FilePath "C:\Windows\Temp\windows-update-2.log"

Write-Host ""
Write-Host "==================================================="
Write-Host " install-updates.ps1 ferdig"
Write-Host "==================================================="
# Reboot styres av Packer's 'windows-restart' provisioner i .pkr.hcl

Stop-Transcript
