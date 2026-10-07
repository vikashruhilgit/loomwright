## PLAN_REVIEW_RESULT

Produced by Plan Reviewer agent when validating a Supervisor-Ready Brief (Launch Pad Phase 5.5).

```yaml
PLAN_REVIEW_RESULT:
  schema_version: 1                    # integer, required
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      section: string                  # brief section name (e.g., "Subtask Structure", "File Impact Map")
      category: string                 # optional — issue category (e.g., "dep_graph" for Criterion 12 violations, "file_path" for missing files, "cited_line_premise" for Criterion 1's STALE cited-line-premise sub-check — a file that EXISTS but whose cited content moved, distinct from "file_path"'s missing-file meaning, "executable_acceptance" for Criterion 14 cmd:/bare-shell trust-surface findings, "canonical_source" for Criterion 15 canonical-list / source-of-truth verification findings, "rule_conformance" for Criterion 17 house-rule conformance findings); free-form, but use canonical names where defined
      description: string              # what's wrong
      suggestion: string               # optional — how to fix
  summary: string                      # required — concise review summary
```

**Validation rules:**
- `schema_version` must equal `1`
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one issue with BLOCKING or HIGH severity
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- `section` must reference a valid brief section name
- `category` is optional but recommended; when present, prefer canonical names — `dep_graph` for Criterion 12 (provides/requires) violations, `file_path` for missing-file violations, `cited_line_premise` for Criterion 1's STALE cited-line-premise sub-check, `feasibility` for Criterion 11 issues, `executable_acceptance` for Criterion 14 (`## Executable Acceptance` `cmd:`/bare-shell bullets), `canonical_source` for Criterion 15 (canonical-list / source-of-truth verification), `lane_overlap` for Criterion 16, `rule_conformance` for Criterion 17 (an applicable `must` house rule contradicted, or its checkable `rule: <id>` bullet missing)
- `summary` must be present

**Severity mapping for plan review:**
- BLOCKING: Missing/nonexistent file paths, missing required brief sections
- HIGH: Incorrect dependencies, unsafe parallelism (false LAUNCHABLE), logic errors
- MEDIUM: Vague acceptance criteria, missing skill references, incomplete risk assessment
- LOW: Style improvements, optional enhancements

---

