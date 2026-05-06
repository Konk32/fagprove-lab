# http/

Files mounted as a virtual floppy during Packer build.

Contains:
- `autounattend.xml` — Windows Setup answer-file
- `winrmConfig.bat` — initial WinRM bootstrap for first boot

Expected behavior from unattend/bootstrap:
- Set temporary computer name
- Set Administrator password
- Enable first-boot automation for provisioning
- Configure locale and timezone
- Enable WinRM
- Open required WinRM firewall ports
