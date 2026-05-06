# Configure WinRM during first login for Packer provisioning.

$ErrorActionPreference = "Stop"

$logFile = "C:\Windows\Temp\setup-winrm.log"
Start-Transcript -Path $logFile -Force

Write-Host "==================================================="
Write-Host " setup-winrm.ps1 starting"
Write-Host "==================================================="

Write-Host ""
Write-Host "Step 1: Set network profile to Private"
Write-Host "-----------------------------------"
try {
    $profiles = Get-NetConnectionProfile
    foreach ($p in $profiles) {
        Write-Host "Setting $($p.Name) to Private (was $($p.NetworkCategory))"
        Set-NetConnectionProfile -Name $p.Name -NetworkCategory Private -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Could not update network profile: $_"
}

Write-Host ""
Write-Host "Step 2: Enable WinRM (quickconfig)"
Write-Host "-----------------------------------"
try {
    & winrm quickconfig -quiet -force
    Write-Host "WinRM quickconfig completed"
} catch {
    Write-Warning "winrm quickconfig failed: $_"
}

Write-Host ""
Write-Host "Step 3: Configure WinRM service for Packer"
Write-Host "-----------------------------------"
& winrm set winrm/config/service '@{AllowUnencrypted="true"}'
& winrm set winrm/config/service/auth '@{Basic="true"}'
& winrm set winrm/config/client/auth '@{Basic="true"}'
& winrm set winrm/config '@{MaxTimeoutms="1800000"}'

Write-Host ""
Write-Host "Step 4: Create HTTPS listener (self-signed cert)"
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

    & winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>$null

    $listenerCmd = "winrm create winrm/config/Listener?Address=*+Transport=HTTPS '@{Hostname=`"$hostname`"; CertificateThumbprint=`"$($cert.Thumbprint)`"}'"
    Invoke-Expression $listenerCmd
} catch {
    Write-Warning "HTTPS listener failed (non-critical for Packer): $_"
}

Write-Host ""
Write-Host "Step 5: Firewall rules"
Write-Host "-----------------------------------"

Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

if (-not (Get-NetFirewallRule -DisplayName "WinRM HTTPS-In" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName "WinRM HTTPS-In" `
        -Name "WinRM-HTTPS-In-TCP" `
        -Profile Any `
        -LocalPort 5986 `
        -Protocol TCP `
        -Action Allow
}

Write-Host ""
Write-Host "Step 6: Restart WinRM service"
Write-Host "-----------------------------------"
Restart-Service WinRM -Force

Write-Host ""
Write-Host "WinRM listeners after configuration:"
& winrm enumerate winrm/config/Listener

Write-Host ""
Write-Host "==================================================="
Write-Host " setup-winrm.ps1 finished - ready for Packer"
Write-Host "==================================================="

Stop-Transcript
