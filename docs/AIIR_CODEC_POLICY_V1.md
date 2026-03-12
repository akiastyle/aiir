# AIIR Codec Policy v1

## Scope
Defines encoding behavior for AIIR runtime, AI2AI sync, and human adapters.

## Default Rules (AI-first)
- Internal runtime representation: binary-first.
- AI2AI transport: signed binary payloads by default.
- Text-only transport fallback: base64.
- Human manual emergency codes (pairing/recovery only): base32 optional fallback.

## Non-Goals
- base32 is not part of normal operational paths.
- base32 must not be used as default for AI2AI sync or runtime contracts.

## Why
- binary/base64 minimize overhead and simplify deterministic machine pipelines.
- base32 is reserved for rare human manual transcription scenarios.

## Enforcement
- Core/runtime scripts and native runtime paths must not require base32 for normal operation.
- Audit checks should fail if base32 is introduced into core operational scripts.
