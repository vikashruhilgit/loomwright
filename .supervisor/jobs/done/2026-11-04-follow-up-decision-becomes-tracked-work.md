# Supervisor Job: A `follow-up` decision on a dismissed finding becomes tracked work, not a silent pile

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (stale linked worktrees from other sessions; unrelated to this item)
- **Source requirement:** .supervisor/requirements/dismissed-followups/01-follow-up-decision-becomes-tracked-work.md
- **Base commit:** e3057ffed1bb1b7ce82829149f66203772eb2ed4

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + awk (+ python3, already a dependency of `automate-dismissed.sh`): the same stack as every sibling helper |
| 2 | Dependency Availability | GO | No new dependency |
| 3 | Architecture Fit | GO | A new `automate-helpers.d/` family file is the dispatcher's documented extension point; the board's closed state set gets one more value; nudges follow the existing startup-arm and PICK-report idioms |
| 4 | Scope vs Supervisor Capability | CAUTION | About 26 files: over the `context-bound` bound (> 12 files), so it is split into 2 dependency-ordered subtasks |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** CAUTION

## Task
**Goal:** Give a `follow-up` decision on a dismissed finding a visible board state with an age, a human-gated verb that bundles follow-up drafts into ONE runnable requirement file, and an advisory nudge, so that follow-up drafts stop piling up silently in `proposed/`.

**Problem Statement:**
The `/automate` owner needs a `follow-up` decision to become tracked work, because today it only records a decision. `dismissed-decide … follow-up` rewrites the draft's `- **Decision:**` line. `dismissed-pending` then stops counting it, `dismissed-drafts` keeps it frozen, intake skips `proposed/`, and `/backlog` lumps it in with undecided drafts and hand-written proposals with no age.
Currently 177 follow-up drafts (369 findings) sit untouched in `.supervisor/requirements/proposed/`, about 9× the pile cleared by hand on 2026-10-01. The option note used to promise "a future queue item" that nothing creates.
Success looks like this: `/backlog --state follow_up` lists every follow-up draft with its age. `followup-bundle … --confirm` turns chosen drafts into one `## Status: pending` requirement file the owner runs with `/automate --folder`. A one-line nudge appears when the oldest follow-up is older than 14 days. The engine stays propose-only: nothing is ever enqueued automatically.

