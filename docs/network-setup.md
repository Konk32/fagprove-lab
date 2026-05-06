# VMware Workstation Network Setup

## Why this is manual

VMware Workstation does not provide a reliable infrastructure-as-code interface
for LAN segment creation. Configure the segment once, then keep the project
config (`config/lab.yml`) aligned with your Workstation setup.

## Recommended setup

Create one isolated LAN segment for all lab VMs:

1. Open VMware Workstation.
2. Go to `Edit -> Virtual Network Editor`.
3. Create a dedicated segment/network (for example `lab-fagprove` or `VMnet2`).
4. Disable built-in DHCP on that segment.
5. Ensure all cloned lab VMs connect to this same segment.

Use matching values in `config/lab.yml`:

```yaml
network:
  lan_segment: VMnet2
  subnet: 10.50.0.0/24
  gateway: 10.50.0.1
```

## Validate

After cloning, verify network adapters from the host:

```powershell
vmrun list
vmrun listNetworkAdapters "<path-to-vm.vmx>"
```

## Troubleshooting

- VMs cannot reach each other: confirm identical segment and subnet on all VMs.
- No internet access: expected on isolated segments unless a router VM is added.
- DHCP issues: expected if no DHCP role has been configured yet in the lab.
