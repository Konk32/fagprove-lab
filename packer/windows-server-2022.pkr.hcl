# =============================================================================
# windows-server-2022.pkr.hcl
# =============================================================================
# Bygger en gylden Windows Server 2022-image i VMware Workstation Pro.
# Resultatet er en VMX/VMDK-fil som vmrun kan klone til de faktiske
# servere som beskrevet i config/lab.yml.
#
# Kjor med:
#   cd packer/
#   packer init .
#   packer build .
# =============================================================================

# Plugin-dependencies — Packer trenger a vite hvilke builders som finnes.
packer {
  required_plugins {
    vmware = {
      version = ">= 1.0.10"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

# -----------------------------------------------------------------------------
# Variabler
# -----------------------------------------------------------------------------
# Verdiene settes i variables.auto.pkrvars.hcl (commit-trygg) eller
# overstyres med PKR_VAR_xxx miljovariabler / -var pa kommandolinjen.

variable "iso_url" {
  type        = string
  description = "Sti til Windows Server 2022 ISO. Lokal sti eller https://"
}

variable "iso_checksum" {
  type        = string
  description = "SHA256-sum av ISO-en. Format: sha256:abc123..."
}

variable "winrm_username" {
  type    = string
  default = "Administrator"
}

variable "winrm_password" {
  type      = string
  default   = "Lab123"  # MA matche autounattend.xml
  sensitive = true
}

variable "output_directory" {
  type    = string
  default = "output/win2022-base"
}

variable "boot_wait" {
  type    = string
  default = "10s"
  description = "Hvor lenge Packer venter for den sender boot_command"
}

# -----------------------------------------------------------------------------
# Source-block: definerer en VM-builder
# -----------------------------------------------------------------------------
source "vmware-iso" "win2022" {

  # ----- ISO og boot -----
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  # autounattend.xml + setup-winrm.ps1 mountes som virtuell floppy.
  # Windows Setup leser autounattend.xml automatisk fra A:\.
  # FirstLogonCommands kjorer 'a:\setup-winrm.ps1'.
  floppy_files = [
    "http/autounattend.xml",
    "http/winrmConfig.bat"
  ]

  # boot_command sendes som tastetrykk til VM-en under boot.
  # Vi sender to mellomrom for a passere "Press any key to boot from CD"-prompten.
  # boot_wait gir VM-en tid til a komme til den prompten for vi sender input.
  boot_wait    = var.boot_wait
  boot_command = ["<spacebar><spacebar>"]

  # ----- VM-spesifikasjoner -----
  vm_name              = "win2022-base"
  guest_os_type        = "windows9srv-64"   # Workstation-tag for Win Server 2022
  cpus                 = 2
  memory               = 4096
  disk_size            = 61440               # 60 GB
  disk_adapter_type    = "lsisas1068"
  network_adapter_type = "vmxnet3"

  # Workstation-spesifikke felt
  version              = "20"                # VM hardware version (Workstation 17)
  output_directory = "win2022-base-final"
  headless             = false               # Set til true for a kjore i bakgrunnen

  # ----- Connection etter boot -----
  # Packer kobler seg til VM-en via WinRM nar setup-winrm.ps1 har kjort.
  communicator         = "winrm"
  winrm_username       = var.winrm_username
  winrm_password       = var.winrm_password
  winrm_timeout        = "2h"                # Inkluderer Windows install-tid
  winrm_use_ssl        = false               # Self-signed cert er pain — Ansible bruker HTTPS senere
  winrm_insecure       = true
  winrm_use_ntlm       = true

  # Ren shutdown nar build er ferdig.
  # MERK: sysprep.ps1 gjor egen shutdown — denne er fallback hvis sysprep skipas.
  shutdown_command = "echo done"
  shutdown_timeout = "30m"

  # Tools-ISO mounting — Packer monterer windows.iso automatisk her hvis tools_upload_flavor er satt
  tools_mode        = "attach"
  tools_source_path = "C:/Program Files (x86)/VMware/VMware Workstation/windows.iso"
}

# -----------------------------------------------------------------------------
# Build-block: hva som skjer etter VM-en er oppe
# -----------------------------------------------------------------------------
build {
  sources = ["source.vmware-iso.win2022"]

  # Steg 1: Cleanup
  provisioner "powershell" {
    pause_before = "60s"
    inline = [
      "Write-Host 'Cleanup'",
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue"
    ]
  }

  # Steg 2: Installer VMware Tools
  provisioner "windows-shell" {
  inline = [
    "E:\\setup.exe /S /v\"/qn REBOOT=R\""
  ]
  valid_exit_codes = [0, 3010]
}

  # Steg 3: Schedule sysprep og la Packer styre shutdown
  provisioner "powershell" {
    inline = [
      "$action = New-ScheduledTaskAction -Execute 'C:\\Windows\\System32\\Sysprep\\sysprep.exe' -Argument '/generalize /oobe /quiet /shutdown'",
      "$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30)",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'PackerSysprep' -Action $action -Trigger $trigger -Principal $principal -Force",
      "Write-Host 'Sysprep scheduled in 30 seconds'"
    ]
  }
}