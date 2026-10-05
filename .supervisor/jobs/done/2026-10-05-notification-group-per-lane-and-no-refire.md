# Supervisor Job: Desktop notifications at fleet scale — one group per session, one banner per question

## Environment
- **Project:** repo root of this checkout (lane s2-d)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 tracked changes), branch: main @ c1692b0 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/automate-followups/26-notification-group-per-lane-and-no-refire.md

> **Warning (1):** sibling lanes (other clones of this repo) run concurrently on this machine and share the macOS
> Notification Center — that is the very condition this item fixes. Never `cd` outside this checkout; never bare
> `git stash`; any real `terminal-notifier` call made for validation uses a group name unique to this lane's test
> (e.g. `loomwright-s2d-probe-*`) and is removed afterwards (`terminal-notifier -remove <group>`).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Two bash 3.2 fail-safe emitters + their bash self-tests; same conventions (`set -u`, no `set -e`, always exit 0). |
| 2 | Dependency Availability | GO | `jq`, `cksum`, `tr`, `tail`, `mv` are POSIX/BSD-present; `terminal-notifier` is installed on this Mac (`/opt/homebrew/bin`) and supports `-group` and `-list <group>`. |
| 3 | Architecture Fit | GO | Both scripts are `type: command` hook leaves on `PreToolUse[AskUserQuestion]` (one re-fanned command, `hooks/hooks.json`); `hooks.json` itself does not change. |
| 4 | Scope vs Supervisor Capability | GO | Four script/test files + one changelog fragment + three doc copies that restate the behaviour — single subtask. |
| 5 | Hard Blockers | CAUTION | The requirement names ONE id file (`.supervisor/logs/.notified-ids`) for both de-duplications. Both scripts run in sequence on the SAME payload inside one hook command (notify-desktop first, then emit-lifecycle), so a single shared ledger would make emit-lifecycle see notify-desktop's fresh record and drop the FIRST ask's `waiting` row. Resolved by D3 (one ledger per consumer). |

**Overall Verdict:** GO (1 CAUTION carried into Risk Assessment)

## Task
**Goal:** In `loomwright/scripts/notify-desktop.sh`, give each Claude Code session its own `terminal-notifier` group, and fire at most one banner per `AskUserQuestion` `tool_use_id`. In `loomwright/scripts/emit-lifecycle.sh`, write at most one `waiting`/`ask_user` row per `tool_use_id` — so a resumed session that replays the same tool call neither re-banners nor double-counts the question.

