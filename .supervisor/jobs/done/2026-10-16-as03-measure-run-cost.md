# Supervisor Job: Per-item /automate cost report — tokens, turns, peak context, subagents, wall time (automate-speed/03)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L7 (lane L7 clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/03-measure-run-cost.md
- **Base commit:** 142540b8210a4b206e87e2b4349999c9978f8e29

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe + jq, same as `read-token-ledger.sh` / `build-insights.sh` |
| 2 | Dependency Availability | GO | no new dependency; transcripts are the Claude Code JSONL files under `~/.claude/projects/` |
| 3 | Architecture Fit | GO | extends the existing fail-SAFE reader and the existing `/insights` builder (requirement Scope forbids a parallel tool) |
| 4 | Scope vs Supervisor Capability | GO | one worker; ~9 files, well under the context-bound threshold |
| 5 | Hard Blockers | CAUTION | reading `~/.claude/projects` transcripts may count as vendor coupling in `scripts/check-vendor-coupling.sh` (ratcheted per-path allowance in `loomwright/docs/vendor-coupling-manifest.json`) — a raise needs an `allowance_reasons` entry in the same PR |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a read-only per-item cost report to `read-token-ledger.sh` (`--per-item <runfile>`), render the same table in `/insights`, and commit a baseline evidence file measured from real per-message transcript `usage`.

**Problem Statement:**
The owner and every later automate-speed item need to know what one `/automate` item costs and in which phase.
Currently, the token ledger records a transcript-bytes proxy per stopping agent and `/insights` shows per-session context size, but nothing answers "what did item X cost, and where" — the 2026-10-15 numbers were computed by hand from `~/.claude/projects` transcripts. This makes every later saving claim uncheckable.
Success looks like one command that prints, per item and per phase, real-usage context tokens, output tokens, turns, peak context, subagent tokens by agent type and wall time, plus a committed baseline file later items are measured against.

