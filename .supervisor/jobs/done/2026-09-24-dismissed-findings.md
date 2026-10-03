# Supervisor Job: Itemised dismissed findings, transported to the postmortem

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ 570fe70)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/05-dismissed-findings.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown skill/doc edits + bash script edits (`classify-bot-review.sh`, `pr-postmortem-gather.sh`) + a `result_block_parser.py` test fixture — matches the plugin's existing tech stack exactly. `findings_dismissed: int` already exists on `REVIEW_HEAL_RESULT` (v2); this item adds the itemised `dismissed: []` array beside it. |
| 2 | Dependency Availability | GO | No new dependency; reuses `jq`, `gh pr comment`, `gh api`, all already used by the touched scripts. |
| 3 | Architecture Fit | GO | Extends the EXISTING §U3.5 Validate-Then-Fix `dismissed = []` accumulator (already declared in `review-heal/SKILL.md` pseudocode, never emitted) and the EXISTING Phase 4.5 "Do NOT touch pre_existing issues or nits" judgment point — both are precedent-following completions of an already-designed seam, not novel plumbing. |
| 4 | Scope vs Supervisor Capability | GO | 7-file, single cohesive transport-chain change (one itemised list flowing from two review loops through a marker comment into the postmortem gather + classifier). Every file depends on the shared `{finding, reason, source}` item shape — splitting would only add coordination overhead on a single shared shape. |
| 5 | Hard Blockers | GO | No migration, no credentials, no missing modules. |

**Overall Verdict:** GO

## Task
**Goal:** Every dismissed finding (validated as stale/invalid/already-addressed, in the `/review-pr` drain or Phase 4.5 self-heal) is itemised — in the result block AND posted once to the PR as a marker-tagged comment the drain recognises as its own — so `/pr-postmortem` can see WHICH findings were dismissed and WHY, and correlate a dismissal that was later re-raised by a human as its own root-cause signal.

**Problem Statement:**
`findings_dismissed: int` already exists on `REVIEW_HEAL_RESULT`, and `review-heal/SKILL.md` §U3.5 already declares a `dismissed = []` / `dismissed += [...]` pseudocode accumulator — but it is never emitted, and Phase 4.5's self-heal loop has no equivalent field at all. `REVIEW_HEAL_RESULT` itself is never persisted anywhere `/pr-postmortem` can read it (`dispatch-pr-review.sh`'s marker holds only URL + timestamp), so a result-block field alone has no transport (decision H4 in the source requirement) — the only durable transport is a PR comment.

