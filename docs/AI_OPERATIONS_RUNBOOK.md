# AI Operations Runbook

## Scope
AI-first runtime operations with minimal human interaction.

## Standard Flow

1. Bootstrap runtime (and optional project):
```bash
/var/www/aiir/server/scripts/aiir up
# optional:
/var/www/aiir/server/scripts/aiir up --project crm-alpha --type webapp --domain crm.local
```

2. Operate via chat intents only:
```bash
/var/www/aiir/server/scripts/aiir chat "stato"
/var/www/aiir/server/scripts/aiir chat "lista progetti"
/var/www/aiir/server/scripts/aiir chat "stato progetto crm-alpha"
/var/www/aiir/server/scripts/aiir chat "ottimizza progetto crm-alpha"
```

3. Diagnostics:
```bash
/var/www/aiir/server/scripts/aiir doctor
/var/www/aiir/server/scripts/aiir doctor --strict
```

4. Stop runtime (requires explicit confirmation in chat path):
```bash
/var/www/aiir/server/scripts/aiir chat "ferma runtime conferma"
# or direct:
/var/www/aiir/server/scripts/aiir down
```

5. Run end-to-end AI-only smoke:
```bash
/var/www/aiir/server/scripts/smoke-ai-ops.sh
```

## Chat Error Codes
- `intent_unknown`
- `confirmation_required`
- `project_not_found`
- `type_map_missing`

## Notes
- Destructive intents are blocked unless `conferma/confirm` is present.
- Project type mapping is centralized in:
  - `/var/www/aiir/server/scripts/project-type-map.sh`
- Legacy human adapter is still available for compatibility, but deprecated:
  - `/var/www/aiir/human/create-project-by-type.sh`