**Design (grounded in the live repo at the base commit):**
- **Reuse `phase-timing.sh` — no second derivation of what it already computes.** `phase-timing.sh --run <rf> --item <path> --logs-dir <root>/.supervisor/logs` already applies the ITEM SCOPE segment rule, joins the `.owner` `cc_session_id=` and returns `.item.pick`, `.item.park` and `.item.pick_to_park.seconds`. The per-item report calls it (as a sibling, `"$(dirname "$0")/phase-timing.sh"`, the same way `build-insights.sh` does) and takes the item's segment start/end, its `session_id` and its wall time from that record; it does NOT re-implement the segment rule. A fixture case asserts the report's item wall time equals `phase-timing.sh`'s `.item.pick_to_park.seconds` for the same run. Only the per-PHASE windows below are new, because `phase-timing.sh` does not emit the Launch Pad / Phase 4.5 / drain spans from Progress lines.
- **Session resolution (run → Claude Code transcripts).** A run file's `## Progress` carries `session_id <sid> (<item>)` lines (the `/autonomous` session id, e.g. `auto-2026-10-13-210421`). For each `<sid>`, the Claude Code session ids are read from `<root>/.supervisor/logs/<sid>.owner` (`cc_session_id=<uuid>` line) AND every distinct `"cc_session_id"` value in `<root>/.supervisor/logs/<sid>.jsonl` (one `/autonomous` session can span several Claude Code sessions — PR #533's `auto-2026-10-13-210421` names four). A `run created (session <uuid>)` Progress line adds that uuid. The transcripts are `<projects>/*/<uuid>.jsonl` (main thread) and `<projects>/*/<uuid>/subagents/agent-*.jsonl`, the agent type read from the sibling `agent-*.meta.json` `agentType`. `<projects>` is resolved as: the `--projects-dir <dir>` flag, else the environment variable `LOOMWRIGHT_CC_PROJECTS_DIR`, else `$HOME/.claude/projects`. `build-insights.sh` takes no arguments, so its `/insights` call relies on the same resolution, and `test-insights.sh` exports `LOOMWRIGHT_CC_PROJECTS_DIR=<mktemp fixture>` (never the real home dir).
- **Lanes.** With repeated `--root`, a root that is a lane clone (its `.supervisor/lane.json`, the existing `lane_run_file` helper) contributes the lane run file's sessions; lane transcripts live in `*-lanes-automate-*` project dirs, which the `<projects>/*/` glob already covers. Their usage is attributed to the lane's item.
- **Usage read.** Only assistant messages carrying `message.usage`; each message counted ONCE by `message.id` (the transcript writes one message several times). Context tokens = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`; output = `output_tokens`; turns = distinct main-thread assistant message ids; peak context = the max per-message context of the main thread. Subagent usage is reported separately, summed by agent type.
- **Item and phase windows.** The item's segment comes from `phase-timing.sh` (above); a message counts toward an item/phase by its `timestamp`. Phase boundaries come from the item's Progress lines, in this order: `picked` → `launch-pad saved` (Launch Pad ends, Build starts) → `FINALIZE:` (Build ends, Phase 4.5 starts) → `ran /autonomous` (Phase 4.5 ends) → `owned drain started` → `drain READY|ESCALATED` (Drain) → `parked` (Decide). Each `Phase 4.5 iter <n>` line is the END of iteration n (iteration 1 runs from `FINALIZE:`); they are sub-rows under Phase 4.5. Only `picked`, `session_id`, `ran /autonomous`, `owned drain started` and `drain READY|ESCALATED` are pinned by the run-file schema; `launch-pad saved`, `FINALIZE:` and `Phase 4.5 iter` are model-written, so match them tolerantly (case-insensitive prefix after the timestamp, extra text ignored). A missing boundary line makes BOTH spans next to it `not recorded`, never 0 and never merged into a neighbour. **Drains** are not matched from the first `owned drain started` line: they come from `phase-timing.sh`'s `.item.owned_drains[]` (each with start, end, result and `fix_now`), one Drain sub-row per drain, a fix-now re-drain marked as such, so a second drain's usage is attributed to its own sub-row. **No `parked` line** (an item that goes from `drain READY` straight to the next resume/pick): `phase-timing.sh` returns no park, so the item's wall time and its Decide row both print `not recorded`. For PR #533 (`automate-2026-10-13-181331`, item `verified-rule-checks`) the lines give Launch Pad ≈13m (15:33:58→15:46:53), Build ≈40m (→16:27:01), Phase 4.5 ≈85m (→17:52:01), Drain ≈2h11m (17:52:42→20:03:50).
- **Output.** One row per item, then one indented row per phase under it; every token figure labelled `real usage`; the existing proxy ledger is never mixed in. Fail SAFE: always exit 0; no resolvable transcript ⇒ a named `no_transcripts` reason on stderr and a row with no number (never a 0 that reads as cheap).

## Acceptance Criteria
- [ ] AC1 — Given an `/automate` run file, when `read-token-ledger.sh --per-item <runfile>` runs, then it prints one row per Queue item with context tokens, output tokens, turns, peak context, subagent tokens by agent type and wall time, and one row per phase under each item, every token figure labelled real usage.
- [ ] AC2 — Given a fixture transcript where one message id appears 3 times, when the per-item report runs, then that message's usage is counted once (fixture test in `test-read-token-ledger.sh`).
- [ ] AC3 — Given a lane run (a `--root` lane clone whose `.supervisor/lane.json` names the parent run), when the per-item report runs with that root, then the lane clone's sessions are attributed to the lane's item.
- [ ] AC4 — Given a run whose sessions resolve to no transcript, when the per-item report runs, then it exits 0, prints a named `no_transcripts` reason on stderr and prints no number for that item.
- [ ] AC5 — Given the existing modes, when `read-token-ledger.sh --session <id>` or `--run-id <run>` runs, then its one-line output is byte-identical to the base commit's (every existing `test-read-token-ledger.sh` case stays green).
- [ ] AC6 — Given `.supervisor/automate/` run files, when `build-insights.sh` runs, then the dashboard renders the same per-item table (a `### Per-item cost` subsection inside `## Token economics`), and an item with no transcripts renders an honest note, never a zero (fixture test in `test-insights.sh`).
- [ ] AC7 — Given the per-item report, when the baseline is recorded, then a committed evidence file `docs/evidence/automate-speed-baseline.md` contains the exact commands used and their output for run `automate-2026-10-13-181331` (PR #533's item) and for every run file whose first `## Progress` timestamp falls in the 7 days before the measurement, and the PR body links to it.
- [ ] AC8 — Given the change, when `loomwright/docs/OBSERVABILITY.md` is read, then it documents the `--per-item` mode, the session-resolution path (run file → `.owner`/log `cc_session_id` → transcripts), the message-id de-duplication and the honest limits (main-thread tokens of the `/automate` engine itself are only counted when its Claude Code session id is resolvable; no dollar figures).
- [ ] AC9 — Given the change, when `bash scripts/check-version-bump.sh` runs, then it passes with a `changelog.d/as03-measure-run-cost.md` fragment carrying `<!-- bump: minor -->` (no hand edit of the version files).

## Validation (must pass before merge)
1. `bash loomwright/scripts/test-read-token-ledger.sh` and `bash loomwright/scripts/test-insights.sh`; report `<passed>/<total>` for each.
2. Mutation control: drop the message-id de-duplication in `read-token-ledger.sh` ⇒ the duplicate-message fixture case goes red (a valid mutant: non-empty, differs from the original, `bash -n` clean).
3. Running system: run `read-token-ledger.sh --per-item .supervisor/automate/automate-2026-10-13-181331.md --root <primary checkout>` (the primary holds the run's `.supervisor/logs/*.owner` files; write it as `/Users/<name>/…` in committed text) and the resulting per-item rows for `automate-2026-10-13-181331` are committed in `docs/evidence/automate-speed-baseline.md` (AC7), and the PR body links to that file; the phase rows must show about Launch Pad 13m / Build 40m / Phase 4.5 85m / Drain 2h11m (Progress: `owned drain started` 17:52:42Z → `drain READY` 20:03:50Z). A fixture case built from these same Progress lines asserts the same four spans.

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `142540b8210a4b206e87e2b4349999c9978f8e29`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/read-token-ledger.sh`** — keep: the fail-SAFE contract `NEVER blocks a caller and NEVER hard-errors` and its zero line `echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"`; the existing one-line result `echo "INPUT=$TOTAL_INPUT OUTPUT=$TOTAL_OUTPUT CACHE_READ=$TOTAL_CACHE_READ CACHE_CREATE=$TOTAL_CACHE_CREATE TOTAL=$total EVENTS=$TOTAL_EVENTS"` byte-unchanged for `--session`/`--run-id`; the usage line `usage: read-token-ledger.sh --session <id> | --run-id <run_id> [--root <checkout>]...` may only gain the new mode; reuse: `JQ="${LOOMWRIGHT_JQ_BIN:-jq}"` (tests swap jq through it), the functional jq probe `printf '{}' | "$JQ" -e .`, the `--root` de-dup loop and the `lane_run_file()` helper for lane roots, and the session-line grep `grep -oE 'session_id [A-Za-z0-9_-]+'`; mirror: `phase-timing.sh`'s record keys (`"kind": "item"`, `.item.pick`, `.item.park`, `.item.pick_to_park.seconds`, `.session_id`) are read as-is, `phase-timing.sh` itself unchanged; its callers parse that one line — `automate-helpers.d/runfile.sh` (`local reader="$(dirname "$0")/read-token-ledger.sh"`, ceiling-check) and `automate-lanes.sh` (`_lanes_tokens`, `LOOMWRIGHT_LANES_TOKEN_LEDGER`); pinned by: `test-read-token-ledger.sh` (`LOOMWRIGHT_JQ_BIN=/nonexistent/jq bash "$SUT" --session s13`), `test-automate-helpers.sh`, `test-automate-lanes.sh`.
- **`loomwright/scripts/build-insights.sh`** — keep: `# Exit:   0 always — a reporting tool must never break its caller.` (a missing helper degrades to a note, as the wall-clock section does: `[ -f "$SCRIPT_DIR/phase-timing.sh" ]`); the per-line tolerant jq idiom `fromjson?`; the section order `## Cost` → `## Token economics` → `## Recent sessions` and the `### Per-session context size` subsection running to `## Recent sessions`; reuse: the sibling-script call shape `bash "$SCRIPT_DIR/phase-timing.sh"` (call `read-token-ledger.sh --per-item` the same way) and the "not recorded, never 0" rendering of the wall-clock section; pinned by: `test-insights.sh` (`te_order="$(awk '/^## Cost$/{c=NR} /^## Token economics$/{t=NR} /^## Recent sessions$/{r=NR} END{print c+0,t+0,r+0}' "$tpd")"` and `scsec="$(sed -n '/^### Per-session context size/,/^## Recent sessions/p' "$scd" 2>/dev/null)"`) — so the new `### Per-item cost` subsection goes inside `## Token economics` BEFORE `### Per-session context size`, never after it.
- **`loomwright/scripts/test-read-token-ledger.sh`, `loomwright/scripts/test-insights.sh`** — keep: the hermetic first line `. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"` (`scripts/check-test-hermetic.sh` fails CI without it); the `ok()`/`no()` counters and isolated `mktemp -d` fixture roots; never read the real `$HOME/.claude/projects` — `test-read-token-ledger.sh` per-item cases pass `--projects-dir <fixture>`, and `test-insights.sh` exports `LOOMWRIGHT_CC_PROJECTS_DIR=<fixture>` around its `build-insights.sh` call (build-insights takes no arguments). `build-insights.sh` exits early with `no session logs in` when `.supervisor/logs/*.jsonl` is empty, so the AC6 fixture includes a session log with a `session_end` event.
- **`loomwright/docs/vendor-coupling-manifest.json`** (conditional — only when `bash scripts/check-vendor-coupling.sh` reports a breach) — keep: every other path's allowance unchanged; raise only `"loomwright/scripts/build-insights.sh": 5` and/or `"loomwright/scripts/read-token-ledger.sh": 2` to the measured count, and in the same commit replace that path's `allowance_reasons` string (currently `re-baseline (agnostic-phase1/01): newly counted token classes: hook_protocol; measured, no reference added`) with a new one-line reason naming as03 and the transcript read — the gate's raise_check rejects an inherited, unchanged reason.
- **`loomwright/docs/TELEMETRY.md`** — keep: the section `### Token ledger (additive session-log probe)`; add one pointer line there to the new OBSERVABILITY.md per-item section (no restated table).

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| reader | `loomwright/scripts/read-token-ledger.sh`, `loomwright/scripts/test-read-token-ledger.sh` | `loomwright/scripts/token-ledger-fixtures/per-item/` (run.md, logs/*.owner + *.jsonl, projects/<dir>/<uuid>.jsonl, subagents/agent-*.jsonl + .meta.json, a lane root) | HIGH |
| insights | `loomwright/scripts/build-insights.sh`, `loomwright/scripts/test-insights.sh` | — | HIGH |
| docs | `loomwright/docs/OBSERVABILITY.md`, `loomwright/docs/TELEMETRY.md` (one pointer line) | `docs/evidence/automate-speed-baseline.md` | HIGH |
| release | — | `changelog.d/as03-measure-run-cost.md` | HIGH |
| CI ratchet (conditional) | `loomwright/docs/vendor-coupling-manifest.json` — only on a `check-vendor-coupling.sh` breach | — | MEDIUM |

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-read-token-ledger.sh` — duplicate-message fixture counts its usage once (AC2) | delete the message-id de-duplication step (the `unique_by`/`group_by` on `message.id`) in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — no-transcript fixture prints `no_transcripts` and no number (AC4) | delete the `no_transcripts` stderr/empty-row branch in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — lane-root fixture attributes the lane's session to the lane item (AC3) | delete the lane-root `lane_run_file` call in the `--per-item` branch of `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-insights.sh` — `### Per-item cost` subsection rendered from a fixture run (AC6) | delete the `read-token-ledger.sh --per-item` call in `loomwright/scripts/build-insights.sh` |
| `loomwright/scripts/test-insights.sh` — an item with no transcripts renders an honest note, never a zero (AC6) | delete the no-transcripts note branch in `loomwright/scripts/build-insights.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — per-phase rows printed under each item (AC1) | delete the per-phase row loop in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — a phase with a missing boundary line prints `not recorded` (AC1) | replace the `not recorded` branch with `0` in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — PR #533-shaped fixture gives Build 40m and Phase 4.5 85m (phase boundaries) | move the Build/Phase 4.5 boundary from the `FINALIZE:` line back to `ran /autonomous` in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — a fixture with two owned drains (second one fix-now) prints two Drain sub-rows, the second marked fix-now | replace the `.item.owned_drains[]` iteration with `.item.owned_drains[0]` only in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — a fixture with no `parked` line prints `not recorded` for item wall time and the Decide row | replace the `not recorded` branch of the item wall time with `0` in `loomwright/scripts/read-token-ledger.sh` |
| `loomwright/scripts/test-read-token-ledger.sh` — item wall time equals `phase-timing.sh` `.item.pick_to_park.seconds` | delete the `phase-timing.sh` call in the `--per-item` branch of `loomwright/scripts/read-token-ledger.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Per-item cost report (reader mode + /insights table + tests + baseline evidence + docs) | all | 6 modify (+1 conditional), 3 create + fixture tree | `skills/unit-testing/SKILL.md`, `skills/monitoring-observability/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/read-token-ledger.sh", name: "--per-item"}
  - {kind: "symbol", path: "loomwright/scripts/read-token-ledger.sh", name: "no_transcripts"}
  - {kind: "symbol", path: "loomwright/scripts/build-insights.sh", name: "### Per-item cost"}
  - {kind: "file", path: "loomwright/scripts/token-ledger-fixtures/per-item/run.md"}
  - {kind: "file", path: "docs/evidence/automate-speed-baseline.md"}
  - {kind: "symbol", path: "loomwright/docs/OBSERVABILITY.md", name: "--per-item"}
  - {kind: "file", path: "changelog.d/as03-measure-run-cost.md"}
requires: []
lanes:
  - "loomwright/scripts/read-token-ledger.sh"
  - "loomwright/scripts/test-read-token-ledger.sh"
  - "loomwright/scripts/token-ledger-fixtures/**"
  - "loomwright/scripts/build-insights.sh"
  - "loomwright/scripts/test-insights.sh"
  - "loomwright/docs/OBSERVABILITY.md"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "docs/evidence/automate-speed-baseline.md"
  - "changelog.d/as03-measure-run-cost.md"
external_requires:
  - "Claude Code transcript JSONL layout: <projects>/<project-dir>/<uuid>.jsonl and <uuid>/subagents/agent-*.jsonl + agent-*.meta.json (agentType)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/monitoring-observability/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): reading `~/.claude/projects` transcripts adds vendor-coupled tokens to `read-token-ledger.sh` / `build-insights.sh`, breaching `scripts/check-vendor-coupling.sh`'s per-path allowance | MEDIUM | Run `bash scripts/check-vendor-coupling.sh` before hand-back; on a breach raise that path's allowance in `loomwright/docs/vendor-coupling-manifest.json` AND add a new one-line `allowance_reasons` entry in the same commit (the gate requires both) |
| Existing one-line `--session`/`--run-id` output drifts, breaking `ceiling-check` and `lane-status --tokens` | HIGH | AC5; keep the new mode in its own branch of the `case "$MODE"`; run `test-automate-helpers.sh` and `test-automate-lanes.sh` too |
| A test reads the real home transcripts (non-hermetic, owner data in CI output) | HIGH | Every per-item test passes `--projects-dir <mktemp fixture>`; fixtures are synthetic, tiny, committed under `token-ledger-fixtures/per-item/` |
| A committed home path (`/Users/<x>/`) in the evidence file or docs trips the `meta-sync.sh` home_path scrub | MEDIUM | Write paths as `~/…` or `/Users/<name>/…` placeholders in every committed file |
| New prose cites `file:N` line numbers that `test-citation-drift.sh` rejects | LOW | Use descriptive anchors, or pin per CLAUDE.md's citation convention |
| bash 3.2 / BSD userland portability (no `timeout`, `date -d`, `stat -c`) for timestamp math | MEDIUM | Do timestamp → epoch conversion inside jq (`fromdateiso8601` after trimming fractional seconds), not with `date` |
| `/insights` dashboard section pins (order + subsection range) break | MEDIUM | Insert `### Per-item cost` before `### Per-session context size`; run `test-insights.sh` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-16-as03-measure-run-cost.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-16T04:43:37Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/570
- **Branch:** feature/as03-measure-run-cost
- **Files changed:** 25
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** read-token-ledger.sh --per-item + /insights Per-item cost + baseline evidence. Phase 4.5 FAIL×3 (5 reproduced HIGH/MEDIUM findings fixed across f9c5f5f, 0a71c99, 169ebd9); the final fix 169ebd9 (resume-pick window boundary) is unreviewed. Ground truth 2/2 PASS. risk_classification high_risk=true (token/auth path+content patterns, size).

## Not verified
- **/insights dashboard on the primary checkout** — only built against fixtures; the CLI was run on real data (subtask 1)
