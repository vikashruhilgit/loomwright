### Crash-safety contract

The run file is the **only** copy of resume state, so (per `skills/automate-loop/SKILL.md` §3):

- **Atomic write (temp + rename):** every update is written to a temp file and `mv`-renamed into place — a crash mid-write never leaves a half-written file; the prior intact version survives.
- **Validated before rename (fail CLOSED on the payload):** `automate-helpers.sh runfile-write` refuses (exit 1, temp removed, run file byte-unchanged, stderr tag `[runfile_write_refused]`) staged content that is empty, lacks the `# Automate Run:` title, a `## Status:` line or the `## Queue` heading, or — replacing an existing run file — does not keep its `## Progress` block as a prefix; `progress-append` / `queue-checkoff` refuse a target with no title instead of fabricating a `## Progress` stub on it. A shrinking line count is NOT a refusal reason (`## Current` legitimately loses lines) — the deliberate difference from `VERIFY_QUEUE`'s line-count guard below. Spec: `skills/automate-loop/SKILL.md` §3 "Validate before rename".
- **`## Progress` is APPEND-ONLY** — never rewritten; existing lines are immutable, new lines are appended.
- **Rewrites are confined** to `## Queue` checkboxes and the `## Current` block (`## Status` changes atomically and rarely; `## Source`/`## Run Config` change rarely).
- **`## Current` moves only through `automate-helpers.sh current-set`** (item form or run-level form, enum-validated, exit 1 with the file byte-unchanged on a refusal); `progress-append` exits 3 with `current_not_set: <line>` on stderr (the line still appended) when a `picked` / `ran /autonomous` / `owned drain started` line meets an unset `## Current`, and RESUME's `current-rebuild` repairs one that was never set, or a `done` one left naming the previous item after the next `picked` line (a `picked` line over a `done` `## Current` is exempt from the exit 3, so this RESUME repair is its only backstop). Spec: `skills/automate-loop/SKILL.md` §3 "`## Current` moves only through `current-set`".
- **Resume = belief vs truth:** the run file is the loop's *belief*; on every start the engine reconciles each in-flight item against ground truth (`gh pr view --json state,mergedAt` / `git branch --contains` / the requirement's `## Status: done` stamp) **before** trusting a checkbox (`skills/automate-loop/SKILL.md` §4).

### Optional terminal JSONL breadcrumb (secondary — never the source of truth)

The engine MAY append **ONE** terminal line per run to the existing `.supervisor/logs/<run_id>.jsonl` (the shared session-log convention) for trend tooling. This is a **secondary breadcrumb only** — the run file (`.supervisor/automate/<run_id>.md`) remains **authoritative** for all resume/state decisions; the JSONL line is never read as the source of truth.
