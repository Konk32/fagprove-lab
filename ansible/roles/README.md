# roles/

Ansible roles used by this deployment. Current structure:

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

Each role has a narrow responsibility so it can be tested and reused independently.
