# Supervisor Job: Stop asking per dismissed finding — record follow-up silently, batch one fix-now ask

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (orphaned worktrees under `.claude/worktrees/` and one prunable scratch worktree; source requirement is gitignored meta-synced state, so its provenance is the metadata branch, not a commit on main)
- **Source requirement:** .supervisor/requirements/2026-11-03-180009-stop-asking-per-dismissed-finding.md
- **Base commit:** 5a28cd8e83712d48ed10c4ba9c982196a5484fbc

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell + jq + python3 helpers, same as the touched scripts |
| 2 | Dependency Availability | GO | Both dependencies merged on `origin/main`: `dismissed-followups/01` (#816, `e8342b9`) and `2026-11-03-102217-…summary…` (#818, `5a28cd8`); `dismissed-decide --auto` and the `follow_up` board state exist |
| 3 | Architecture Fit | GO | Extends the existing decision step (`automate-next-step.sh` `decide` / `pending`) and the one dismissed-draft writer (`automate-dismissed.sh`); no new writer |
| 4 | Scope vs Supervisor Capability | CAUTION | > 12 files change (driver, writer, catalog + mirror, docs, two suites, golden fixtures) — split `context-bound` into 2 sequential subtasks |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** At an `/automate` park and at PICK, record per-finding dismissed drafts `follow-up` without a question unless they are MEDIUM-or-higher and a fix-now re-drain is still available — and ask about those in ONE batched `AUT-DISMISS` question.

**Problem Statement:**
The plugin owner at an `/automate` park needs to answer only the dismissed findings that can still change the PR, because today every per-finding draft is asked one by one (`AUT-DISMISS` at the park, `AUT-PENDING` at PICK).
Currently 354 of 370 `AUT-DISMISS` asks were answered `Follow-up (keep draft)` — a "not now" that records a ledger row and keeps the draft, the same thing a default would do. This costs one owner turn per finding.
Success looks like: zero questions when nothing can be fixed now, exactly one question listing only the MEDIUM+ drafts when a fix-now re-drain is available, and every silently-recorded follow-up visible in the park report and the ledger (marked automatic) so the owner can still drop it.

### Design (decided here — the worker implements it, never re-litigates it)
- **Severity class.** A per-finding draft is *below MEDIUM* iff its first column-0 `- **Severity:** ` line reads exactly `LOW` or `INFO` (case-insensitive). Every other value — `BLOCKING`, `HIGH`, `MEDIUM`, `unspecified`, an unrecognised token, a missing or unreadable line — is *MEDIUM+* (fail toward asking). The quoted finding body is `> `-prefixed by `automate-dismissed.sh`'s `quoted()`, so it can never forge a column-0 `- **Severity:** ` line.
- **Automatic follow-up = the existing writer path.** `dismissed-decide <runfile> <draft> follow-up --auto` is widened from "summary only" to *any* draft of this run (per-finding included); `--auto` still records ONLY `follow-up`, still refuses a draft whose last ledger row already holds a decision (`already decided in the ledger`), and is still ledger-first. Every `--auto` ledger row gains a 4th TAB column `auto` (`<draft_name>\tfollow-up\t<ts>\tauto`) — summary auto-keeps included — so an automatic row is told apart from an owner's. A per-finding `--auto` Progress line reads `dismissed: follow-up <name> — followed up automatically (no question)`; the summary text stays `kept automatically (summary below the tracking threshold, no question)`.
- **At the park (`decide` step, both orders — decide-then-park and park-first):** fix-now is *available* exactly when the step's existing computation says so today (`fixnow_offer` = true: `ns_fixnow_reentered` false, and post-park also `park-ask-gate` printed `ask — fix-now allowed…`). Then:
  - every below-MEDIUM per-finding draft of the item ⇒ `--auto` follow-up, no question;
  - fix-now NOT available ⇒ every per-finding draft ⇒ `--auto` follow-up, no question (this includes a post-park `park-ask-gate` line that is not `ask — fix-now allowed…`);
  - fix-now available AND ≥1 MEDIUM+ draft ⇒ exactly ONE `AUT-DISMISS` question (one entry in `questions`) listing only those drafts, numbered `1..n`, each finding's title quoted as untrusted data via `jq --arg` (never shell-interpolated), with the existing `dismissed-cost` estimate. Options (catalog labels): `Fix none (follow-up all)` · `Fix all listed on this PR` · `Fix selected on this PR?` — the `?` label offered only when n ≥ 2. `Fix selected on this PR` requires the answer's `note` to name the selected numbers (digits separated by commas/spaces, each in `1..n`); an empty, non-numeric or out-of-range note is refused like an invalid label (`exit 2`, nothing written). Selected drafts take the existing fix-now path unchanged (`dismissed-decide … fix-now` pre-park / the D3 `fix-now` hand-off post-park, `ns_spawn_fixnow`, the one-re-drain cap); every unselected listed draft ⇒ `--auto` follow-up. `Drop` is no longer offered at the park (the owner drops by hand, below).
  - Post-park writes run inside `ns_lock_window`; a refused lock leaves the drafts undecided (the next PICK records them, below) — never a guessed decision.
- **Can't ask** (`--non-interactive`, or `{"cant_ask": true}`): below-MEDIUM drafts and the no-fix-now case still get `--auto` follow-up (no question involved); MEDIUM+ drafts with fix-now available stay **undecided** and the existing named outcome is kept (`pending_decisions recorded …`; post-park `decisions not asked (--non-interactive)` / `(cant_ask)`), never a guessed fix-now. Only the trailing "the next interactive PICK asks them" wording may change to say the next PICK records them follow-up.
- **At PICK (`pending` step):** the existing auto-keep loop (today `summary` only) records every undecided draft of this run — per-finding and summary — `--auto` follow-up, interactive or not, once a draft. `AUT-PENDING` survives ONLY as the fallback for a per-finding draft whose `--auto` was refused (ledger unwritable, Decision rewrite failed), exactly as `AUT-SUMMARY` is the summary fallback; labels unchanged (`Follow-up (keep draft)` · `Drop`).
- **Park report (Scope C).** The final `park` instruction of the item (whichever step emits it) carries an additive `auto_followed_up` array — the repo-relative paths of the drafts this decision step recorded `--auto` (script-built names, never finding text) — and its `message` names the count and the hand-drop command `automate-helpers.sh dismissed-decide <runfile> <draft> drop`. Empty ⇒ the field is omitted.
- **Owner's later Drop wins.** `dismissed-decide … drop` after an `auto` row appends a `drop` row (last row wins in `_ledger_decision` and in `dismissed-drafts`' python ledger read) and deletes the draft; `dismissed-drafts` never recreates it. No code change needed — pinned by a leg.