**Problem Statement (verified in S1 v2, 2026-10-04 — see the requirement's `## Problem`):**
1. `notify-desktop.sh`'s Darwin branch hard-codes `TN_GROUP="loomwright"` (the `-group coalesces banners` comment block), so every lane's banner removes every other lane's from Notification Center. This lane's own `.supervisor/logs/notifications.log` shows the `* Removing previously sent notification…` lines.
2. The `PreToolUse[AskUserQuestion]` hook fires again when a resumed session replays the same tool call to deliver the answer (v2-a: 8 `waiting/ask_user` rows for 4 questions). The S1 relay hook (`.supervisor/s1h-ask-hook.sh`) keys questions and answers on the SAME `tool_use_id`, which is the evidence that the replay carries the original id.

## Design decisions (binding on the worker)
- **D1 — group per session.** Darwin `-group` becomes `loomwright-<key>`, where `<key>` is the first 8 characters of the payload's `.session_id` (falling back to `CLAUDE_CODE_SESSION_ID`, exactly the `SESSION_ID` the click-target block already resolves) after sanitising to `[A-Za-z0-9_-]`. When neither yields a non-empty sanitised value, `<key>` is `p` + the `cksum` checksum of the checkout path (`pwd -P`, fallback `$PWD`), e.g. `loomwright-p1234567890`. No `shasum`/`md5` (not on every Linux). Same-session bursts still coalesce (same group). Compute the group once, near the click-target block, so both `terminal-notifier` calls use it.
- **D2 — no re-fire on resume (notify-desktop).** For `hook_event_name == PreToolUse` with `tool_name == AskUserQuestion`, read `.tool_use_id` (sanitised `[A-Za-z0-9_-]`). If it is non-empty AND already listed in `.supervisor/logs/.notified-ids` (exact whole-line match, `grep -qxF`), exit 0 with no banner. The check and the record both sit AFTER the scope gate and BEFORE the debounce block, so a replay never touches `.notify-debounce`. Record the id there, at first sight — the question counts as handled even when the debounce then suppresses its banner, so a later replay cannot raise a late banner. Missing/empty `tool_use_id`, a missing ledger file, or an unreadable one ⇒ "not seen" ⇒ notify (fail toward notifying). Bound the ledger to the newest 200 ids: append, then `tail -n 200` into a temp file in the same dir and `mv` it over the ledger, every step `|| true`. `Notification` events (no `tool_use_id`) are unaffected.
- **D3 — one ledger per consumer (resolves Feasibility CAUTION 5).** `emit-lifecycle.sh` keeps its OWN ledger `$LOG_DIR/.lifecycle-asked-ids` (main-worktree anchored, the same `LOG_DIR` it already writes to), with the same bounded format. It applies ONLY to `waiting` invoked with `$2 == ask_user` and a non-empty sanitised `tool_use_id`. An already-listed id ⇒ exit 0 with no row (de-duplicate; NOT the `replay: true` alternative). Rationale to state in the header: `build-floor.sh` derives an agent's current lifecycle state from its latest row, and a replay row written after the owner answered would show a session as `waiting` that is not. Record the id only AFTER the row was appended successfully, so a no-op first call (no session id, `plugin_present` false, …) does not suppress a later legitimate row. The `Notification` seam (`waiting` without `$2`), `heartbeat` and `failed` are byte-unchanged. Never share one file between the two scripts — they run in sequence on the same payload in one hook command, and a shared ledger would make the second script drop the first ask.
- **D4 — observable audit line.** Before the platform dispatch, `notify-desktop.sh` appends ONE line to `.supervisor/logs/notifications.log`: `<UTC ts> notify group=<group> tool_use_id=<id or ->`. A D2 replay skip appends `<UTC ts> skip replay tool_use_id=<id>`. Both lines are written on every host, Linux included, so the de-duplication is testable without a notifier. Every write ends in `|| true`. This is the evidence for Validation 3.
- **D5 — fail-safe unchanged.** Both scripts keep exiting 0 on every path (bimodal rule, CLAUDE.md §"Failure-Mode Invariants"). Never `set -e`. A missing id file means "notify"/"emit".
- **D6 — restated copies move in the same change (house rule: restating copies move with their authority).** Update these copies in this PR:
  - `notify-desktop.sh` header "Behaviour" list and the `-group` comment;
  - `emit-lifecycle.sh` header, `waiting` subcommand paragraph;
  - `docs/RESULT_SCHEMAS.md` `## agent_lifecycle` "`waiting`-specific" paragraph (one row per `tool_use_id`);
  - `docs/HOOKS.md` PreToolUse (AskUserQuestion) row (per-session group, per-`tool_use_id` de-duplication in both leaves).
  Grep the whole repo for `"loomwright"` group / `notify-debounce` / `waiting.*ask_user` prose and fix any other restatement found. `hooks/hooks.json` is NOT edited.

## Acceptance Criteria
- [ ] Given two payloads with different `session_id`s, when `notify-desktop.sh` runs on each (Darwin sandbox with a recording `terminal-notifier` stub), then the two recorded invocations carry two different `-group` values, each `loomwright-<first 8 sanitised chars of its session id>`. Given a third payload from the first session, its group equals the first's.
- [ ] Given a payload with no `session_id` and no `CLAUDE_CODE_SESSION_ID`, when the script runs from two different checkout dirs, then the groups are `loomwright-p<cksum>`, they differ from each other, and they are stable when re-run from the same dir.
- [ ] Given the same `PreToolUse[AskUserQuestion]` payload (same `tool_use_id`) fed twice with the debounce disabled (`LOOMWRIGHT_NOTIFY_DEBOUNCE=0`), then exactly one notifier invocation is recorded and `notifications.log` holds one `notify` line and one `skip replay` line. This is asserted on any host via the audit line, and on Darwin also via the stub. Given two different `tool_use_id`s, two banners fire. Given no `tool_use_id`, every call fires (no de-duplication).
- [ ] Given the same ask payload fed twice to `emit-lifecycle.sh waiting ask_user`, then the session JSONL holds exactly one `waiting`/`ask_user` row. Given two different `tool_use_id`s, two rows. Given a first call that wrote no row (e.g. the `.supervisor/` gate absent), a later call after `.supervisor/` exists still writes the row. Given the same payload run through notify-desktop THEN emit-lifecycle (the real hook order), both the banner and the row are produced once.
- [ ] Given more than 200 distinct ids recorded, then each ledger holds at most the newest 200 ids, and the oldest has rolled off (a re-ask of it notifies again).
- [ ] Given every existing case in `test-notify-desktop.sh` and `test-emit-lifecycle.sh`, then all still pass, including the debounce cases (the single-session unchanged path: one banner per question). Paste `RESULT:` lines (passed/total and SKIP) for base and branch.
- [ ] Mutation controls, each recorded verbatim (hunk + failing assertion text) in `WORKER_RESULT` and the PR body. (a) Revert to the fixed `-group "loomwright"` ⇒ the two-session group test FAILS. (b) Remove the D2 ledger check ⇒ the replay test FAILS. (c) Remove the D3 check ⇒ the emit-lifecycle replay test FAILS. (d) Make both scripts share one ledger file ⇒ the real-hook-order test FAILS.
- [ ] Running system (this Mac, real `terminal-notifier`): run the patched `notify-desktop.sh` from two scratch dirs (each with its own `.supervisor/logs/` and `jobs/in-progress/` marker so the scope gate passes) with two different `session_id`s and a replay of the first `tool_use_id`. Paste both dirs' `notifications.log` lines showing two distinct groups and one `skip replay`, plus `terminal-notifier -list <group>` output proving both groups are present at once. Then `terminal-notifier -remove` both groups. Use probe session ids whose first 8 chars start `s2dprobe`, so no real lane's group is touched.
- [ ] `bash scripts/ci-local.sh` is green (includes `check-doc-currency.sh`, `test-citation-drift.sh`, the hermetic lint).
- [ ] A `changelog.d/automate-followups-26-notification-group-per-lane-and-no-refire.md` fragment exists in the `<!-- bump: patch -->` format. No version file is hand-edited and `bump-version.sh` is NOT run (parallel wave: the release lane bumps).

## Outcomes Rubric
- `notify-desktop.sh` contains no literal `-group "loomwright"` / `TN_GROUP="loomwright"`; the group is built from the resolved session id, with a `cksum` path-hash fallback.
- `notify-desktop.sh` reads `.tool_use_id` and consults/records `.supervisor/logs/.notified-ids`, bounded to 200 entries, after the scope gate and before the debounce.
- `emit-lifecycle.sh` consults/records its own `.lifecycle-asked-ids` ledger only for `waiting` + `ask_user`, recording after a successful append.
- `test-notify-desktop.sh` has a two-session distinct-group case, a no-session path-hash case and a same-`tool_use_id` replay case; `test-emit-lifecycle.sh` has a replay case and a real-hook-order case.
- `docs/RESULT_SCHEMAS.md` (`agent_lifecycle` waiting paragraph) and `docs/HOOKS.md` (AskUserQuestion row) describe the per-`tool_use_id` de-duplication.
- `changelog.d/automate-followups-26-notification-group-per-lane-and-no-refire.md` exists with a `<!-- bump: patch -->` header.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Per-session notification group + per-`tool_use_id` de-duplication in notify-desktop and emit-lifecycle (+ tests, doc copies, changelog) | ALL | 6 modify, 1 create | `unit-testing`, `quality-checklist` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole change (LAUNCHABLE; no siblings)
provides:
  - {kind: "file",   path: "changelog.d/automate-followups-26-notification-group-per-lane-and-no-refire.md"}
  - {kind: "symbol", path: "loomwright/scripts/notify-desktop.sh", name: "TN_GROUP"}
requires: []
lanes:
  - "loomwright/scripts/notify-desktop.sh"
  - "loomwright/scripts/test-notify-desktop.sh"
  - "loomwright/scripts/emit-lifecycle.sh"
  - "loomwright/scripts/test-emit-lifecycle.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/HOOKS.md"
  - "changelog.d/automate-followups-26-notification-group-per-lane-and-no-refire.md"
external_requires: []
```

**Exact-name mandate:** `TN_GROUP` stays the variable that holds the computed group. The ledger paths are exactly `.supervisor/logs/.notified-ids` (notify-desktop, cwd-relative like its sibling `.notify-debounce`) and `$LOG_DIR/.lifecycle-asked-ids` (emit-lifecycle). The two doc files are outside the requirement's `## Touches`; they change only because they restate the behaviour (D6). Say so in the PR body.

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask).

