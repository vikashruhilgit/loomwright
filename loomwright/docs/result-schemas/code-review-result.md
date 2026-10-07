## CODE_REVIEW_RESULT

Produced by Code Reviewer agent on review completion.

```yaml
CODE_REVIEW_RESULT:
  schema_version: 3                    # integer, required — v3 adds review_mode + consistency audit fields
  review_mode: enum [diff_review, consistency_audit]  # required — plan/prompt review is an audit_focus, not a mode
  audit_focus: string[]                # required — non-empty iff review_mode=consistency_audit; else []
                                       # allowed values: mirrored_prompt, metadata, counts, docs, hooks, plan_prompt
                                       # A single audit may carry multiple focus tags.
  trigger_paths_detected: string[]     # required — subset of reviewed paths matching audit trigger surfaces
                                       # (agents/, commands/, skills/, docs/, plugin.json,
                                       # hooks.json, .supervisor/jobs/, README.md, CLAUDE.md,
                                       # .claude-plugin/README.md, SKILLS_INDEX.md). Empty = no trigger fired.
                                       # INVARIANT: non-empty ⇒ review_mode MUST equal "consistency_audit".
  scope_expanded: string[]             # required — files added beyond the original diff; [] if no expansion
  files_checked: string[]              # required, non-empty — all files actually read during review
  consistency_checks:                  # required when review_mode=consistency_audit; omit otherwise
    mirrored_prompts:   enum [pass, fail, not_applicable]
    version_strings:    enum [pass, fail, not_applicable]   # authoritative-tier only
    counts:             enum [pass, fail, not_applicable]
    workflow_alignment: enum [pass, fail, not_applicable]
    hooks_parity:       enum [pass, fail, not_applicable]   # advisory; fail cannot raise severity > LOW
  consistency_summary: string          # required when review_mode=consistency_audit
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      category: enum [new, pre_existing, nit, drift]  # drift added in v3
      drift_kind: enum [version_authoritative, version_secondary, mirrored_prompt,
                        count, workflow, hooks_parity, wording]  # required when category=drift
      file: string                     # file path, or a sentinel: environment (environment-blocked run), brief (unaddressed acceptance criterion; omit line)
      line: integer                    # optional — line number
      description: string              # what's wrong
      suggestion: string               # optional — how to fix
  pattern_proposals: object[]          # optional — patterns for CLAUDE.md
    - pattern: string
      file: string
      description: string
  knowledge_sources_used: string[]     # optional (v14.28.0+) — advisory, non-gating telemetry: which memory sources the reviewer consulted. Reviewer-reachable tags ONLY: `project_memory`, `agent_memory:code-reviewer`, `brain_context` (its consult reads per-agent + project memory). **(Retired 2026-08-17 — graphify-tier retirement.)** The reviewer's optional brain-context consult was removed with the tier; `brain_context` **stays in the reviewer-reachable vocabulary** (open set, no schema change; past emissions remain valid) but has **no live reviewer path that emits it** as of this change. The reviewer does NOT run `read-lessons.sh` or consult the System Twin, so it MUST NOT emit `lessons:<category>` or `twin:<path>` on a CODE_REVIEW_RESULT (those belong to the cross-agent open set on SUPERVISOR_RESULT). Self-reported — records *claimed* usage, not machine-verified reads. Absent ⇒ "none used". NEVER changes the `decision`, NEVER blocks the PR; NOT enumerated by the Code Reviewer SubagentStop hook. Additive — does NOT bump `schema_version` (stays 3).
  summary: string                      # required — concise review summary
```

**Validation rules (schema_version: 3):**
- `schema_version` must equal `3` (v2 still accepted for backward compatibility / legacy agent memory)
- `review_mode` must be one of: `diff_review`, `consistency_audit`
- `audit_focus` is required; non-empty iff `review_mode == consistency_audit`; each element ∈ {mirrored_prompt, metadata, counts, docs, hooks, plan_prompt}
- `trigger_paths_detected` is required (may be empty)
- **Cross-field invariant:** if `trigger_paths_detected` is non-empty → `review_mode` MUST equal `consistency_audit`
- `files_checked` must be a non-empty array
- `scope_expanded` must be present (may be empty for `diff_review`)
- When `review_mode == consistency_audit`: `consistency_checks` object with all 5 sub-keys present; `consistency_summary` non-empty
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- Each issue must include `category` ∈ {new, pre_existing, nit, drift}
- When `category == drift`: `drift_kind` required
- **`drift_kind` severity caps are enforced** (issues violating these caps are rejected):
  - `drift_kind ∈ {count, version_secondary}` → severity MUST be `≤ MEDIUM`
  - `drift_kind ∈ {hooks_parity, wording}` → severity MUST be `≤ LOW`
  - `drift_kind ∈ {version_authoritative, mirrored_prompt, workflow}` → no cap
- When `decision=FAIL`: `issues` must contain at least one issue with `category ∈ {new, drift}` AND severity ∈ {BLOCKING, HIGH}. Because of the caps above, `count`, `version_secondary`, `hooks_parity`, and `wording` drift cannot satisfy FAIL on their own
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- `knowledge_sources_used` is optional (additive in v14.28.0, schema version unchanged at 3). When present it MUST be an array of short lowercase source-tag strings drawn ONLY from the reviewer-reachable subset `project_memory`, `agent_memory:code-reviewer`, `brain_context` — the Code Reviewer does not run `read-lessons.sh` or consult the System Twin, so `lessons:<category>` / `twin:<path>` MUST NOT appear here (they are valid on SUPERVISOR_RESULT, whose run does read those). **(Retired 2026-08-17 — graphify-tier retirement.)** The reviewer's optional brain-context consult was removed with the tier, so no live reviewer path emits `brain_context`; the tag **stays in the reviewer-reachable vocabulary** (open set, no schema change — stays 3; past emissions remain valid). The value is **self-reported** (claimed usage, not machine-verified). Absent ⇒ "none used". The field is **advisory and non-gating**: it NEVER changes the `decision`, NEVER blocks the PR, and is NOT enumerated by the Code Reviewer SubagentStop hook, so blocks with or without it validate unchanged. Pre-v14.28.0 blocks without this field remain valid.
- `summary` must be present

**Validation rules (schema_version: 2, legacy):**
- `schema_version` must equal `2`
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one `new` issue with BLOCKING or HIGH severity
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- Each issue must include `category` ∈ {new, pre_existing, nit}
- Only `new` issues with BLOCKING/HIGH severity can trigger FAIL
- `summary` must be present

**Migration notes (v2 → v3):**
- v3 introduces review modes and a repo-consistency audit contract. Existing v2 producers remain valid.
- The `drift` category and `drift_kind` enum make consistency-audit findings first-class issues rather than free-text notes, and the severity caps prevent advisory drift (counts, hooks parity, wording) from blocking PRs.
- Plan/prompt review is represented as `audit_focus: plan_prompt` (not a distinct `review_mode`), so a single audit touching both prompts and metadata emits one result with multiple focus tags instead of requiring mode precedence rules.
- The `trigger_paths_detected` ↔ `review_mode` cross-field invariant is what makes the new hook enforcement possible: the reviewer is accountable to its own self-report of which trigger surfaces the diff touched.

---

