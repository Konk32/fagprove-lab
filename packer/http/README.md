# http/

Filer som mountes som virtuell floppy under Packer-builden.

Skal innholde i Fase 2:
- `autounattend.xml` — Windows Setup answer-file

Vi bygger denne i neste steg. Den kommer til a:
- Sette computer name til `packer-build` (renames senere ved cloning)
- Sette administrator-passord
- Aktivere autologin slik at provisioning-scripts kan kjøre
- Sette locale til en-US (vi gjor norsk-locale via GPO senere)
- Sette tidssone til W. Europe Standard Time
- Aktivere WinRM med self-signed cert
- Apne brannmur for port 5985 og 5986
