# VMware Workstation Network Setup

## Hvorfor manuelt?

VMware Workstation Pro har ingen offisiell PowerCLI-stotte og ingen Ansible-modul
for nettverkskonfigurasjon. Vi konfigurerer derfor LAN-segmentet en gang manuelt
og dokumenterer det her. Workstation lar oss eksportere konfigurasjonen til en
fil som kan committes — det gir oss reproduserbarhet.

## Hva er et LAN Segment?

I Workstation Pro er LAN Segments isolerte private nettverk. Tenk pa det som en
virtuell switch som bare lab-VM-ene dine henger pa. Det er INGEN DHCP-server pa
segmentet, og det er INGEN forbindelse ut til internett. Det er et tilsiktet
designvalg — vi vil at vart eget DC01 skal vare DHCP-server, og vi vil ha kontroll
pa hva som ngr ut.

For internett-tilgang i lab-en (for Windows Updates osv.) gir man typisk en
ruter-VM (pfSense, OPNsense, eller en Linux-VM) to nettverkskort:
- Et pa NAT (gir internett)
- Et pa LAN-segmentet (gir tjenester til lab-en)

## Manuelt oppsett — gjor en gang

1. Apne VMware Workstation Pro
2. Edit -> Virtual Network Editor (krever admin)
3. Klikk **LAN Segments...**
4. Klikk **Add**, navngi det `lab-fagprove`
5. OK, lukk
6. Eksporter hele network-konfig: **Export...** -> lagre som `vmnet-config.export`
7. Commit `vmnet-config.export` til repoet (under `config/`)

## Reimport pa ny maskin

1. Edit -> Virtual Network Editor -> Import...
2. Velg `vmnet-config.export`
3. Workstation rebuilder alle vmnet-adaptere

## Subnett-tildeling

I `config/lab.yml`:

```yaml
network:
  lan_segment: lab-fagprove
  subnet: 10.50.0.0/24
  gateway: 10.50.0.1   # ruter-VM hvis du har en
```

Statiske IP-er settes per server via Ansible (se `ansible/roles/network-config`
nar den blir bygget i Fase 4).

## Verifikasjon

Etter Packer + clone-fasen, sjekk at en VM faktisk er pa segmentet:

```powershell
vmrun list
vmrun listNetworkAdapters "path\to\DC01.vmx"
```

Adapter skal vise `lansegment: lab-fagprove`.

## Vanlige problemer

**"Nettverket er der men VM-ene ser ikke hverandre"**
LAN Segments tillater bare trafikk *innenfor* segmentet. Sjekk at alle VM-ene
har samme segment-navn og at de er i samme subnett.

**"Internett funker ikke"**
Forventet — LAN Segments har INGEN ruting ut. Du trenger en ruter-VM eller
midlertidig bytte til NAT for opdateringer.

**"DHCP funker ikke"**
LAN Segments har ingen innebygd DHCP. Det er DC01 som skal levere det. Forste
boot trenger statisk IP for det.