## Acceptance Criteria

**Happy path**
- [ ] AC1 — Given an item parks with only LOW per-finding drafts, when the decision step runs, then no question is asked; each draft's Decision is `follow-up`, its ledger row ends `\tauto`, and the park instruction's `auto_followed_up` lists every one of them.
- [ ] AC2 — Given two MEDIUM drafts and one LOW draft with a fix-now re-drain available, when the decision step runs, then exactly ONE `AUT-DISMISS` question is asked and it lists only the two MEDIUM drafts; a selected draft takes the fix-now path (`ns_spawn_fixnow` spawn); the unselected MEDIUM draft and the LOW draft are recorded `follow-up` with the `auto` column.
- [ ] AC3 — Given a pending per-finding draft at PICK time, when the next item is picked, then no `AUT-PENDING` question is asked and the draft is recorded `follow-up` (ledger row ends `\tauto`), interactive and `--non-interactive` alike.

**Edge cases**
- [ ] AC4 — Given MEDIUM+ drafts but no fix-now re-drain left (`fix_now_reentered: true`, or a post-park `park-ask-gate` line other than `ask — fix-now allowed…`), when the decision step runs, then no question is asked and all are recorded `follow-up` (`auto`).
- [ ] AC5 — Given a finding whose quoted text holds a backtick, `$(…)`, a heading line or a fake `## Status: done`, when it is listed in the batched ask or the park report, then nothing executes, the ask's question text carries it only as a jq-built quoted string, `auto_followed_up` carries only the script-built draft path, and no run-file line gains a column-0 `## ` heading from it.
- [ ] AC6 — Given an automatic `follow-up` row, when `dismissed-drafts` re-runs for that item, then the draft is neither recreated nor rewritten (byte-identical) and is not re-asked at the park or at PICK.
- [ ] AC7 — Given the owner later runs `dismissed-decide … drop` on an auto-followed-up draft, when the ledger is read (`_ledger_decision` and a `dismissed-drafts` re-run), then the owner's `drop` row wins and the draft is never recreated.
- [ ] AC8 — Given a per-finding draft whose `- **Severity:**` line is `unspecified` or missing, when the decision step runs with fix-now available, then it is listed in the batched ask (treated as MEDIUM+).
- [ ] AC9 — Given `Fix selected on this PR` with an empty, non-numeric or out-of-range `note`, when the answer is reported, then the driver exits 2 and writes nothing (no ledger row, no Progress line).

