# =============================================================================
# setup-winrm.ps1
# =============================================================================
# Kjorer pa Windows Server 2022 ved forste innlogging.
# Trigget av FirstLogonCommands i autounattend.xml.
# Floppy-en (A:) inneholder denne filen — vi kjorer den derfra.
#
# Hovedoppgave: gjore WinRM klar slik at Packer kan koble seg til over
# nettverk og ta over orkestreringen.
# =============================================================================

# Stopp pa forste feil — bedre enn a hykle suksess
$ErrorActionPreference = "Stop"

# Logg til fil i tilfelle vi trenger a feilsoke senere
$logFile = "C:\Windows\Temp\setup-winrm.log"
Start-Transcript -Path $logFile -Force

Write-Host "==================================================="
Write-Host " setup-winrm.ps1 starter"
Write-Host "==================================================="

# -----------------------------------------------------------------------------
# Steg 1: Sett nettverksprofilen til Private
# -----------------------------------------------------------------------------
# WinRM krever Private eller Domain network category. Public har sterkere
# brannmur-regler som blokkerer 5985/5986. autounattend gjorde dette ogsa,
# men vi gjenta her som safety net hvis nettverket ble lagt til etter.
Write-Host ""
Write-Host "Steg 1: Sett nettverk til Private"
Write-Host "-----------------------------------"
try {
    $profiles = Get-NetConnectionProfile
    foreach ($p in $profiles) {
        Write-Host "Setter $($p.Name) til Private (var $($p.NetworkCategory))"
        Set-NetConnectionProfile -Name $p.Name -NetworkCategory Private -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Kunne ikke sette nettverksprofil: $_"
}

# -----------------------------------------------------------------------------
# Steg 2: Aktiver WinRM med standardkonfig
# -----------------------------------------------------------------------------
# 'winrm quickconfig' starter WinRM-tjenesten, lager en HTTP-listener pa
# port 5985, og apner brannmur-regelen. Det gir oss mest av jobben gratis.
Write-Host ""
Write-Host "Steg 2: Aktiver WinRM (quickconfig)"
Write-Host "-----------------------------------"
try {
    # -quiet hopper over Y/N-prompts
    & winrm quickconfig -quiet -force
    Write-Host "WinRM quickconfig kjort"
} catch {
    Write-Warning "winrm quickconfig feilet: $_"
}

# -----------------------------------------------------------------------------
# Steg 3: Tillat unkrytptert + basic auth (KUN for Packer-builden)
# -----------------------------------------------------------------------------
# Dette er IKKE produksjons-config. Packer bruker det fordi self-signed
# sertifikater er en hodepine i en byggepipeline. Etter Ansible tar over
# vil vi enten:
#   a) bruke ekte sertifikat fra intern CA, eller
#   b) bruke Kerberos-autentisering nar VM-en er domain-joined
Write-Host ""
Write-Host "Steg 3: Konfigurer WinRM-service for Packer"
Write-Host "-----------------------------------"
& winrm set winrm/config/service '@{AllowUnencrypted="true"}'
& winrm set winrm/config/service/auth '@{Basic="true"}'
& winrm set winrm/config/client/auth '@{Basic="true"}'
& winrm set winrm/config '@{MaxTimeoutms="1800000"}'

# -----------------------------------------------------------------------------
# Steg 4: HTTPS-listener med self-signed sertifikat
# -----------------------------------------------------------------------------
# Bra a ha klart slik at Ansible kan velge HTTP eller HTTPS senere.
# Self-signed her — vil bli erstattet av cert fra AD CS i produksjon.
Write-Host ""
Write-Host "Steg 4: Lag HTTPS-listener (self-signed cert)"
Write-Host "-----------------------------------"
try {
    $hostname = $env:COMPUTERNAME
    $cert = New-SelfSignedCertificate `
        -DnsName $hostname `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(5)

    Write-Host "Cert thumbprint: $($cert.Thumbprint)"

    # Slett evt eksisterende HTTPS-listener forst (idempotens)
    & winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>$null

    # Lag listeneren med ny cert
    $listenerCmd = "winrm create winrm/config/Listener?Address=*+Transport=HTTPS '@{Hostname=`"$hostname`"; CertificateThumbprint=`"$($cert.Thumbprint)`"}'"
    Invoke-Expression $listenerCmd
} catch {
    Write-Warning "HTTPS-listener feilet (ikke kritisk for Packer): $_"
}

# -----------------------------------------------------------------------------
# Steg 5: Brannmur-regler
# -----------------------------------------------------------------------------
# WinRM HTTP (5985) og HTTPS (5986). Begge for Private og Domain profiler.
# Vi unnggar Public — det er bedre praksis.
Write-Host ""
Write-Host "Steg 5: Brannmur-regler"
Write-Host "-----------------------------------"

# Aktiver de innebygde "Windows Remote Management"-reglene
Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

# Eksplisitt regel for HTTPS hvis den ikke finnes
if (-not (Get-NetFirewallRule -DisplayName "WinRM HTTPS-In" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName "WinRM HTTPS-In" `
        -Name "WinRM-HTTPS-In-TCP" `
        -Profile Any `
        -LocalPort 5986 `
        -Protocol TCP `
        -Action Allow
}

# -----------------------------------------------------------------------------
# Steg 6: Restart WinRM-tjenesten slik at endringer tar effekt
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "Steg 6: Restart WinRM"
Write-Host "-----------------------------------"
Restart-Service WinRM -Force

# Verifiser at den lytter pa rett porter
Write-Host ""
Write-Host "WinRM-listenere etter konfig:"
& winrm enumerate winrm/config/Listener

Write-Host ""
Write-Host "==================================================="
Write-Host " setup-winrm.ps1 ferdig — klar for Packer"
Write-Host "==================================================="

Stop-Transcript
