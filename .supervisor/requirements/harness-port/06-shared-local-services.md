# 06 — Shared local services declared, not assumed (host CLAUDE.md → brief → spawn paste)

## Status: pending
## Depends on: 01 (worker rule (c) consumes the spawn line)

## Problem
Parallel workers in worktrees can reset or write the same local `<service>` (database, cache, dev server on a shared
port) and corrupt a sibling's run. Nothing in the brief, the spawn contract or the worker prompt names the services
a project shares. The information exists only in the operator's head or in a host `CLAUDE.md` paragraph no agent is
told to look for. And because `.supervisor/` is absent inside worktrees and the spawn contract is
pointers-not-payloads, a line written only into the brief's `## Environment` would never reach the worker that needs it.

## Goal
An optional `## Shared local services` section in the host project's `CLAUDE.md` is copied — bounded — into the
brief's `## Environment` and into every worker spawn prompt as one `Shared local services:` line; item 01's rule (c)
then applies. Section absent ⇒ no brief line, no spawn line, byte-identical.

## Scope
1. **`loomwright/agents/launch-pad.md` Phase 1 VALIDATE** — new action appended after action 7 (no renumber): read
   the host `CLAUDE.md` for a heading matching `^## Shared local services\b` (case-insensitive on the words, exact
   level 2); take the body up to the next `^## ` heading; **bound it**: strip fenced code blocks entirely, keep at
   most 10 non-empty lines, append `(truncated)` when more existed; collapse to one line joined by ` · `. Hold as
   `shared_local_services`. Absent heading or empty body ⇒ unset.
2. **`launch-pad.md` Phase 5 PACKAGE step 3a** (beside `Source requirement`): when set, emit
   `- **Shared local services:** <line>` in `## Environment`; when unset, emit nothing — copy the existing
   "do NOT emit an empty or 'none' placeholder" sentence verbatim.
3. **`loomwright/skills/supervisor-readiness/SKILL.md`** brief template `## Environment`: add the optional
   `Shared local services` row with the omit rule — AND add the missing `- **Base commit:** {sha}` row (unconditional
   since v15.19.0; pre-existing drift — fix it here, note it in the CHANGELOG line).
4. **`loomwright/skills/async-orchestration/SKILL.md` Part 2 spawn contract:** when the brief's `## Environment`
   carries the line, paste it verbatim into every worker spawn prompt as `Shared local services: <line>` (parallel,
   sequential, Single-Agent). This is a deliberate paste exception — add the row to
   `loomwright/docs/POINTER_AUDIT.md` with the justification "worktree workers cannot read the brief; ≤10 lines,
   fences stripped, bounded at the producer". `execute-manager` budget 3216 — re-measure.
5. **`loomwright/agents/plan-reviewer.md` Criterion 9 (Completeness):** one sentence in its `Note:` — the
   `Shared local services` line is optional and its absence is not evaluated (mirror the `## Feasibility` sentence).
   Criterion count stays 16.
6. **Portability guard (this repo's own CLAUDE.md is a host too):** the plugin text names only `<service>`,
   `<how to reach it>`, `<PORT_ENV>`; the example in the template is `- <service>: <how to reach it> (<PORT_ENV> if
   any)` — no product, host, or port number.
7. **Docs:** CHANGELOG paragraph; version bump; `check-doc-currency.sh` green.

## Non-goals
No parsing of the service list into structure; it is free text for the worker to read. No enforcement — the plugin
cannot stop a worker's `<service-cli>` call; the rule is advisory and the honest-limits item (01a)
carries what the worker skipped. No port allocation service; the ordinal offset is a convention the host app may
ignore, and item 01's rule says so.

## Acceptance criteria
- Fixture host `CLAUDE.md` WITH a 3-line section ⇒ the brief differs from the WITHOUT fixture by exactly one
  `- **Shared local services:** …` line (fixture diff test; record the command in the PR body).
- Fixture with 14 body lines including a fenced block ⇒ the line has 10 items, no fence content, ends `(truncated)`.
- Fixture with the heading and an empty body ⇒ no line.
- Spawn contract text shows the paste rule; POINTER_AUDIT has the row; `grep -c 'Shared local services'
  loomwright/skills/async-orchestration/SKILL.md` ≥ 1.
- `supervisor-readiness/SKILL.md` template now shows `Base commit`; `grep -n 'Base commit' …` ≥ 1.
- Plan Reviewer Criterion 9 body unchanged except the added optional-note sentence; criteria count 16.
- `grep -nE 'localhost|127\.0\.0\.1|:[0-9]{4}\b|postgres|mysql|redis|docker' <changed plugin files>` → 0 new hits
  vs `origin/main`.
- `check-token-budget.sh`, full test loop + root checks green.

## Verified premises (re-check before starting)
- `launch-pad.md` Phase 1 actions 1–7 (7 = source-doc provenance, advisory) and Phase 5 step 3a wording.
- `supervisor-readiness/SKILL.md` §"Supervisor-Ready Brief Template" `## Environment` rows (has `Source requirement`,
  lacks `Base commit`).
- `async-orchestration/SKILL.md` §"Pointers, not payloads" naming `docs/POINTER_AUDIT.md` as the exception list.
- `plan-reviewer.md` Criterion 9 body + its `## Feasibility` optional note.
