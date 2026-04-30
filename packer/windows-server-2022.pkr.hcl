# =============================================================================
# windows-server-2022.pkr.hcl
# =============================================================================
# Bygger en gylden Windows Server 2022-image i VMware Workstation Pro.
# Resultatet er en VMX/VMDK-fil som vmrun kan klone til de faktiske
# servere som beskrevet i config/lab.yml.
#
# Kjor med:
#   packer init .
#   packer build .
# =============================================================================

# Plugin-dependencies — Packer trenger a vite hvilke builders som finnes.
# 'vmware' = lokal Workstation/Fusion. (For vSphere bruker man en annen plugin.)
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
# overstyres med PKR_VAR_xxx miljovariabler / -var p kommandolinjen.
#
# winrm_password er sensitiv — settes via miljovariabel, ikke i fil.

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
  sensitive = true
}

variable "output_directory" {
  type    = string
  default = "output/win2022-base"
}

# -----------------------------------------------------------------------------
# Source-block: definerer en VM-builder
# -----------------------------------------------------------------------------
# Source-en beskriver "hvordan VM-en lages og bootes". Build-blokken (under)
# beskriver "hva som skjer etter at VM-en er oppe".

source "vmware-iso" "win2022" {
  # ----- ISO og boot -----
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  # autounattend.xml mountes som virtuell floppy. Windows Setup leser den
  # automatisk og kjorer hele installasjonen uten brukerinput.
  floppy_files = [
    "http/autounattend.xml",
    "scripts/setup-winrm.ps1"
  ]

  # ----- VM-spesifikasjoner -----
  vm_name              = "win2022-base"
  guest_os_type        = "windows9srv-64"   # Workstation-tag for Win Server 2022
  cpus                 = 2
  memory               = 4096
  disk_size            = 61440               # 60 GB
  disk_adapter_type    = "lsisas1068"
  network_adapter_type = "vmxnet3"

  # Workstation-spesifikke felt
  version              = "20"                # VM hardware version
  output_directory     = var.output_directory

  # ----- Connection efter boot -----
  # Packer kobler seg til VM-en via WinRM nar autounattend.xml er ferdig.
  # WinRM blir aktivert av setup-winrm.ps1 i 'specialize'-fasen.
  communicator         = "winrm"
  winrm_username       = var.winrm_username
  winrm_password       = var.winrm_password
  winrm_timeout        = "2h"                # Inkluderer Windows install-tid
  winrm_use_ssl        = false               # Self-signed cert er pain
  winrm_insecure       = true

  # Ren shutdown nar build er ferdig
  shutdown_command     = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer build done\""
}

# -----------------------------------------------------------------------------
# Build-block: hva som skjer etter VM-en er oppe
# -----------------------------------------------------------------------------
# Provisioners kjorer i rekkefolge over WinRM. Hver er en sjanse til a
# tilpasse imaget for vart formal.

build {
  sources = ["source.vmware-iso.win2022"]

  # Steg 1: Installer Windows Updates (gjor imaget ferskt, men tidkrevende)
  provisioner "powershell" {
    script         = "scripts/install-updates.ps1"
    pause_before   = "30s"
    timeout        = "2h"
  }

  # Steg 2: Reboot etter updates
  provisioner "windows-restart" {
    restart_timeout = "20m"
  }

  # Steg 3: Installer VMware Tools fra ISO som er montert
  provisioner "powershell" {
    script = "scripts/install-vmware-tools.ps1"
  }

  # Steg 4: Generaliser med sysprep — gjor imaget klonebart
  # Etter dette MA imaget aldri bootes igjen for det er klonet.
  provisioner "powershell" {
    script = "scripts/sysprep.ps1"
  }
}
