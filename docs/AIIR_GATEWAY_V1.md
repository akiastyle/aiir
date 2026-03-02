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
Each call creates a new `project_ref` and `db_ref` pair that can coexist with other projects on the same host.

## Endpoint: `POST /aiir/db/exec`

AIIR-managed DB operation bound to `db_ref`; credentials are internal and never exposed.

Request:
```json
{
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

## Human vs AI Responsibilities

- human:
  - declares intent (create project, save/read business data)
  - receives references and results
- AI:
  - provisions DB
  - manages schema/index/retention/backup
  - applies optimization and recovery flows
  - enforces policy and security controls
