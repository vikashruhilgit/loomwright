## LAUNCH_PAD_RESULT

Produced by Launch Pad at the end of its workflow (after Phase 6 SAVE) to communicate the outcome and — critically — the **exact path of the saved Supervisor-Ready Brief** for programmatic consumers (notably `/autonomous` PLAN phase, which previously relied on a fragile `ls`-diff of `.supervisor/jobs/pending/`).

**Added in v14.2.0.** Emission is non-blocking — the schema is purely additive. Existing Launch Pad consumers (the user reading the markdown output) are unaffected; new consumers (`/autonomous`) read the structured block from the transcript, or from the SubagentStop hook payload when Launch Pad runs in `-runner` mode (`claude --agent loomwright:launch-pad-runner`).

```yaml
LAUNCH_PAD_RESULT:
  schema_version: 1                    # integer, required — always 1
  status: enum [saved, discarded, blocked, aborted]  # required
  saved_brief_path: string | null      # required field; null unless status=saved
  summary: string                      # required — one-line outcome (≤ 200 chars recommended)
  cmd_bullets_stripped_non_interactive: true  # OPTIONAL, additive (v15.90.0+, red-team-hardening item 05) — see below
```

**Validation rules (schema_version: 1):**
- `schema_version` must equal `1`.
- `status` must be one of: `saved` | `discarded` | `blocked` | `aborted`.
- `saved_brief_path`:
  - When `status: saved` → MUST be a non-empty string matching `.supervisor/jobs/pending/*.md`, and the file MUST exist on disk at emission time.
  - When `status ∈ {discarded, blocked, aborted}` → MUST be the literal YAML `null` (not the string `"null"`, not empty).
- `summary` must be a non-empty string.
- `cmd_bullets_stripped_non_interactive` (OPTIONAL, additive — no `schema_version` bump; `scripts/validate-launch-pad-result.py` accepts it as a fifth allowed key alongside the original four): when PRESENT, MUST be the YAML boolean `true` (lowercase) — any other value (including the string `"true"`, `"True"`, or `false`) is rejected. When ABSENT, treated as `false` — Launch Pad's Phase 6 action 2a OMITS the field entirely rather than emitting `false` explicitly (keeps the common case's YAML unchanged; see `agents/launch-pad.md` Phase 7 action 4).

**Status semantics:** `saved` (Phase 6 save completed, file on disk) · `discarded` (user chose Discard, no file) · `blocked` (Phase 1 BLOCKER or Plan Review FAIL × 3 without override; save never offered) · `aborted` (user aborted mid-flight; no clean Phase 6 outcome).

**`cmd_bullets_stripped_non_interactive` (v15.90.0+, red-team-hardening item 05 — "cmd: valve by provenance").** `true` when Launch Pad's Phase 6 action 2a auto-stripped ≥1 unstamped/stale `cmd:`/bare Executable Acceptance bullet from the brief during a **non-interactive** run (`--non-interactive`/`--non-interactive-fallback`) because Plan Reviewer Criterion 14 escalated to NEEDS_HUMAN and there was no human to ask `approve-and-stamp`/`strip-cmd-bullets`/`discard`. This is the non-interactive path's fail-safe: it NEVER silently proceeds with an unreviewed executable brief — it strips rather than keeps. Consumers (e.g. `/autonomous` PLAN phase, a postmortem reader) can use this as an auditable signal that a brief's Executable Acceptance section was machine-modified after Plan Review's first pass.

**Emission cadence:** emitted **once per Launch Pad invocation**, immediately after Phase 6 (whether or not a file was written). The SubagentStop hook (`scripts/validate-launch-pad-result.py`) validates the block in the agent-owned (`-runner`) path; for the inline slash-command path the autonomous-loop skill reads the last emitted block from the transcript and runs the same validator in `--raw` mode, mirroring the `SUPERVISOR_RESULT` pattern.

**Example (status: saved):**
```yaml
LAUNCH_PAD_RESULT:
  schema_version: 1
  status: saved
  saved_brief_path: .supervisor/jobs/pending/2026-05-28-add-version-command.md
  summary: Plan Review PASS on attempt 1/3; saved Supervisor-Ready Brief for /supervisor handoff.
```

**Example (status: discarded):**
```yaml
LAUNCH_PAD_RESULT:
  schema_version: 1
  status: discarded
  saved_brief_path: null
  summary: User chose Discard at Phase 6 after reviewing the assembled brief.
```

**Consumer pattern (`/autonomous` PLAN phase):** when `status: saved`, read `LAUNCH_PAD_RESULT.saved_brief_path` directly as the iteration's `current_brief_path`. When `status ∈ {discarded, blocked, aborted}`, exit the loop with the corresponding terminal status. The `ls`-diff fallback (Launch Pad pre-v14.2.0) remains supported during the transition window but is no longer primary.

---