## Acceptance Criteria
- [ ] `loomwright/docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT: keep `findings_dismissed: int` unchanged; add optional additive `dismissed: [{finding: string, reason: string, source: string}]` to the v2 drain-fields group. `source` enum reuses the EXACT channel spellings already used in §"All-Channel Read" (`reviews | reviewThreads | issue_comments | check_outputs`) plus `code_reviewer` for the earned-fallback lens — read that section first and match its spellings verbatim, do not invent new ones. `schema_version` stays 2 (additive field, no bump — same convention as `channels_scanned`/`rejected_instruction_like`). "Empty ⇒ absent" stated explicitly (no `dismissed: []` on the wire when there were zero dismissals).
- [ ] `loomwright/docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT: add the parallel `heal_dismissed: [{finding, reason, source}]` to the self-heal block (flat, `heal_*`-prefixed, matching the existing `heal_*` field family's naming — read that family first). `source` enum here is `code_reviewer | red_team | voter:<provider>` (the Phase 4.5 lenses), not the drain's channel enum — state the distinction explicitly since the two lists differ. Same "empty ⇒ absent" rule.
- [ ] `loomwright/skills/review-heal/SKILL.md` §U3.5 case 4: the pseudocode's existing `dismissed = []` / `dismissed += [f for f in bot_findings if validate(f) == STALE_OR_INVALID]` (and the fallback-review equivalent) records `{finding, reason, source}` per item — wire the `source` value from the channel the finding came from (already known at classification time) and a short `reason` (the validation-failure basis: stale / invalid / already-addressed). Emit `dismissed` on the result block when non-empty.
- [ ] `loomwright/skills/review-heal/SKILL.md`: **marker comment** — at the end of each round with ≥1 new dismissal, post ONE `gh pr comment` whose body starts with `<!-- loomwright:dismissed round=<n> -->` followed by one `- **<finding>** — <reason> (<source>)` bullet per item.
- [ ] **Self-skip (MUST, mechanized not prose-only):** `loomwright/scripts/classify-bot-review.sh` gains a `--skip-marker '<!-- loomwright:'` prefix filter, **default ON**, that drops any comment whose body starts with that prefix BEFORE classification — mirror the existing `--trusted-actors` flag's plumbing shape (parse, default, one-line stderr note when it changes behavior). Without this, §U1's `classify(issue_comments)` would classify the drain's own marker comment as HUMAN-authored (since it's posted under the operator's `gh` login) and surface it every subsequent round.
- [ ] `loomwright/skills/review-heal/SKILL.md` §U1's `classify(issue_comments)` call is updated to pass `--skip-marker` (or documents that it's ON by default and no caller flag is needed — read the actual call site first and match whichever the script implements).
- [ ] Re-measure `review-pr` token budget live (`loomwright/docs/prompt-token-budgets.json`) — do not trust the source requirement's cited "1737 headroom" figure; the CURRENT measured/budget/headroom must be independently re-read at implementation time (live figures at brief-authoring time: budget 34614, measured 31467, headroom 3147 — already stale relative to the source requirement's citation, so re-measure again after this change and raise + mirror in `ARCHITECTURE_CONTRACTS.md` only if breached).
- [ ] `loomwright/skills/self-heal-advisory/SKILL.md` Part 2 loop: the actual exclusion of pre_existing/nit findings happens UPSTREAM and mechanically at the `fixable_issues = [i for i in review.issues if i.category == "new" and i.severity in (BLOCKING, HIGH)]` filter (~line 799-800) — NOT at the "Do NOT fix pre_existing issues or nits" line (~827, a fix-worker scope guardrail, not a judgment point; corrected citation per Plan Review). Itemise `review.issues` minus `fixable_issues` (i.e. every `pre_existing`/`nit`/`drift` finding plus any `new`-but-below-severity-floor finding) into a `heal_dismissed` accumulator using a `reason` vocabulary of `pre_existing | nit | drift | below_severity_floor` (mirroring the reviewer's own `category`+`severity` fields, including the 4th `category: drift` enum value at `docs/RESULT_SCHEMAS.md:610` — do not invent free-text reasons here, unlike the drain side's stale/invalid/already-addressed prose). Emit `heal_dismissed` in `SUPERVISOR_RESULT` when non-empty; post the SAME marker-comment shape (`<!-- loomwright:dismissed round=<n> -->`, same bullet format) on the PR once at completion-tail time (Phase 4.5 is not round-numbered the way the drain is — use the review round number if one exists at the completion-tail call site, else read the site to decide the right anchor and record the choice).
- [ ] Re-measure `supervisor` token budget live — do not trust the source requirement's cited "2412" figure (live figures at brief-authoring time: budget 27488, measured 24989, headroom 2499); raise + mirror in `ARCHITECTURE_CONTRACTS.md` only if breached by this change.
- [ ] `loomwright/scripts/pr-postmortem-gather.sh`: extract marker comments (bodies starting `<!-- loomwright:dismissed `) into a new top-level key `dismissed_findings: [{round, finding, reason, source}]` (jq-built, `[]` when none — fail-safe, matching this script's existing `[]`-on-absence convention). Parse ONLY the fixed marker + `- **<finding>** — <reason> (<source>)` bullet shape emitted above; anything else (malformed body, hand-edited comment) ⇒ that comment's items are skipped, never a crash.
- [ ] `loomwright/skills/pr-postmortem/SKILL.md` (the authority for the 6 root-cause classes — NOT `commands/pr-postmortem.md`, which is just the entry point and explicitly defers to this skill, §"Related Commands" line: "That skill is the authority") gains: a dismissed finding whose text later appears (normalised substring match) in a HUMAN-authored review comment is its own root-cause signal `dismissed_then_raised`, attributed to flow stage `self_heal`. **Verified premise:** the `class` field inside `categories[]` has NO closed JSON-schema enum in `docs/RESULT_SCHEMAS.md` §POSTMORTEM_RESULT — the 6 classes are narrative-documented in the SKILL, not enum-validated — so `dismissed_then_raised` is added as an ADDITIVE PER-ROUND BOOLEAN SIGNAL (mirroring the existing `self_heal_miss` boolean), never a 7th class string, exactly as the source requirement instructs for the closed-enum case. Document it beside the existing 6 classes without renumbering them. `commands/pr-postmortem.md` needs no edit unless it independently restates the class list (check; if it does, sync it — R "agent↔command mirror drift" precedent).
- [ ] `loomwright/scripts/result_block_parser.py` tests: a `REVIEW_HEAL_RESULT` fixture whose `dismissed:` list has a flow-map item containing `: ` inside a quoted string (`{finding: "missing: null check", reason: "already fixed in a prior round", source: "reviewThreads"}`) parses to the right three fields per item; a `SUPERVISOR_RESULT` fixture validates with and without `heal_dismissed` present.
- [ ] `CHANGELOG.md` gains one paragraph; `plugin.json` + `marketplace.json` version bump (patch — additive, non-breaking; current version 15.98.0 → 15.99.0, re-verify live at implementation time in case another item merged first). README.md/CLAUDE.md are NOT touched (memory: `release-surfaces-readme-claude-md-no-longer-bump`).
- [ ] Fixture: a drain round with one rejected finding ⇒ `dismissed` has one entry, `findings_dismissed: 1`, and exactly one marker comment posted (assert via a stubbed `gh` in the suite's existing fixture-test convention).
- [ ] Fixture: the NEXT round's `classify(issue_comments)` yields 0 candidates from the marker comment (`classify-bot-review.sh` fixture with the marker-prefixed body ⇒ `[]`); mutation control: the same fixture with `--skip-marker` explicitly disabled (or its default flipped) still classifies it, proving the filter is load-bearing.
- [ ] Fixture: zero rejections ⇒ no `dismissed` key on the result block, no `heal_dismissed` key on `SUPERVISOR_RESULT`, no comment posted.
- [ ] Fixture: `pr-postmortem-gather.sh` with one marker comment in its input ⇒ `dismissed_findings` length 1 with the right 4 fields; a malformed/hand-edited marker-prefixed body ⇒ `dismissed_findings: []` for that comment (fail-safe, no crash).
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` → the same five sanctioned surfaces (this item touches none of them).
- [ ] `scripts/check-token-budget.sh`, `scripts/check-doc-currency.sh`, `scripts/check-vendor-coupling.sh`, `scripts/test-citation-drift.sh` green; full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh`) green.

## Non-goals (from the source requirement — do not implement)
No change to what §U3.5's four validate-then-fix cases dismiss or fix (only case 4's transport is new). Dismissed findings still do not block READY and are not fixed. No `schema_version` bump anywhere. No change to `/pr-postmortem`'s read-only / append-only posture. No second comment per round; no edit of earlier marker comments. No 7th root-cause class string (see the closed-enum verification above).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Itemised dismissed findings: schema fields → drain + self-heal emission → marker comment + self-skip filter → postmortem gather + classifier signal → tests + doc sync | all | 8 modify, 0 create | quality-checklist, review-heal, self-heal-advisory, pr-postmortem | LAUNCHABLE |

