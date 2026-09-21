# Supervisor Job: Floor — attention-derived lane groups + catch-up feed

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (v15.81.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (non-main worktrees from other concurrent plugin activity — acknowledged, non-blocking)
- **Source requirement:** .supervisor/requirements/orca-derived/05-floor-attention-and-feed.md

## Task
**Goal:** The Floor's lane list groups by DERIVED state — **Needs you · Working · Done · Quiet** (`unknown` lanes never silently collapsed into `Quiet`) — every state stated as "as of the last recorded event, N s ago," plus a newest-first feed of the events the session log already holds, with previews and per-tab unread counts.

**Problem Statement:**
The Floor currently renders one lane per agent as event-count + last-event age, under a permanent "liveness unavailable" note (`loomwright/scripts/floor-ui/floor.js`'s `renderLanes`, 2049-line file — read it in full before touching it, its comments carry load-bearing honesty invariants this item must not violate). It cannot answer "is anything waiting on me" at a glance, and it cannot say what happened while the operator was away. v15.79.0/v15.80.0 (PR #231/#233, already merged) gave the plugin the raw signals this item needs — `agent_lifecycle:waiting/failed` events and `worker_checkpoint` — but nothing derives a Needs-you/Working/Done/Quiet grouping from them or renders a feed. `loomwright/docs/FLOOR_UI.md`'s "What it does not claim" section also still says "No spawn event exists in any log," which has been stale since `agent_identity` shipped (2026-09-07) — this item corrects that line too.

## Acceptance Criteria
- [ ] Given `build-floor.sh`'s existing per-agent projection (`sessions.detail.current.agents[]`, which already carries `last_checkpoint` since PR #233 and `agent_scope`/`identified_at` from earlier), when this PR lands, then it additively gains ONE new per-agent field, `lifecycle` (`{state, since_epoch, reason, last_checkpoint, ended_without_result}`), derived per `.supervisor/requirements/orca-derived/01-agent-lifecycle-ledger.md` §4's rules: `state` derives from the MOST RECENT recognized lifecycle-relevant row for that `agent_id` (`agent_lifecycle:waiting` → `waiting`; a fresh heartbeat/event → `working`; a terminal row with `result_block_present:true` → `done`; `agent_lifecycle:failed` → `failed`; nothing recent → `quiet`); `since_epoch` for a spawn comes from `agent_identity.recorded_at` (that row carries no `ts` by design — see `identified_at`'s own existing FLOOR_PROJECTION doc entry) and every OTHER state's `since_epoch` comes from a real event `ts`; `reason` is carried through from `agent_lifecycle:waiting`'s own `reason` field when present; `last_checkpoint` is the ALREADY-SHIPPED field (do not re-derive it — reuse it verbatim); `ended_without_result` is TRI-STATE (`true`/`false`/absent) exactly as item 01 §4 derives it (a `subtask_complete`/`token_ledger` row with `result_block_present:false` → `true`; explicit `false`; the key absent → `unknown`, never guessed). A lane with NO lifecycle-relevant row at all carries NO `lifecycle` field (stays `unknown` downstream), never a default `quiet`.
- [ ] Given the projected `lifecycle.state` values, when `floor.js` renders the Lanes section, then lanes are grouped into exactly four visible sections — **Needs you** (state `waiting` or `failed`) · **Working** (state `working`) · **Done** (state `done`) · **Quiet** (state `quiet`, i.e. no recent event but a lifecycle WAS recorded at some point) — with **Needs you always first**, and EMPTY groups are omitted from the DOM entirely (never rendered as a header with zero rows). A lane with NO `lifecycle` field renders under a fifth, explicit **`unknown`** label — it is NEVER folded into `Quiet` (a lane with no evidence is a different fact from a lane with stale evidence).
- [ ] Given the existing permanent "liveness unavailable" note in `floor.js`/`FLOOR_UI.md`, when this PR lands, then its wording is REPLACED (not deleted) with an equally honest, narrower claim: "state is inferred from the last recorded hook event; a lane can be `Working` and dead" — the claim shrinks, it does not disappear, and every group heading itself also states its own derivation rule in words (mirroring this file's own established "state the rule where it's shown" convention, e.g. the `renderLanes` comments' running commentary on tri-state honesty).
- [ ] Given the session log's existing event types, when `floor.js` renders a NEW "Feed" section, then it lists, newest-first: `subtask_complete` (a worker ended — corrected per item 01/02's own finding: there is NO `agent_result` event), `agent_lifecycle:waiting`/`agent_lifecycle:failed`, `worker_checkpoint`, `pr_created`, `self_heal_iteration`, `review_heal_done`, `autonomous_done` — each row shows a `last_assistant_message` preview WHEN the projector carries one for that event. `token_ledger` (a ~13k-line volume event in this repo's own real logs) is DELIBERATELY EXCLUDED from the feed (it is the same stop moment as `subtask_complete` for non-worker roles and would drown the feed) — the projector folds it into the lane's `lifecycle` derivation instead, never into the feed list.
- [ ] Given the feed's unread state, when a viewer scrolls/reads the feed in one browser tab, when they RELOAD that same tab, then the unread count/highlighting survives (persisted via the SAME `sessionStorage`-with-try/catch-wrapped, memory-fallback pattern `floor.js` already uses for its page token — read that existing code before adding a second, inconsistent persistence mechanism); when they open a NEW tab, then unread resets (sessionStorage is per-tab by design — verify this is the actual, intended behavior, not an accidental one). Unread = "newer than the last-seen `ts` kept beside the existing token, same lifetime rules."
- [ ] Given a fixture with one `waiting` lane, one heartbeat-fresh (`working`) lane, one `done` lane, one 40-minutes-quiet lane, and one lane with NO lifecycle evidence at all, when the page renders, then it shows exactly the four non-empty derived groups PLUS the `unknown` label for the fifth lane — and the EXISTING `?stale=` fixture-staleness convention (read how other fixtures under `loomwright/scripts/fixtures/floor-ui/` use it) still applies unchanged.
- [ ] Given `loomwright/scripts/test-setup-ui.sh`'s existing GET-byte-identity assertion for the server (a test that the served page/assets are byte-stable except for the actual page content), when this PR lands, then that assertion STILL PASSES — this PR changes page rendering/content, not server behavior, so the byte-identity contract for what the SERVER does (as opposed to what the page shows) must hold.
- [ ] Given `loomwright/docs/FLOOR_UI.md`'s "What it does not claim" section (currently: "No spawn event exists in any log"), when this PR lands, then that sentence is corrected to reflect that `agent_identity` DOES exist (shipped 2026-09-07) — while preserving whatever OTHER non-claims in that section remain true (read the whole section before editing — do not remove claims that still hold).
- [ ] Given `docs/RESULT_SCHEMAS.md`'s `FLOOR_PROJECTION` section, when this PR lands, then it gains a new additive-field entry (mirroring the EXACT prose style/rigor of the existing `last_checkpoint`/`identified_at`/`agent_scope` entries immediately above it — read all three before writing a fourth) documenting `lifecycle` — no `schema_version` bump (purely additive, matching every prior FLOOR_PROJECTION addition in this file).

## Outcomes Rubric
- Four derived groups render correctly with Needs-you first, empty groups omitted; the derivation rule is stated in words on the page, not just in code comments
- `unknown` (no lifecycle evidence) is NEVER collapsed into `Quiet` (stale-but-recorded evidence) — these are different facts and stay visually/textually distinct
- Feed is strictly time-ordered (no other ranking), previews sourced from the projection (never fabricated), `token_ledger` excluded by design
- Unread state persists correctly per-tab (survives reload, resets in a new tab) via the SAME existing sessionStorage pattern, not a second one
- The permanent liveness non-claim is narrowed honestly, never silently deleted or overclaimed
- `FLOOR_UI.md`'s stale "no spawn event" line is corrected without removing still-true claims nearby
- `check-doc-currency.sh` stays green after the FLOOR_PROJECTION additive-field doc entry

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Floor attention groups + feed (projector derivation, page rendering, doc fixes) | all | 5 modify, 0 create | `skills/state-management/SKILL.md` | LAUNCHABLE |

**Split reason:** none — single subtask. The projector-side derivation (`build-floor.sh`) and the page-side rendering (`floor.js`/`floor.css`) are two halves of ONE feature that must land together (a page change with no data, or data with no page change, is not independently shippable/testable) — below the file-conflict, context-bound, and genuine-parallelism thresholds as a cohesive unit.

### Provides / Requires Schema

```yaml
# Subtask 1 — Floor attention groups + feed (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "lifecycle"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.js", name: "renderLanes"}
  - {kind: "file", path: "loomwright/scripts/floor-ui/floor.css"}
  - {kind: "file", path: "loomwright/docs/FLOOR_UI.md"}
  - {kind: "file", path: "loomwright/docs/RESULT_SCHEMAS.md"}
requires: []
lanes:
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/floor-ui/floor.js"
  - "loomwright/scripts/floor-ui/floor.css"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/docs/FLOOR_UI.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md` (session JSONL conventions this reads) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `floor.js` is a large (2049-line), densely-commented file with explicit honesty invariants (e.g. never say "not yet" when an emitter genuinely cannot fire; never let a dot's color be the only read-only signal) — a naive edit could silently violate one of these while adding the new feature | HIGH | Read the WHOLE file, not just `renderLanes`, before editing; preserve every existing invariant the comments describe; the new groups/feed must follow the SAME "state the rule, state the limit" register as the existing code |
| The `unknown` vs `Quiet` distinction is easy to accidentally collapse (both look like "nothing recent") — this is explicitly called out as a MUST-NOT in the source requirement | HIGH if violated | Dedicated acceptance criterion + fixture with a no-lifecycle-evidence lane specifically testing this is never mislabeled |
| A live UI change — per this project's own `run` skill convention, a UI change should be verified by actually running the app and looking at it, not just by unit tests | MEDIUM | Worker should start the Floor locally (`loomwright:ui` / `scripts/setup-floor-ui.sh` or equivalent — check `loomwright/docs/FLOOR_UI.md`'s own "serve loop" section for the actual start command) against a fixture and visually confirm the four groups + feed render before declaring done, not just pass automated tests |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | LOW | Single-subtask, edits to 1 script + 2 UI files (+2 test files) + 2 docs; within Single-Agent Path capacity though on the larger end (JS/CSS UI work, not just prose/bash) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-17-floor-attention-and-feed.md
```

## Outcome
- **Heal loop ran:** true
- **Heal iterations:** 2 fix cycles (round 1: internal review PASS w/ 2 MEDIUM accessibility/doc findings, fixed; round 2: external claude-review 3 findings — 2 real (since_epoch naming, done-state scope doc), 1 accepted pre-existing gap (frontend test coverage) — 2 fixed, PASS)
- **Heal decision:** PASS (external claude-review clean on findings 1/3; finding 2 explicitly characterized as pre-existing, non-regressing)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/236
- **Merge commit:** ee31cc2682cb6d0f0ac8227dee8219235d9468b9 (merge commit, --admin — required 1 approving review, no human reviewer available; standing order)
- **Honest limit carried forward:** no live browser/screenshot verification was possible in this environment; logic traced by hand against fixtures and cross-checked against executable server-side tests. Frontend (floor.js) has zero executable test coverage for this feature, matching the file's pre-existing testing methodology gap (not a regression).
- **Version:** no plugin version bump (UI feature PR; no version-bump convention enforced by check-doc-currency.sh beyond count/string consistency, which stayed green throughout)
