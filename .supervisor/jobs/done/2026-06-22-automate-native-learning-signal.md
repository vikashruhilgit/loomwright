# Supervisor Job: Automate-Native Learning Signal — emit ground-truth churn from data the engine already holds (don't rely on the GitHub-blind postmortem)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** working tree **CLEAN** (`git diff --quiet` passes), currently on `local-twin/step3-graph`. `graphify-out/` is **gitignored** (`git status --ignored` shows `!! graphify-out/`) so it does NOT dirty the tree or follow you onto a new branch. **Before running Supervisor, cut a fresh branch off `main`** — `git checkout main && git pull && git checkout -b feature/automate-native-learning-signal`. Do NOT build on the local-twin branch. (No stash needed — the tree is clean.)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Plugin version:** 14.43.0 (this change ships as **v14.44.0** — confirm `plugin.json` is 14.43.0 at start; bump in Subtask 4)
- **Counts (verify at start, expected UNCHANGED):** 14 agents · 19 commands · 56 skills · 20 hook leaf entries — **no new agent/command/skill/hook** (additive skill/script edits + **two** additive optional schema fields: `source` + `automate_key`).
- **Blockers:** 0 | **Warnings:** 2 (see Risk Assessment)

## Task

**Goal (this run):** Make `/automate` capture an **honest, ground-truth churn/learning signal per processed PR** — emitted at **end-of-DRAIN (§6 step 3)** from data the engine **already holds in hand** (the owned drain's `REVIEW_HEAL_RESULT` + the inner `SUPERVISOR_RESULT`) — instead of depending on the GitHub-surface `/pr-postmortem`, which reads **false `review_rounds: 0`** on exactly the flow `/automate` produces (inline `--until-mergeable` drain + CI-check review + squash-merge).

**Root cause (verified in code):**
1. `/pr-postmortem`'s gather takes `MAX` of three **GitHub-visible** signals ([`scripts/pr-postmortem-gather.sh:306`](ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh:306)): review-fix commit headlines (`review_fix_re`, [`:252`](ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh:252)), `.reviews[]` churn objects ([`:282`](ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh:282)), and bot **issue comments** ([`:194`](ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh:194)). In an `/automate` flow the review happens **inside the owned `/review-pr --until-mergeable` drain session** and never reaches GitHub (no review object, no issue comment), and heal commits (`fix(...)`, `polish(...)`) miss `review_fix_re` → all three read 0 → `review_rounds: 0`. (Squash is **not** the cause — `gh pr view --json commits` keeps the PR commit list regardless of merge method.)
2. `/automate` has **no direct postmortem wiring** — `skills/automate-loop/SKILL.md` and `commands/automate.md` have zero postmortem mentions, and there is no postmortem hook in `hooks/hooks.json`. The only auto-trigger is the **churn-gated Postmortem Dispatch Tail** inside `/review-pr --until-mergeable` ([`skills/review-heal/SKILL.md:529`](ai-agent-manager-plugin/skills/review-heal/SKILL.md:529)), inherited indirectly via automate's DRAIN step ([`skills/automate-loop/SKILL.md:194`](ai-agent-manager-plugin/skills/automate-loop/SKILL.md:194)). That tail (a) is a silent no-op on clean/≤2-cycle merges by design, (b) is never restated in the automate prose so the inline main-thread drain can silently skip it, and (c) is GitHub-blind even when it fires.

**The opportunity (the engine already has the truth):** at §6 step 3 (DRAIN) the engine **reads the terminal `REVIEW_HEAL_RESULT` synchronously**, which under `--until-mergeable` emits `fix_cycles` (the real fix→push count), `repeat_check_failure`, `unresolved_bot_feedback`, `rounds`/`max_rounds` ([`docs/RESULT_SCHEMAS.md:1901,1927`](ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md:1901)); and at §6 step 2 (RUN) it captures `SUPERVISOR_RESULT` (`heal_decision`, `rubric_score`, `pr_url`, `branch`). So a truthful churn line can be emitted **right after DRAIN reads `REVIEW_HEAL_RESULT` (§6 step 3)** — **no postmortem gather, no false-0** — drawing the churn signal from data already in hand. The **one** thing not already held is `changed_paths` + the integer size fields (required by the consumer, see next), sourced by a single `gh pr view "<pr_url>" --json files,additions,deletions,changedFiles` (`changed_paths` = `[.files[].path]`).

> **Emit AFTER DRAIN, not at CHECK OFF (corrects a placement bug).** A **parked** item (`escalated`, or `awaiting_merge` in safe mode) stops the loop at §6 step 4 (GATE) and **never reaches** §6 step 6 (CHECK OFF) — so emitting at CHECK OFF would silently skip every parked PR. Emit at the end of DRAIN (step 3), where both `SUPERVISOR_RESULT` and `REVIEW_HEAL_RESULT` are in hand, so merged AND parked PRs are both recorded exactly once.

> **Why `changed_paths` is load-bearing (review finding, verified).** [`read-postmortem.sh:125-126`](ai-agent-manager-plugin/scripts/read-postmortem.sh:125) selects a prior-churn hit **only** when a corpus line's `changed_paths` array overlaps the query paths. A line **without** `changed_paths` is **invisible** to the advisory reader — so target A does **not** feed `read-postmortem.sh` "for free" unless the line carries `changed_paths` (and a `categories[]`/`self_heal_misses`/`flow_stages` shape for the class/stage/SHM aggregation at [`:136-146`](ai-agent-manager-plugin/scripts/read-postmortem.sh:136)). This is why target A must emit a **FULL** `POSTMORTEM_RESULT` record, not a minimal line.

**North star / explicit non-goals:**
- ❌ Do **NOT** add consumer-repo (BetterBlocks) log-parsing into the generic `pr-postmortem-gather.sh`. It stays a generic GitHub-surface analyzer. This brief adds an **engine-native** signal alongside it, it does not patch the postmortem.
- ❌ Do **NOT** make the new signal a gate. It is **advisory / append-only / fail-safe (always exit 0)** — it can NEVER change `owned_drain_result`, the merge-or-park decision, `## Status`, or any `/autonomous` gate. Mirrors the `postmortem_dispatched`-is-informational invariant.
- ❌ Do **NOT** bend merge hygiene (renaming heal commits, disabling squash) to satisfy any detector.
- ❌ Do **NOT** introduce a second `gh pr merge --squash` executor or touch the never-merge invariants.

## Pre-Implementation Evidence (gathered)
- Verified `fix_cycles`, `repeat_check_failure`, `unresolved_bot_feedback` are **emitted** `REVIEW_HEAL_RESULT` v2 fields ([`docs/RESULT_SCHEMAS.md:1901,1927`](ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md:1901)), not just internal loop vars ([`skills/review-heal/SKILL.md:365,418`](ai-agent-manager-plugin/skills/review-heal/SKILL.md:365)).
- Verified automate DRAIN reads that block synchronously ([`skills/automate-loop/SKILL.md:194,230`](ai-agent-manager-plugin/skills/automate-loop/SKILL.md:194)) and RUN captures `SUPERVISOR_RESULT` ([`:193`](ai-agent-manager-plugin/skills/automate-loop/SKILL.md:193)).
- Verified the existing terminal-breadcrumb convention (one appended line per run to `.supervisor/logs/<run_id>.jsonl`, [`:148`](ai-agent-manager-plugin/skills/automate-loop/SKILL.md:148)) — the new ledger line is the same spirit.
- Verified the postmortem corpus shape this would unify with: `.supervisor/postmortem/results.jsonl` (POSTMORTEM_RESULT; the still-deferred eval harness's seed corpus — see memory `pr-churn-self-heal-blindspot`).

## Open design decision (resolve in Launch Pad Phase 5.5 / Plan Review — recommendation given)
**Where does the engine-native line land?** Two viable targets:
- **(A — RECOMMENDED) Unified corpus, FULL record:** append a **complete, valid `schema_version: 1` `POSTMORTEM_RESULT`** to the **same** `.supervisor/postmortem/results.jsonl`, with **every** required field present (`schema_version`, `ts`, `repo`, `number`, `agent_generated_guess`, `review_rounds`, `additions`, `deletions`, `changed_files`, `categories[]`, `self_heal_misses`, `flow_stages{...}`, `summary`) **plus the two additive fields `source: "automate_drain"` (discriminator) and `automate_key` (idempotency)**. This is NOT a new shape — it is the *same* schema + two additive fields (`source`, `automate_key`) — so it does **not** "pollute the corpus with a second schema" (the review's concern about a minimal line is resolved by emitting the full record). Mapping from data in hand:
- **Define once, use everywhere: `effective_review_rounds = (drain_result == "ESCALATED" and fix_cycles == 0) ? 1 : fix_cycles`.** This single term resolves the zero-cycle-escalation edge case so it never contradicts the `fix_cycles` mapping. `review_rounds` ← `effective_review_rounds`; `flow_stages.self_heal` ← `effective_review_rounds`.
- **`categories[]` length MUST equal `effective_review_rounds`'s zero/non-zero state (load-bearing — `read-postmortem.sh` counts every `categories[]` element as a prior-churn round, [`:144`](ai-agent-manager-plugin/scripts/read-postmortem.sh:144)):**
  - `effective_review_rounds == 0` (clean / no-churn merge, i.e. `fix_cycles == 0 AND drain_result != "ESCALATED"`) → **`categories: []`** and `review_rounds: 0`. NEVER a synthetic entry here, or the live reader reports **fake churn**.
  - `fix_cycles > 0` → **one** synthetic entry `{round: fix_cycles, class: "drain_churn", self_heal_miss: (self_heal_misses>0), flow_stage: "self_heal", evidence: "until-mergeable drain, decision=<READY|ESCALATED>, fix_cycles=<n>"}`. (read-postmortem then counts this PR as ONE churny-drain round for the path — an entry-granularity unit, intentionally distinct from the `review_rounds` field's depth; documented in Subtask 3.)
  - **Zero-cycle `ESCALATED`** (`fix_cycles == 0 AND drain_result == "ESCALATED"`, so `effective_review_rounds == 1`) → **one** `{round: 1, class: "drain_escalation", self_heal_miss: (self_heal_misses>0), flow_stage: "self_heal", evidence: "until-mergeable drain escalated before any fix cycle"}` entry, so an escalation is never recorded as 0-churn.
- `self_heal_misses` ← `1` if `repeat_check_failure or unresolved_bot_feedback` else `0`.
- `changed_paths` / `additions` / `deletions` / `changed_files` ← from the **single allowed fetch** `gh pr view "<pr_url>" --json files,additions,deletions,changedFiles` (`changed_paths` = `[.files[].path]`). On any fetch failure these degrade to `changed_paths: []` and `additions/deletions/changed_files: 0` — they are **integers per schema, default `0`, NEVER `null`** ([pr-postmortem-gather.sh:335](ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh:335)).
- `agent_generated_guess: true`; `summary` ← one neutral sentence. **Pro:** one ledger for the deferred eval harness AND `read-postmortem.sh` actually picks it up (because `changed_paths` + `categories[]` are present). **Con:** the synthetic `categories[]` entry is coarser than `/pr-postmortem`'s per-round classification — but it is honestly labeled (`source`, `class:"drain_churn"`) and `read-postmortem.sh` aggregates `class` strings, so a new class value is fine.
- **(B) Separate ledger:** append a purpose-built shape to a new `.supervisor/automate/learning.jsonl`. **Pro:** zero risk to the existing corpus; honest fields with no synthetic `categories[]`. **Con:** splits the corpus; the eval harness AND `read-postmortem.sh` must learn a second path (extra work to consume).

Recommend **(A — full record)**. Plan Review confirms A-full or B before implementation; the Subtask scope below is written for A-full and notes the B-delta. **Either way, the line MUST carry `changed_paths`** (else it is invisible to `read-postmortem.sh` — verified [`read-postmortem.sh:125`](ai-agent-manager-plugin/scripts/read-postmortem.sh:125)).

## Acceptance Criteria
- [ ] **Given** `/automate` processes a Queue item that produced a PR (merged OR **parked** — `escalated`/`awaiting_merge`), **when** the owned DRAIN has read `REVIEW_HEAL_RESULT` (§6 **step 3**, BEFORE the GATE so parked items are still covered), **then** it appends **exactly one** learning line — a **FULL valid `schema_version: 1` POSTMORTEM_RESULT** (target A: all required fields present per [RESULT_SCHEMAS.md:1684](ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md:1684)) carrying the additive `source: "automate_drain"`, `review_rounds` = `effective_review_rounds` (= `fix_cycles`, or `1` for a zero-cycle `ESCALATED`), a populated **`changed_paths`**, and a `categories[]`/`self_heal_misses`/`flow_stages` per the §"Open design decision" mapping (incl. the **`categories: []` only when `effective_review_rounds == 0`** zero-rule) — built **jq-only** (injection-safe). No postmortem gather; the only fetch permitted is **one** `gh pr view "<pr_url>" --json files,additions,deletions,changedFiles` supplying `changed_paths` AND the integer size fields in a single call.
- [ ] **Given** a crash between the emit and the §6-step-6 check-off (or a `--resume` that re-enters the item), **when** the emit would run again, **then** a deterministic **idempotency key** (`run_id` + item + `pr_url` + `source`) makes `learning-emit` **skip if a line with that key already exists** — so an item yields **exactly one** line across crashes/resumes (closes the append-then-checkoff dup window).
- [ ] **Given** any failure in the emit (jq missing, unwritable ledger, missing field, changed_paths fetch fails), **when** the line would be written, **then** the engine **continues unaffected and exits 0** — the signal NEVER changes `owned_drain_result`, the merge-or-park gate, `## Status`, `## Current`, or any `/autonomous` gate (advisory/fail-safe, mirrors `postmortem_dispatched`). A failed fetch degrades to `changed_paths: []` and integer size fields `= 0` (NEVER `null`); the line is still written, just invisible to `read-postmortem.sh`.
- [ ] **Given** the owned `/review-pr --until-mergeable` drain runs inside `/automate`, **when** it would fire its GitHub-blind Postmortem Dispatch Tail, **then** the engine passes **`--no-auto-postmortem`** to that owned drain so the corpus gets **one honest engine-native line, not one honest + one false-0** for the same PR. (Outside `/automate`, the standalone `/review-pr --until-mergeable` tail is **unchanged**.)
- [ ] **Given** target (A), **when** the FULL record lands in `.supervisor/postmortem/results.jsonl`, **then** (i) `read-postmortem.sh` returns it as a prior-churn hit for a touched path (because `changed_paths` + `categories[]` are present — verified [`:125`,`:136`](ai-agent-manager-plugin/scripts/read-postmortem.sh:125)); (ii) every existing POSTMORTEM_RESULT consumer still parses the file (the `source` field is additive/ignored; no `schema_version` bump beyond the additive field); (iii) a drain-measured entry is distinguishable from a GitHub-measured one via `source`.
- [ ] **Given** the change is implemented via the helper, **when** the ledger is written, **then** it goes through a new fail-safe `automate-helpers.sh learning-emit` subcommand, with a self-test in `scripts/test-automate-helpers.sh` covering: happy path (full valid record, `fix_cycles>0` → exactly one `drain_churn` `categories[]` entry, `review_rounds == fix_cycles`), **`fix_cycles==0` non-escalated → `categories: []` AND `review_rounds: 0`** (no fake round — the zero-rule), zero-cycle `ESCALATED` (`fix_cycles==0 AND drain_result==ESCALATED`) → `review_rounds: 1` + one `drain_escalation` entry, idempotency skip on duplicate key, missing-field degrade → still exit 0, jq-absent → exit 0 no-write, fetch-fail → `changed_paths: []` + integer size fields `0` (never `null`) line still written, and injection-safe field values.
- [ ] **Given** the work touches docs/metadata, **when** it lands, **then** counts stay 14/19/56/20, version bumps to 14.44.0 across `plugin.json` + `marketplace.json` + CLAUDE.md current-version lines, `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` are green, and the automate-loop / RESULT_SCHEMAS single-source-of-truth references stay in sync (no mirror drift).
- [ ] **Given** all invariants, **when** the work lands, **then**: `/review-pr` & Phase 4.5 still never merge; the sole `gh pr merge --squash` executor (the automate `--auto-merge` gate) is unchanged; runtime emitters fail-SAFE (exit 0); correctness gates fail-CLOSED; the `/automate` single-drain ownership invariant is untouched.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | `automate-helpers.sh` fail-safe `learning-emit` subcommand (FULL POSTMORTEM_RESULT + idempotency-key skip) + self-test | 2 modify | LAUNCHABLE |
| 2 | Wire the emit into the per-item loop AFTER DRAIN (step 3) + suppress the redundant drain tail | 1–2 modify | BLOCKED (by #1) |
| 3 | Schema: additive `source` field on POSTMORTEM_RESULT (target A) + RESULT_SCHEMAS doc | 1 modify | LAUNCHABLE (can run parallel to #1) |
| 4 | Version bump, CHANGELOG, doc-currency, cross-surface sync | ~5 modify | BLOCKED (by #1,#2,#3) |

**Recommended serial order: 1 → 3 → 2 → 4** (or 1 ∥ 3, then 2, then 4). Single worker recommended (every file is a single-source-of-truth surface; mirror-drift risk per the `prompt-is-program` lesson).

### Subtask 1 — `automate-helpers.sh learning-emit` (fail-safe, FULL record, idempotent)
- **Scope:** Add a `learning-emit <ledger_path> <args...>` subcommand to [`scripts/automate-helpers.sh`](ai-agent-manager-plugin/scripts/automate-helpers.sh) that:
  - builds a **complete, valid `schema_version: 1` POSTMORTEM_RESULT** (target A — ALL required fields per [RESULT_SCHEMAS.md:1684](ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md:1684), including a populated `changed_paths`, integer size fields defaulting to `0`, and a `categories[]` honoring the **zero-rule** — `[]` only when `effective_review_rounds == 0` (i.e. `fix_cycles == 0 AND drain_result != "ESCALATED"`); one synthetic entry otherwise (`drain_churn` for `fix_cycles>0`, `drain_escalation` for a zero-cycle escalation)) **plus** the additive `source: "automate_drain"` + `automate_key`, with **jq `--arg`/`--argjson` only** (no string interpolation of PR text);
  - **idempotency-key skip:** before appending, derive the key (`run_id` + item + `pr_url` + `source`) and **scan the ledger for an existing line with that key** (jq `select`); if found, **no-op exit 0** (so crash/resume can't duplicate). Store the key as an additive field on the line (e.g. `automate_key`) so the scan is exact, jq-only, and injection-safe;
  - appends atomically. **Always exits 0** — jq missing, unwritable path, unreadable ledger, or any missing field degrades to a no-op or a `changed_paths: []` line, never a non-zero exit. Model the fail-safe contract on `dispatch-pr-postmortem.sh` / `send-webhook.sh`.
- **Files:** `ai-agent-manager-plugin/scripts/automate-helpers.sh`, `ai-agent-manager-plugin/scripts/test-automate-helpers.sh`.
- **provides:** `{kind: symbol, path: ai-agent-manager-plugin/scripts/automate-helpers.sh, name: "learning-emit subcommand (full POSTMORTEM_RESULT, idempotency-key skip, jq-built, append-only, always exit 0)"}`
- **requires:** none. **Confidence:** HIGH.
- **Invariant:** fail-SAFE (exit 0 on every path); injection-safe (jq args only); append-only (never rewrites the ledger); exactly-once per key.

### Subtask 2 — Wire into the per-item loop (after DRAIN) + suppress the redundant tail
- **Scope:** In [`skills/automate-loop/SKILL.md`](ai-agent-manager-plugin/skills/automate-loop/SKILL.md) §6, add the emit call via `automate-helpers.sh learning-emit` **at the end of step 3 (DRAIN), BEFORE step 4 (GATE)** — NOT at step 6 (CHECK OFF), because parked items (`escalated`/`awaiting_merge`) stop at the GATE and never reach CHECK OFF. At end-of-DRAIN both blocks are in hand: read `fix_cycles`/`repeat_check_failure`/`unresolved_bot_feedback`/`drain_result` from the step-3 `REVIEW_HEAL_RESULT` and `heal_decision`/`rubric_score`/`pr_url`/`branch`/`repo`/`number` from the step-2 `SUPERVISOR_RESULT`; source `changed_paths` + integer size fields from the **single allowed fetch** `gh pr view "<pr_url>" --json files,additions,deletions,changedFiles` (degrade to `[]`/`0` on failure). Pass the `run_id`+item+`pr_url`+`source` idempotency key so a resume/crash yields exactly one line. Emit for **every** item that produced a PR (merged OR parked). In §7 (the owned drain invocation, [`:230`](ai-agent-manager-plugin/skills/automate-loop/SKILL.md:230)), pass **`--no-auto-postmortem`** to the owned `/review-pr --until-mergeable` so it does not also append a false-0 postmortem line.
- **Files:** `ai-agent-manager-plugin/skills/automate-loop/SKILL.md` (§6 **step 3, end of DRAIN** + §7), and the `AUTOMATE_RUN` summary section if a per-run `learning_lines_emitted` count is added (optional, advisory).
- **provides:** `{kind: file, path: ai-agent-manager-plugin/skills/automate-loop/SKILL.md, name: "end-of-DRAIN (§6 step 3) learning-emit + --no-auto-postmortem on owned drain"}`
- **requires:** `{kind: symbol, path: ai-agent-manager-plugin/scripts/automate-helpers.sh, name: "learning-emit", from: subtask-1}`
- **Confidence:** HIGH. **Invariant:** single-drain ownership untouched; emit is advisory (a learning-emit failure must be invisible to the gate/`## Status`).

### Subtask 3 — Schema: additive `source` discriminator + the `automate_drain` full-record variant (target A)
- **Scope:** In [`docs/RESULT_SCHEMAS.md`](ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md) POSTMORTEM_RESULT, document **two additive optional fields** — `source` (`"github_postmortem"` default/implicit | `"automate_drain"`) and `automate_key` (the idempotency key, present only on `automate_drain` lines) — AND a worked **`source: "automate_drain"` variant example** spelling out the field mapping (the synthetic `categories[].class: "drain_churn"` entry, `review_rounds`/`flow_stages.self_heal` ← `fix_cycles`, `self_heal_misses` derivation, `changed_paths` requirement). Clarify that a `"automate_drain"` line's `review_rounds` is `effective_review_rounds` — the **ground-truth drain `fix_cycles`** (or `1` for a zero-cycle escalation), not a GitHub-measured count — and that the synthetic `categories[]` is coarser than `/pr-postmortem`'s per-round classification. **No `schema_version` bump** (additive optional fields, same precedent as prior additive fields). If Plan Review picks **target B** instead, this subtask documents the new `.supervisor/automate/learning.jsonl` shape and POSTMORTEM_RESULT is untouched.
- **Files:** `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`.
- **provides:** `{kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: "POSTMORTEM_RESULT.source additive field (or learning.jsonl shape under target B)"}`
- **requires:** none. **Confidence:** HIGH.

### Subtask 4 — Version bump, CHANGELOG, doc-currency, cross-surface sync
- **Scope:** Bump 14.43.0 → **14.44.0** (`plugin.json`, `marketplace.json`, CLAUDE.md current-version lines + one banner; descriptions updated **in place**). Bump `automate-loop/SKILL.md` `version:` minor. Add `CHANGELOG.md` entry. Reconcile `commands/agent-help.md` / `commands/automate.md` if a described behavior changed (the `--no-auto-postmortem`-on-owned-drain note). Run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` green. **Counts stay 14/19/56/20.**
- **Files:** `plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `CHANGELOG.md`, `commands/automate.md`/`agent-help.md` (if needed), `skills/automate-loop/SKILL.md` (frontmatter).
- **requires:** subtasks 1, 2, 3. **Confidence:** HIGH.

## Parallelism Analysis
- **Recommended workers: 1 (serial).** Helper + single-source-of-truth skill + schema doc — small surface, high mirror-drift risk; serial is the disciplined choice. Subtasks 1 and 3 are independent and *could* run parallel, but the payoff is marginal.
- **Order:** 1 → 3 → 2 → 4.

## Outcomes Rubric
- `/automate` emits exactly one ground-truth learning line per PR-producing item (merged OR parked), **at end-of-DRAIN (§6 step 3)** so parked items are covered, built jq-only from `REVIEW_HEAL_RESULT` + `SUPERVISOR_RESULT` the engine already holds (only added fetch: one `gh pr view ... --json files,additions,deletions,changedFiles`).
- The line is a **FULL valid `schema_version: 1` POSTMORTEM_RESULT** (target A) — all required fields present, with `changed_paths` populated so `read-postmortem.sh` actually returns it as a prior-churn hit (verified the reader matches only on `changed_paths`).
- The line carries the real churn (`review_rounds` = `effective_review_rounds`, i.e. drain `fix_cycles` or `1` for a zero-cycle escalation), not a GitHub-measured count; `source: "automate_drain"` distinguishes it; the synthetic `categories[]` is honestly labeled (`class: "drain_churn"` / `"drain_escalation"`) with length matching the zero-rule.
- **Idempotency:** a crash between emit and check-off, or a `--resume`, yields exactly ONE line — `learning-emit` skips on a duplicate `run_id`+item+`pr_url`+`source` key.
- The owned drain runs with `--no-auto-postmortem`, so an automate'd PR gets one honest line, not one honest + one false-0.
- The emit is advisory/fail-safe (always exit 0); it never changes the merge-or-park gate, `owned_drain_result`, `## Status`, or any `/autonomous` gate; a failed `changed_paths` fetch degrades to `[]` without failing.
- `pr-postmortem-gather.sh` is **unchanged** — no consumer-specific log parsing leaked into the generic tool.
- Existing POSTMORTEM_RESULT consumers (`read-postmortem.sh`, eval-harness corpus) still parse the ledger; no `schema_version` bump (additive `source`/`automate_key` fields only).
- Invariants intact: never-merge; sole `gh pr merge --squash` executor unchanged; single-drain ownership untouched; emitters exit 0 / correctness gates fail closed.
- Counts unchanged (14/19/56/20); version 14.44.0 consistent; doc-currency + validate-version green.

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| The advisory emit accidentally gates the engine (a write failure parks/aborts the item) | HIGH | Failure-mode invariant | `learning-emit` always exits 0; loop ignores its status; covered by self-test (jq-absent → exit 0) |
| Double-counting: owned drain still fires its postmortem tail AND the engine emits → false-0 line + honest line for same PR | MEDIUM | Code (review-heal tail) | Pass `--no-auto-postmortem` to the owned drain (AC) |
| `source` discriminator missing → a drain `fix_cycles` is read as a GitHub `review_rounds` by a consumer | MEDIUM | Schema | Subtask 3 additive `source` field; consumers key off it |
| Mirror drift: `automate-loop` / `review-heal` / `RESULT_SCHEMAS` references diverge | MEDIUM | Lessons (`agent-command-mirror-drift`, `prompt-is-program`) | Reference-don't-restate; consistency_audit auto-triggers on `skills/`+`docs/`; state-trace the §6 loop |
| Injection via PR title/branch into the jq line | MEDIUM | Security | jq `--arg`/`--argjson` only (same contract as `pr-postmortem-gather.sh`) |
| Line invisible to `read-postmortem.sh` — it matches ONLY on `changed_paths` overlap ([`:125`](ai-agent-manager-plugin/scripts/read-postmortem.sh:125)) | HIGH | Review finding (verified) | Emit a FULL record WITH populated `changed_paths` (one `gh pr view ... --json files,...` fetch); AC + self-test assert `read-postmortem.sh` returns the line as a hit |
| Exactly-once broken by crash between emit and check-off, or by `--resume` re-entry | MEDIUM | Review finding (verified) | `run_id`+item+`pr_url`+`source` idempotency key; `learning-emit` skips on duplicate; self-test covers it |
| Synthetic `categories[]` misread as `/pr-postmortem`'s real per-round classification | LOW | Design | `source:"automate_drain"` + `class:"drain_churn"` label it; documented in Subtask 3 as coarser-than-postmortem |

## Configuration
- New behavior: `/automate` owned drain runs with `--no-auto-postmortem` (engine-native signal replaces it inside automate). Standalone `/review-pr --until-mergeable` tail unchanged.
- No new user-facing flags required. Optional future: `--no-learning-signal` opt-out (defer unless asked).
- Target A-full vs B is a Plan-Review decision (recommend **A-full** — full valid POSTMORTEM_RESULT + `source` discriminator + `changed_paths`). Either way the line MUST carry `changed_paths` or it is invisible to `read-postmortem.sh`.

## Handoff
```
# In a fresh session, after cutting a branch off main:
/supervisor job: .supervisor/jobs/pending/2026-06-22-automate-native-learning-signal.md
# Suggested: /supervisor --red-team (touches the learning corpus + automate engine).
```

## Outcome
- **Status:** done
- **Result:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/77 (v14.44.0, base main, OPEN — awaiting human merge)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0 (code review found 0 new BLOCKING/HIGH issues; 1 LOW nit applied as optional polish)
- **heal_remaining_issues:** 0
- **rubric_score:** 10/10 (advisory; grader output truncated, items independently verified this session + by the holistic Code Reviewer)
- **Until-mergeable dispatched:** true (PostToolUse[Bash] hook at gh pr create; detached, isolated worktree; never merges)
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260622T123625Z-38c2337b03dbced34ca55bff9bc62471e9d52b1c.log
- **Gates:** test-automate-helpers.sh 60/60 · check-doc-currency green · validate-version green · counts 14/19/56/20 · no schema_version bump
- **Commits:** f81bce6 (feature) + c52c193 (clamp polish)