```yaml
# Subtask 1 — itemised dismissed findings, end-to-end transport (LAUNCHABLE)
subtask_id: dismissed-findings-01
title: "Itemised dismissed findings: schema + drain/self-heal emission + marker comment + self-skip + postmortem transport"
lanes:
  - loomwright/docs/RESULT_SCHEMAS.md
  - loomwright/skills/review-heal/SKILL.md
  - loomwright/skills/self-heal-advisory/SKILL.md
  - loomwright/scripts/classify-bot-review.sh
  - loomwright/scripts/pr-postmortem-gather.sh
  - loomwright/skills/pr-postmortem/SKILL.md
  - loomwright/scripts/result_block_parser.py  # tests
  - loomwright/docs/prompt-token-budgets.json  # + ARCHITECTURE_CONTRACTS.md mirror if raised
  - loomwright/docs/ARCHITECTURE_CONTRACTS.md
  - CHANGELOG.md
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
requires: []
external_requires: []
provides:
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "dismissed"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "heal_dismissed"}
  - {kind: "symbol", path: "loomwright/scripts/classify-bot-review.sh", name: "--skip-marker"}
  - {kind: "symbol", path: "loomwright/scripts/pr-postmortem-gather.sh", name: "dismissed_findings"}
  - {kind: "symbol", path: "loomwright/skills/pr-postmortem/SKILL.md", name: "dismissed_then_raised"}
out_of_lane: []
```