## Acceptance Criteria
- [ ] AC1. Given a file directly under `.supervisor/requirements/proposed/` named `*--dismissed-*.md` whose FIRST `- **Decision:**` value is `follow-up` (the real draft shape: `## Status: proposed` as its first status line, then the `- **Decision:** follow-up` line), when `automate-helpers.sh item-state` or `backlog` reads it, then its state is `follow_up` (a new member of `_BL_STATES`, placed right after `proposed`). Its evidence is `follow-up <N>d — run <run_id>, PR <url>`. `<N>` comes from that draft name's last `follow-up` row `ts` in the run's `<run_id>.dismissed-decisions` ledger beside `.supervisor/automate/<run_id>.md` when the ledger is readable, else from the draft's mtime, labelled `(mtime)`. An existing but unreadable ledger also falls back to mtime and says so (`(mtime — ledger unreadable)`). An undecided draft and a hand-written `proposed/` file still read `proposed`. `totals` still sum to `item_count`, and `--state follow_up` filters as usual. Every follow-up fixture draft in the legs has the real shape above (a `## Status: proposed` first status line), never a status-less stub. Legs in `test-automate-helpers.d/18-backlog.sh` cover: ledger ts, mtime fallback with no ledger, an unreadable ledger (mtime + says so), an undecided draft and a hand-written proposal (`proposed`), and the totals sum.
- [ ] AC2. Given one or more follow-up drafts, when `automate-helpers.sh followup-bundle <draft>... --into <queue-dir>/<NN-slug>.md` runs WITHOUT `--confirm`, then it prints the exact requirement file it would write and writes and removes nothing. With `--confirm` it writes exactly ONE file and removes exactly the named drafts, nothing else. The file has `## Status: pending`, then a provenance quote naming each source draft, its run, its PR and its `Key`/h8. Then `## Findings`, each finding's text `> `-quoted as untrusted data. Then `## Acceptance criteria` (re-verify each finding on `main`, then fix it or record it as not reproducible), `## Depends on` (`none`) and `## Touches` (the union of the drafts' `## Touches`, else `unknown`). It appends one `dismissed: bundled <draft> → <file>` `## Progress` line per draft whose run file `.supervisor/automate/<run_id>.md` exists, and skips silently when it does not. Legs in a new `test-automate-helpers.d/19-followup.sh`.
- [ ] AC3. Given each refusal case, when `followup-bundle` runs (with or without `--confirm`), then it exits non-zero naming the reason and writes and removes NOTHING, one leg per case. The cases: a draft that is not a regular file; a draft not directly under `proposed/`; a draft not named `*--dismissed-*.md`; a draft whose decision is not `follow-up`; an `--into` path outside `.supervisor/requirements/`; an `--into` path inside `proposed/`; an existing target file. Every draft is validated before the first write, so one bad draft among good ones also writes nothing.
- [ ] AC4. Given a follow-up draft removed by `followup-bundle --confirm`, when `dismissed-drafts` is re-run for its run and item over the same sidecars, then the draft is not recreated, and no `draft … keep` row names the absent file. A kept follow-up must be on disk to be reported, so the summary line's counts do not include it. This holds for a per-finding draft AND for a bundled follow-up SUMMARY draft (no `keep summary` row for it, and its entries are not counted in `m`). Legs in `19-followup.sh`, one per draft kind; `test-automate-dismissed.sh` stays green.
- [ ] AC5. Given finding text containing a backtick, `$(…)`, a line starting `#`, and a fake `## Status: done` line, when it is bundled, then every such line in the written file is `> `-prefixed. No new heading, no command substitution and no second `## Status:` line appear in the output. `item-state` on the written file reads `open` (its first `## Status:` is `pending`), never `done`. Leg in `19-followup.sh`.
- [ ] AC6. Given `automate-helpers.sh followup-nudge [--root <checkout>]`, when at least one follow-up draft exists and the oldest is older than `LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS` (default 14; a non-integer reads as 14), then it prints exactly the one line `automate: <n> follow-up drafts, oldest <d>d — /backlog --state follow_up, then followup-bundle`. It prints nothing otherwise (no drafts, all younger, no `proposed/` dir, an unreadable dir). Its exit code is always 0. The interactive PICK (driver step `pending`, beside the pending-decisions ask) and `session-resume.sh` on `startup` each emit that line once when it is non-empty, and never ask or block. `--non-interactive` PICK emits nothing. Legs: the subcommand in `19-followup.sh`, the startup-arm line in `test-session-resume.sh`, the PICK line in a `test-automate-next-step` leg.
- [ ] AC7. Given the AUT-PENDING ask and the park-time decision ask in `automate-next-step.sh`, when either offers **Follow-up (keep draft)**, then its option note names the `follow_up` board state and `followup-bundle`, in the same text at both sites. `test-automate-dismissed.sh` C8's pinned needle (which reads the park-time copy in `ns_decide_next_batch`) is updated in the same change, and a new C8 leg pins the AUT-PENDING copy in `ns_pending_next_batch` by asserting its `Follow-up (keep draft)` note is byte-equal to the park-time one.
- [ ] AC8. Given the doc surfaces, when this ships, then each of these names the `follow_up` state and `followup-bundle`: the `proposed/README.md` template in `scripts/propose-work.sh` and its byte-identical fixture `scripts/fixtures/proposed-readme/README.md`, `commands/propose.md` §Promote, `commands/backlog.md`, and `skills/automate-loop/per-item-loop.md` §"Dismissed-findings decision step (before the park)". `skills/automate-loop/helpers.md` gains a row for `followup-bundle` · `followup-nudge`.
- [ ] AC9. `bash scripts/check-version-bump.sh` passes: a `changelog.d/` fragment folded by `bash scripts/bump-version.sh`, with no hand edits to version files.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| engine (Subtask 1) | `loomwright/scripts/automate-helpers.d/backlog.sh` (726 — the one closed state set and classifier; the follow-up age lookup is NOT written here, it calls followup.sh's helper), `loomwright/scripts/automate-helpers.sh` (1170 — two `case` arms, one `_ah_source followup` block, one `_AH_HELP_SEGMENTS` entry and one carve-out paragraph; the dispatcher is the single registry), `loomwright/scripts/automate-dismissed.sh` (997 — one guard in the existing follow-up `keep` branch; the single owner of `dismissed-drafts`), `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` (418 — the backlog legs' existing home), `loomwright/scripts/test-automate-helpers.sh` (430 — `TAH_PARTS` gains `19-followup`), `loomwright/scripts/test-automate-helpers-dispatch.sh` (273 — `SEGMENTS` gains `followup`), `loomwright/scripts/fixtures/automate-helpers-help/backlog.golden` (3 — mirrors the item-state usage line's closed set) | `loomwright/scripts/automate-helpers.d/followup.sh` (new family: `followup-bundle`, `followup-nudge` and the ONE follow-up-age helper that backlog.sh and followup-nudge both call), `loomwright/scripts/test-automate-helpers.d/19-followup.sh`, `loomwright/scripts/fixtures/automate-helpers-help/followup.golden` | HIGH |
| nudges + option note (Subtask 2) | `loomwright/scripts/automate-next-step.sh` (3300 — both option-note copies live here, and the PICK nudge sits beside the `pending` step's meta-push report, the single PICK driver), `loomwright/scripts/session-resume.sh` (1164 — the single SessionStart emitter; a new `followup_nudge_line` block beside `backlog_nudge_line`), `loomwright/scripts/test-session-resume.sh` (2021 — the startup-arm harness lives here; one leg pair beside the `(bn*)` legs), `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh` (40 — the PICK legs' home; the new `leg_followup_nudge` helper is DEFINED in this part, not in the 2485-line `test-automate-next-step.sh`, which stays unmodified; the part is sourced by the harness, so it can call the harness's existing helpers), `loomwright/scripts/test-automate-dismissed.sh` (1257 — C8 needle only) | — | MEDIUM |
| docs + release (Subtask 2) | `loomwright/scripts/propose-work.sh` (389 — the README template), `loomwright/scripts/fixtures/proposed-readme/README.md` (25), `loomwright/commands/propose.md` (142), `loomwright/commands/backlog.md` (73), `loomwright/skills/automate-loop/per-item-loop.md` (106), `loomwright/skills/automate-loop/helpers.md` (60), `loomwright/docs/prompt-token-budgets.json` (93 — `commands.backlog` has 6 tokens of headroom), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (§"Prompt Token Budgets" mirror row(s) only), `loomwright/capabilities.json` (generated by `build-capabilities.sh`, never hand-edited; only if it changes) | `changelog.d/follow-up-decision-becomes-tracked-work.md` | MEDIUM |
| bump-owned (written by `scripts/bump-version.sh`, Subtask 2) | `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `loomwright/capabilities.json` (`plugin_version`) | — | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` (doc surface), `scripts/check-token-budget.sh` (command and skill budgets, hence the budgets JSON and its ARCHITECTURE_CONTRACTS mirror), `test-automate-helpers-dispatch.sh` (help goldens + `SEGMENTS`), `test-loop-inventory.sh` (a `script:… <sub>` row resolves only to a real `case` arm), and `test-automate-dismissed.sh` B (README template == fixture, byte for byte). Each is in the map above.

**Module layout.** Each new responsibility has one home. `followup-bundle`, `followup-nudge` and the follow-up-age lookup go in the CREATE `automate-helpers.d/followup.sh`. They are not appended to `backlog.sh` (726) or `automate-dismissed.sh` (997), both already over the threshold. backlog.sh calls the family's age helper; the family file is sourced in the same process before dispatch, so the call resolves. The engine legs go in the CREATE `19-followup.sh`. Only two large test files gain legs, each with its reason in the map above: `test-session-resume.sh` (the startup-arm harness) and `test-automate-dismissed.sh` (C8 owns the option-note pins). The PICK leg helper lives in the 40-line `04-pick-resume.sh`, and `test-automate-next-step.sh` (2485) is not modified. The nudge **line text** has ONE home, the `followup-nudge` subcommand: `session-resume.sh` and `automate-next-step.sh` only call it and relay its stdout, and neither rebuilds the line.

**Total estimated files:** 21 modify + 4 create (plus the 4 bump-owned files).

## Touched-file invariants

> Grounded at base `e3057ffed1bb1b7ce82829149f66203772eb2ed4`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.d/backlog.sh`** — keep: the board is READ-ONLY (`READ-ONLY (item-state, backlog): writes only its own mktemp dir (trap-removed); never git`) and the fail-safe region (`set +e   # FAIL-SAFE reads from here: a source that cannot be read degrades, never aborts`); totals are a reduction over the ONE closed set (`Totals are` / `a reduction over the closed set _BL_STATES.`); `--state` validation reads the same set (`unknown state '$state' (one of: $_BL_STATES)`); NO ABSOLUTE PATHS in a printed row (`NO ABSOLUTE PATHS in any printed row: paths are repo-relative.`); field cleaning via `_bl_clean` (tabs and separators never split a field). Placement: every real dismissed draft's first status line is `## Status: proposed`, so it is caught by the `elif [[ "$fs" =~ $_BL_RE_PROPOSED ]]; then` branch (`BL_S=proposed; BL_E="$fs"`) BEFORE the `case "$rel" in .supervisor/requirements/proposed/*) BL_S=proposed; BL_E="file under proposed/" ;; esac` fallback is ever reached. `follow_up` is therefore decided in a NEW `elif` placed AFTER the parked branch and BEFORE the `_BL_RE_PROPOSED` branch (a `proposed/*--dismissed-*.md` file whose first Decision is `follow-up`). Editing only the `case` fallback would leave every real follow-up draft reading `proposed`. The header's PRECEDENCE step 1 text states the same order. A draft carrying a done stamp still reads `done`. Ages: computed in ONE pass over the drafts (one process), never a process per item; no `stat -f`/`stat -c` and no GNU/BSD `date -d`/`-j` flags (macOS-green ≠ CI-green); mirror: the header's `STATES` and `PRECEDENCE` paragraphs are the authority and change in the same edit, and the `#:  item-state` usage line lists the closed set (`done|abandoned|parked|proposed|brief_shipped|…`); pinned by: `test-automate-helpers.d/18-backlog.sh` (`"done abandoned parked proposed brief_shipped merged_unstamped pr_open in_flight conflict open unknown"`), `fixtures/automate-helpers-help/backlog.golden`.
- **`loomwright/scripts/automate-helpers.sh`** — keep: families are listed by name, never globbed (`Listed by name, never globbed: a stray file in automate-helpers.d/ is never sourced.`); each family sits between `# >>> automate-helpers.d/<name>.sh` / `# <<< automate-helpers.d/<name>.sh` markers around ONE `_ah_source <name>` line; the header enumerates every write carve-out (`A sixth carve-out, in THIS process: \`backlog-stamp\``), so `followup-bundle` (which writes ONE requirement file and removes named `proposed/` drafts, never git, never `gh`) is added as the next carve-out paragraph in the same shape; reuse: `progress_append` for the bundled Progress line, the backlog-stamp temp-copy + `mv` write idiom; mirror: `_AH_HELP_SEGMENTS=` gains `followup` at the position matching `SEGMENTS=` in `test-automate-helpers-dispatch.sh` and the `followup.golden` content (`ADDING A SUBCOMMAND? Add its \`#:  \` line beside its implementation and the same line to fixtures/automate-helpers-help/<segment>.golden.`); pinned by: `test-automate-helpers-dispatch.sh` (`A NEW FAMILY also needs its name in the dispatcher's _AH_HELP_SEGMENTS and in SEGMENTS here.`).
- **`loomwright/scripts/automate-dismissed.sh`** — keep: its write scope list (`SCOPE OF ITS WRITES (the whole list — anything else is a bug):`) is unchanged, because this item adds no write here; a `follow-up` ledger row still means never rewritten or recreated (`` `follow-up` ⇒ `` / `kept as is, never rewritten or recreated`); the change is confined to the `elif d == "follow-up":` branch (`emit("keep", str(k), e["sev"] or "-", name, "-", "-", "0")`) and the summary `kept_slot` emission. A follow-up name is reported `keep` only when its draft is on disk (the file's own `on_disk(name)` helper); an absent one emits no row and is not counted; mirror: the header's output paragraph (`then ONE summary line`) is updated to say an absent follow-up draft is not reported; pinned by: `test-automate-dismissed.sh` (the A-section keep/summary-count legs).
- **`loomwright/scripts/automate-next-step.sh`** — keep: the option note is ONE string at two sites, the AUT-PENDING batch in `ns_pending_next_batch` and the park-time `option_notes:` in the decide batch (`"Follow-up (keep draft)": "0 min now (draft kept in proposed/ — nothing is enqueued; promote it by hand)"`), and both copies change identically; the label `Follow-up (keep draft)` is unchanged because `ns_label_decision` maps it (`"Follow-up (keep draft)"|"Keep summary") echo follow-up ;;`); PICK nudge: emitted only in the interactive branch (`ns_interactive || { NEXT=reconcile; return 0; }`), as a report that is never a park and never an ask, mirroring the meta-push report (`ns_once once_pk_meta ns_progress "$(ns_ts) meta-push-failed: $l" || return 1`). It is `ns_once`-guarded so a replayed PICK step emits it once. Its text is `followup-nudge`'s stdout verbatim. A failing or empty `followup-nudge` emits nothing and never changes `NEXT`; the step's one-JSON-instruction-per-call contract holds; pinned by: `test-automate-dismissed.sh` C8 (`"0 min now (draft kept in proposed/ — nothing is enqueued; promote it by hand)", "Drop": "0 min"`), and the `test-automate-next-step.d/*` goldens for the pending step.
- **`loomwright/scripts/session-resume.sh`** — keep: startup emits NOTHING when no block has anything to say (`When no block has anything to say, startup emits NOTHING`); every block is fail-safe and the hook always exits 0; a block is defined above the case and called from `startup_arm_emit` (`DEFINED ABOVE THE CASE (startup_arm_emit calls it).`); reuse: `backlog_nudge_line`'s shape: an OWN `.supervisor/requirements` check (`[ -d ".supervisor/requirements" ] || return 0`), the sibling resolved via `here="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"`, and the background + 0.1 s poll + kill deadline (bash 3.2 has no `timeout`); mirror: the numbered startup-block list in the header (`7. the backlog stamp nudge (backlog_nudge_line, below — startup ONLY)`) gains block 8; pinned by: `test-session-resume.sh` (`(bn1)`/`(bn2)` legs and the startup zero-bytes legs).
- **`loomwright/scripts/propose-work.sh`** + **`loomwright/scripts/fixtures/proposed-readme/README.md`** — keep: the template is static so re-runs stay byte-identical (`# The directory contract. Static content, so re-runs stay byte-identical.`), written through `guarded_write "README.md"`; mirror: the fixture equals the template output byte for byte; pinned by: `test-automate-dismissed.sh` (`ok "B: committed proposed/README.md == propose-work.sh template, byte for byte"`, and `--dismissed-*.md\` drafts for dismissed review findings`, so that sentence stays).
- **`loomwright/scripts/test-automate-helpers.d/18-backlog.sh`** — keep: the totals key-order pin (`jq -r '.totals | keys_unsorted | join(" ")'`) asserts the whole closed set in `_BL_STATES` order, so `follow_up` is inserted after `proposed` in the expected string; existing legs and their `bl_mut_check` mutants stay green; new follow-up fixtures use the real draft shape (`## Status: proposed` first).
- **`loomwright/scripts/test-automate-helpers-dispatch.sh`** — keep: `SEGMENTS=` is the test's own EXPECTED order (`SEGMENTS is the EXPECTED order — the` / `test's own copy, so a reordered _AH_HELP_SEGMENTS in the dispatcher fails check 5.`), so `followup` sits at the same position as in `_AH_HELP_SEGMENTS`, with `incidental` still last; the fixture dir holds exactly the SEGMENTS files (`the fixture dir holds exactly those files`), hence `followup.golden`.
- **`loomwright/scripts/test-automate-dismissed.sh`** — keep: C8's subject is `SUB2="$(dfn "$DRV" ns_decide)$(dfn "$DRV" ns_decide_next_batch)$(dfn "$DRV" ns_decide_record)"`, i.e. the park-time copy; its needle keeps the structure `"<note>", "Drop": "0 min"` with only the note text changed; the new AUT-PENDING equality leg reads `dfn "$DRV" ns_pending_next_batch`; section B's README byte-equality leg is untouched (it changes only through the template + fixture).
- **`loomwright/scripts/test-session-resume.sh`** — keep: the `(bn1)`-`(bn6)` backlog-nudge legs and the startup zero-bytes legs stay green, since a tree with no follow-up drafts must still emit zero bytes on startup; the new follow-up legs build their own `proposed/` drafts with the `LOOMWRIGHT_FOLLOWUP_NOW` seam.
- **`loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh`** — keep: its `LEG_MSG=""` / `if leg_… "$DRIVER"; then ok … else no …; fi` shape; the new helper `leg_followup_nudge` is defined in this part; `test-automate-next-step.sh` is not modified.
- **`loomwright/scripts/test-automate-helpers.sh`** — keep: parts are sourced BY NAME from `TAH_PARTS` (`test part not in TAH_PARTS: test-automate-helpers.d/$tah_p.sh`), so `19-followup` is appended to `TAH_PARTS=` and the file must pass `bash -n`.

## Closed enumerations touched

> Sibling grep at base `e3057ff`: `git grep -nE "merged_unstamped" -- ':!CHANGELOG.md'` (a sibling of the new state `follow_up` in the same closed set as `proposed`) → 52 hits in 16 files; plus `git grep -nE "abandoned\|parked\|proposed"` for the pipe-form list → 2 hits.

- **`follow_up`** (sibling: `proposed`) — must be named in:
  - `loomwright/scripts/automate-helpers.d/backlog.sh` — `_BL_STATES="done abandoned parked proposed brief_shipped …"`, the header `STATES` line, the `PRECEDENCE` step 1 text, and the `#:  item-state` usage closed set `done|abandoned|parked|proposed|…` — extend.
  - `loomwright/scripts/fixtures/automate-helpers-help/backlog.golden` — the same usage line — extend.
  - `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — the totals key-order pin `"done abandoned parked proposed brief_shipped …"` — extend.
  - `loomwright/commands/backlog.md` — the states paragraph (`The states** are one closed set, defined once in the header`) — extend (name `follow_up`, keep the pointer to the header as the authority).
  - `loomwright/scripts/session-resume.sh` (`(.totals.merged_unstamped // 0) + (.totals.conflict // 0)`) — no change: the stamp nudge counts only stamp-needing states; follow-ups get their own block.
  - `loomwright/scripts/build-floor.sh` (`select(.state == "merged_unstamped" or .state == "conflict"`) and `loomwright/docs/result-schemas/floor-projection.md` (`needs_decision`) — no change: `follow_up` is not a stamp decision; the floor copies board totals as-is, and the totals object gains the key additively.
  - `loomwright/scripts/test-build-floor.sh`, `loomwright/scripts/test-session-resume.sh` (`merged_unstamped` legs) — no change: they assert only `merged_unstamped`/`conflict`.
  - `loomwright/scripts/fixtures/backlog-state/README.md` — extend only if a follow-up fixture item is added under `fixtures/backlog-state/tree` (one row per fixture item); no change if the legs build their tree in mktemp.
  - `docs/evidence/pa18a-backlog-board.md`, `docs/evidence/pa25-backlog-board-feeds.md`, `docs/evidence/dismissed-05-resume-host.md` — no change: frozen historical evidence.
  - `loomwright/docs/HOOKS.md`, `loomwright/skills/automate-loop/helpers.md` (hits name `merged_unstamped` in the stamp-nudge description) — no change for the state set; helpers.md gains its new subcommand row (AC8).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-helpers.d/18-backlog.sh` — totals key order incl. `follow_up` | delete `follow_up ` from `_BL_STATES=` in `loomwright/scripts/automate-helpers.d/backlog.sh` |
| `test-automate-helpers.d/18-backlog.sh` — follow-up draft reads `follow_up` | delete the `BL_S=follow_up` assignment line in `loomwright/scripts/automate-helpers.d/backlog.sh` |
| `test-automate-helpers.d/18-backlog.sh` — a real-shape draft (`## Status: proposed` first) reads `follow_up` | move the new `follow_up` `elif` below the `elif [[ "$fs" =~ $_BL_RE_PROPOSED ]]; then` branch in `loomwright/scripts/automate-helpers.d/backlog.sh` (reviewer-applied: not a one-line machine form) |
| `test-automate-helpers.d/18-backlog.sh` — mtime fallback labelled `(mtime)` | flip `(mtime)` → `()` in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/18-backlog.sh` — unreadable ledger says so | flip `ledger unreadable` → `ledger` in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/19-followup.sh` — dry run writes nothing | delete the `--confirm` gate line (the early return before the write) in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/19-followup.sh` — refusal: decision not follow-up | delete the decision-is-`follow-up` refusal line in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/19-followup.sh` — refusal: `--into` inside `proposed/` | delete the `proposed/` target refusal line in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/19-followup.sh` — refusal: existing target | delete the existing-target refusal line in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/19-followup.sh` — injected `## Status: done` stays quoted | delete the line that `> `-prefixes finding text in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-automate-helpers.d/19-followup.sh` — bundled per-finding draft not re-reported | delete the `on_disk(name)` guard added to the follow-up `keep` branch in `loomwright/scripts/automate-dismissed.sh` |
| `test-automate-helpers.d/19-followup.sh` — bundled summary draft not re-reported | delete the on-disk guard added before `emit("keep", "summary", "-", nm, "-", "-", str(kept_slot[nm]))` in `loomwright/scripts/automate-dismissed.sh` |
| `test-automate-helpers.d/19-followup.sh` — nudge silent below the threshold | flip `14` → `0` (the `LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS` default) in `loomwright/scripts/automate-helpers.d/followup.sh` |
| `test-session-resume.sh` — startup prints the follow-up line | delete the `followup_nudge_line` call in `startup_arm_emit` in `loomwright/scripts/session-resume.sh` |
| `test-automate-next-step.d/04-pick-resume.sh` — interactive PICK emits the line once | delete the `followup-nudge` call line in the `pending` step of `loomwright/scripts/automate-next-step.sh` |
| `test-automate-dismissed.sh` — C8 follow-up option note (park-time copy) | flip `followup-bundle` → `followup` in the `option_notes:` of `ns_decide_next_batch` in `loomwright/scripts/automate-next-step.sh` |
| `test-automate-dismissed.sh` — C8 AUT-PENDING note byte-equal to the park-time note | flip `followup-bundle` → `followup` in the AUT-PENDING `option_notes` of `ns_pending_next_batch` in `loomwright/scripts/automate-next-step.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Engine: `follow_up` board state + `followup-bundle` / `followup-nudge` family | AC1, AC2, AC3, AC4, AC5, AC6 (the subcommand) | 7 modify, 3 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Nudge wiring, honest option note, doc surfaces, release | AC6 (PICK + startup wiring), AC7, AC8, AC9 | 14 modify (+4 bump-owned), 1 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1) |

**Subtask 1 notes:** Family `automate-helpers.d/followup.sh` heads with its `#:  ` usage lines, `followup-bundle` then `followup-nudge`, identical in `fixtures/automate-helpers-help/followup.golden` (two-space form). It defines:
- The age helper. In one pass over `<root>/.supervisor/requirements/proposed/*--dismissed-*.md`, it reads each draft's first `- **Decision:**`, its `- **Run:**`/`- **PR:**`, and its ledger `ts`. The ledger lives in the `.supervisor/automate/` dir under the draft's run-id prefix (the text before the first `--`). It falls back to mtime with no ledger, and to mtime marked `ledger unreadable` for an existing unreadable ledger. A tests-only `LOOMWRIGHT_FOLLOWUP_NOW` seam (epoch seconds) is documented under a `TEST SEAMS` paragraph like backlog.sh's. Age = whole days.
- `followup-bundle`: validates ALL inputs before any write. It renders the file to a temp, prints it on a dry run, and under `--confirm` `mv`s it into place, then `rm`s each named draft, then calls `progress_append` per draft whose run file exists. Finding text comes from each draft's fenced finding block(s) (`### Entry N` blocks for a summary draft) and is `> `-prefixed line by line.
- `followup-nudge`: always exits 0.

backlog.sh calls the age helper once per pass and maps its rows into precedence step 1. The dispatcher gets `_ah_source followup` between markers (after the backlog block), case arms `followup-bundle) followup_bundle "$@" ;;` and `followup-nudge) followup_nudge "$@" ;;`, the carve-out paragraph, and `followup` in `_AH_HELP_SEGMENTS` (after `backlog`, before `hdr-lanes`); the same position in `SEGMENTS` of `test-automate-helpers-dispatch.sh`. automate-dismissed.sh: guard BOTH keep emissions with an on-disk check: the per-finding `elif d == "follow-up":` branch (`on_disk(name)`) and the summary `if nm in kept_slot:` emission (`on_disk(nm)`). backlog.sh: the new `follow_up` `elif` goes AFTER the parked branch and BEFORE the `_BL_RE_PROPOSED` branch (see Touched-file invariants). Run `bash loomwright/scripts/test-automate-helpers.sh 18-backlog 19-followup`, `bash loomwright/scripts/test-automate-helpers-dispatch.sh`, `bash loomwright/scripts/test-automate-dismissed.sh`.

**Subtask 2 notes:**
- `automate-next-step.sh`: new option note at BOTH sites, e.g. `0 min now (draft kept in proposed/ as /backlog state follow_up — nothing is enqueued; bundle it into a queue item with followup-bundle)`; same string at both; update C8's needle. PICK: in the `pending` step's interactive path, before the pending-decisions ask, call `bash "$H" followup-nudge --root "$ROOT"` and relay a non-empty line once (`ns_once`). That covers both the case where an ask follows and the case where `NEXT=reconcile` follows. It never parks or asks.
- `session-resume.sh`: block 8 `followup_nudge_line` (startup only), bounded by the backlog-nudge deadline idiom, and called from `startup_arm_emit` beside `backlog`.
- Docs: README template + fixture: add one sentence naming `/backlog --state follow_up` and `followup-bundle` as the promotion path for follow-up drafts. Keep the "NOT an `/automate --folder` target" and "second writer" sentences. Also update `propose.md` §Promote, `backlog.md` (states paragraph + a `follow_up` mention), `per-item-loop.md` §"Dismissed-findings decision step (before the park)", and a `helpers.md` row `followup-bundle` · `followup-nudge`.
- Budgets: re-measure with `bash scripts/check-token-budget.sh`; raise `commands.backlog` (and any other entry that goes over) to measured + ~10% in `loomwright/docs/prompt-token-budgets.json` and its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row.
- Release: write `changelog.d/follow-up-decision-becomes-tracked-work.md` (`<!-- bump: minor -->`, headline `Follow-up decisions become tracked work`) and commit it. Run `bash loomwright/scripts/build-capabilities.sh` and commit `loomwright/capabilities.json` if it changed. Then run `bash scripts/bump-version.sh`, then `bash scripts/check-version-bump.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-loop-inventory.sh`. Pre-push: `bash scripts/ci-local.sh --affected`.

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-helpers.d/followup.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/followup.sh", name: "followup_bundle"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/followup.sh", name: "followup_nudge"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "follow_up"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "followup-bundle)"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "followup-nudge)"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/19-followup.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/followup.golden"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.d/followup.sh"
  - "loomwright/scripts/automate-helpers.d/backlog.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-helpers.d/18-backlog.sh"
  - "loomwright/scripts/test-automate-helpers.d/19-followup.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/backlog.golden"
  - "loomwright/scripts/fixtures/automate-helpers-help/followup.golden"
  - "loomwright/scripts/fixtures/backlog-state/**"
external_requires:
  - "jq, python3 (already dependencies of the automate helpers)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "followup_nudge_line"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "followup-nudge"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/proposed-readme/README.md", name: "followup-bundle"}
  - {kind: "symbol", path: "loomwright/commands/backlog.md", name: "follow_up"}
  - {kind: "symbol", path: "loomwright/commands/propose.md", name: "followup-bundle"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "followup-bundle"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/helpers.md", name: "followup-bundle"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "Follow-up decisions become tracked work"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/followup.sh", name: "followup_nudge"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "followup-nudge)"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "follow_up"}
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/propose-work.sh"
  - "loomwright/scripts/fixtures/proposed-readme/README.md"
  - "loomwright/commands/propose.md"
  - "loomwright/commands/backlog.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/capabilities.json"
  - "changelog.d/follow-up-decision-becomes-tracked-work.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
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
| Subtask 1 | Subtask 2 | none (ordered by `requires`: Subtask 2 calls `followup-nudge` and names `follow_up`) | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md` (§6 "Dismissed-findings decision step"), `skills/unit-testing/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope spans about 26 files (Feasibility (Phase 2.5), check 4 CAUTION) | MEDIUM | Split `context-bound` into an engine subtask and a wiring/docs subtask; each worker re-checks its Touched-file invariants |
| Prior churn on touched paths (Prior churn (postmortem ledger)): `automate-helpers.sh` (33), `per-item-loop.md` (14), `session-resume.sh` (12), `test-automate-dismissed.sh` (12), `automate-next-step.sh` (7); recurring `drain_churn` + `self_heal_churn`, with a `self_heal_miss` recurring | HIGH | Each pin has a mutation row; run each pin red on its mutant before hand-back; run `test-automate-dismissed.sh` (B + C8) and `test-automate-helpers-dispatch.sh` in full, since they pin text this item changes |
| Bundled finding text is untrusted (it came from review comments) | HIGH | `> `-quote every line; never interpolate it into a heading, a filename, a shell command or `printf` format; AC5 legs with backtick, `$(…)`, `#` and fake `## Status: done` |
| `followup-bundle` deletes files | HIGH | Validate every draft and the target before the first write; delete only the named drafts, only after the bundle file is in place; refusal legs per case (AC3) |
| Per-item age lookup on ~180 drafts slows `/backlog` and the SessionStart read | MEDIUM | One pass, one process for all drafts; the startup block keeps the existing deadline idiom |
| macOS/Linux divergence in mtime/date arithmetic | MEDIUM | No `stat -f/-c`, no `date -d/-j`; python3 or `find` only; `LOOMWRIGHT_FOLLOWUP_NOW` seam for deterministic legs |
| A dismissed-drafts `keep` row for a bundled (absent) draft miscounts the summary line | MEDIUM | `on_disk(name)` guard in the follow-up branch (AC4) |
| `commands/backlog.md` has 6 tokens of budget headroom | MEDIUM | Re-baseline `commands.backlog` in `prompt-token-budgets.json` + the ARCHITECTURE_CONTRACTS mirror row in the same change |
| The nudge prints at every startup while the condition holds (no daily marker; the requirement asks for none) | LOW | It is one advisory line and stops once the oldest follow-up is bundled or under the threshold; noted, not built |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-04-follow-up-decision-becomes-tracked-work.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-04T05:12:21Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/816
- **Branch:** feature/follow-up-decision-becomes-tracked-work
- **Files changed:** 33
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** follow_up board state with age, followup-bundle (dry-run default, --confirm writes one pending requirement file, removes named drafts) and followup-nudge, wired into SessionStart and interactive PICK; honest Follow-up option note at both asks; docs + v17.30.0. Phase 4.5: iteration 1 fixed one HIGH (case-variant PROPOSED/ bypass of the inside-proposed/ refusal, de4063e); iteration 2 PASS. 4 findings dismissed below the HIGH floor (see PR marker comment).

## Not verified
- **commands/backlog.md, skills/automate-loop/helpers.md, proposed README template, per-item-loop.md** — Subtask 2 owns the doc surfaces naming follow_up / followup-bundle (subtask 1)
- **session-resume.sh startup arm and automate-next-step.sh PICK nudge** — Subtask 2 wires followup-nudge into them; only the subcommand is tested here (subtask 1)
- **scripts/build-floor.sh floor projection reading totals.follow_up** — not run; the totals key is additive and no test of it was in scope (subtask 1)
- **interactive /automate PICK relaying the stderr nudge to the owner in a live Claude session** — needs a live multi-step /automate session; only the driver's stderr was observed in the test harness (subtask 2)
