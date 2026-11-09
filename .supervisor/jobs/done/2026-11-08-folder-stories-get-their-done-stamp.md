# Supervisor Job: Folder stories outside .supervisor/requirements/ get their done stamp (explicit `--source-requirement` from the driver)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (an unrelated orphan worktree `wt-842` on `fix-842` in another session's scratchpad — not touched by this job)
- **Source requirement:** .supervisor/requirements/2026-11-08-134816-folder-stories-get-their-done-stamp.md
- **Base commit:** 4fbe30deeafcecdd51dc120dd3fa2d3660272ca9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 scripts + markdown prompts + jq; no new stack |
| 2 | Dependency Availability | GO | Existing `brief-pointer.sh`, `closeout.sh`, `automate-next-step.sh` only |
| 3 | Architecture Fit | GO | Closeout already matches `brief_requirement_pointer` against the trusted run-file item (`ptr="${ptr#./}"` then `[ "$ptr" = "$item" ]`); the fix only makes Launch Pad write the pointer. Guarded readers stay untouched |
| 4 | Scope vs Supervisor Capability | GO | ~15 files, mostly short in-place prose edits; one subtask |
| 5 | Hard Blockers | CAUTION | The driver's Launch Pad invocation and `/autonomous`'s "only flag forwarded to Launch Pad" claim are restated in files outside the requirement's `## Touches` (`commands/autonomous.md`, `skills/automate-loop/per-item-loop.md`, `docs/result-schemas/automate-run.md`, `docs/loop-inventory/automate-loop.md`, `docs/loop-inventory/launch-pad-autonomous.md`, `scripts/test-automate-next-step.sh`, `scripts/test-non-interactive-gates-seam.sh`) — asked at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Every story an `/automate --folder <dir>` run merges is stamped `## Status: done` by the normal close-out, wherever the story lives, without loosening the guarded requirement readers.

**Problem Statement:**
An owner running `/automate --folder stories` on stories kept outside `.supervisor/requirements/` needs each merged story stamped done so the next run does not re-queue it.
Currently Launch Pad sets `source_requirement` only for a goal path under `.supervisor/requirements/` (`agents/launch-pad.md` Phase 2 step 0), so a `stories/x.md` item yields a brief with no `- **Source requirement:**` line; `closeout.sh` step 5 then finds no done brief whose pointer equals the item, prints `closeout: skipped — no done brief`, and the item becomes an `AUT-LEFTOVER` that "Clean up now" cannot clear.
Success looks like: the driver (fresh phases) and `/autonomous` (inline phases) hand Launch Pad the item path through a new explicit flag `--source-requirement <path>`; Launch Pad records it as `source_requirement`, so the brief carries the pointer, Plan Reviewer gets the story in `--- SOURCE REQUIREMENT ---`, and closeout stamps the story. A hand-typed goal naming a repo file stays a literal goal; `brief_requirement_path`, `stamp-requirement-status.sh` and `reconcile-jobs.sh` are unchanged and still refuse the outside pointer.

