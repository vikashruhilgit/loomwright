## RED_TEAM_RESULT (adversarial audit summary)

Emitted by the Red Team Reviewer (`agents/red-team-reviewer.md`) as the **last** structured block of
every audit, after the human-readable report. It is **advisory only** — there is **no hook validator**
(mirroring POSTMORTEM_RESULT — the agent's free-form report stays the primary output; this block exists
so telemetry and programmatic consumers can read the verdict without parsing prose).

```yaml
RED_TEAM_RESULT:
  schema_version: 1                    # integer, required — always 1
  verdict: enum [SHIP_BLOCKED, SHIP_WITH_RISKS, ACCEPTABLE]  # required — overall adversarial verdict
  fatal_count: integer                 # required — count of FATAL findings
  critical_count: integer              # required — count of CRITICAL findings
  warning_count: integer               # required — count of WARNING findings
  top_risks: string[]                  # required — up to 3 one-line risk statements (empty only when no findings)
  summary: string                      # required — one-line audit summary
```

**Validation rules:**
- `schema_version` must equal `1`
- `verdict` derivation is mechanical: any FATAL → `SHIP_BLOCKED`; no FATAL but any CRITICAL → `SHIP_WITH_RISKS`; otherwise `ACCEPTABLE`
- counts are non-negative integers matching the report's findings
- `top_risks` lists the highest-severity findings first, max 3 entries

**Example:**
```yaml
RED_TEAM_RESULT:
  schema_version: 1
  verdict: SHIP_WITH_RISKS
  fatal_count: 0
  critical_count: 2
  warning_count: 5
  top_risks:
    - "Refresh tokens never rotate — a leaked token is valid for 7 days"
    - "Rate limiter keyed on IP only — trivially bypassed behind a NAT"
  summary: "No fatal exploits; 2 critical auth weaknesses must be fixed before public launch."
```

---

