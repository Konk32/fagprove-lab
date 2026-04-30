# roles/

Ansible-roller — bygges i Fase 4. Forventet struktur:

```
roles/
├── ad-forest/
│   ├── tasks/main.yml
│   ├── defaults/main.yml
│   └── README.md
├── dhcp-server/
├── ou-structure/
├── security-groups/
├── users-from-config/
└── gpo-baseline/
```

Hver rolle har et tydelig ansvar — det gjor det lett a teste isolert og a
gjenbruke pa tvers av prosjekter.