### Batch Plan
One batch, one worker.

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | Non-vacuous assertions, mutation controls |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A single shared id ledger drops the first ask's `waiting` row, because both scripts run in sequence on one payload (Feasibility CAUTION 5) | HIGH | D3: one ledger per consumer; real-hook-order test plus mutation (d) prove it |
| The replay does not actually carry the original `tool_use_id` in some runtime path, so de-duplication never fires | MEDIUM | The S1 relay hook keys its answer delivery on the same id (evidence). The de-dup fails toward notifying, so the worst case is today's behaviour. State the limit in the PR body |
| The test sandbox lacks the new tools (`cksum`, `tr`, `mv`, `pwd`), so the SUT silently skips the ledger and the tests pass vacuously | HIGH | Add them to `test-notify-desktop.sh`'s `BASE_TOOLS` (`test-emit-lifecycle.sh`'s `CURATED_TOOLS` already has `tr`/`mv`; add `cksum` only if used); the mutation controls prove the assertions bite |
| Darwin-only group assertions are SKIPped on Linux CI | LOW | D4's audit line makes group + de-dup assertions host-independent where possible; Darwin stub checks run on this Mac |
| The real-system probe removes or overwrites a live lane's banner | MEDIUM | Probe groups use the `s2dprobe` prefix only, and are removed after |
| `.notified-ids` is not covered by `.gitignore` | LOW | `.supervisor/logs/` is already gitignored (same dir as `.notify-debounce`); verify with `git check-ignore` |
| A new bare `file.ext:N` citation fails `test-citation-drift.sh` | LOW | Use descriptive anchors or `[pins: …]` |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-notification-group-per-lane-and-no-refire.md
```

## Plan Review
- **Decision:** PASS (attempt 1 of 3)
- **Non-blocking notes for the worker (apply them):**
  - MEDIUM — sandbox tool sets: `test-notify-desktop.sh` `BASE_TOOLS` gains `tr cksum mv` (plus `pwd` is a builtin); `test-emit-lifecycle.sh` `CURATED_TOOLS` gains `grep` (the D3 membership check) and, for the real-hook-order case that also runs notify-desktop.sh, `uname find cksum`. Read the cksum CRC with `${out%% *}` / `read`, never `awk`/`cut` (not in `BASE_TOOLS`).
  - MEDIUM — AC4 real-hook-order case setup: both scripts run with cwd = the same git sandbox repo top level (as `hooks/hooks.json` does), `.supervisor/` present, `LOOMWRIGHT_NOTIFY_SCOPE=all`, `LOOMWRIGHT_NOTIFY_DEBOUNCE=0`, payload carrying `session_id` and `tool_use_id`; "banner once" is asserted via D4's `notify` audit line on every host. Mutation (d) only bites in exactly this setup.
  - LOW — add `loomwright/docs/ARCHITECTURE_CONTRACTS.md` to the worker's lanes: its `logs/` retention row names `.notify-debounce` among the files left alone — name `.notified-ids` / `.lifecycle-asked-ids` there too (D6).
  - LOW — D3 header rationale: the concrete harms of a replay row are a duplicate `waiting` feed entry in `build-floor.sh`, an inflated per-lane question count, and a `since_ts` moved to answer time; a `replay: true` flag would be ignored by build-floor's lifecycle allowlist and feed filter, which is why de-duplication is chosen. Do not claim it flips state to waiting.
  - LOW — ledger trim temp file gets a `$$` suffix; record the overlapping-fire lost-update race (two simultaneous asks) as an accepted LOW risk in the header — it fails toward notifying.
  - LOW — scope: `send-webhook.sh`, the third `PreToolUse[AskUserQuestion]` leaf, still re-fires on replay. Say so in the HOOKS.md row and the PR body as a named follow-up; do not change it here.
  - LOW — AC1: also assert the two distinct groups through the D4 audit line on every host (so mutation (a) is proven on Linux CI too); keep the Darwin stub assertion.

---

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T01:59:01Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/386
- **Branch:** feature/automate-followups-26-notification-group-per-lane-and-no-refire
- **Files changed:** 8
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Rubric score:** 6/6
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Children check:** settled (worker add214739e5f7b26e hit its 40-turn limit once and was resumed via SendMessage — same agent, settled)
- **Summary:** per-session TN_GROUP (loomwright-<sid8>, cksum path fallback) + per-tool_use_id replay de-dup with separate ledgers (.notified-ids / .lifecycle-asked-ids, newest 200) + host-independent audit line; notify 40→75/75, lifecycle 69→87/0; mutants (a)–(d) red; real terminal-notifier probe showed two groups at once + one skip replay; ci-local PASS (stamped); Phase 4.5 consistency_audit PASS iter 1 with 4 sub-floor findings dismissed (1 MEDIUM stderr leak via late 2>/dev/null, 2 LOW, 1 nit); risk_classification high_risk=true (size: 470 > 400 lines).

## Not verified
- **real resumed-session replay carrying the original tool_use_id** — no live resume observed; de-dup rests on the S1 relay-hook evidence and fails toward notifying (subtask 1)
- **Linux CI run of the new cases** — no local Linux runtime; Darwin-only stub cases skip there, audit-line cases are host-independent (subtask 1)
- **send-webhook.sh replay re-fire** — out of scope by brief; named as a follow-up in HOOKS.md and the PR body (subtask 1)
