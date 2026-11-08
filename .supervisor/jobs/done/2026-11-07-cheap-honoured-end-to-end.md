# Supervisor Job: --cheap is honoured end to end in /automate runs (persisted across --resume, reaches the /review-pr drain)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-11-06-131342/L3 (lane L3 of a `--parallel 2` wave)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/2026-11-05-192936-cheap-honoured-end-to-end.md
- **Base commit:** 3b4bc0f780e4a93a715e40e379685dad9648df39

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2-compatible scripts + markdown prompts + jq; no new stack |
| 2 | Dependency Availability | GO | jq and the existing `runfile-write` helper only |
| 3 | Architecture Fit | GO | Extends the existing flag/persist pattern (`max_tokens`, `auto_gates`) and the review-heal driver's flag state |
| 4 | Scope vs Supervisor Capability | CAUTION | ~24 files; `context-bound` split into 2 ordered subtasks |
| 5 | Hard Blockers | CAUTION | Needs files outside the requirement's `## Touches` (driver of the drain, its schema doc, the automate-loop skill files that restate the "cheap is not persisted" rule, test part files) — recorded in `## Scope widening` for the coordinator re-gate |

**Overall Verdict:** CAUTION

## Task
**Goal:** A run started with `--cheap` stays on the Sonnet cost profile across every `--resume` and through the `/review-pr` drain, until the owner turns it off with `--no-cheap`.

**Problem Statement:**
A plugin owner who starts `/automate --cheap` needs every later spawn of that run — including resumed passes and the review drain — to run on the Sonnet cost profile, because the run is the unit they asked to be cheap.
Currently, `scripts/automate-next-step.sh` sets cheap mode only from its own command line (or, in a lane, from `lane.json`) and never reads it back from the run file, so a bare `/automate --resume` silently reverts to full cost; and the owned drain / fix-now re-drain spawn `/review-pr $PR --until-mergeable --no-auto-postmortem` with no cost flag, while `/review-pr` has no `--cheap` at all. This causes the most spawn-heavy phase (up to 5 drain rounds × 3 heal iterations) and every resumed pass to run at full cost.
Success looks like: `## Run Config` carries `- cheap: true`, every Supervisor/`/autonomous`/drain spawn the driver prints carries `--cheap` while it is set, `/review-pr --cheap` puts `model: "sonnet"` on its reviewer, fix and Earned Fallback Review spawns, and `--no-cheap` turns it off durably.

## Acceptance Criteria

