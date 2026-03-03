# Human Layer

This directory contains human-facing adapters only.

Principles:
- keep AIIR runtime generic and stable
- map human intents into AIIR contracts
- avoid exposing direct DB credentials

## Project Type Provisioning

1. Choose project name and business type.
2. Optionally add domain.
3. Run:

```bash
/var/www/aiir/human/create-project-by-type.sh <project-name> <project-type> [domain]
```

The adapter maps `project_type` to DB defaults and calls:
- `/var/www/aiir/server/scripts/provision-project-domain.sh`

Project type catalog:
- `/var/www/aiir/human/PROJECT_TYPES_V1.md`