**Design (chosen at planning, per the requirement's first Assumption):**
- New Launch Pad flag `--source-requirement <path>` (driver-facing; documented in both Launch Pad flag tables). When given, Phase 2 step 0 resolves `<path>` relative to the project root and accepts it only when it is relative (no leading `/`), has no `..` segment, ends in `.md` and passes `test -f`; then it `Read`s that file as the requirement source and records `source_requirement` = `<path>` exactly as passed (no rewriting, so it equals the queued item). A value failing any of those checks is not used, nothing is invented, the goal falls back to step 0's existing rule, and Launch Pad notes `source_requirement_unresolved: <path>` as a Phase 1 WARNING. Without the flag, step 0 is byte-for-byte today's rule (a hand-typed goal naming `README.md` or `stories/x.md` stays a literal goal string).
- `automate-next-step.sh` `ns_plan`: `inv="/loomwright:launch-pad goal: $ITEM --source-requirement $ITEM"` for every queued item (an item under `.supervisor/requirements/` resolves to the same `source_requirement` it gets today, so its brief, Plan Reviewer input and stamp are unchanged); `--non-interactive` is still appended after it.
- `/autonomous` PLAN step 1: the inlined Launch Pad always receives `<requirement_path> --source-requirement <requirement_path>` (the requirement path is a requirement file by construction — INIT-written or `--requirement`), plus `--non-interactive` under the fallback as today. The "ONLY flag the loop forwards to Launch Pad" claims become "two forwards".

## Acceptance Criteria

**Happy path**
- [ ] AC1. Given an `/automate --folder <dir>` run (fresh phases) whose queued item is `stories/02-x.md`, when the driver prints the `plan` step's `launch pad phase` spawn, then its `invocation` is `/loomwright:launch-pad goal: stories/02-x.md --source-requirement stories/02-x.md` (plus ` --non-interactive` on a non-interactive run) and its `prompt` begins with that invocation — pinned in the new `scripts/test-automate-next-step.d/15-source-requirement.sh`, and the existing `leg_fresh_walk` pin in `scripts/test-automate-next-step.sh` is updated to the new invocation.
- [ ] AC2. Given Launch Pad invoked with `--source-requirement <path>` naming an existing relative `.md` file outside `.supervisor/requirements/`, when it runs Phase 2 step 0 and Phase 5 step 3a, then `source_requirement` = `<path>` and the saved brief's `## Environment` carries `- **Source requirement:** <path>` exactly as passed — stated in `agents/launch-pad.md` Phase 2 step 0 and Phase 5 step 3a (prose pin in `15-source-requirement.sh`).
- [ ] AC3. Given `/autonomous --single-iteration --requirement <item>` (the `--inline-phases` path), when PLAN step 1 invokes Launch Pad, then `skills/autonomous-loop/SKILL.md` PLAN step 1 says it passes `<requirement_path> --source-requirement <requirement_path>` (prose pin in `15-source-requirement.sh`), and the "only flag forwarded to Launch Pad" sentences in `skills/autonomous-loop/SKILL.md` (§"Launch Pad forward" and EXECUTE step 1's closing paragraph) and `commands/autonomous.md` (the `--cheap` interaction note) name both forwards. The existing `scripts/test-non-interactive-gates-seam.sh` section (g) pins on that wording are updated in the same change: the SKILL `**Launch Pad forward` line keeps its order `` `--non-interactive-fallback` was passed at INIT `` … the flag form … an interactive-run clause … `still exactly four flags`, with the flag form now `` `<requirement_path> --source-requirement <requirement_path> --non-interactive` `` and the `ONLY flag` / `requirement path alone` phrases replaced by the two-forward wording; the `commands/autonomous.md` note check keeps `**No other flag is forwarded to `/supervisor`.**` and `only when `--non-interactive-fallback` was passed at INIT` and its `one other forward is to Launch Pad` phrase is replaced by the new two-forward phrase. The `/supervisor` four-flag checks in that section are untouched.
- [ ] AC4. Given Launch Pad holds a `source_requirement` set by `--source-requirement`, when it reaches Phase 5.5, then Plan Reviewer receives the file verbatim in the `--- SOURCE REQUIREMENT ---` block — the existing Phase 5.5 rule keys on `source_requirement` alone, so `agents/launch-pad.md` Phase 5.5 needs no new condition; the prose pin asserts step 0 names `--source-requirement` as a setter of `source_requirement`.
- [ ] AC5. Given a run whose `## Queue` item is `stories/02-x.md` (a folder outside `.supervisor/requirements/`), a done brief carrying `- **Source requirement:** stories/02-x.md`, and a merged-PR fixture, when `closeout` runs, then it prints `closeout: stamped — stories/02-x.md`, the story reads `## Status: done` with the close-out block (Completed, Brief, PR), and no `no done brief` line is printed — a new leg in `scripts/test-automate-trail.d/02-closeout.sh` (no change to `closeout.sh`).
- [ ] AC6. Given that story now stamped done, when `automate-helpers.sh resolve-folder` resolves the folder again, then the story is not in the Queue it prints — asserted in the same `02-closeout.sh` leg.

**Edge cases**
- [ ] AC7. Given a hand-typed `/launch-pad goal: "stories/02-x.md"` with no `--source-requirement`, when Phase 2 step 0 runs, then the goal stays a literal goal string and no `Source requirement` line is written: `agents/launch-pad.md` Phase 2 step 0 keeps its sentence "is treated as a literal goal string" and its `.supervisor/requirements/`-scoped auto-resolution unchanged, and states that only `--source-requirement` extends `source_requirement` outside that directory (prose pin in `15-source-requirement.sh`).
- [ ] AC8. Given a queued item under `.supervisor/requirements/`, when the driver spawns Launch Pad, then the invocation carries `--source-requirement <item>` and Launch Pad's `source_requirement` is the same path it resolves today (brief line, Plan Reviewer block and closeout stamp unchanged; the existing `02-closeout.sh` legs stay green unmodified).
- [ ] AC9. Given `--source-requirement <path>` where `<path>` fails `test -f`, is absolute, contains a `..` segment, or does not end in `.md`, when Launch Pad resolves it, then it does not invent a file: `source_requirement` comes only from step 0's existing rule applied to the goal, and the Phase 1 report carries a `source_requirement_unresolved: <path>` WARNING (stated in `agents/launch-pad.md` Phase 2 step 0; prose pin).

**Security / guard (must not loosen)**
- [ ] AC10. Given a brief whose pointer is `stories/x.md`, when `reconcile-jobs.sh` and `stamp-requirement-status.sh` read it through `brief_requirement_path`, then each refuses it exactly as `README.md` is refused today (`did not resolve under` / no write; `stories/x.md` byte-identical afterwards) — a new `outside-folder-story` entry added to both guard loops (6a and 6b) in `scripts/test-brief-pointer.sh`, beside the existing `absolute`, `..`, `outside-prefix`, `symlink-final`, `symlink-parent` cases.
- [ ] AC11. `loomwright/scripts/brief-pointer.sh`, `stamp-requirement-status.sh`, `reconcile-jobs.sh` and `automate-trail.d/closeout.sh` are not modified (`git diff --stat origin/main -- <those four>` is empty); `BRIEF_REQUIREMENT_PREFIX=".supervisor/requirements/"` is unchanged.

**Validation**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh` (budget entries raised in `loomwright/docs/prompt-token-budgets.json` and the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror rows for any of `agents/launch-pad.md`, `commands/launch-pad.md`, `commands/autonomous.md`, `skills/supervisor-readiness/`, `skills/autonomous-loop/`, `skills/automate-loop/` that grows past its budget), `check-doc-currency.sh`, `check-prompt-history-refs.sh` (no history reference added to any prompt — the incident story goes to the changelog fragment), `test-citation-drift.sh` and `loomwright/scripts/test-loop-inventory.sh`.
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/folder-stories-get-done-stamp.md` and no hand-edited version file.
- [ ] V3 (running system — owner-run, not a worker gate and not in Subtask 1's criteria subset; the heal loop never treats it as a worker gate). An `/automate --folder stories` run in a sandbox repo (e.g. `vikashruhilgit/studio-sandbox`) on one story outside `.supervisor/requirements/`, merged through `--merge-parked` or by hand, ends with the story stamped `## Status: done` on `main`, no `AUT-LEFTOVER`, and its saved brief showing the `Source requirement` line. Recorded under the PR's `## Not verified` if not run.

## Scope widening
- loomwright/commands/autonomous.md
- loomwright/docs/loop-inventory/automate-loop.md
- loomwright/docs/loop-inventory/launch-pad-autonomous.md
- loomwright/docs/result-schemas/automate-run.md
- loomwright/scripts/test-automate-next-step.sh
- loomwright/scripts/test-non-interactive-gates-seam.sh
- loomwright/skills/automate-loop/per-item-loop.md
- accepted: LP-SCOPE 2026-11-08

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| explicit-source-requirement (Subtask 1) | `loomwright/agents/launch-pad.md` (911 — the single authority for Phase 2 step 0 and the flag table; one paragraph appended to step 0, one clause to Phase 5 step 3a, one flag-table row), `loomwright/commands/launch-pad.md` (245), `loomwright/skills/supervisor-readiness/SKILL.md` (556 — the `Source requirement` template field note, edited in place), `loomwright/skills/autonomous-loop/SKILL.md` (435), `loomwright/commands/autonomous.md` (one sentence of the `--cheap` interaction note, in place), `loomwright/scripts/automate-next-step.sh` (3946 — the single emitter of the Launch Pad spawn; one-line change to `ns_plan`'s `inv=`), `loomwright/scripts/test-automate-next-step.sh` (2772 — the `leg_fresh_walk` invocation pin, plus `15-source-requirement` added to `TNS_PARTS` and one `TNS_GROUPS` group), `loomwright/skills/automate-loop/per-item-loop.md` (123), `loomwright/docs/result-schemas/automate-run.md` (163), `loomwright/docs/loop-inventory/automate-loop.md` (806 — the AL-578 claim column restated in place; its `q:` anchor untouched), `loomwright/scripts/test-automate-trail.d/02-closeout.sh` (344), `loomwright/scripts/test-brief-pointer.sh` (532 — one entry appended to each of the two existing guard loops' lists; no new function), `loomwright/scripts/test-non-interactive-gates-seam.sh` (441 — the two section (g) Launch Pad forward pins, edited in place), `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (1002 — the LP-325, LP-009 and LP-029 claim cells restated in place; `q:` anchors untouched), `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — §"Prompt Token Budgets" mirror rows only) | `loomwright/scripts/test-automate-next-step.d/15-source-requirement.sh`, `changelog.d/folder-stories-get-done-stamp.md` | HIGH |

> **Validator-owned surfaces:** V1 depends on `loomwright/scripts/test-loop-inventory.sh` (its LIVE ANCHORS check fails a `global`/`prose` row whose `q:` anchor no longer occurs in its cited file — AL-578's anchor `**Fresh phases (the default` in `per-item-loop.md` must stay intact; only the parenthesised invocation later in that paragraph changes), `check-token-budget.sh` (headroom at base as `check-token-budget.sh` measures it live — not the stale `measured` fields in the JSON: `launch-pad` agent 925, `commands/launch-pad.md` 490, `commands/autonomous.md` 397, `supervisor-readiness` 409, `autonomous-loop` 1603 tokens), `check-doc-currency.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh` (no bare unpinned `file:N` citation may be added to committed prose).

**Module layout:** new responsibilities and their one home — (1) the `--source-requirement` resolution rule → `agents/launch-pad.md` Phase 2 step 0 (the rule's single authority; `commands/launch-pad.md` restates it in its parameter row and step 0 mirror); (2) the driver hand-over → `ns_plan` in `automate-next-step.sh` (one-line change at the only emitter); (3) the driver/prose pins → CREATE `scripts/test-automate-next-step.d/15-source-requirement.sh` (the parent suite is 2772 lines); (4) the folder-story close-out leg → appended to `scripts/test-automate-trail.d/02-closeout.sh` (344, below the threshold; reuses `closeout_fixture` / `run_closeout` from `00-shared.sh`); (5) the guard case → the existing loops in `scripts/test-brief-pointer.sh`. No helper is copied by 2+ siblings.

**Total estimated files:** 16 modify + 2 create

## Touched-file invariants

> Grounded at base `4fbe30d`. The worker re-checks these before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** — keep: `ns_interactive || inv="$inv --non-interactive"` stays after the `inv=` line, so `--non-interactive` is still the LAST token of the invocation; the prompt `p="$inv — If the requirement file at $ITEM has an ## Outcomes Rubric section, copy it verbatim …"` still begins with `$inv` (the `phase-launch` line and the rubric-preservation check both read it); the `{what: "launch pad phase", session: "fresh", phase: "launch-pad", invocation: $i, …}` object keeps its key set (`07-doc-mirror.sh` pins the `what` values); stdout carries exactly ONE JSON instruction. Only `ns_plan`'s `inv=` line changes — the `/autonomous --single-iteration --requirement $ITEM` emitter (`inv="/autonomous --single-iteration --requirement $ITEM"`) is NOT changed (AC3 lands in `/autonomous`'s own prose). pinned by: `scripts/test-automate-next-step.sh` `leg_fresh_walk` (`.invocation == ("/loomwright:launch-pad goal: " + $i + " --non-interactive")` → updated to the new form).
- **`loomwright/scripts/test-automate-next-step.sh`** — keep: the part map `TNS_PARTS=` / `TNS_GROUPS="1=…` checked by `pg_select` — every part in `TNS_PARTS` sits in exactly one group; the new part joins a group without renumbering existing ones.
- **`loomwright/scripts/test-automate-trail.d/02-closeout.sh`** — reuse: `closeout_fixture`, `run_closeout`, `ok`/`no` from `00-shared.sh`; keep: the global `REQ=".supervisor/requirements/f/01-a.md"` for every existing leg — the new leg sets its own item (e.g. `stories/02-x.md`, with `mkdir -p` of its dir) locally and restores `REQ` afterwards, so no existing leg's fixture changes (see `shared-fixture-default` risk below).
- **`loomwright/scripts/test-brief-pointer.sh`** — keep: `guard_names="absolute .. outside-prefix symlink-final symlink-parent"` is positional with the `for evil in …` lists in BOTH 6a and 6b — the new name is appended to `guard_names` AND the matching path appended at the same position of both lists; the 6b byte-unmodified assertion style (`before_v` / `cat` compare) is reused to prove `stories/x.md` is not written. The new case CREATES `stories/x.md` in each sandbox with NO `## Status` heading (stamp-requirement-status.sh already skips a file carrying one, which would let the `BRIEF_REQUIREMENT_PREFIX=""` mutation pass) and compares it byte for byte before/after; the worker confirms that mutation turns the new case red in both 6a and 6b.
- **`loomwright/agents/launch-pad.md`** — keep: the sentence "**Any other value — including a bare path to an existing repo file such as `README.md` or `docs/spec.md` — is treated as a literal goal string**" and the `.supervisor/requirements/`-scoped auto-resolution verbatim (AC7); the omit-when-empty convention for the `- **Source requirement:**` line ("omit the line entirely — do NOT emit an empty or \"none\" placeholder"); Phase 5.5's `--- SOURCE REQUIREMENT ---` block rule keyed on `source_requirement` alone; Phase 6 action 1a's `scope-outside <source_requirement>` call (a story with no `## Touches` reads `unknown` ⇒ no question).
- **`loomwright/skills/autonomous-loop/SKILL.md`** / **`loomwright/commands/autonomous.md`** — keep: the `/supervisor` forward set "exactly four flags" is unchanged (`**Auto-forwarded flags (the complete `/supervisor` forward set):**` … `exactly four flags to the inlined `/supervisor``, and `still exactly four flags` inside the `**Launch Pad forward` line); only the Launch Pad forward sentences change, and both files say the same thing (the SKILL is the authority, the command note mirrors it). pinned by: `loomwright/scripts/test-non-interactive-gates-seam.sh` section (g) — the `lp_fwd` case pattern (`` *'`--non-interactive-fallback` was passed at INIT'*'`<requirement_path> --non-interactive`'*'ONLY flag'*'an interactive run'*'requirement path alone'* ``) and the `cheap_note` case pattern (`*'one other forward is to Launch Pad'*`) are rewritten to the new wording in the same change; the `still exactly four flags` and `sv_set` checks stay byte-identical.
- **`loomwright/docs/loop-inventory/launch-pad-autonomous.md`** — keep: every row's `q:` anchor (`q: **Launch Pad forward (separate from the `/supervisor` forward set):**`, `q: **Resolve requirement-file input (do FIRST):**`, `q: is a path **under `.supervisor/requirements/`** ending in `.md` that resolves with `test -f``) must remain a substring of its cited file (`test-loop-inventory.sh` LIVE ANCHORS) — so the agent's step 0 sentences those anchors quote stay verbatim; row ids are stable; only the claim cells of LP-325 (names the `--source-requirement` forward), LP-029 and LP-009 (name `--source-requirement` as the second setter) change.

## Closed enumerations touched

> Sibling grep at base `4fbe30d`: `grep -rn -e "--no-auto-gates" loomwright/ | grep -v scripts/test-` → Launch Pad flag lists at `agents/launch-pad.md` (flag table row `` | `--no-auto-gates` | false | ``) and `commands/launch-pad.md` (parameter table row `` | `--no-auto-gates` | No | ``); the other hits are `/automate`'s own `--no-auto-gates` (`commands/automate.md`, `run-file.md`, `automate-run.md`, `resume.md`, `ARCHITECTURE_CONTRACTS.md` §gate tiers, AL-610) — a different command's flag, not a Launch Pad list.

- **`--source-requirement <path>` (new Launch Pad flag)** — must be named in:
  - `loomwright/agents/launch-pad.md` flag table — extend (one row).
  - `loomwright/commands/launch-pad.md` parameter table — extend (one row, documenting it as the driver's / `/autonomous`'s explicit form that a hand-typed goal never sets, per the requirement's first Assumption).
  - `/autonomous` → Launch Pad forward set (`skills/autonomous-loop/SKILL.md` §"Launch Pad forward" + EXECUTE step 1 closing paragraph, `commands/autonomous.md` `--cheap` interaction note) — extend from one forward to two.
  - Restatements of the driver's Launch Pad invocation (`skills/automate-loop/per-item-loop.md` fresh-phases paragraph, `docs/result-schemas/automate-run.md` `spawn` row, `docs/loop-inventory/automate-loop.md` AL-578 claim column) — extend.
- **`source_requirement_unresolved`** (new Phase 1 WARNING token) — stated only in `agents/launch-pad.md` Phase 2 step 0; no schema key (it is not a `LAUNCH_PAD_RESULT` key — that block's key set is closed).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-next-step.sh` `leg_fresh_walk` — invocation pin updated to `/loomwright:launch-pad goal: <item> --source-requirement <item> --non-interactive` | revert `ns_plan`'s `inv=` line in `loomwright/scripts/automate-next-step.sh` to `inv="/loomwright:launch-pad goal: $ITEM"` |
| `15-source-requirement.sh` — AC1 fresh-phase invocation carries `--source-requirement <item>` | revert `ns_plan`'s `inv=` line in `loomwright/scripts/automate-next-step.sh` to `inv="/loomwright:launch-pad goal: $ITEM"` |
| `15-source-requirement.sh` — AC1 non-interactive form ends `--source-requirement <item> --non-interactive` | move the `--source-requirement` append after the `ns_interactive \|\| inv="$inv --non-interactive"` line in `ns_plan` |
| `15-source-requirement.sh` — AC2/AC4 step 0 names `--source-requirement` as a setter of `source_requirement` | delete the new `--source-requirement` paragraph from `loomwright/agents/launch-pad.md` Phase 2 step 0 |
| `15-source-requirement.sh` — AC7 hand-typed goal stays literal | delete the sentence "is treated as a literal goal string" from `agents/launch-pad.md` Phase 2 step 0 |
| `15-source-requirement.sh` — AC3 `/autonomous` PLAN step 1 passes `--source-requirement <requirement_path>` | delete `--source-requirement <requirement_path>` from PLAN step 1 in `loomwright/skills/autonomous-loop/SKILL.md` |
| `15-source-requirement.sh` — AC9 fallback WARNING | delete `source_requirement_unresolved` from `agents/launch-pad.md` Phase 2 step 0 |
| `02-closeout.sh` folder-story leg — AC5 `closeout: stamped — stories/02-x.md` | in the leg's own fixture, drop the `- **Source requirement:**` line from the done brief (the control: closeout must then print `skipped — no done brief`, proving the pointer is what drives the stamp); AND, as the code mutation, temporarily prepend `case "$ptr" in .supervisor/requirements/*) ;; *) continue ;; esac` before the `[ "$ptr" = "$item" ] \|\| continue` match in step 5 of `loomwright/scripts/automate-trail.d/closeout.sh` — the leg must turn red (`closeout.sh` stays unmodified in the diff) |
| `02-closeout.sh` folder-story leg — AC6 re-resolve skips the stamped story | delete the `is_done "$f" && continue` skip in `resolve_folder` in `loomwright/scripts/automate-helpers.d/intake.sh` (a temporary local mutation; the file is not part of this change) |
| `test-non-interactive-gates-seam.sh` (g) — `/autonomous` PLAN step 1 Launch Pad forward (rewritten pin) | delete `--source-requirement <requirement_path>` from the `**Launch Pad forward` sentence in `loomwright/skills/autonomous-loop/SKILL.md` |
| `test-non-interactive-gates-seam.sh` (g) — `commands/autonomous.md` note names both Launch Pad forwards (rewritten pin) | revert the `--cheap` interaction note in `loomwright/commands/autonomous.md` to `one other forward is to Launch Pad` |
| `test-brief-pointer.sh` — AC10 `outside-folder-story` refused by `reconcile-jobs.sh` and not written by `stamp-requirement-status.sh` | set `BRIEF_REQUIREMENT_PREFIX=""` in `loomwright/scripts/brief-pointer.sh` (temporary local mutation) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Explicit `--source-requirement` from the `/automate` driver and `/autonomous` to Launch Pad; folder-story close-out and guard pins | AC1–AC11, V1, V2 | 16 modify, 2 create | `skills/automate-loop/SKILL.md`, `skills/supervisor-readiness/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "--source-requirement"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "source_requirement_unresolved"}
  - {kind: "symbol", path: "loomwright/commands/launch-pad.md", name: "--source-requirement"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "--source-requirement $ITEM"}
  - {kind: "symbol", path: "loomwright/skills/autonomous-loop/SKILL.md", name: "--source-requirement <requirement_path>"}
  - {kind: "symbol", path: "loomwright/scripts/test-brief-pointer.sh", name: "outside-folder-story"}
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.d/15-source-requirement.sh"}
  - {kind: "file", path: "changelog.d/folder-stories-get-done-stamp.md"}
requires: []
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/skills/autonomous-loop/SKILL.md"
  - "loomwright/commands/autonomous.md"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/15-source-requirement.sh"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/scripts/test-automate-trail.d/02-closeout.sh"
  - "loomwright/scripts/test-brief-pointer.sh"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/folder-stories-get-done-stamp.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | — | N/A (single subtask) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md`, `skills/supervisor-readiness/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Seven restating files / pins sit outside the requirement's `## Touches` (Feasibility (Phase 2.5)) | MEDIUM | Put to the owner at Phase 6 (`LP-SCOPE`); each is a one-sentence in-place edit required by the house rule on restated lists |
| A planner widens `BRIEF_REQUIREMENT_PREFIX` or edits `brief_requirement_path` to make the stamp work | HIGH | Out of scope (requirement non-goal); AC10 pins the refusal of `stories/x.md` in both guard loops and AC11 asserts the four guard/closeout scripts are untouched |
| Folder-story items now reach Phase 6 action 1a (`scope-outside`) because `source_requirement` is set; a story WITH a `## Touches` whose brief plans outside it gets an `LP-SCOPE` ask (or `scope_widening_non_interactive` under `--non-interactive`) where today it got none | MEDIUM | Same behaviour `.supervisor/requirements/` items already have; a story without `## Touches` reads `unknown` ⇒ no question. Name it in the changelog fragment |
| `stamp-requirement-status.sh` (SessionStart/SubagentStop) now meets done briefs with a `stories/…` pointer and prints its existing `skip: requirement path outside .supervisor/requirements/` stderr line for each | LOW | Expected and correct (the guard refusing, AC10); it writes nothing. No change to the script |
| Token budgets with thin headroom (`supervisor-readiness` 409, `commands/autonomous.md` 397, `commands/launch-pad.md` 490) | MEDIUM | Edit in place, keep additions to a clause; raise the `prompt-token-budgets.json` entry + `ARCHITECTURE_CONTRACTS.md` mirror row (measured + ~10%) only for a surface that exceeds its budget |
| Overriding the global `REQ` in `00-shared.sh` would disarm the existing closeout legs (shared fixture default) | MEDIUM | The new leg sets its item locally and restores `REQ`; existing legs stay unmodified (Touched-file invariants) |
| AL-578's `q:` anchor drifts if the per-item-loop paragraph opening is reworded | LOW | Edit only the parenthesised invocation; run `test-loop-inventory.sh` |
| `--source-requirement` given a path with spaces | LOW | `/automate` queue items are whitespace-free paths (the driver already passes `$ITEM` unquoted in `goal: $ITEM`); no new quoting behaviour is introduced |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-08-folder-stories-get-their-done-stamp.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-08T18:58:11Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/852
- **Branch:** feature/folder-stories-get-their-done-stamp
- **Files changed:** 16
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Added the Launch Pad flag `--source-requirement <path>`, passed by the /automate driver's `ns_plan` and by /autonomous PLAN step 1, so a story outside .supervisor/requirements/ gets the Source requirement pointer and the normal close-out stamps it; guard scripts (brief-pointer, stamp-requirement-status, reconcile-jobs, closeout.sh) untouched. Phase 4.5: code-reviewer PASS on iteration 1 (consistency_audit, no issues); first CI run red on test-automate-helpers.sh 19-followup.sh "bundle lock removed" race mutant (a file this diff does not touch), rerun of the failed jobs on the same head green.

## Not verified
- **V3 /automate --folder stories in a sandbox repo** — owner-run running-system check; needs a real merge through a sandbox repo (subtask 1)
- **a live Launch Pad session handed --source-requirement** — the flag rule is prose; the pins prove the wording, not that a live Launch Pad follows it (subtask 1)
