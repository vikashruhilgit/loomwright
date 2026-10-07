## MISSING_FUNCTIONALITY_REPORT

Produced by QA Executor during Phase 4.5 gap analysis. Separate from QA_RESULT.

```yaml
MISSING_FUNCTIONALITY_REPORT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — QA run identifier
  gaps: object[]                       # required — MAY be empty. An empty array with total_gaps: 0 is valid and means "analysis ran, no gaps found"
    - category: enum [missing_crud, missing_pagination, missing_search,
                      missing_validation, missing_error_handling, missing_confirmation,
                      missing_loading_state, missing_rate_limiting,
                      data_integrity_risk, security_boundary_gap, best_practice_gap]
      severity: enum [CRITICAL, HIGH, MEDIUM, LOW]
      location: string                 # route/endpoint/component where gap found
      description: string              # what's missing and why it matters
      evidence: string                 # what discovery data led to this conclusion
      recommendation: string           # what should be built/fixed
  summary: string                      # required — concise summary of all gaps
  total_gaps: integer                  # required — total gap count
  critical_count: integer              # required — CRITICAL gaps count
```

**Validation rules:**
- **Always emit the report** — even when `gaps` is empty. Absence of the block means Phase 4.5 was skipped (Strategist will reject).
- `gaps` MAY be `[]` (empty). When empty, `total_gaps` MUST be `0` and `critical_count` MUST be `0`.
- Each gap (when present) must have `category`, `severity`, `location`, `description`
- `total_gaps` must equal `gaps.length`
- `critical_count` must equal count of gaps with `severity=CRITICAL`
- `summary` must be present (e.g., "No gaps detected." for empty report)

**Example:**
```
MISSING_FUNCTIONALITY_REPORT:
  schema_version: 1
  task_id: qa-run-2026-03-22
  gaps:
    - category: missing_crud
      severity: HIGH
      location: POST /api/tournaments
      description: Tournament entity has create endpoint but no edit (PUT) or delete (DELETE)
      evidence: Discovery found POST /api/tournaments but no PUT or DELETE for same resource
      recommendation: Add PUT /api/tournaments/:id and DELETE /api/tournaments/:id endpoints
    - category: missing_rate_limiting
      severity: HIGH
      location: POST /api/auth/login
      description: Login endpoint has no rate limiting — brute force attack vector
      evidence: 5 rapid requests all returned 200 with no 429 response
      recommendation: Add rate limiting (max 5 attempts per minute per IP)
    - category: missing_pagination
      severity: MEDIUM
      location: GET /api/tournaments
      description: List endpoint returns all items with no pagination support
      evidence: No limit/offset/page query parameters detected in API calls
      recommendation: Add pagination with limit/offset or cursor-based approach
  summary: 3 gaps found (2 HIGH, 1 MEDIUM). Missing CRUD operations and rate limiting are highest priority.
  total_gaps: 3
  critical_count: 0
```

---

