# Final image cleanup and sysprep step for Packer builds.

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\sysprep.log" -Force

Write-Host "==================================================="
Write-Host " sysprep.ps1 starting"
Write-Host "==================================================="

Write-Host ""
Write-Host "Step 1: Cleanup"
Write-Host "-----------------------------------"

$tempPaths = @(
    "$env:windir\Temp\*",
    "$env:LOCALAPPDATA\Temp\*",
    "C:\Users\Administrator\AppData\Local\Temp\*"
)
foreach ($path in $tempPaths) {
    Write-Host "Removing: $path"
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Stopping wuauserv for cleanup..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "DISM /Cleanup-Image (may take a few minutes)..."
& dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet

Write-Host ""
Write-Host "Step 2: Optimize disk"
Write-Host "-----------------------------------"
Optimize-Volume -DriveLetter C -Defrag -Verbose -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Step 3: Disable WinRM firewall rules (re-enabled on clone boot)"
Write-Host "-----------------------------------"
Disable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Step 4: Run sysprep"
Write-Host "-----------------------------------"

$sysprepUnattend = "C:\Windows\Panther\unattend.xml"
$sysprepExe = "C:\Windows\System32\Sysprep\sysprep.exe"

if (Test-Path $sysprepUnattend) {
    Write-Host "Using existing unattend.xml"
    Start-Process -FilePath $sysprepExe -ArgumentList "/generalize", "/oobe", "/quit", "/quiet", "/unattend:$sysprepUnattend" -Wait
} else {
    Write-Host "No unattend.xml found"
    Start-Process -FilePath $sysprepExe -ArgumentList "/generalize", "/oobe", "/quit", "/quiet" -Wait
}

Stop-Transcript
