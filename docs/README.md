# Documentation

This directory contains AI/LLM-consumable reference documentation. For comprehensive human-readable documentation, see the [Notion workspace](https://www.notion.so/Home-Lab-17027a0ad6888053b8cbf2584d07c33c).

## Quick Reference

| Document | Purpose |
|----------|---------|
| [windmill.md](windmill.md) | Windmill Terraform GitOps automation |
| [vault.md](vault.md) | HashiCorp Vault secrets management |
| [github-token-setup.md](github-token-setup.md) | GitHub PAT for Actions Runner Controller |

## Notion Resources

| Resource | Link |
|----------|------|
| Operations Guide | [Notion](https://www.notion.so/Operations-Guide-2d327a0ad688818a9fb7f14fea22e3d9) |
| Services Catalog | [Notion](https://www.notion.so/Services-Catalog-50a1adf14f1d4d3fbd78ccc2ca36facc) |
| Tech References | [Notion](https://www.notion.so/Tech-References-f7548c57375542b395694ae433ff07a4) |
| Quick Reference | [Notion](https://www.notion.so/Quick-Reference-2d327a0ad688818b9d89c9e00a08bbad) |

## Directory Structure

```
docs/
├── README.md              # This file
├── windmill.md            # Windmill operations reference
├── vault.md               # Vault operations reference
├── github-token-setup.md  # GitHub token configuration
└── plans/
    ├── archive/           # Completed plans and migrations
    └── *.md               # Active design plans
```

## Design Plans

Active design plans live in `docs/plans/`. Completed plans are archived in `docs/plans/archive/`.

Plan naming: `YYYY-MM-DD-<topic>-design.md`