**Part A — `--cheap` survives resume (sequential runs and lanes)**
- [ ] A1. Given a sequential run started with `--cheap`, when the run file is written at start, then `## Run Config` contains `- cheap: true` (the run-file template line, and the driver writes it when it is called with `--cheap` and the line is absent — outside a lane only).
- [ ] A2. Given that run file, when `/automate --resume` runs WITHOUT `--cheap`, then every Supervisor and `/autonomous` spawn invocation the driver prints carries `--cheap` (test in a new `scripts/test-automate-next-step.d/14-cheap-persist.sh` part of `scripts/test-automate-next-step.sh`).
- [ ] A3. Given a run started without `--cheap`, when it resumes, then no spawn carries `--cheap` and `## Run Config` has no `cheap` line.
- [ ] A4. Given a run file with `- cheap: true`, when `/automate --resume --no-cheap` runs, then the driver removes the line, appends one `## Progress` line recording the change (`cheap mode off (--no-cheap)`), no later spawn carries `--cheap`, and a following bare `--resume` still runs at full cost.
- [ ] A5. Given a lane created with `--cheap`, when the coordinator resumes with `--no-cheap`, then `lane-launch … --no-cheap` (any of its launch / `--resume-run` / `--continue` forms) removes `cheap` from that lane's `lane.json` before it spawns, the command it sends carries no `--cheap`, and the in-lane driver's next spawns carry no `--cheap` — **inside a lane `lane.json` is authoritative**: the driver sets cheap mode from `lane.json` `"cheap": true` alone and ignores a command-line `--cheap` (the lane session's own original `/loomwright:automate … --cheap` command, which a `--continue` or answer resume keeps). Tests: beside the existing Z-CH leg in `scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` (lane-launch clears the key; the sent command has no `--cheap`), plus a driver leg in `14-cheap-persist.sh` that runs a lane checkout WITH a command-line `--cheap` against a `lane.json` without `cheap` and asserts no spawn carries `--cheap`.
- [ ] A6. Given both `--cheap` and `--no-cheap` on one driver command, when the driver starts, then it refuses with the named error `cheap_flags_conflict` (exit 2) and writes nothing (run file and sidecar byte-identical).
- [ ] A7. Given a `cheap:` line in `## Run Config` with any value other than `true`, when the driver reads it, then cheap mode is off and it prints exactly one warning line to stderr naming the value (`cheap_value_unrecognised: '<value>'`); it never guesses on, and stdout stays the one JSON instruction.
- [ ] A8. Given `commands/automate.md`, when the change lands, then its `--cheap` and `--resume` rows say the profile is persisted in `## Run Config` and name `--no-cheap` as the off switch, with the "omitting it silently reverts" warning removed — rewritten in place (the command doc is at its token budget; any growth raises its `prompt-token-budgets.json` entry and mirror row in the same change) — and every skill surface that restates "`--cheap` is not persisted" (`skills/automate-loop/SKILL.md` §"Flags", `invariants.md`, `resume.md` step 5, `lanes.md` "Cost profile", `skills/verify-walkthrough/SKILL.md`'s "exactly like `/automate`'s — **not** persisted" comparison, and the stale "there --cheap stays passthrough-only" comment in `scripts/test-automate-next-step.sh`) says the same or points at `commands/automate.md`; and the `docs/loop-inventory/automate-loop.md` rows that anchor on the old text (AL-094, AL-135, AL-160, AL-218, AL-254, AL-530, AL-537 — `test-loop-inventory.sh` fails any `global` row whose `q:` anchor no longer occurs in its cited file) are re-anchored to the rewritten text, their claim columns restated as "persisted in `## Run Config`; `--no-cheap` turns it off", and their test cells moved from `GAP` to the new `14-cheap-persist.sh` legs that now cover them (with the numbered untested-items list below the table kept consistent).

**Part B — the `/review-pr` drain honours `--cheap`**
- [ ] B1. Given an `/automate` run in cheap mode, when the driver prints the owned-drain spawn (inline and fresh-phase forms) and the fix-now re-drain spawn, then each invocation is `/review-pr <pr> --until-mergeable --no-auto-postmortem --cheap` (driver test in `scripts/test-automate-next-step.d/14-cheap-persist.sh`).
- [ ] B2. Given `/review-pr --cheap`, when review-heal spawns its reviewer, fix and Earned Fallback Review tasks, then each spawn carries `model: "sonnet"`: the drain driver (`scripts/review-heal-next-step.sh`) puts `model: "sonnet"` on its `fix worker` and `fallback review` spawn instructions (test in `scripts/test-review-heal-next-step.sh`), the executor prose passes that key on — `skills/review-heal/SKILL.md` §U4 (fix worker) and `skills/review-heal/fallback-review.md`'s "Seat routing" paragraph (the fallback Task) each say: pass the instruction's `model` to the Task call when present, ignore it on the routed `lens-run.sh` path (B6); and the default (non-drain) loop's `Task(loomwright:code-reviewer)` and `Task(general-purpose)` prose in `skills/review-heal/SKILL.md` carries the conditional `model: "sonnet"` (pinned prose checks for both sentences in the same test file).
- [ ] B3. Given an `/automate` run not in cheap mode, when the driver prints the drain spawns, then none carries `--cheap`.
- [ ] B4. Given `/review-pr` without `--cheap`, when it spawns, then no spawn instruction carries a `model` key (the emitted JSON is byte-identical to today's for the existing golden fixtures).
- [ ] B5. Given a lane created with `--cheap`, when the lane reaches its drain, then the drain spawn carries `--cheap`.
- [ ] B6. Given a drain spawn routed through `lens-run.sh` (a Bash shell-out, not a Task spawn), when `--cheap` is on, then the Cost Profiles table marks it N/A the same way it does for routed voters, and nothing errors (the `--cheap` flag is accepted and ignored on the routed path).
- [ ] B7. Given `/review-pr` (and `review-heal-next-step.sh`) with an unknown cost flag (e.g. `--cheaper`), when it parses its arguments, then it refuses with its existing unknown-flag error (`unknown option '<flag>'`, exit 2) rather than ignoring it.
- [ ] B8. Given `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles", when the change lands, then the `--cheap` table gains rows for the drain's code-reviewer review, fix worker and Earned Fallback Review spawns (with the routed-seat N/A note), its intro names `/review-pr --cheap` as a second entry point, and `commands/review-pr.md`'s flag table lists `--cheap`.

**Validation (both parts)**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes, including `loomwright/scripts/test-loop-inventory.sh`, `check-token-budget.sh` (budget entries raised in `loomwright/docs/prompt-token-budgets.json` and the mirror table when `commands/review-pr.md`, `commands/automate.md`, `skills/review-heal/` or `skills/automate-loop/` grow), `check-doc-currency.sh` and `check-prompt-history-refs.sh`.
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/` fragments and no hand-edited version (in this `--parallel` lane the PR carries fragments only and never bumps — `wave-build` folds them).

## Scope widening
- loomwright/scripts/review-heal-next-step.sh
- loomwright/scripts/test-review-heal-next-step.sh
- loomwright/docs/result-schemas/review-heal-next-step.md
- loomwright/agents/review-pr.md
- loomwright/scripts/automate-lanes.d/launch.sh
- loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh
- loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh
- loomwright/skills/automate-loop/SKILL.md
- loomwright/skills/automate-loop/invariants.md
- loomwright/skills/automate-loop/resume.md
- loomwright/skills/automate-loop/lanes.md
- loomwright/docs/loop-inventory/automate-loop.md
- loomwright/skills/verify-walkthrough/SKILL.md
- loomwright/scripts/automate-helpers.sh
- loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden
- accepted: LP-SCOPE 2026-11-07

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
| review-drain (Subtask 1) | `loomwright/scripts/review-heal-next-step.sh` (1192 — the drain's single driver: flag parse, sidecar flag state and spawn emission all live here), `loomwright/scripts/test-review-heal-next-step.sh` (1268 — the driver's single suite; its stub/fixture harness is file-local, so the new legs append to it), `loomwright/docs/result-schemas/review-heal-next-step.md` (110), `loomwright/commands/review-pr.md` (71), `loomwright/agents/review-pr.md` (151), `loomwright/skills/review-heal/SKILL.md` (578 — the default loop's Task prose and the §U4 drain-flag list are edited in place; no new section), `loomwright/skills/review-heal/fallback-review.md` (24), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1063 — rows added to the existing §"Cost Profiles" table, the single source of truth for cost profiles), `loomwright/docs/prompt-token-budgets.json` (93) | `changelog.d/review-drain-honours-cheap.md` | HIGH |
| cheap-persist (Subtask 2) | `loomwright/scripts/automate-next-step.sh` (3788 — the single reader/writer of the run file; the cheap-mode resolution goes in ONE function beside the existing `lane.json` read, reusing `ns_record_orig`'s `runfile-write` idiom), `loomwright/scripts/test-automate-next-step.sh` (2770 — the `TNS_PARTS` / `TNS_GROUPS` map gains the new part, plus the `leg_lane_cheap` header comment is rewritten (A8)), `loomwright/scripts/automate-helpers.sh` (1234 — one `#:` help line for `lane-launch`, edited in place), `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden` (25 — the pinned copy of that help line), `loomwright/scripts/automate-lanes.d/launch.sh` (320), `loomwright/scripts/automate-lanes.sh` (446 — usage header line for `lane-launch` only), `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` (945 — extends the existing Z-CH cheap leg in place), `loomwright/commands/automate.md` (125), `loomwright/skills/automate-loop/run-file.md` (83), `loomwright/docs/result-schemas/automate-run.md` (162), `loomwright/skills/automate-loop/SKILL.md` (343), `loomwright/skills/automate-loop/invariants.md` (18), `loomwright/skills/automate-loop/resume.md` (68), `loomwright/skills/automate-loop/lanes.md` (110), `loomwright/docs/loop-inventory/automate-loop.md` (813 — existing rows re-anchored and restated in place; no new rows), `loomwright/skills/verify-walkthrough/SKILL.md` (463 — one sentence reworded in place), `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1063 — §"Prompt Token Budgets" mirror row only, if `commands/automate.md` grows) | `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh`, `changelog.d/cheap-persists-across-resume.md` | HIGH |

> **Validator-owned surfaces:** acceptance V1 depends on `loomwright/scripts/test-loop-inventory.sh` (its LIVE ANCHORS check fails any `global`/`prose` row in `docs/loop-inventory/*.md` whose `q:` anchor no longer occurs in its cited file — `docs/loop-inventory/automate-loop.md` is in the map for the rows anchored on the `--cheap` text this change rewrites; a worker editing any other quoted line must re-run it), `check-token-budget.sh` (scans every agent, command doc and skill dir — `prompt-token-budgets.json` + the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror are in the map), `check-doc-currency.sh` and `check-prompt-history-refs.sh` (every agent/command/skill file edited here is in their scan set; no history references may be added to prompts — the story goes to the changelog fragments).

**Module layout:** new responsibilities and their one home — (1) cheap-mode resolution for `/automate` → one function in `automate-next-step.sh` next to the existing lane.json read (append reason above); (2) `--cheap` flag state + `model` key for the drain → `review-heal-next-step.sh` (append reason above); (3) `lane.json` cheap off switch → `automate-lanes.d/launch.sh` (`lanes_launch` flag parse + `_lanes_cheap_flag`, the module that already owns the lane cheap read); (4) driver tests for persistence/drain forwarding → CREATE `test-automate-next-step.d/14-cheap-persist.sh` (the parent suite is 2770 lines). No helper is copied by 2+ siblings.

**Total estimated files:** 25 modify + 3 create

## Touched-file invariants

> Grounded at base `3b4bc0f780e4a93a715e40e379685dad9648df39`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** — keep: the unknown-flag refusal `-*) ns_die2 "unknown option '$1'" ;;` (exit 2, nothing written) — `--no-cheap` is a new explicit arm beside `--cheap) CHEAP=1; shift ;;`, and the `cheap_flags_conflict` refusal runs before any write, like every exit-2 usage error; stdout carries exactly ONE JSON instruction, so the A7 warning goes to stderr; the `--merge-parked` entry's "never writes ## Run Config" contract (`never writes ## Run Config`) — the persistence write must not run on that entry; inside a lane `lane.json` is AUTHORITATIVE and the ONLY persisted cheap record (`ns_lane && "$JQ" -e '.cheap == true'`): when `ns_lane` holds, cheap mode is exactly `lane.json` `.cheap == true` — the driver ignores a command-line `--cheap` (the lane session keeps its original command across `--continue`/answer resumes) and neither writes nor reads `## Run Config`'s `cheap` line — so `lane-launch --no-cheap` alone turns a lane off. reuse: the `## Run Config` rewrite idiom of `ns_record_orig()` (awk over `$RF` piped to `runfile-write`), the existing spawn-site form `[ "$CHEAP" = 1 ] && inv="$inv --cheap"` for the three drain sites. mirror: the pinned drain progress line `owned drain started` keeps its current shape (readers of the timeline parse it) — only the spawn `invocation` / `drain_invocation` gain `--cheap`. pinned by: `loomwright/scripts/test-automate-next-step.d/*.sh` (golden instructions for `/review-pr $PR --until-mergeable --no-auto-postmortem` without `--cheap` must stay byte-identical when cheap is off).
- **`loomwright/scripts/review-heal-next-step.sh`** — keep: `-*) rh_die2 "unknown option '$1'" ;;` (B7 relies on it unchanged); the flag arm shape `--no-auto-postmortem) F_NOPM=1; run_flags=1; shift ;;` (a `--cheap` arm follows it, setting `run_flags=1`); the sidecar flag carry (`flag_no_postmortem: $np`) — `flag_cheap` joins that object so a no-flag re-call keeps it; the one-fallback-per-run guard (`fallback_already_spawned`). mirror: the instruction shape documented once in `docs/result-schemas/review-heal-next-step.md` — a new optional `model` key on `spawn` instructions is documented there; spawn emitters `what: "fallback review", agent: "loomwright:code-reviewer"` and `agent: "general-purpose", tools:` gain `model: "sonnet"` only when the flag is set. pinned by: `loomwright/scripts/test-review-heal-next-step.sh` and the golden fixtures under `loomwright/scripts/fixtures/review-heal-golden/` (must stay byte-identical without `--cheap`).
- **`loomwright/scripts/automate-lanes.d/launch.sh`** — keep: `_lanes_cheap_flag()` as the single reader that decides ` --cheap` on every `/loomwright:automate` command it sends; the flag-parse arm style `--continue) cont=1; shift ;;`; the launch lock and owner-command authority (`--no-cheap` never launches anything on its own). reuse: write `lane.json` via jq to a temp file then `mv -f` (atomic; `lane-create` writes it with jq in `create.sh`). pinned by: `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` (`Z-CHa lane-create --cheap records cheap in lane.json` … `Z-CHj`).
- **`loomwright/scripts/automate-lanes.sh`** — keep: the `lane-launch` usage shape `lane-launch <lane_dir> --owner-command '<cmd the owner typed>' [--resume-run <run_id> | --continue]` (add `[--no-cheap]`, nothing else); the dispatcher `case` arm set (`lane-scope-decide) lanes_scope_decide "$@" ;;` style) is unchanged — no new subcommand. mirror: sync the header's cheap-carry sentence (`every \`/loomwright:automate\` command lane-launch sends the lane — launch and --resume-run`) with the new off switch in the same change.
- **`loomwright/docs/loop-inventory/automate-loop.md`** — keep: every `global`/`prose` row's `q:` anchor must be a substring of a line in its cited file (`test-loop-inventory.sh` LIVE ANCHORS); row ids (`AL-094`, `AL-537`, …) are stable — re-anchor and restate, never renumber.
- **`loomwright/skills/automate-loop/lanes.md`** — keep: the closed list of coordinator writes into a lane after launch (`After launch the coordinator never writes into the lane again`) — `lane-launch --no-cheap`'s `lane.json` edit is added to that exception list, not left implicit.
- **`loomwright/scripts/test-automate-next-step.sh`** — keep: the part map `TNS_PARTS=` / `TNS_GROUPS="1=` checked by `pg_select` — every part in `TNS_PARTS` must sit in exactly one group; the existing `leg_lane_cheap` leg keeps passing (only its header comment changes).
- **`loomwright/scripts/test-review-heal-next-step.sh`** — reuse: its own `ok() { echo "  ok: $1"; pass=$((pass + 1)); }` counter idiom, PATH stubs and golden fixture harness (no network, no `gh`); keep: the existing golden fixtures under `scripts/fixtures/review-heal-golden/` unchanged (new `--cheap` legs add their own expectations rather than editing goldens).
- **`loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh`** — reuse: its `check "<id> …" <actual> <expected>` / `has` / `hasnt` assertions and the `STUB_LOG` `STDIN` capture of the sent command; keep: the Z-CH leg ids (`Z-CHa lane-create --cheap records cheap in lane.json` … `Z-CHj`) — new legs continue the series (`Z-CHk`, …) without renumbering.
- **`loomwright/scripts/automate-helpers.sh`** — keep: the `#:` help line stays byte-identical to `scripts/fixtures/automate-helpers-help/hdr-lanes.golden` (update both together); the delegation arm `lane-create|lane-launch|relay-hook|lane-answer|lane-remove) exec bash` is unchanged (flags pass through).
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: §"Cost Profiles" is the single source of truth (`| phase45-fix-task (general-purpose) | inherit | **sonnet** |` row style; the routed-voter N/A wording is the model for B6); "Frontmatter unchanged" — no agent `model:` frontmatter edits.

## Closed enumerations touched

> Sibling grep at base `3b4bc0f`: `grep -rnF -- '--postmortem-churn-threshold' loomwright/ ` (a `/review-pr` drain flag) → hits in `review-heal-next-step.sh` (usage header + `case` arm), `docs/result-schemas/review-heal-next-step.md` (usage line), `skills/review-heal/SKILL.md` (§U4 drain-flag list), `commands/review-pr.md` (flag table), `agents/review-pr.md` (prose), `dispatch-pr-postmortem.sh` + its test + golden `expected.side` fixtures (postmortem dispatcher args), `docs/result-schemas/review-heal-result.md` (field doc).

- **`--cheap` on `/review-pr`** (sibling: `--no-auto-postmortem`) — must be named in:
  - `loomwright/scripts/review-heal-next-step.sh` — usage header + `case` arm set (`--no-auto-postmortem) F_NOPM=1;`) — extend.
  - `loomwright/docs/result-schemas/review-heal-next-step.md` — usage line (`[--no-auto-postmortem] [--postmortem-churn-threshold N]`) — extend.
  - `loomwright/skills/review-heal/SKILL.md` — §U4 drain-flag list (`` `--no-auto-postmortem`, `--postmortem-churn-threshold`) ``) — extend.
  - `loomwright/commands/review-pr.md` — flag table — extend.
  - `loomwright/agents/review-pr.md` — prose mentions only — no change unless it restates the flag list (sync if it does).
  - `dispatch-pr-postmortem.sh`, its test, golden `expected.side` fixtures, `review-heal-result.md` — postmortem args / result fields — no change: the cost flag is not forwarded to the postmortem dispatcher and adds no result field.
- **`--no-cheap` on `/automate`** (sibling: `--cheap`, `grep -rnF -- '--cheap' loomwright/scripts/automate-next-step.sh loomwright/docs/result-schemas/automate-run.md loomwright/commands/automate.md`) — must be named in: `automate-next-step.sh` usage header (`[--notify] [--cheap]`) + `case` arm set — extend; `docs/result-schemas/automate-run.md` driver usage line (`[--notify] [--cheap] [--max-tokens <N>]`) — extend; `commands/automate.md` flag rows — extend.
- **`--no-cheap` on `lane-launch`** (repo-wide grep of its usage: `grep -rn "lane-launch .*--continue" loomwright/`) — must be named in: `automate-lanes.sh` header usage line (`[--resume-run <run_id> | --continue]`) — extend; `automate-lanes.d/launch.sh` flag parse (`--continue) cont=1; shift ;;` arm set) — extend; `automate-helpers.sh` `#:` help line (`lane-launch      <lane_dir> --owner-command '<cmd>' [--resume-run <run_id> | --continue]`) — extend; `scripts/fixtures/automate-helpers-help/hdr-lanes.golden` line 2 (byte-for-byte pin of that help line) — extend in the same change; `skills/automate-loop/lanes.md` lane-launch prose — extend where it lists the forms.
- **`cheap_flags_conflict`** (new named refusal) — documented in `docs/result-schemas/automate-run.md` beside the driver's other named exit-2 refusals — extend.
- **`flag_cheap`** (sidecar key; sibling `flag_no_postmortem`) — `review-heal-next-step.sh` sidecar object — extend.
- **`model`** (optional spawn-instruction key) — `docs/result-schemas/review-heal-next-step.md` `spawn` row — extend.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A2 bare resume carries `--cheap` from `## Run Config` | delete the `## Run Config` `cheap: true` read line in the new cheap-resolution function in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A1 `- cheap: true` written at start | delete the `runfile-write` call of the new cheap-persist write in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A4 `--no-cheap` removes the line and a later bare resume is full cost | delete the line-removal branch for `--no-cheap` in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A3 a run without `--cheap` gets no `--cheap` spawn and no `cheap` line | flip the `## Run Config` cheap read so it always sets `CHEAP=1` in the new cheap-resolution function in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — B3 a non-cheap run's drain spawns carry no `--cheap` | make the `--cheap` append unconditional (drop its `[ "$CHEAP" = 1 ] &&` guard) at the inline owned-drain site in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A6 `cheap_flags_conflict` | delete the `cheap_flags_conflict` refusal line in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A7 non-`true` value is off + one warning | flip `true` → `*` in the cheap-value comparison in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — B1 owned drain + fix-now re-drain carry `--cheap` | delete the `--cheap` append at the fix-now re-drain `drain_invocation` site in `loomwright/scripts/automate-next-step.sh` (and, as a second row run, at the inline owned-drain site) |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — B5 lane drain spawn carries `--cheap` from `lane.json` | delete `ns_lane && "$JQ" -e '.cheap == true'` read line in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh` — A5 lane ignores a command-line `--cheap` when `lane.json` lacks the key | delete the in-lane override that clears a command-line `CHEAP=1` in the new cheap-resolution function in `loomwright/scripts/automate-next-step.sh` |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` — A5 `lane-launch --no-cheap` clears `lane.json` cheap | delete the jq `del(.cheap)` write in `lanes_launch` in `loomwright/scripts/automate-lanes.d/launch.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — B2 fix worker + fallback spawns carry `model: "sonnet"` | delete the `model: "sonnet"` addition on the `fix worker` emitter in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — B2 fallback review spawn carries `model: "sonnet"` | delete the `model: "sonnet"` addition on the `fallback review` emitter in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — B2 flag survives a no-flag re-call | delete `flag_cheap` from the sidecar carry object in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — B2 default-loop prose pin | delete the `model: "sonnet"` conditional line from the default loop's `Task(` block in `loomwright/skills/review-heal/SKILL.md` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `/review-pr --cheap`: drain driver flag + `model: "sonnet"` spawns, review-heal prose, Cost Profiles rows | B2, B4, B6, B7, B8, V1, V2 | 9 modify, 1 create | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `/automate` cheap mode persisted in `## Run Config`, `--no-cheap` (sequential + lanes), drain spawns forward `--cheap`, docs + loop inventory | A1–A8, B1, B3, B5, V1, V2 | 18 modify, 2 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "--cheap)"}
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "flag_cheap"}
  - {kind: "symbol", path: "loomwright/commands/review-pr.md", name: "--cheap"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "/review-pr --cheap"}
  - {kind: "file", path: "changelog.d/review-drain-honours-cheap.md"}
requires: []
lanes:
  - "loomwright/scripts/review-heal-next-step.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/docs/result-schemas/review-heal-next-step.md"
  - "loomwright/commands/review-pr.md"
  - "loomwright/agents/review-pr.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/skills/review-heal/fallback-review.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "changelog.d/review-drain-honours-cheap.md"
external_requires:
  - "Claude Code Task tool `model` parameter (spawn-time override, as the existing --cheap profile uses)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "--no-cheap)"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "cheap_flags_conflict"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/launch.sh", name: "--no-cheap"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/run-file.md", name: "- cheap:"}
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh"}
  - {kind: "file", path: "changelog.d/cheap-persists-across-resume.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "--cheap)"}
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/14-cheap-persist.sh"
  - "loomwright/scripts/automate-lanes.d/launch.sh"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh"
  - "loomwright/commands/automate.md"
  - "loomwright/skills/automate-loop/run-file.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/automate-loop/invariants.md"
  - "loomwright/skills/automate-loop/resume.md"
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/skills/verify-walkthrough/SKILL.md"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/cheap-persists-across-resume.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```
(Subtask 2 makes the `/automate` driver print `/review-pr … --cheap`, which only works once Subtask 1's `/review-pr` accepts the flag; it also edits `prompt-token-budgets.json` / `ARCHITECTURE_CONTRACTS.md` after Subtask 1 does — a legal sequential share.)

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | YES (Subtask 2 requires Subtask 1) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope: ~24 files, several outside the requirement's Touches (Feasibility (Phase 2.5)) | MEDIUM | Split `context-bound` into 2 ordered subtasks; outside-Touches paths recorded in `## Scope widening` for the coordinator's re-gate |
| `commands/automate.md` has ~2 tokens of budget headroom (Feasibility (Phase 2.5)) | MEDIUM | Rewrite the `--cheap` / `--resume` rows in place (net shrink by dropping the warning); if it still grows, raise its `prompt-token-budgets.json` entry and the `ARCHITECTURE_CONTRACTS.md` mirror row in the same change |
| A lane's own run file also persisting `cheap: true` would make `lane-launch --no-cheap` ineffective | HIGH | Inside a lane the driver neither writes nor reads `## Run Config` `cheap` — `lane.json` stays the lane's only record (Touched-file invariants) |
| A lane session keeps its original `/loomwright:automate … --cheap` command across `--continue` / answer resumes, so a command-line `--cheap` would defeat a cleared `lane.json` | HIGH | Inside a lane `lane.json` is authoritative and the driver ignores a command-line `--cheap` (A5, Touched-file invariants, pinned by a 14-cheap-persist leg run WITH `--cheap` against a cleared `lane.json`) |
| A lane already running (not relaunched) when the coordinator resumes with `--no-cheap` keeps its profile until its `lane.json` is cleared | MEDIUM | `lanes.md` says the coordinator passes `--no-cheap` on every `lane-launch` (launch, `--resume-run`, `--continue`) of that resumed session; the in-lane driver re-reads `lane.json` each call, so the cleared key takes effect at the lane's next driver call. State the limit (a lane the coordinator does not relaunch in that session keeps the profile) in `lanes.md` |
| Restated "cheap is not persisted" prose drifts (SKILL.md §Flags, invariants.md, resume.md, lanes.md, automate-run.md) | MEDIUM | House rule on restated lists: update each in the same change or replace with a pointer to `commands/automate.md` / `run-file.md`; after the change, `grep -rn "not persisted\|re-pass it\|Passthrough-only" loomwright/` must show no stale claim about `--cheap` |
| Golden drain fixtures change when `--cheap` is absent | MEDIUM | Add the `model` key and `--cheap` suffix only when the flag/mode is on; existing goldens must stay byte-identical (B4, B3) |
| Sonnet drain reviewer finds issues differently than the session model | LOW | `--cheap` is opt-in; the default path is unchanged |
| Changelog fragment folded by a later bump | LOW | This is a `--parallel` lane: fragments only, no bump; `provides` names the fragments, which survive the subtask |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-07-cheap-honoured-end-to-end.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-07T18:33:15Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/845
- **Branch:** feature/cheap-honoured-end-to-end
- **Files changed:** 31
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** /review-pr --cheap (sidecar flag_cheap, model sonnet on drain fix/fallback spawns) and /automate cheap mode persisted in ## Run Config with --no-cheap (sequential + lanes), drain spawns carry --cheap. Phase 4.5 ran 3 review→fix rounds (fc7bf81, 41f0a85, 08b0a5d); the final fix (cheap write moved under the held run lock) was not re-reviewed — escalated for a human look. CI ci check was pending at the last read.

## Not verified
- **live /review-pr --cheap session spawning a Task with model sonnet** — no live PR drain run; the Task model parameter is applied by the main thread reading the instruction and prose, which are what the tests pin (subtask 1)
- **interactive /automate --resume AUT-RESUME Continue with --no-cheap** — needs a multi-step resume flow with PICK/RECONCILE; modelled in 14-cheap-persist by a sidecar wipe (subtask 2)
- **--parallel coordinator resumed without --cheap creating new lanes** — unchanged behaviour, no driver path; prose-only in lanes.md (subtask 2)