## Parallelism Analysis
- **Mode:** single-agent (no fan-out) — one LAUNCHABLE subtask, no dependents, no file-conflict/context-bound/genuine-parallelism reason to split (see Feasibility #4).
- **Recommended workers:** 1

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation quality gates for any worker task. |
| review-heal | Authority for the `/review-pr --until-mergeable` drain's §U3.5 Validate-Then-Fix loop, the seam this item's `dismissed[]` emission and marker-comment logic extends. |
| self-heal-advisory | Authority for Supervisor Phase 4.5's fix-worker findings filter, the seam this item's `heal_dismissed[]` emission extends. |
| pr-postmortem | Authority for the 6 root-cause classes and the `POSTMORTEM_RESULT` trend-line schema this item adds the `dismissed_then_raised` signal to. |

## File Impact Map
- **Modify:** RESULT_SCHEMAS.md, review-heal/SKILL.md, self-heal-advisory/SKILL.md, classify-bot-review.sh, pr-postmortem-gather.sh, pr-postmortem/SKILL.md, result_block_parser.py (tests), prompt-token-budgets.json (+ possibly ARCHITECTURE_CONTRACTS.md), CHANGELOG.md, plugin.json, marketplace.json.
- **Create:** none (test fixtures added to existing suites, not new files, unless the worker finds no existing suite covers `classify-bot-review.sh`'s marker-skip path — check first).

## Risk Assessment
- **Two independent emission sites (drain §U3.5, self-heal Part 2) sharing one item shape.** Risk: the two implementations drift on field names/order. Mitigation: both read the SAME `{finding, reason, source}` shape from this brief and from RESULT_SCHEMAS.md — worker should implement the drain side first, then mirror the shape exactly for self-heal rather than re-deriving it.
- **Self-skip filter is security/correctness-critical** (an unfiltered marker comment would cause the drain to treat its own output as a human blocking a merge, or worse, loop on it every round). Mitigation: the mutation-control fixture (marker fixture WITH and WITHOUT the filter active) is a hard AC, not optional.
- **Marker-comment posting adds one `gh pr comment` write per round with a dismissal** — low risk (posting is already the established pattern for review-heal notifications) but re-verify it does not fire when `dismissed` is empty (the "zero rejections ⇒ no comment" AC is the guard).

## Environment Validation
- ✓ `gh` authenticated, ✓ `jq` available, ✓ existing `test-review-heal` / `test-classify-bot-review.sh` / `test-pr-postmortem-gather.sh` (or equivalent) suites present as extension points — worker to confirm exact filenames at start.

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## Handoff
Run: `/supervisor job: .supervisor/jobs/pending/2026-09-24-dismissed-findings.md`
