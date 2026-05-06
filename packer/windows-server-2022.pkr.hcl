# Build a reusable Windows Server 2022 base image for VMware Workstation.

packer {
  required_plugins {
    vmware = {
      version = ">= 1.0.10"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "iso_url" {
  type        = string
  description = "Path or URL to a Windows Server 2022 ISO"
}

variable "iso_checksum" {
  type        = string
  description = "ISO SHA256 checksum in the format sha256:<hash>"
}

variable "winrm_username" {
  type    = string
  default = "Administrator"
}

variable "winrm_password" {
  type      = string
  default   = "Lab123"
  sensitive = true
}

variable "output_directory" {
  type    = string
  default = "output/win2022-base"
}

variable "boot_wait" {
  type    = string
  default = "10s"
  description = "How long Packer waits before sending boot command"
}

source "vmware-iso" "win2022" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  floppy_files = [
    "http/autounattend.xml",
    "http/winrmConfig.bat"
  ]

  boot_wait    = var.boot_wait
  boot_command = ["<spacebar><spacebar>"]

  vm_name              = "win2022-base"
  guest_os_type        = "windows9srv-64"
  cpus                 = 2
  memory               = 4096
  disk_size            = 61440
  disk_adapter_type    = "lsisas1068"
  network_adapter_type = "vmxnet3"

  version              = "20"
  output_directory = "win2022-base-final"
  headless             = false

  communicator         = "winrm"
  winrm_username       = var.winrm_username
  winrm_password       = var.winrm_password
  winrm_timeout        = "2h"
  winrm_use_ssl        = false
  winrm_insecure       = true
  winrm_use_ntlm       = true

  shutdown_command = "echo done"
  shutdown_timeout = "30m"

  tools_mode        = "attach"
  tools_source_path = "C:/Program Files (x86)/VMware/VMware Workstation/windows.iso"
}

build {
  sources = ["source.vmware-iso.win2022"]

  provisioner "powershell" {
    pause_before = "60s"
    inline = [
      "Write-Host 'Cleanup'",
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue"
    ]
  }

  provisioner "windows-shell" {
  inline = [
    "E:\\setup.exe /S /v\"/qn REBOOT=R\""
  ]
  valid_exit_codes = [0, 3010]
}

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