# AIIR Gateway v1

## Goal
Provide a single AI-managed interface where human operators can create and use projects without direct database credentials.

Core rule:
- human never receives DB user/password
- AIIR provisions and manages DB in background
- DB access is only through AIIR contracts
- multiple projects and multiple dedicated DBs can run on the same server host

## Endpoint: `POST /aiir/project/create`

Creates a project and provisions a default DB automatically.

Request:
```json
{
  "contract_version": "hal.v1",
  "intent": "create_project",
  "project_name": "crm-alpha",
  "db_profile": "default",
  "region": "eu-central",
  "retention_days": 30,
  "idempotency_key": "fbe6ca3b-8d3a-4f64-9c6a-1fcae6ed9f8a"
}
```

Response `202`:
```json
{
  "ok": 1,
  "project_ref": "prj_01J...",
  "db_ref": "db_01J...",
  "status": "provisioning",
  "events_channel": "aiir.ev.project.prj_01J..."
}
```

Final status (`ready`) is delivered via events.
With a new `idempotency_key`, a new `project_ref` and `db_ref` pair is created.
If the same `idempotency_key` is reused, gateway returns the same refs (`idempotent: 1`) to prevent duplicate provisioning.

## Endpoint: `POST /aiir/db/exec`

AIIR-managed DB operation bound to `db_ref`; credentials are internal and never exposed.

Request:
```json
{
  "contract_version": "hal.v1",
  "intent": "save_data",
  "project_ref": "prj_01J...",
  "db_ref": "db_01J...",
  "op_id": "entity.upsert",
  "payload": {
    "collection": "customers",
    "doc": {
      "id": "cus_1001",
      "name": "Acme Srl"
    }
  },
  "req_id": "req_01J..."
}
```

Validation notes:
- `contract_version` currently supports `hal.v1`.
- `intent` accepted values:
  - create endpoint: `create_project`, `create_project_typed`
  - db exec endpoint: `save_data`, `read_data`
- token-like fields (`project_name`, `project_ref`, `db_ref`, `op_id`, `req_id`, `db_profile`, `region`, `idempotency_key`) are validated for safe ASCII patterns.

Response `200`:
```json
{
  "ok": 1,
  "req_id": "req_01J...",
  "result": {
    "status": "applied"
  }
}
```

## Events (WS, no polling)

- `aiir.ev.project.created`
- `aiir.ev.db.provisioning`
- `aiir.ev.db.ready`
- `aiir.ev.db.error`
- `aiir.ev.db.exec.result`
- `aiir.ev.db.exec.error`

## Security Model

- deny-by-default for DB operations
- capability token required on sensitive calls
- all operations audited
- secret storage and rotation are internal to AIIR
- direct DB credentials are disabled for human mode
- gateway behavior is independent from Apache/Nginx; it is a runtime contract concern
- mTLS is not a mandatory baseline dependency for runtime operation
- capability-based AIIR auth is the default core model (JWT is not required for core gateway ops)

## Human vs AI Responsibilities

- human:
  - declares intent (create project, save/read business data)
  - receives references and results
- AI:
  - provisions DB
  - manages schema/index/retention/backup
  - applies optimization and recovery flows
  - enforces policy and security controls

## Provision Automation Script

For end-to-end project bootstrap (project create + DB refs + policy/env + Apache/Nginx conf generation):

- `/var/www/aiir/server/scripts/provision-project-domain.sh <project-name> [domain]`
- default behavior:
  - generates project env and policy files
  - generates web server conf under `/var/www/aiir/server/generated/`
- optional direct install/reload of system web server conf:
  - `AIIR_PROVISION_APPLY=1 /var/www/aiir/server/scripts/provision-project-domain.sh ...`

## Zero-Conf AI Operations

- Unified CLI:
  - `/var/www/aiir/server/scripts/aiir <up|chat|down|doctor|optimize|ui|ingest|convert|parity|bench|clean|audit>`
- Full runbook:
  - `/var/www/aiir/docs/AI_OPERATIONS_RUNBOOK.md`
  - migration policy: `/var/www/aiir/docs/AI2AI_MIGRATION_POLICY_V1.md`
- Single bootstrap command:
  - `/var/www/aiir/server/scripts/aiir-up.sh`
- Stop command:
  - `/var/www/aiir/server/scripts/aiir-down.sh`
- Diagnostic command:
  - `/var/www/aiir/server/scripts/aiir-doctor.sh`
- Conversion + parity commands:
  - `/var/www/aiir/server/scripts/aiir-convert-project.sh <source-dir> <out-dir> [project-id]`
  - `/var/www/aiir/server/scripts/aiir-parity-check.sh <source-dir> <convert-out-dir>`
- Optional bootstrap + project creation in one step:
  - `/var/www/aiir/server/scripts/aiir-up.sh --project <name> --type <project-type> [--domain <domain>]`
- Chat-style operational entrypoint:
  - `/var/www/aiir/server/scripts/aiir-chat.sh "crea progetto <name> tipo <type> dominio <domain>"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "stato"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "lista progetti"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "stato progetto <project-ref|project-name>"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "ottimizza progetto <project-ref|project-name>"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "ui progetto <project-ref|project-name> preset <utility|material|bootstrap-like>"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "ferma runtime conferma"`
  - destructive intents are blocked unless `conferma/confirm` is present
