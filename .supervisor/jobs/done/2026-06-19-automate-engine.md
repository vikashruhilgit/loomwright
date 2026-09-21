# Supervisor Job: `/automate` — generic automation engine (single run file → per-item loop)

## Environment  *(snapshot 2026-06-19 — ADVISORY ONLY; Supervisor MUST re-derive at Phase 0)*
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git (volatile — re-check live):** snapshot showed branch `feat/measure-heal-signal-tool`, `origin/main` `plugin.json` = **`14.39.0`**. This block went stale 4× this session as the repo moved — **treat it as advisory. Supervisor's Phase 0 is the source of truth**: `git checkout main && git pull`, branch the feature from a **clean, current `main`**, read the live `plugin.json` version at FINALIZE (bump from `main`'s then-current value; do NOT hardcode).
- **GitHub CLI:** assume authenticated (verify at Phase 0).
- **Blockers:** 0 | **Warnings:** 1 (branch from a freshly-pulled clean `main`; stash any dirty tree first).

## Task

**Goal:** Add a `/automate` command + `automate-loop` authority skill — a **generic automation engine**. It converts **any source** (a prompt, a requirements folder, a backlog/plan doc, an export) into a **full Queue with a per-run processing cap** inside **one run file** `.supervisor/automate/<run_id>.md` — that file is the contract, the dashboard, and the resume state — then drives each Queue item through the per-item loop (`/autonomous --single-iteration` → owned inline `/review-pr --until-mergeable` → trusted-merge-or-park → pull `main` → check the item off + append to `## Progress`). It is **smart about resume**: on start it globs `.supervisor/automate/*.md` for incomplete runs, reconciles them against ground truth, and offers continue / start-fresh / archive.

**Why:** The plugin can drive one requirement deep (`/autonomous`) but nothing walks arbitrary work from any starting point. The per-item engine is source-agnostic — only the *intake* differs, and intake is just "convert the source into the run file's Queue, once" (NOT a pluggable adapter framework). Layering: `/autonomous` (one requirement) ⊂ per-item loop ⊂ `/automate` (source → Queue → loop). **`/backlog` is NOT a separate command** — a folder or a backlog-doc is simply one kind of source.