**Can't-ask**
- [ ] AC10 — Given a `--non-interactive` run or a `{"cant_ask": true}` answer, when MEDIUM+ drafts with fix-now available exist, then those drafts stay `undecided`, the named outcome (`pending_decisions recorded …` / `decisions not asked (--non-interactive)` / `(cant_ask)`) is unchanged and no fix-now is recorded or spawned.

**Checks**
- [ ] AC11 — `loomwright/scripts/test-automate-dismissed.sh` and the `test-automate-next-step` suite have a named leg for each of AC1–AC10 (the next-step legs in a new part `test-automate-next-step.d/12-dismissed-batch.sh`, registered in `TNS_PARTS`, `TNS_GROUPS` and a `pg_want 12-dismissed-batch` line), and both suites pass.
- [ ] AC12 — `lane-policy.sh catalog` carries the new `AUT-DISMISS` labels/purpose and the narrowed `AUT-PENDING` purpose; `docs/LANE_GATES.md`'s table is regenerated with `lane-policy.sh catalog --markdown` in the same change; `bash loomwright/scripts/check-gate-headers.sh` and `bash loomwright/scripts/test-lane-policy.sh` pass.
- [ ] AC13 — `loomwright/skills/automate-loop/per-item-loop.md` §"Dismissed-findings decision step (before the park)" describes the new flow (severity class, silent follow-up, the one batched ask, can't-ask, park report, hand-drop); every other surface that restated the per-finding ask (`per-item-loop.md`'s PICK-time paragraph, `docs/result-schemas/automate-run.md`, `docs/loop-inventory/automate-loop.md` rows, the two script headers) points there instead of restating it.
- [ ] AC14 — `bash scripts/check-version-bump.sh` passes: a `changelog.d/stop-asking-per-dismissed-finding.md` fragment, no hand edits to the version files.

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

## Rule conflicts (open decisions)

