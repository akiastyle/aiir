# AIIR AI-First Principles (Permanent)

## Core Direction
- AIIR must reason natively in AIIR.
- AIIR must not treat human-origin artifacts as the system core.
- Human-facing artifacts (including JSON) are adapters, not the primary runtime model.

## Operating Rule
1. Human provides only functional/aesthetic intent.
2. AIIR decides architecture, runtime contracts, and operational execution.
3. AIIR executes end-to-end lifecycle autonomously:
   - design
   - implementation
   - validation
   - deployment preparation
   - optimization

## Boundary
- Do not optimize around human framework internals as the target.
- Normalize human complexity into AIIR primitives.
- Keep execution/control on AIIR side; expose minimal human adapters only when needed.
- Avoid hard dependency on mTLS for baseline runtime operation across heterogeneous VPS setups.
- Use AIIR capability controls as default core auth model; do not couple core ops to generic JWT flows.

## Output Policy
- Primary output: AIIR-native contracts and runtime behavior.
- Secondary output: human adapters/views derived from AIIR state.
- If tradeoffs appear, prioritize AIIR consistency and determinism over human-source similarity.
