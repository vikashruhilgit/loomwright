## GATE_VERDICT (pre-execution gate audit)

Emitted by the QA Strategist in **Gate Audit Mode** (spawned by QA Executor Phase 11) and consumed by
QA Executor Phase 11's pass/fail handling (max 1 retry on fail). **Advisory between the two QA agents —
no hook validator** (the block never terminates a session by itself; QA_RESULT carries the session outcome
via its `gate_audit_verdict` field).

```yaml
GATE_VERDICT:
  schema_version: 1                    # integer, required — always 1
  verdict: enum [pass, fail]           # required
  gates_passed: number[]               # required — gate numbers that passed (13-gate checklist, qa-gates skill; the checklist includes fractional gates 0.5 and 1.5)
  gates_failed: number[]               # required — gate numbers that failed (empty when verdict=pass)
  violations: object[]                 # required — empty when verdict=pass
    - gate: number                     # which gate (fractional gate numbers 0.5 / 1.5 are valid)
      file: string                     # offending test file
      line: integer | null             # line number when known
      description: string              # what violated the gate
  summary: string                      # required — 1-2 sentences
```

**Validation rules:**
- `schema_version` must equal `1`
- `verdict=fail` requires non-empty `gates_failed` AND non-empty `violations`
- `verdict=pass` requires empty `gates_failed` and empty `violations`
- GATE_VERDICT is final: on `fail`, the Executor fixes the violations and re-submits (max 1 retry); a second `fail` → QA_RESULT `status: needs_human` with `gate_failures`

---

