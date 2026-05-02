# LAN Segment-oppsett for Workstation Pro

VM-ene kobles til et **isolert LAN-segment** kalt `lab-fagprove`. Dette er
et internt nettverk uten DHCP og uten internett-tilgang — som et ekte
production-domene-nettverk.

## Hvorfor isolert?

- DC01 skal vaere DHCP-server. Hvis Workstation NAT ogsa kjorer DHCP,
  konkurrerer to DHCP-servere pa samme nettverk.
- Vi vil ikke at lab-en skal ha tilfeldig kontakt med utsiden under
  utvikling. Realistisk segmentering = bedre laering.

## Engangs-oppsett

Du gjor dette **en gang** i Workstation. Etter det er konfigurasjonen
lagret i Workstation's Virtual Network Editor.

### Steg 1 — Apne Virtual Network Editor

1. Apne VMware Workstation Pro
2. Edit -> Virtual Network Editor
3. Klikk **Change Settings** (krever admin)

### Steg 2 — Opprett LAN segmentet

1. Klikk **Add Network...**
2. Velg en ledig **VMnet** (f.eks VMnet2 eller VMnet9)
3. **Type**: Velg `Host-only` (eller `LAN Segment` hvis tilgjengelig)
4. **DHCP**: Slau av — VI har DC01 som DHCP-server senere
5. **Subnet IP**: La staende standard (Workstation tildeler en)
6. Apply

### Steg 3 — Gi den et navn (Workstation Pro 17+)

I VMware Workstation 17+ kan VMnet-en omdopes:
1. Velg VMnet-en du nettopp lagde
2. Boksen **Subnet IP** -> bytt til en passende: `10.50.0.0/24`
3. Lukk Virtual Network Editor

### Steg 4 — Verifiser i .vmx

`scripts/clone-vms.ps1` setter denne linjen automatisk i klonens .vmx:

```
ethernet0.connectionType = "custom"
ethernet0.vnet = "VMnet2"
```

Hvis du valgte en annen VMnet en VMnet2, juster `lab.network.lan_segment`
i `config/lab.yml`.

## Verifiser at det fungerer

Etter cloning:
1. Klonen booter, far statisk IP fra unattend.xml
2. Du skal kunne pinge IP-en fra Workstation-hosten:
   ```powershell
   Test-NetConnection -ComputerName 10.50.0.10 -Port 5985
   ```

Hvis det feiler:
- Sjekk i .vmx at `ethernet0.vnet` matcher VMnet-navnet
- Sjekk Virtual Network Editor for at VMnet-en er aktiv
- Sjekk at host har en VMnet-adapter med IP i samme range

## Vanlige problemer

### "VM-en faler ikke fa IP"
Sjekk at `unattend.xml` ble lest. Forste boot etter clone tar lengre tid
fordi specialize-pass kjorer. Vent 5-10 min.

### "Pakkene faller utenfor lab-segmentet"
Hvis Wireguard er aktiv kan den catch-all routinge alle pakker.
Slau av Wireguard mens du jobber med lab-en.

### "Host kan ikke se VM-ene"
Workstation host-only adapteren MA ha en IP. Gjentest og sjekk Get-NetIPAddress.