**The single-file principle (this design's core):** there is **no manifest, no registry, no progress.jsonl, no dashboard file**. One markdown run file holds everything; "find prior runs" = glob `.supervisor/automate/*.md` for files not marked `## Status: done`. The only other artifact is a *transient* config-backup sidecar that exists only during a tick.

```
/automate "<what you want to automate>"      # prompt source (via /product-owner) → generated requirements → Queue
/automate                                    # bare → resume an incomplete run, else ASK "what do you want to automate?"
/automate --folder <dir>                     # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>            # backlog-doc source — dependency-ordered Queue
/automate --limit N                          # cap PROCESSED items this run, full Queue still stored (default 5; "pull 5–10 and start")
/automate --resume [<run_id>]                # reconcile + continue a prior incomplete run file
/automate ... --auto-merge                   # opt-in fire-and-forget (gated; default OFF)
/automate ... --notify / --non-interactive-fallback   # passthrough to inner /autonomous
# Driven continuously by Claude's /loop:  /loop /ai-agent-manager-plugin:automate [...]
```

**Non-goals (v1):** sources beyond prompt/folder/backlog-doc (issues / Beads `bd ready` / Jira are additive later — each just populates the Queue, no framework); a `-runner` agent (inline-only, agents stay 14); QA-in-loop; parallel/multi-item execution; **multiple concurrent open PRs** (BOTH modes keep a single-open-PR invariant — `escalated` parks the run, it never opens a second PR); a separate registry/manifest/JSONL-ledger (deliberately deferred — the run file is enough).

## The run file (the contract)

`.supervisor/automate/<run_id>.md`:
```md
# Automate Run: <title>
## Status: running          # running | paused | done   (paused = stopped, work remains; done only when the Queue is fully resolved)
## Source
- <user prompt text | folder <dir> | backlog <_BACKLOG.md> | ...>
## Run Config
- mode: safe|auto-merge | limit: 5 | trust_unprotected: false
- auto_review_original: <true|false|absent> | config_backup: <run_id>.config-backup.json
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|escalated|failed|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|escalated|limit_reached|resume_ambiguous|null
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED | suppressed_default_dispatch: true
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> ran /autonomous → PR <url>
- <ts> drain READY → awaiting_merge
```
Item lifecycle: `queued (- [ ]) → running → pr-open → awaiting_merge → merged (- [x]) | escalated (parks) | failed | skipped`. **Skipped/abandoned** items are written `- [x] <path>  # skipped|abandoned: <reason>` — checked-off so they're never re-picked, reason logged in `## Progress`; `remaining` counts only `- [ ]` items, so a skipped item does not block `## Status: done`.

## Acceptance Criteria

### Intake — any source → the Queue (convert once, no framework)
- [ ] **prompt:** `/automate "X"` runs **`/product-owner`** on the prompt (REUSE — PO already writes `.supervisor/requirements/*.md` story files + an optional `_BACKLOG.md` in Beads-absent mode); the generated file paths become the `## Queue`. 1 file → single-item run; N files → loop. Bare `/automate` first attempts resume (below); if none, it ASKs "what do you want to automate?" then proceeds as a prompt source.
- [ ] **folder:** `/automate --folder <dir>` enqueues every `.md` in `<dir>` (skipping ones already `## Status: done`).
- [ ] **backlog-doc:** `/automate --backlog <_BACKLOG.md>` enqueues in the doc's documented dependency order (build order + `## Status: done`/✅ markers as ground truth; `_BACKLOG.md`-absent ⇒ fall back to `## Status:`-stamp ordering over the dir, or `remaining: 0`).
- [ ] **`--limit N` (caps PROCESSED items, not Queue size):** the run file's `## Queue` always holds the **FULL** resolved list; `limit: N` (in `## Run Config`, default **5**) caps how many items are **completed** this run. After N are processed → `## Status: paused`, `pause_reason: limit_reached`, report `remaining: <unchecked count>`; raise `limit` or `--resume` to continue. The full resolved Queue (count + ordered items) is **shown to the user for confirmation before processing** (a prompt that explodes into 40 files never runs silently); under `--non-interactive-fallback` the cap is enforced without the prompt.

### Run file + resume (single-file model)
- [ ] **One run file:** `/automate` creates/maintains exactly one `.supervisor/automate/<run_id>.md` per the template above. It IS the manifest, registry, progress log, and dashboard — **no other persistent tracking files**.
- [ ] **Crash-safe writes:** the run file is updated by **atomic write (temp + rename)**; `## Progress` is **append-only** (never rewritten); rewrites are confined to `## Queue` checkboxes and `## Current`. (Optional secondary breadcrumb: ONE terminal line per run appended to the existing `.supervisor/logs/<run_id>.jsonl` for trend tooling — never the source of truth.)
- [ ] **Resume = glob + reconcile:** on every start, glob `.supervisor/automate/*.md` for runs NOT marked `## Status: done`. The run file is the loop's **belief**; **reconcile each in-flight item against ground truth** (PR merged via `gh`, branch via `git`, requirement `## Status: done` stamp) BEFORE trusting a checkbox (a crash between merge and check-off makes them disagree). If an incomplete run exists, `AskUserQuestion`: **continue / start new / archive**; `--resume [<run_id>]` targets one explicitly (most-recent incomplete if id omitted). Under `--non-interactive-fallback`, an ambiguous resume fails closed (`status_reason: "resume_ambiguous_non_interactive"`).
- [ ] **Skipped/abandoned form:** an item the human (or loop) abandons is written `- [x] <path>  # skipped|abandoned: <reason>` in `## Queue` (checked-off ⇒ never re-picked; reason in `## Progress`); `remaining` counts only `- [ ]` items, so skipped items don't block `## Status: done`. This is the documented way to unblock an `escalated`-parked run without merging.

### Per-item loop *(carried over from the reviewed engine — unchanged behavior)*
- [ ] For each `- [ ]` Queue item: RECONCILE → run `/autonomous --single-iteration --requirement <path>` → own one inline `/review-pr --until-mergeable` → GATE → SYNC → **check the item off in `## Queue` + append a `## Progress` line (atomic write)**; report `remaining: N` (count of `- [ ]` items). **Queue fully resolved** (no `- [ ]` left) → `## Status: done`, `remaining: 0`, `/loop` stops. **`limit` items processed** (queue NOT empty) → `## Status: paused`, `pause_reason: limit_reached`, `remaining: <unchecked count>`, loop stops.
- [ ] **Single drain (no double-dispatch):** `/autonomous` already triggers Supervisor's default detached until-mergeable drain (step 5.5 + the `PostToolUse[Bash]` `gh pr create` hook). The loop sets `.supervisor/config.json {"auto_review": false}` **before invoking `/autonomous`** (wrapping the RUN phase — both dispatches fire *during* `/autonomous`; setting it at DRAIN is too late) and restores in a **finally-style cleanup** after `/autonomous` returns/fails. **Config-toggle contract:** byte-for-byte backup to a transient `<run_id>.config-backup.json` (its path + the original `.auto_review` value recorded in `## Run Config`; record absence if no prior config); restore overwrites or **deletes if originally absent** (never leave a partial `config.json` shadowing legacy `notify-config.json`); **malformed pre-existing config ⇒ abort**; RECONCILE restores a crash-stranded backup. Then DRAIN owns exactly ONE inline `/review-pr --until-mergeable`, terminal `REVIEW_HEAL_RESULT` read synchronously and written to `## Current` (`owned_drain_started`/`owned_drain_result`/`suppressed_default_dispatch`). (Verifiable via those `## Current` fields + absence of any detached `dispatch-pr-review.sh` artifact for the PR.)
- [ ] **Single-open-PR invariant (both modes):** while ANY item has an OPEN unmerged PR — status `awaiting_merge` **or** `escalated` — the loop MUST NOT PICK a new item (at most ONE open PR at a time). For `awaiting_merge`, RECONCILE re-checks the PR each tick and resumes once it merges (next item branches off fresh `main`); for `escalated`, the run stays paused until a human resolves it. (`--auto-merge` skips the `awaiting_merge` park by merging at the gate, but still parks on `escalated`.)
- [ ] **`READY` is "ready, left open for a human" — nothing in the plugin merges.** Without a merge the loop would stale-base or build a PR tower, so the merge is the engine's own step: opt-in `--auto-merge`, default OFF, gated (below). **`ESCALATED` never merges and PARKS the run** (`## Status: paused`, `pause_reason: escalated`, notify) — it does NOT pick a new item, because an escalated PR is open + unresolved and stacking another PR would violate the single-open-PR invariant. To proceed: resolve the PR (fix + merge, or close) **or** mark the item `skipped`/`abandoned` in `## Queue`, then `--resume`.
- [ ] **Trusted auto-merge gate** (`gh pr merge --squash` fires ONLY when ALL hold, else fail **closed** → park+notify): (1) owned drain == `READY`; (2) head SHA still == the `READY` SHA (`gh pr view --json headRefOid`) and base == `main`; (3) `reviewDecision` (via `gh pr view --json reviewDecision`) ∉ {`CHANGES_REQUESTED`,`REVIEW_REQUIRED`} **and** null/unreadable `reviewDecision` ⇒ park, **and** no unresolved human-authored review thread — threads are **GraphQL-only** (`gh api graphql` `reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{author{login __typename}}}}}`, NOT the non-existent `--json reviewThreads` flag, `review-heal/SKILL.md:544`; author classification direct off the `author` node — `__typename=="Bot"` or login `*[bot]` ⇒ bot, else block; unreadable ⇒ do-not-merge); (4) **enforceable** branch protection — `required_approving_review_count >= 1` OR required status checks (toothless/unreadable ⇒ unprotected; **GitHub rulesets out of scope v1**) — OR explicit `--trust-unprotected`; (5) required checks green AND **rubric satisfied — read from `SUPERVISOR_RESULT.rubric_score`** (Supervisor's Phase 4.5 Rubric Grader, which runs even under single-iteration `/autonomous`; do NOT rely on the autonomous EVALUATE rubric loop, which single-iteration short-circuits): satisfied = N==M; a null/absent `rubric_score` (item had no `## Outcomes Rubric`) makes this condition **N/A — not a blocker**.

### Invariant preservation
- [ ] `review-heal` / Supervisor Phase 4.5 still never merge; the only place that **executes** `gh pr merge --squash` is the `automate-loop` `--auto-merge` gate (positive-form grep excludes the negative-assertion mentions in review-heal/review-pr/RESULT_SCHEMAS). Recorded in a **durable** CLAUDE.md section (Failure-Mode Invariants / Common Pitfalls), not just the release banner.
- [ ] All `/autonomous` correctness gates still bubble up; `--notify` / `--non-interactive-fallback` pass through.

## Subtask Structure

| # | Title | Est. files | Status |
|---|-------|-----------|--------|
| 1 | Author `automate-loop` skill — protocol authority for ALL phases: source→Queue intake (prompt via PO / folder / backlog-doc) + `--limit` + queue-confirm; **run-file create/maintain** (one `<run_id>.md`, atomic write, append-only `## Progress`); **RESUME** (glob `*.md` for not-done + reconcile-vs-ground-truth + gate); per-item RECONCILE/RUN/DRAIN/GATE/SYNC/check-off; two modes; termination | 1 create (`skills/automate-loop/SKILL.md`) | LAUNCHABLE |
| 2 | Author `/automate` command shell (2 inline-exec callouts + Purpose/Usage/Parameters/What-This-Does + Step 0 `${CLAUDE_PLUGIN_ROOT}` canonical-body reads; references skill #1) | 1 create (`commands/automate.md`) | BLOCKED (by #1) |
| 3 | Document the **run-file layout** (`AUTOMATE_RUN`) in `docs/RESULT_SCHEMAS.md` — explicitly flagged as a **markdown state-file contract, NOT a hook-validated emitted result block** (no SubagentStop hook enumerates it): the `.supervisor/automate/<run_id>.md` section contract (`## Status`/`## Source`/`## Run Config`/`## Queue` checklist/`## Current` with item-status enum + `suppressed_default_dispatch`/`owned_drain_started`/`owned_drain_result`/append-only `## Progress`) + the optional one-line terminal JSONL to `.supervisor/logs/<run_id>.jsonl` | 1 modify | BLOCKED (by #1) |
| 4 | Helpers + **scriptable self-tests (stubbed `gh`)**: prompt→PO wiring, folder/backlog-doc resolver, run-file read/atomic-write, resume-reconcile; tests for config suppress/restore (incl. absent-file & malformed-abort), **run-file atomic-write + append-only-`## Progress`**, **resume reconcile (belief vs git/gh truth)**, and auto-merge gate fail-closed | 2–4 create (`scripts/` + tests) | BLOCKED (by #1) |
| 5 | Doc-currency + counts + version sweep (commands +1, skills +1 relative to `main`'s LIVE counts; version bump; durable invariant carve-out; SKILLS_INDEX `automate-loop` row); run `check-doc-currency.sh` / `validate-version.sh` / `check-command-sync.sh` green | ~9 modify | BLOCKED (by #1,#2,#3,#4) |

### Subtask Contracts (provides / requires)

```yaml
subtask_1:   # automate-loop skill (greenfield)
  provides: [ { kind: file, path: ai-agent-manager-plugin/skills/automate-loop/SKILL.md } ]
  requires: []
subtask_2:   # /automate command shell
  provides: [ { kind: file, path: ai-agent-manager-plugin/commands/automate.md } ]
  requires: [ { kind: file, path: ai-agent-manager-plugin/skills/automate-loop/SKILL.md } ]
subtask_3:   # AUTOMATE_RUN run-file layout doc
  provides: [ { kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: AUTOMATE_RUN } ]
  requires: [ { kind: file, path: ai-agent-manager-plugin/skills/automate-loop/SKILL.md } ]
subtask_4:   # helpers + self-tests
  provides: [ { kind: claim, name: automate-helpers-and-selftests } ]
  requires:
    - { kind: file,   path: ai-agent-manager-plugin/skills/automate-loop/SKILL.md }
    - { kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: AUTOMATE_RUN }
subtask_5:   # doc-currency + counts + version (must run last)
  provides: [ { kind: claim, name: doc-currency-green } ]
  requires:
    - { kind: file,   path: ai-agent-manager-plugin/commands/automate.md }
    - { kind: file,   path: ai-agent-manager-plugin/skills/automate-loop/SKILL.md }
    - { kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: AUTOMATE_RUN }
    - { kind: claim,  name: automate-helpers-and-selftests }
```

## Parallelism Analysis
- Batch 1: Subtask 1 (the protocol everything references).
- Batch 2: Subtask 2 + Subtask 3 + Subtask 4 (parallel after #1 — distinct files: `commands/`, `docs/RESULT_SCHEMAS.md`, `scripts/`).
- Batch 3: Subtask 5 (after #1–#4 land, so counts/refs are accurate).
- Recommended workers: **2–3** (3 launchable in batch 2, no file overlap).

## Storage & Tracking Layout  *(single run file — nothing else persistent)*
```
.supervisor/
  requirements/                   # canonical requirement store (existing; PO/Launch Pad resolve here)
      <run_id>-<slug>.md           #   prompt-source writes generated requirements here (via /product-owner)
  automate/                       # NEW — one markdown file per run
      <run_id>.md                  #   THE run file (Status/Source/Run Config/Queue/Current/append-only Progress)
      <run_id>.config-backup.json  #   TRANSIENT — byte-for-byte config.json backup during a tick; deleted on clean restore
  logs/<run_id>.jsonl             # existing session-log convention — optional ONE terminal line/run for trend tooling
```
"Find prior runs" = glob `.supervisor/automate/*.md` not `## Status: done`. Resume safety = **run file is belief; git/gh is truth** (reconcile before trusting a checkbox) + **atomic write + append-only `## Progress`**.

## Configuration
- **Base Branch:** `main` (branch from a clean, pulled `main` — re-derived at Phase 0).
- **Affects:** `ai-agent-manager-plugin/{commands,skills,docs,scripts}/`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, root `.claude-plugin/marketplace.json` + `README.md`, `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`.
- **New:** 1 command (`/automate`), 1 skill (`automate-loop`). **No** new agent/hook/runner. `AUTOMATE_RUN` documented at `schema_version: 1` as a **run-file state contract (a markdown layout), NOT a hook-validated emitted result block** — unlike SUPERVISOR_RESULT/CODE_REVIEW_RESULT/etc., nothing validates it at a SubagentStop.

## Risk Assessment

| Risk | Sev | Mitigation |
|------|-----|------------|
| `--auto-merge` on bare `READY` bypasses the human gate (READY ignores `REVIEW_REQUIRED`/human threads) | **HIGH** | The 5-condition trusted-merge gate; fail-closed; opt-in/default-OFF; durable CLAUDE.md carve-out. |
| Double until-mergeable drain (`/autonomous`'s detached drain + an engine drain) racing the branch | **HIGH** | Suppress via `.auto_review:false` around the RUN phase; own ONE inline drain; `## Current` drain fields + no-dispatch-artifact assertion. |
| **run-file corruption** — markdown is the only copy of resume state; a crash mid-rewrite loses it | **HIGH** | **Atomic write (temp + rename)**; `## Progress` append-only; rewrites confined to Queue checkboxes + `## Current`; optional `.supervisor/logs/<run_id>.jsonl` terminal line as a secondary breadcrumb. |
| **prompt-source explodes** — `/product-owner` is interactive/heavy and may emit 0 or many files | MED | `--limit` caps **processed** items (the full Queue is still materialized in the run file); the resolved Queue is **human-confirmed before processing**; 0 files ⇒ report + stop, never wedge. |
| **resume reconcile is wrong** — the run file's checkbox says done/pending but reality differs | MED | Run file is *belief*; reconcile vs ground truth (`gh`/`git`/`## Status: done`) before trusting a checkbox; ambiguous ⇒ fail closed; `--resume` explicit. |
| **concurrent runs** — two `/automate` in one repo collide on the repo-global `.auto_review` toggle | MED | Single-run-per-repo assumption (documented constraint); the `.auto_review:false` window is repo-global while set — don't run two loops in one repo. |
| config-toggle crash window | MED | byte-for-byte backup/restore + absent-delete + malformed-abort; RECONCILE crash-restore; backup path recorded in `## Run Config`. |
| Version/counts bump must target `main`'s LIVE values (the tree lags) | MED | Phase 0 re-derive; FINALIZE reads `git show origin/main:...plugin.json`; don't hardcode. |
| `/loop` "Unknown command" headless | LOW | Document namespaced form `/loop /ai-agent-manager-plugin:automate`. |

## Outcomes Rubric
- [ ] `commands/automate.md` exists, mirrors `commands/review-pr.md` structure + Step 0 `${CLAUDE_PLUGIN_ROOT}` reads, references `skills/automate-loop/SKILL.md`.
- [ ] `skills/automate-loop/SKILL.md` exists with frontmatter and documents the three sources, `--limit`+queue-confirm, the single run-file model (create/maintain, atomic write, append-only Progress), RESUME (glob + reconcile + gate), the per-item loop, both modes, and termination.
- [ ] **Intake works:** prompt → `/product-owner` → generated requirements → Queue; folder → `*.md` items; backlog-doc → dependency order; `--limit` caps **processed items** (full Queue still stored); the full resolved Queue is human-confirmed before processing.
- [ ] **Single-file run + resume works:** one `.supervisor/automate/<run_id>.md` (Status/Source/Run Config/Queue/Current/Progress); glob finds incomplete runs; reconcile-vs-truth before trusting a checkbox; continue/new/archive (fail-closed under `--non-interactive-fallback`). **No** `manifest.json`/`runs.jsonl`/`progress.jsonl` created.
- [ ] **Crash-safety:** run file written atomically (temp+rename); `## Progress` append-only; a kill mid-tick leaves a parseable file the next run reconciles from.
- [ ] `docs/RESULT_SCHEMAS.md` documents the `AUTOMATE_RUN` run-file layout (sections + item-status enum + drain fields) + the optional terminal logs line, **explicitly labeled a markdown state-file contract, NOT a hook-validated emitted result block**.
- [ ] **Single drain + safe-mode pause + trusted auto-merge gate** behave per the per-item ACs (suppress around RUN; one inline drain; park while awaiting_merge; `gh pr merge` only behind the 5-condition gate; `ESCALATED`/blocked ⇒ never merge).
- [ ] **Scriptable self-tests pass** (stubbed `gh`): config suppress/restore (absent-file + malformed-abort), run-file atomic-write + append-only-Progress, resume reconcile, and auto-merge fail-closed on each blocker (unprotected/toothless, moved SHA, `CHANGES_REQUESTED`, null `reviewDecision`, unresolved human thread).
- [ ] **Doc-currency green:** version bumped in place (`plugin.json` + `marketplace.json`, from `main`'s LIVE value at FINALIZE); counts → `main`+1 command / `main`+1 skill; `SKILLS_INDEX` `automate-loop` row; all current-claim surfaces updated (derive the file:line set from `check-doc-currency.sh`'s `Authoritative →` output); `check-doc-currency.sh` + `validate-version.sh` + `check-command-sync.sh` all exit 0.
- [ ] The only executed `gh pr merge --squash` is the `automate-loop` gate (positive-form grep); review-heal/review-pr/RESULT_SCHEMAS keep only their negative-assertion mentions.
- [ ] CLAUDE.md documents the feature in a **durable** section (auto-merge scoped-exception + single-drain ownership) AND a single trimmed release banner.

## Verification (end-to-end)
1. `scripts/check-doc-currency.sh && scripts/validate-version.sh && scripts/check-command-sync.sh` → exit 0.
2. `/agent-help` lists `/automate`; `/skills` shows `automate-loop`.
3. **prompt source (dry, safe mode):** `/automate "add a /version command"` → runs `/product-owner`, shows the resolved Queue for confirmation, creates one `.supervisor/automate/<run_id>.md`, processes item 1 to a PR driven to `READY`, marks it `awaiting_merge` in `## Current`, prints `remaining: N` — does NOT merge. Confirm no `manifest.json`/`runs.jsonl`/`progress.jsonl` were created.
4. **folder + limit:** `/automate --folder <dir> --limit 3` materializes the **FULL** `*.md` list in `## Queue` (skipping `## Status: done`), processes **3**, then sets `## Status: paused` / `pause_reason: limit_reached` with `remaining: <unchecked count>`.
5. **resume:** kill a run mid-tick; re-launch `/automate` → it globs `*.md`, finds the incomplete run file, reconciles (a merged PR ⇒ checked `- [x]`, an unmerged one ⇒ `awaiting_merge`), and offers continue/new/archive. Confirm the run file is parseable (atomic write held).
6. **single-drain:** `## Current` records `suppressed_default_dispatch:true` + `owned_drain_started`/`owned_drain_result`; `.auto_review:false` set before `/autonomous`, restored finally-style (config-backup deleted); NO detached `dispatch-pr-review.sh` artifact for the PR.
7. **auto-merge fail-closed:** `--auto-merge` does NOT merge on (a) unprotected/toothless branch w/o `--trust-unprotected`, (b) `CHANGES_REQUESTED`, (c) unresolved human thread (GraphQL), (d) null/unreadable `reviewDecision`, (e) moved head SHA.
8. **single-open-PR / escalation park:** when an item ESCALATES, the run sets `## Status: paused` + `pause_reason: escalated` and does NOT open a second PR; `--resume` proceeds only after the PR is resolved (merged/closed) or the item is marked `skipped`/`abandoned`. An `awaiting_merge` item likewise blocks PICK of the next item.
9. **`--limit`:** the run file's `## Queue` holds the FULL list; after `limit` items are completed → `## Status: paused`, `pause_reason: limit_reached`, `remaining: <unchecked count>`.
10. **self-tests:** the new stubbed-`gh` tests under `scripts/` → green.
11. Invariant: `grep -rn "gh pr merge --squash" ai-agent-manager-plugin/ | grep -viE "no |never |not "` resolves only under `skills/automate-loop/` / `commands/automate.md`.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-19-automate-engine.md
```
(Run in a fresh session. Supervisor re-derives git/version/cleanliness at Phase 0 — branch from a clean, pulled `main`; add `--cheap` for the Sonnet profile.)

## Outcome
- **Status:** completed
- **Completed:** 2026-06-20T19:11:11Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/74
- **Branch:** feature/automate-engine
- **Files changed:** 13
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Heal fixable issues fixed:** 0
- **Heal remaining issues:** 0
- **Red team advisory:** disabled
- **Rubric score:** null (grader truncated twice — rubric_grader_parse_failed; spec-fidelity independently confirmed by the holistic consistency_audit reviewer + 3 green CI gates + 29/29 self-tests)
- **Until-mergeable dispatched:** false (auto-review drain deliberately suppressed via .supervisor/config.json {auto_review:false} to avoid racing the inline Phase 4.5; restored after)
- **Summary:** /automate generic automation engine (v14.41.0) — new /automate command + automate-loop authority skill + AUTOMATE_RUN run-file schema + helpers & 29 stubbed-gh self-tests + v14.41.0 doc-currency sweep (counts 14/19/56/20) + durable CLAUDE.md invariants. Phase 3 review PASS (3 LOW fixed); Phase 4.5 holistic consistency_audit PASS (1 MED count-drift + 2 LOW fixed). All CI gates green.
