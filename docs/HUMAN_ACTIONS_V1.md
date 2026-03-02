# Human Action Layer (HAL) v1

## Goal
Provide a minimal human-facing action model where intent is mapped to AIIR contracts.

Core principle:
- human sends business intent
- AIIR translates intent into runtime contracts
- no direct DB credentials or low-level DB operations are exposed

## Actions

### 1) `create_project`

Intent:
- create a new project
- optionally bind a domain
- auto-provision dedicated DB in background

Mapping:
- `POST /aiir/project/create`

Input:
```json
{
  "project_name": "crm-alpha",
  "db_profile": "default",
  "region": "local",
  "retention_days": 30,
  "idempotency_key": "hal-req-001"
}
```

Output:
```json
{
  "ok": 1,
  "project_ref": "prj_...",
  "db_ref": "db_...",
  "status": "provisioning"
}
```

### 2) `save_data`

Intent:
- save/update business data in project scope

Mapping:
- `POST /aiir/db/exec` with write-oriented `op_id`

Input:
```json
{
  "project_ref": "prj_...",
  "db_ref": "db_...",
  "op_id": "entity.upsert",
  "payload": {
    "collection": "customers",
    "doc": {"id":"cus_1001","name":"Acme Srl"}
  },
  "req_id": "hal-req-002"
}
```

Output:
```json
{
  "ok": 1,
  "req_id": "hal-req-002",
  "result": {"status":"queued"}
}
```

### 3) `read_data`

Intent:
- read/filter business data in project scope

Mapping:
- `POST /aiir/db/exec` with read-oriented `op_id`

Input:
```json
{
  "project_ref": "prj_...",
  "db_ref": "db_...",
  "op_id": "entity.query",
  "payload": {
    "collection": "customers",
    "filter": {"name":"Acme Srl"},
    "limit": 50
  },
  "req_id": "hal-req-003"
}
```

Output:
```json
{
  "ok": 1,
  "req_id": "hal-req-003",
  "result": {"status":"queued"}
}
```

### 4) `project_status`

Intent:
- check runtime and project-level status

Mapping:
- `GET /health`
- project/db refs from gateway state (`project_ref` / `db_ref`)

Output (example):
```json
{
  "ok": 1,
  "runtime": "healthy",
  "project_ref": "prj_...",
  "db_ref": "db_...",
  "status": "ready"
}
```

## Errors (human-safe)

Standard high-level errors:
- `project_name`
- `project_ref`
- `db_ref`
- `gateway-disabled`
- `policy-op`
- `capability`

Technical details remain in AI audit logs.

## Security Boundary

- human never handles DB users/passwords
- direct DB credentials are disabled by default
- sensitive execution remains capability-gated and audited