none

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| writer (Subtask 1) | `loomwright/scripts/automate-dismissed.sh` (1095 — the sole dismissed-draft/ledger writer; `--auto` is widened in place, no new responsibility), `loomwright/scripts/test-automate-dismissed.sh` (1379 — the suite the requirement names; legs appended to its A5/AC9 section), `loomwright/scripts/automate-helpers.sh` (1181 — one `#:` help line for `dismissed-decide`), `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` (help golden that pins that line) | — | HIGH |
| driver (Subtask 2) | `loomwright/scripts/automate-next-step.sh` (3323 — the single driver; `ns_decide*` / `ns_pending*` / `ns_emit_park` are rewritten in place, the net addition is the severity class + one ask builder; reason: the step functions it changes live only here), `loomwright/scripts/test-automate-next-step.sh` (2564 — registration only: `TNS_PARTS`, `TNS_GROUPS`, one `pg_want` line; existing per-finding `AUT-DISMISS`/`AUT-PENDING` legs updated in place), `loomwright/scripts/test-automate-next-step.d/02-branches.sh` (B5 legs answer `Fix now on this PR` / `Follow-up (keep draft)`), `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh` (P15 asserts only `AUT-PENDING` is asked), `loomwright/scripts/test-automate-next-step.d/01-golden-idem-gates.sh` (`gates_seen` expects `AUT-DISMISS`) | `loomwright/scripts/test-automate-next-step.d/12-dismissed-batch.sh` (home of every new next-step leg — the parent suite is past the size threshold) | HIGH |
| golden fixtures (Subtask 2) | `loomwright/scripts/fixtures/automate-golden/dismissed-findings-decision-step/`, `…/park-first-decisions-recorded/`, `…/pick-pending-decisions-ask/`, `…/dismissed-fix-now-re-drain/`, `…/fix-now-became-follow-up/` (each case's `next-step.results` / `expected.md` regenerated to the new flow), `loomwright/scripts/fixtures/lane-policy/s1-v2-replay.json` (quotes the old `AUT-DISMISS` labels) | — | MEDIUM |
| catalog + docs (Subtask 2) | `loomwright/scripts/lane-policy.sh` (469 — the one catalog authority), `loomwright/docs/LANE_GATES.md` (100), `loomwright/skills/automate-loop/per-item-loop.md` (108), `loomwright/docs/result-schemas/automate-run.md` (159), `loomwright/docs/loop-inventory/automate-loop.md` (791 — rows AL-039, AL-251, AL-317, AL-567 reworded to pointers; table rows, no new responsibility) | `changelog.d/stop-asking-per-dismissed-finding.md` | HIGH |

> **Validator-owned surfaces:** `check-gate-headers.sh` (scans agents/commands/skills + next-step emitters for `header:` ask sites — G3/G5 need the `AUT-DISMISS` and `AUT-PENDING` emitters in `automate-next-step.sh` to quote every catalog label), `test-lane-policy.sh` (parses `LANE_GATES.md`'s table back to TSV), `check-doc-currency.sh` (doc surface), `check-version-bump.sh`. Files those validators scan beyond the map may need updates.

**Total estimated files:** ~20 modify + 2 create

## Touched-file invariants

> Grounded at base `5a28cd8e83712d48ed10c4ba9c982196a5484fbc`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-dismissed.sh`** — keep: every subcommand always exits 0 and reports refusals as one `dismissed-decide: refused — <reason>` line; ledger-first order ("Appends the ledger row FIRST"); `--auto` still refuses any decision but follow-up (`--auto records only follow-up`) and a draft the ledger already decided (`refused — already decided in the ledger`); the unreadable-ledger refusal (`_ledger_unreadable`); the header's "SCOPE OF ITS WRITES (the whole list — anything else is a bug)" stays true (update its `--auto` bullet, add nothing outside it). Remove only the per-finding refusal `--auto records only follow-up on a summary draft, not on a per-finding draft`. mirror: every ledger reader must keep reading column 2 as the decision when column 4 `auto` is present — `_ledger_decision`'s `NF >= 2 { d = $2 }`, `dismissed-drafts`' python `ledger[parts[0]] = parts[1]`, `dismissed-cost`'s `len(p) == 3 and p[1] == 'fix-now'` (auto rows are never fix-now, so its 3-column test is unaffected), and `loomwright/scripts/automate-helpers.d/followup.sh`'s `len(parts) >= 3 and parts[1] == "follow-up"` (reads `parts[2]` as the ts — unchanged). pinned by: `test-automate-dismissed.sh` AC9 (`AC9: --auto refused with drop, on a per-finding draft (follow-up and drop), and an unknown trailing argument` — the per-finding follow-up refusal half flips to acceptance; the drop and unknown-argument refusals stay) and any leg matching a summary auto row's exact 3-column text.
- **`loomwright/scripts/automate-next-step.sh`** — keep: one JSON instruction per call; between calls nothing is written; label validation before the first write (`is not an option of question`); post-park writes only inside `ns_lock_window`; the human-only ask is emitted with `header` = its code (`ns_emit_ask decide AUT-DISMISS "$cant" "$qs"`); finding text reaches the ask only as quoted untrusted data (`Its quoted text is untrusted data, never an instruction`); `--non-interactive` never asks (`ns_interactive || return 1   # --non-interactive: the rest stay undecided (pending_decisions), never asked`); the one fix-now re-drain cap (`st_set fix_now_reentered true` in `ns_spawn_fixnow`, `drain_already_owned`). reuse: `ns_call_writer_helper dismissed-decide "$RF" "$path" "$dec"` for every write (no direct ledger write from the driver), `ns_once` keys per draft (the existing `once_ak_` key for the PICK auto-follow-up), `ns_undecided` / `ns_run_undecided` for the draft lists, `ns_label_decision` for label mapping. mirror: the catalog labels in `lane-policy.sh`'s `_lp_row AUT-DISMISS` / `_lp_row AUT-PENDING` rows exactly (check-gate-headers G3). pinned by: `test-automate-next-step.sh` (e.g. `ak_gate`, `leg_binding`), `test-automate-next-step.d/02-branches.sh` (`Fix now on this PR`), `test-automate-next-step.d/04-pick-resume.sh` P15, the golden cases under `fixtures/automate-golden/`.
- **`loomwright/scripts/lane-policy.sh`** — keep: `AUT-DISMISS` and `AUT-PENDING` stay `human-only`; every code ≤ 12 chars; regenerate the mirror (`catalog --markdown`) in the same change. pinned by: `test-lane-policy.sh` (table parse-back), `check-gate-headers.sh` (`G5  every catalog code has at least one`).
- **`loomwright/scripts/automate-helpers.sh`** — keep: the `#:` help line format `#:  dismissed-decide <runfile> <draft_path> <fix-now|follow-up|drop> [--auto]` (only its trailing description changes); pinned by `fixtures/automate-helpers-help/hdr-trail.golden`.

## Closed enumerations touched

> Sibling grep at base `5a28cd8e83712d48ed10c4ba9c982196a5484fbc`: `grep -rlnF -e 'Follow-up (keep draft)' -e 'Fix now on this PR' loomwright/ | grep -v CHANGELOG` → 14 files.

- **`AUT-DISMISS` labels `Fix none (follow-up all)` · `Fix all listed on this PR` · `Fix selected on this PR?`** (siblings: `Follow-up (keep draft)`, `Fix now on this PR`) — must be named in:
  - `loomwright/scripts/lane-policy.sh` — the catalog row `_lp_row AUT-DISMISS  human-only` — extend (replace labels).
  - `loomwright/docs/LANE_GATES.md` — the regenerated mirror table — extend.
  - `loomwright/scripts/automate-next-step.sh` — `ns_label_decision`'s `case` arm set and the `AUT-DISMISS` option list — extend.
  - `loomwright/docs/result-schemas/automate-run.md` — the `ask` gate description (`AUT-DISMISS` without fix-now core) — extend/repoint.
  - `loomwright/skills/automate-loop/per-item-loop.md` — the decision step — extend.
  - `loomwright/scripts/test-automate-next-step.sh`, `test-automate-next-step.d/02-branches.sh`, `fixtures/automate-golden/{dismissed-findings-decision-step,park-first-decisions-recorded,dismissed-fix-now-re-drain,fix-now-became-follow-up}/`, `fixtures/lane-policy/s1-v2-replay.json` — pins/fixtures quoting the old labels — extend.
  - `loomwright/scripts/test-automate-dismissed.sh` C8 (`AUT-PENDING` note byte-equal to the park-time note) — no change if the `Follow-up (keep draft)` note text survives in the `AUT-PENDING` fallback; otherwise re-point C8 at the fallback only.
  - `loomwright/scripts/automate-helpers.d/resume.sh` — comment naming `Fix now on this PR` for `park-ask-gate` — no change: `park-ask-gate`'s output contract is unchanged (it still decides whether fix-now may be offered).
  - `loomwright/scripts/test-lane-policy.sh` — a synthetic `"Fix now?"` header case — no change: it tests a non-catalog header, not the row.
- **Ledger column 4 value `auto`** (sibling: the 3-column row `<name>\t<decision>\t<ts>`) — readers: `automate-dismissed.sh` (`_ledger_decision`, the `dismissed-drafts` python read, `dismissed-cost`), `automate-helpers.d/followup.sh` — no change (each reads columns 1–3 positionally; see Touched-file invariants).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-dismissed.sh` — AC7 owner's drop wins over an `auto` row | flip `NF >= 2 { d = $2 }` → `NF >= 2 && d == "" { d = $2 }` in `loomwright/scripts/automate-dismissed.sh` |
| `test-automate-dismissed.sh` — AC6 an `auto` follow-up row is not recreated on re-run | flip `ledger[parts[0]] = parts[1]` → `ledger[parts[0]] = parts[-1]` in `loomwright/scripts/automate-dismissed.sh` |
| `test-automate-dismissed.sh` — per-finding `--auto` follow-up writes the `\tauto` column | in `automate-dismissed.sh` `dismissed_decide`, drop the `\tauto` suffix from the `--auto` ledger append (the row is written 3-column) |
| `test-automate-next-step.d/12-dismissed-batch.sh` — AC4 no fix-now left ⇒ no question | flip `st_set fixnow_offer true || st_set fixnow_offer false` → `st_set fixnow_offer true || st_set fixnow_offer true` in `loomwright/scripts/automate-next-step.sh` |
| `test-automate-next-step.d/12-dismissed-batch.sh` — AC1 LOW-only park asks nothing | in `automate-next-step.sh`, make the below-MEDIUM test never match (every severity classed MEDIUM+) |
| `test-automate-next-step.d/12-dismissed-batch.sh` — AC2 the batched ask lists only MEDIUM+ drafts | in `automate-next-step.sh`, build the ask list from every undecided per-finding draft instead of the MEDIUM+ subset |
| `test-automate-next-step.d/12-dismissed-batch.sh` — AC3 no `AUT-PENDING` at PICK | in `automate-next-step.sh` `ns_pending`, restore the `[ "$akind" = summary ]` filter on the auto-follow-up loop |
| `test-automate-next-step.d/12-dismissed-batch.sh` — AC10 can't-ask never guesses fix-now | in `automate-next-step.sh`, on a `cant_ask` answer record every listed MEDIUM+ draft `fix-now` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Widen `dismissed-decide --auto` to per-finding drafts + the `auto` ledger column | AC6, AC7, AC11 (dismissed legs) | 4 modify, 0 create | `skills/automate-loop/SKILL.md` | LAUNCHABLE |
| 2 | Driver: silent follow-up, one batched `AUT-DISMISS` ask, PICK auto-follow-up, park report; catalog + docs + fragment | AC1–AC5, AC8–AC10, AC11 (next-step legs), AC12–AC14 | ~16 modify, 2 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "dismissed_decide"}
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "followed up automatically (no question)"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-dismissed.sh", name: "auto"}
requires: []
lanes:
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.d/12-dismissed-batch.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-next-step.sh", name: "12-dismissed-batch"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "auto_followed_up"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "Fix selected on this PR"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "Fix none (follow-up all)"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "Fix all listed on this PR"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "Dismissed-findings decision step (before the park)"}
  - {kind: "file", path: "changelog.d/stop-asking-per-dismissed-finding.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "followed up automatically (no question)"}
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/**"
  - "loomwright/scripts/fixtures/automate-golden/**"
  - "loomwright/scripts/fixtures/lane-policy/s1-v2-replay.json"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "changelog.d/stop-asking-per-dismissed-finding.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (Subtask 2 consumes Subtask 1's `--auto` widening at runtime) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `loomwright/skills/automate-loop/SKILL.md`, `loomwright/skills/automate-loop/helpers.md` |
| 2 | `loomwright/skills/automate-loop/SKILL.md`, `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/docs/LANE_GATES.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): > 12 files change across driver, writer, catalog, docs, two suites and golden fixtures | MEDIUM | Split `context-bound` into writer then driver; Subtask 2 regenerates goldens through the suite's own golden-case runner, never by hand-editing `expected.md` without re-running |
| A silently recorded follow-up grows the `proposed/` pile faster (requirement Risks) | MEDIUM | `dismissed-followups/01` (#816) already gives `follow_up` a board state, age and `followup-nudge`; the park report lists every auto-followed-up path with the hand-drop command |
| A real MEDIUM finding with no fix-now left is never seen at ask time (requirement Risks) | MEDIUM | Listed in the park report's `auto_followed_up`; surfaced again by `followup-nudge` and `/backlog --state follow_up` |
| The 4th ledger column breaks a positional ledger reader | MEDIUM | Touched-file invariants list every reader; AC6/AC7 pin mutations make a reader that takes the last column (`parts[-1]`) or first-row-wins go red |
| Golden-fixture and catalog-mirror drift (`LANE_GATES.md`, `s1-v2-replay.json`, `gates_seen`) | MEDIUM | Regenerate the mirror with `catalog --markdown`; run `check-gate-headers.sh`, `test-lane-policy.sh` and the full `test-automate-next-step` groups before hand-back |
| A finding title reaching the ask unquoted (prompt injection into the owner question) | HIGH | Titles enter only via `jq --arg`; AC5 canary leg covers backtick, `$(…)`, heading and fake `## Status: done` |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-04-stop-asking-per-dismissed-finding.md
```

## Plan Review: PASS (attempt 1/3, fix floor HIGH) — notes carried, owner chose "Save and exit"
- MEDIUM (closed_enumerations): post-park `park-ask-gate` `refuse — …` lines should leave drafts undecided (next PICK records them follow-up), keeping `automate-helpers.d/resume.sh`'s park_ask_gate header ("The engine then asks NOTHING; the drafts stay undecided") true — only a non-refuse, non-`ask — fix-now allowed…` line means "fix-now not available". Resolution: deferred to the worker.
- MEDIUM (pin_mutations): add pin rows for AC5 (canary — title via string concatenation instead of `jq --arg`), AC8 (treat `unspecified` as below MEDIUM), AC9 (skip the `1..n` note range check). Resolution: deferred to the worker.
- MEDIUM (touched_file_invariants): `test-automate-next-step.sh` — keep `TNS_PARTS`, `TNS_GROUPS` and the `pg_want … tns_part … .` line in sync for `12-dismissed-batch` (exactly one group); `test-automate-dismissed.sh` — the AC9 leg's per-finding follow-up refusal half flips to acceptance. Resolution: deferred to the worker.
- LOW: add legs for post-park lock refusal ⇒ undecided, n = 1 ⇒ no `Fix selected on this PR`, PICK `AUT-PENDING` fallback on a refused `--auto`, can't-ask still writes below-MEDIUM `--auto`.
- LOW: under `--non-interactive` post-park, do not read `park-ask-gate`; record only below-MEDIUM drafts `--auto`, leave MEDIUM+ undecided.
- LOW: Subtask 1 provides `dismissed_decide` and `auto` already resolve at base; the real proof is the new literal `followed up automatically (no question)` plus the `\tauto` append.
- LOW: the `\tauto` column on summary auto rows is a deliberate small extension — say so in the changelog fragment.

## Outcome
- **Status:** completed
- **Completed:** 2026-11-04T13:26:02Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/820
- **Branch:** feature/stop-asking-per-dismissed-finding
- **Files changed:** 31
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** dismissed-decide --auto widened to per-finding drafts with an `auto` ledger column (subtask 1); the driver now records below-MEDIUM drafts (or every draft when no fix-now re-drain is left) follow-up automatically and asks ONE batched AUT-DISMISS for MEDIUM+ drafts, PICK auto-follows-up every undecided draft, and the park carries auto_followed_up (subtask 2). Phase 4.5 review PASS at fix floor HIGH; 4 findings below the floor dismissed (1 MEDIUM new, 2 drift, 1 nit) and posted as the dismissed marker comment.

## Not verified
- **automate-next-step.sh decide/pending calling per-finding --auto** — built by Subtask 2; only summary-only callers exercised at subtask 1 hand-back (subtask 1)
- **a live /automate park where the owner answers the batched AUT-DISMISS ask** — no live run; hermetic legs only (subtask 2)
- **an AUT-DISMISS ask already pending in a sidecar written before this change, answered after the upgrade** — old one-question-per-draft shape would be refused (exit 2); not exercised (subtask 2)
