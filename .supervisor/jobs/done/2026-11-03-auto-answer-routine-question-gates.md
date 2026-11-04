# Supervisor Job: Auto-answer routine question gates in every run, and show the owner what was auto-answered

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (orphaned/prunable worktrees under `.claude/worktrees/` and one prunable scratch worktree — unrelated to this item)
- **Source requirement:** .supervisor/requirements/2026-11-03-180008-auto-answer-routine-question-gates.md
- **Base commit:** 8275b2ca5356f0c55fec05e0f127a221df897944

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe scripts + jq + markdown prose, the stack every touched file already uses |
| 2 | Dependency Availability | GO | No new dependency; jq, python3 (check-gate-headers) and git are already required |
| 3 | Architecture Fit | CAUTION | The catalog (`lane-policy.sh catalog`) is the one authority and `queue-confirm` is a working deterministic precedent, but `/automate` phase sessions route every ask to the coordinator through the relay (`_lanes_relay_phase`: "No policy lookup"), so the answer seat must be a helper the prose/driver calls BEFORE asking, not the relay |
| 4 | Scope vs Supervisor Capability | CAUTION | ~24 files touched (> 12) — needs the `context-bound` split |
| 5 | Hard Blockers | CAUTION | `classify-risk.sh` classifies only a git diff; Launch Pad and the Queue have no diff. Owner decision (LP-CLARIFY, this session): add a read-only `--paths` mode that runs its path + trusted-root classes over the brief's File Impact Map paths — the literal trigger, accepted knowing most plugin-self briefs will still escalate |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a deterministic `auto` tier to the gate catalog so that `LP-SAVE`, `LP-SAVE-NOTE`, `AUT-QUEUE` and `AUT-RESUME` apply their catalog-designated answer without asking — in sequential `/automate` runs, inline `/launch-pad`, phase sessions and lanes — unless a deterministic escalation trigger fires, with an off switch and one end-of-run / park list of every auto-answer.

**Problem Statement:**
The plugin owner running `/automate`, `/launch-pad` and `/supervisor` needs routine gates whose recommended answer is accepted essentially every time to stop costing a relay round trip and a turn, because the evidence (2,825 ask calls) shows LP-SAVE-NOTE, LP-SAVE, AUT-QUEUE and AUT-RESUME took the default 100% of the time.
Currently, pre-answering exists only inside `--parallel` lanes, only for `allowed` codes with a stamped project or owner-set wave policy, and `LP-SAVE-NOTE` (22% of all catalog-coded questions) is `human-only`. This causes every sequential run and every inline Launch Pad to stop on questions with no decision in them.
Success looks like: those four gates are answered by a deterministic helper with one `## Progress` record each, escalate to the owner on the requirement's four triggers, can be switched off per run (kept across `--resume`), and are listed in one block at every park and at the run's end.

**Owner decision carried (requirement §"Owner decision (recorded)"):** moving `LP-SAVE-NOTE` out of `human-only` is a deliberate policy change. The docs state the new tier and its triggers; they never quietly reword the old tier.

**Design (binding for the worker — choices the requirement left to the implementer, made here so every AC is testable):**
- **D1 — tier value.** `lane-policy.sh catalog`'s `policy` column takes a third value, `auto`. Lane-policy answerability (wave-set / resolve / decide) is decided by ONE helper in `lane-policy.sh`, `_lp_policy_answerable`: `allowed` codes, and `auto` codes that were `allowed` at the base commit (`AUT-QUEUE`, `AUT-RESUME`, `LP-SAVE`), so a stamped project or wave policy that answers them today keeps working byte-identically. `LP-SAVE-NOTE` was never policy-answerable and stays refused by wave-set / resolve / decide: the owner decision moves it to the deterministic `auto` tier only, never to policy, so an escalated `LP-SAVE-NOTE` ask (severity, high_risk) can never be answered by a policy in a lane. The exemption is ONE constant beside the helper (`_LP_POLICY_EXEMPT`, holding `LP-SAVE-NOTE`) — never restated in the three call sites. `human-only` stays never-answered by anything.
- **D2 — the auto label lives in the catalog row.** The label an `auto` gate applies is marked in the row's labels field with a trailing `!` (the same idiom as the optional `?` marker; the `!` is not part of the label): `Save and exit!` for `LP-SAVE` and `LP-SAVE-NOTE`, `Process!` for `AUT-QUEUE`, `Continue!` for `AUT-RESUME`. Exactly one `!` per `auto` row, none on any other row. Every reader of the raw catalog labels that compares them to an ask's options strips it like `?`: `_lp_catalog_json` (both `labels` and `core`), `check-gate-headers.sh`, `gate-auto.sh`, and the golden test `test-automate-next-step.d/01-golden-idem-gates.sh` (`CATJ=`); the full reader list is in `## Closed enumerations touched`; `catalog --markdown` keeps it raw exactly as it keeps `?`, so `docs/LANE_GATES.md` shows which label is auto and test-lane-policy.sh (cat7)'s table-to-TSV round trip stays byte-exact. No other surface restates the `auto` set as a list — each points at the catalog.
- **D3 — the answer seat is a deterministic helper, `loomwright/scripts/gate-auto.sh` (CREATE).** Subcommands:
  - `gate-auto.sh decide <code> [--offered <label>]… [--recommended <label>] [--max-severity BLOCKING|HIGH|MEDIUM|LOW|NONE] [--risk-paths <file>] [--risk-diff <base> <head>] [--destructive] [--runfile <path>] [--off] [--root <dir>]` — prints exactly ONE line: `answer <label>` or `ask <trigger>`. It reads the code's row from `lane-policy.sh catalog` (never a second copy). Fail toward asking: any error, missing jq, unknown code, unreadable input ⇒ `ask <reason>`. Always exit 0 except a usage error (exit 2, still printing `ask usage`).
  - `gate-auto.sh record <runfile> <code> <label> <reason> [--item <item>]` — appends ONE `## Progress` line via `automate-helpers.sh progress-append`: `auto-answered <code>: <label> — <reason>[ (item <item>)]`; for an escalated ask, `auto-escalated <code>: <trigger>[ (item <item>)]`. Fail-SAFE (exit 0; a failed append never blocks the run). With no run file resolvable (standalone `/launch-pad`), it prints the same line on stdout for the phase output instead.
  - `gate-auto.sh list <runfile>` — prints the end-of-run / park block: a heading line `Auto-answered gates (<n>):` and one row per `auto-answered` Progress line (code, label, reason, item); nothing at all when there are none. Read-only, exit 0.
  - Run-file resolution: `--runfile`, else `$LOOMWRIGHT_PHASE_DIR` (`<checkout>/.supervisor/automate/<run_id>.phase/<phase>` ⇒ `<checkout>/.supervisor/automate/<run_id>.md`), else none.
- **D4 — escalation triggers (any one ⇒ `ask <trigger>`; every one a deterministic read, no LLM):** `off` (off switch, D5) · `not_auto` (the code's policy is not `auto` — `human-only` and `allowed` codes are never auto-answered by this helper) · `severity` (`--max-severity` is MEDIUM or higher, or is missing/unparseable for `LP-SAVE-NOTE`) · `high_risk` (`classify-risk.sh` returns `high_risk: true` OR `null` for the given paths or diff — `null` fails toward asking) · `destructive` (`--destructive`: the answer would delete, discard, merge or push) · `label` (the offered labels, `(Recommended)` stripped, are not exactly the catalog row's labels or its core set; or `--recommended` is given and is not the catalog's `!` label; or no `!` label exists).
- **D5 — off switch.** `/automate --no-auto-gates` and `/launch-pad --no-auto-gates` flags, and `.supervisor/config.json` `{"auto_gates": false}` (read with `has("auto_gates")`, never `// empty` — a `false` must not collapse). `/automate` records `- auto_gates: off` in `## Run Config` when either source turns it off (absent otherwise, like `max_tokens`), so a bare `--resume` keeps it; `lane-create` carries it into `lane.json` as `auto_gates: false`. `gate-auto.sh decide` honours `--off`, the run file's `## Run Config` line, `lane.json`, and the config key.
- **D6 — classify-risk paths mode (owner decision, this session).** `classify-risk.sh --paths <file> [--root <dir>]` (one repo-relative path per line) runs the path and trusted-root classes (a), (b), trusted-root and the project `.agent/risk.json` `paths[]` (read at `HEAD`) over the listed paths, and emits the same JSON object shape with `source: "classify-risk.sh"` (content and size classes are not applicable and emit no reason). Read-only, always exit 0. The existing `<base_ref> <head_ref>` mode and its output are byte-identical, so `gate-eval`'s sixth condition is unchanged and still has no override.
- **D8 — AUT-RESUME is decided in the driver, applied by the caller that can ask.** The driver cannot tell whether its caller can ask (its only signal is `--non-interactive`; a subagent or headless caller answers `{"cant_ask": true}`). So `automate-next-step.sh` never auto-continues on its own: it still emits the `AUT-RESUME` ask instruction, adding one field `auto_answer` (`"Continue"` when `gate-auto.sh decide AUT-RESUME` printed `answer Continue`, else `null`, plus `auto_reason`). The coordinator prose (`skills/automate-loop/resume.md`) applies it ONLY when it could have asked: it runs `gate-auto.sh record`, then answers `--result {"answers": ["Continue"]}` without calling the ask tool. A caller that cannot ask still answers `{"cant_ask": true}`, which still reaches `ns_resume_stop` (`resume_requires_flag_non_interactive`) exactly as today.
- **D7 — can't-ask unchanged.** The helper is consulted ONLY on a path that would otherwise ask (interactive main thread, or an HR phase session whose relay defers). Every `--non-interactive` / subagent branch keeps its named status (`saved_on_pass_non_interactive`, `resume_requires_flag_non_interactive`, …) exactly as today.

## Acceptance Criteria

**Happy path**
- [ ] AC1. Given an interactive sequential `/automate` run and a Plan Review PASS with notes (no issue MEDIUM or higher, `classify-risk.sh --paths` not high-risk), when Launch Pad reaches Phase 6, then no question is asked, the brief is saved with the PASS's issues and notes carried exactly as a human `Save and exit` carries them, and `## Progress` gains one line `auto-answered LP-SAVE-NOTE: Save and exit — <reason>`.
- [ ] AC2. Given a folder or prompt source, when the Queue is resolved and `queue-confirm` prints `ask`, then `AUT-QUEUE` is auto-answered `Process` with one `auto-answered AUT-QUEUE: Process — <reason>` line; the existing `queue-confirm` skip lines (`skipped AUT-QUEUE: <reason>`) are unchanged for the cases they already cover.
- [ ] AC3. Given exactly one incomplete run, no `--run` and no rebuilt `## Current`, when `/automate` starts interactively, then the driver's `AUT-RESUME` ask instruction carries `auto_answer: "Continue"`, the coordinator answers it without calling the ask tool, the run continues (`rebuild`), and `## Progress` gains one `auto-answered AUT-RESUME: Continue — <reason>` line. Given two or more incomplete runs, or a rebuilt `## Current`, then `auto_answer` is `null` and it asks `AUT-RESUME` as before. Given one run and a `{"cant_ask": true}` answer, then the driver still stops `resume_requires_flag_non_interactive` with nothing written past the start steps.
- [ ] AC4. Given a finished or parked run with at least one auto-answer, when the run ends or parks, then one block printed by `gate-auto.sh list <runfile>` lists every auto-answer of the run (code, label, reason, item); a run with none prints no block.

**Escalation and edge cases**
- [ ] AC5. Given a Plan Review PASS that carries a MEDIUM-or-higher issue, when Phase 6 runs, then `LP-SAVE-NOTE` is asked and `## Progress` gains `auto-escalated LP-SAVE-NOTE: severity`.
- [ ] AC6. Given `classify-risk.sh` reports high-risk (or `null`), then the gate asks and the record names `high_risk` — per gate: `LP-SAVE` / `LP-SAVE-NOTE` read `classify-risk.sh --paths` over the brief's File Impact Map paths; `AUT-RESUME` reads the refs diff of the run's open PR when one exists (none ⇒ no risk read); `AUT-QUEUE` takes no risk read, because no item is picked yet — an honest limit stated in `docs/LANE_GATES.md`.
- [ ] AC7. Given the off switch is set (flag or config key), when any gate fires, then it asks exactly as before this item, `## Run Config` carries `- auto_gates: off`, and a bare `--resume` keeps the setting.
- [ ] AC8. Given a question whose labels, with `(Recommended)` stripped, are not exactly the catalog row's labels (or its core set), or a `--recommended` label that is not the catalog's `!` label, or a row with no `!` label, then `gate-auto.sh decide` prints `ask label`. The tier fails toward asking, never toward an answer.
- [ ] AC9. Given a `human-only` code, then nothing in this item answers it, in a lane or out of one (`gate-auto.sh decide` prints `ask not_auto`; `decide`/`resolve`/`wave-set` still refuse it).
- [ ] AC10. Given `classify-risk.sh <base_ref> <head_ref>` on any diff, then its output is byte-identical to the base commit's; given `classify-risk.sh --paths <file>` listing a path under `agents/` or matching `*auth*`, then `high_risk` is `true` with a `path:` reason; a list of only low-risk paths gives `false`; an unreadable list gives `null`.

**Can't-ask and lanes**
- [ ] AC11. Every gate's can't-ask branch is unchanged. An `auto` answer applies only where the run could have asked; non-interactive and subagent runs keep their named fail-closed statuses (`docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory").
- [ ] AC12. Inside a lane, an `auto` gate is answered the same way (the lane's engine calls `gate-auto.sh decide` before asking), and the existing policy path (`lane-policy.sh resolve` / `decide` / `wave-set`) behaves byte-identically for every code that was `allowed` at the base commit, including `AUT-QUEUE`, `AUT-RESUME` and `LP-SAVE` after they become `auto`; `LP-SAVE-NOTE` stays refused by all three (D1).

**Checks**
- [ ] AC13. `lane-policy.sh catalog` carries the new tier and the `!` marker; `docs/LANE_GATES.md` is regenerated from it in the same change; `bash loomwright/scripts/check-gate-headers.sh` exits 0. No other surface restates the `auto` set as a list; each points to the catalog.
- [ ] AC14. `scripts/test-lane-policy.sh` has legs for: the `auto` tier (each of the four codes answered), each escalation trigger (`off`, `not_auto`, `severity`, `high_risk`, `destructive`, `label`), the off switch from each source, a label mismatch, a `human-only` code that stays human, the D1 policy-answerability (the three base-`allowed` codes answered, `LP-SAVE-NOTE` refused by wave-set / resolve / decide), and the rewritten (cat2) / (cat5) catalog pins; the B9 mutation control still turns red.
- [ ] AC15. `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" and `docs/LANE_GATES.md` describe the three tiers and the `auto` triggers, and state that `LP-SAVE-NOTE` left `human-only` by owner decision.
- [ ] AC16. `bash scripts/check-token-budget.sh` passes for every edited agent, command and skill (a raised budget carries its `docs/prompt-token-budgets.json` entry and the mirror row in the same change).
- [ ] AC17. `bash scripts/check-version-bump.sh` passes (a `changelog.d/` fragment folded by `bash scripts/bump-version.sh`, no hand version edits).

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

## Rule conflicts (open decisions)

none

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| catalog + helper (Subtask 1) | `loomwright/scripts/lane-policy.sh` (438), `loomwright/scripts/check-gate-headers.sh` (121), `loomwright/scripts/classify-risk.sh` (406), `loomwright/scripts/test-lane-policy.sh` (538 — the requirement's AC names this file as the home of the auto-tier legs), `loomwright/scripts/test-classify-risk.sh` (751 — the single test home of classify-risk; the `--paths` legs sit beside the refs-mode legs they must not disturb), `loomwright/docs/LANE_GATES.md` (78), `loomwright/scripts/test-automate-next-step.d/01-golden-idem-gates.sh` (124 — its `CATJ` jq must strip the `!` marker like `?`) | `loomwright/scripts/gate-auto.sh` (new responsibility: decide / record / list — its own module, so `lane-policy.sh` gains only the tier value and the `!` marker) | HIGH |
| driver + run-file seams (Subtask 2) | `loomwright/scripts/automate-next-step.sh` (3249 — `ns_resume_ask` is the single AUT-RESUME emitter and `NS_RESERVED_PREFIXES` the single reserved list; the decision itself is a call to `gate-auto.sh`), `loomwright/scripts/automate-lanes.d/status-read.sh` (800 — one alternation in the existing stage classifier), `loomwright/scripts/automate-lanes.d/create.sh` (143), `loomwright/scripts/test-automate-next-step.sh` (2417 — legs live beside `leg_resume_entry`, which the part `04-pick-resume.sh` calls), `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh` (24), `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (777 — the existing home of the lane.json legs A7/A8/O1 the `auto_gates` leg extends), `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` (627 — the existing home of the stage-classifier legs AJ1–AJ4b the `auto-*` legs extend), `loomwright/docs/result-schemas/automate-run.md` (158), `loomwright/skills/automate-loop/run-file.md` (80) | — | MEDIUM |
| prose + docs + release (Subtask 3) | `loomwright/agents/launch-pad.md` (893 — Phase 6 action 3 is the one LP-SAVE/LP-SAVE-NOTE ask site), `loomwright/commands/launch-pad.md` (242), `loomwright/commands/automate.md` (121), `loomwright/skills/automate-loop/intake.md` (43), `loomwright/skills/automate-loop/resume.md` (45), `loomwright/skills/automate-loop/per-item-loop.md` (104), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1055 — §"Question-gate inventory" and §"Prompt Token Budgets" are the authorities edited), `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (1001 — row LP-152), `loomwright/docs/loop-inventory/automate-loop.md` (789 — rows AL-187 / AL-213), `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/scripts/test-lane-policy.sh` (538 — only the g5 mutation needle that quotes the Phase 6 sentence), `loomwright/capabilities.json` (generated by `build-capabilities.sh`, never hand-edited) | `changelog.d/auto-answer-routine-question-gates.md` | MEDIUM |
| bump-owned (written by `scripts/bump-version.sh`, Subtask 3) | `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `loomwright/capabilities.json` (`plugin_version`) | — | HIGH |

> **Validator-owned surfaces:** `check-gate-headers.sh` scans `agents/*.md`, `commands/*.md`, `skills/**/*.md` and `scripts/*-next-step.sh`; `check-doc-currency.sh`, `check-token-budget.sh`, `test-loop-inventory.sh` and `check-prompt-history-refs.sh` scan the prose files above — files they scan may need updates.

**Not modified (checked):** `loomwright/scripts/automate-lanes.d/relay.sh` — the answer seat is the pre-ask helper, so the relay keeps its pre-policy defer and `_lanes_policy_apply` unchanged; `loomwright/hooks/hooks.json` — no new hook (requirement Assumptions leave the seat to the implementer); `loomwright/scripts/automate-helpers.d/intake.sh` — `queue-confirm` unchanged (AC2).

## Touched-file invariants

> Grounded at base `8275b2ca5356f0c55fec05e0f127a221df897944`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/lane-policy.sh`** — keep: `set -uo pipefail   # NO \`set -e\`` (every failure is an explicit refusal or `human`); decide's exit-0-always contract and "Never a partial answer"; the 12-character header limit (`Every code is at most 12 characters`); the catalog as the ONE authority. reuse: the `?` optional-label idiom — strip `!` the same way `_lp_catalog_json` strips `?` (`map(sub("\\?$"; ""))`), and in `catalog --markdown`. mirror: the policy check line `THE POLICY CHECK (B9 mutation control)` must accept `auto` as well as `allowed` while keeping ONE mutable expression that `test-lane-policy.sh`'s B9 sed (`/THE POLICY CHECK (B9 mutation control)/s/\$row\.policy != "allowed"/false/`) still rewrites — change both in the same commit; the same answerability in `_lp_filter` and `lp_wave_set`, all three through the one `_lp_policy_answerable` helper (D1); `catalog --markdown` prints labels raw (its awk `"`" l[i] "`"`), so a `!` stays visible like `?`. pinned by: `loomwright/scripts/test-lane-policy.sh`, `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh`.
- **`loomwright/scripts/check-gate-headers.sh`** — keep: `fail CLOSED: a check that cannot run never reads clean` (exit 2 when the catalog or python3 is missing); rules G1–G5. mirror: the label parser `l[:-1] if l.endswith("?") else l` must also drop a trailing `!`, so G3/G4 compare bare labels. pinned by: `loomwright/scripts/test-lane-policy.sh` (`gh_mut` legs).
- **`loomwright/scripts/classify-risk.sh`** — keep: `Output (ONE JSON object on stdout, always exit 0)`; `NO way to mark a diff low-risk` (the paths mode adds no exclude, flag or config to lower risk); `.agent/risk.json` read from git, never the working tree; the refs mode byte-identical. fired by: `automate-helpers.sh gate-eval` (condition 6, refs mode only — unchanged). pinned by: `loomwright/scripts/test-classify-risk.sh`, `loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh`.
- **`loomwright/scripts/automate-next-step.sh`** — keep: the can't-ask split `if [ -n "$2" ] || [ "$(st resume_n)" != 1 ]; then cant="resume_ambiguous park"` (the auto branch runs only on the interactive path with `resume_n == 1` and no rebuilt line, BEFORE `ns_emit_ask`); the `NS_RESERVED_PREFIXES='picked` list — add `auto-answered` and `auto-escalated` so a model-authored `progress_note` cannot forge an auto-answer record. pinned by: `loomwright/scripts/test-automate-next-step.sh` (`leg_resume_entry() {`, the reserved-notes heredoc ending `skipped AUT-QUEUE x`).
- **`loomwright/scripts/automate-lanes.d/status-read.sh`** — keep: the stage classifier's closed alternation `skipped AUT-QUEUE|trail-gate|trail-unstage)") then ["pick"]`; an `auto-answered AUT-*` / `auto-escalated AUT-*` line maps to `pick`, an `LP-*` one to `plan`. pinned by: `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` (AJ1–AJ4b).
- **`loomwright/scripts/automate-lanes.d/create.sh`** — keep: the lane.json object `parallel: $parallel, max_tokens: $mt, created: $created, policy: $policy}` — add `auto_gates` only when the parent run's `## Run Config` says `auto_gates: off`, so every other lane.json is byte-identical. pinned by: `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh`.
- **`loomwright/scripts/test-classify-risk.sh`** — keep: every refs-mode leg unchanged (AC10's byte-identical half); the new `--paths` legs sit beside them and never alter a fixture the refs legs read. pinned by: itself (`bash loomwright/scripts/test-classify-risk.sh`).
- **`loomwright/scripts/test-automate-next-step.sh`** — keep: `leg_resume_entry() {`'s existing assertions (the cant_ask stop, the re-printed pending ask — `a second --resume did not re-print the pending AUT-RESUME ask`), extended not rewritten; the reserved-notes heredoc keeps every existing forged line. pinned by: `loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh` (`if leg_resume_entry "$DRIVER"; then ok "P3 (AC4)`).
- **`loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh`** — keep: the `LEG_MSG=""` / `ok` / `no` leg idiom and the P-numbering; a new leg gets the next free P number. pinned by: the part-group runner (`test-automate-next-step.d/<part>.sh in three pool groups`).
- **`loomwright/scripts/test-automate-next-step.d/01-golden-idem-gates.sh`** — keep: the Q leg's rule that every ask offers exactly the catalog's labels (all of them, or the non-`?` core) — `CATJ="$(bash "$HERE/lane-policy.sh" catalog | jq -Rnc` gains a `!` strip and nothing else. pinned by: itself (the Q leg; run through `test-automate-next-step.sh`).
- **`loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh`** — keep: AJ1–AJ4b's existing stage expectations byte-identical. pinned by: `loomwright/scripts/test-automate-lanes.sh`.
- **`loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh`** — keep: its existing lane.json and status-read legs byte-identical (a lane.json without `auto_gates` is the default case). pinned by: `loomwright/scripts/test-automate-lanes.sh`.
- **`loomwright/scripts/test-lane-policy.sh`** — keep: `(op5) the same core under LP-SAVE-NOTE (human-only) ⇒ human` stays green or is renamed truthfully (its policy has no LP-SAVE-NOTE answer, so `decide` still prints `human`); `gh_mut g5 agents/launch-pad.md` keeps a needle that exists verbatim in the new Phase 6 sentence; (cat8)'s drift control `` sed 's/`Process` · `Stop`/`Process` · `Halt`/' `` must still land, so retarget it to the AUT-QUEUE row's new text; (cat2) `every row is code<TAB>allowed|human-only<TAB>labels<TAB>purpose` and (cat5) `the allowed gates are EXACTLY the five B1 names` are closed pins over the tier column — rewrite both (Subtask 1), never delete them.

## Closed enumerations touched

> Sibling grep at base `8275b2ca5356f0c55fec05e0f127a221df897944`: `grep -rlF 'human-only' --exclude=CHANGELOG.md loomwright scripts .github | grep -v /fixtures/` → 27 files; `grep -rnF 'skipped AUT-QUEUE' --exclude=CHANGELOG.md loomwright scripts | grep -v /fixtures/` → 16 hits in 9 files.

- **`auto`** (sibling tier: `human-only`) — must be named in:
  - `loomwright/scripts/lane-policy.sh` — the catalog header comment (`policy` is `allowed` … or `human-only`), `_lp_filter`, `lp_wave_set`, `lp_decide` — extend.
  - `loomwright/docs/LANE_GATES.md` — the tier list (`allowed` / `human-only` bullets) and the regenerated table — extend.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — §"Question-gate inventory" — extend.
  - `loomwright/agents/launch-pad.md` — Phase 6 action 3 (`header: "LP-SAVE-NOTE"` (human-only, so it always reaches a human)) — extend.
  - `loomwright/docs/loop-inventory/launch-pad-autonomous.md` — row LP-152 (LP-SAVE-NOTE described human-only) — extend.
  - `loomwright/scripts/test-lane-policy.sh` — (cat2) `allowed|human-only` tier list — extend to three tiers; (cat5) the exact `allowed` set — rewrite to two closed sets (`allowed`, `auto`); plus the new legs.
  - `loomwright/scripts/check-gate-headers.sh` — no change for the tier (it never reads the policy column); `!` marker — extend (label parser).
  - `loomwright/skills/automate-loop/lanes.md`, `loomwright/docs/PITFALLS.md`, `loomwright/agents/product-owner.md`, `loomwright/commands/{janitor,backlog,product-owner}.md`, `loomwright/scripts/supervisor-next-step.sh` — no change: each says a human-only code is never policy-answered, still true.
  - `loomwright/scripts/run-lock.sh`, `loomwright/scripts/automate-next-step.sh` (the `--force-unlock is human-only` park text), `loomwright/docs/result-schemas/{supervisor-result,automate-run}.md`, `loomwright/docs/loop-inventory/review-heal.md`, `loomwright/skills/automate-loop/per-item-loop.md` (run-lock line) — no change: "human-only" there is not the catalog tier.
  - Test files (`test-automate-next-step.sh`, `test-automate-next-step.d/01-golden-idem-gates.sh`, `test-automate-lanes.d/03-fixes-to-finalize.sh`, `test-supervisor-next-step.sh`, `test-rule-conformance-seam.sh`, `test-not-verified-transport-seam.sh`) — no change: they use human-only codes that stay human-only.
- **`!` auto-label marker** (sibling: the `?` optional marker; readers found with `grep -rnE 'lane-policy\.sh"? catalog|_lp_catalog_rows' --include='*.sh'` → 9 files) — every reader that compares raw catalog labels to an ask:
  - `loomwright/scripts/lane-policy.sh` — `_lp_catalog_json` — extend (strip `!`); `catalog --markdown` — no change (prints raw, like `?`).
  - `loomwright/scripts/check-gate-headers.sh` — label parser — extend.
  - `loomwright/scripts/test-automate-next-step.d/01-golden-idem-gates.sh` — `CATJ` — extend.
  - `loomwright/scripts/test-lane-policy.sh` — (cat7)/(cat9) compare raw text — no change; (cat8) drift sed — extend (retarget).
  - `loomwright/scripts/supervisor-next-step.sh` — `sn_ask` / line `opts=` strip only `?` — no change: it asks `SUP-*` codes only and no `SUP-*` row carries `!` (stated as an invariant in `docs/LANE_GATES.md`: the `!` marker appears only on `auto` rows).
  - `loomwright/scripts/test-supervisor-next-step.sh`, `loomwright/scripts/test-rule-conformance-seam.sh` — read `SUP-*`, `LP-RULE-OVR`, `PO-RULE-MUST` rows only — no change.
- **`auto-answered` / `auto-escalated`** (sibling Progress prefix: `skipped AUT-QUEUE`) — must be named in:
  - `loomwright/scripts/automate-next-step.sh` — `NS_RESERVED_PREFIXES` — extend.
  - `loomwright/scripts/test-automate-next-step.sh` — the reserved-notes heredoc (`skipped AUT-QUEUE x`) — extend with one forged line per new prefix.
  - `loomwright/docs/result-schemas/automate-run.md` — the `progress_note` reserved-prefix text — extend.
  - `loomwright/scripts/automate-lanes.d/status-read.sh` — stage classifier — extend (legs in `test-automate-lanes.d/05-timeline-and-gate.sh`).
  - `loomwright/docs/loop-inventory/automate-loop.md` — rows AL-187 / AL-213 — extend.
  - `loomwright/skills/automate-loop/intake.md`, `loomwright/skills/automate-loop/helpers.md`, `loomwright/scripts/automate-helpers.d/intake.sh`, `loomwright/scripts/test-automate-helpers.d/16-queue-gates.sh`, `loomwright/docs/result-schemas/automate-run/parallel-lanes.md` — no change: they describe the unchanged `queue-confirm` skip line (intake.md gains a separate sentence for the auto line, Subtask 3).
- **`auto_gates`** (sibling Run Config key: `max_tokens`) — must be named in:
  - `loomwright/skills/automate-loop/run-file.md` — the `## Run Config` block — extend.
  - `loomwright/docs/result-schemas/automate-run.md` — the `## Run Config` block — extend.
  - `loomwright/scripts/automate-lanes.d/create.sh` — the lane.json object — extend.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-lane-policy.sh` — auto tier answers LP-SAVE-NOTE | in `loomwright/scripts/lane-policy.sh`, change the `LP-SAVE-NOTE` row's policy from `auto` back to `human-only` |
| `loomwright/scripts/test-lane-policy.sh` — severity trigger | in `loomwright/scripts/gate-auto.sh`, delete the line that turns a MEDIUM-or-higher `--max-severity` into `ask severity` |
| `loomwright/scripts/test-lane-policy.sh` — high_risk trigger | in `loomwright/scripts/gate-auto.sh`, delete the line that turns `high_risk` true/null into `ask high_risk` |
| `loomwright/scripts/test-lane-policy.sh` — destructive trigger | in `loomwright/scripts/gate-auto.sh`, delete the `--destructive` ⇒ `ask destructive` line |
| `loomwright/scripts/test-lane-policy.sh` — off switch (config key `false`) | in `loomwright/scripts/gate-auto.sh`, replace the `has("auto_gates")` read with `.auto_gates // empty` (the false-collapse) |
| `loomwright/scripts/test-lane-policy.sh` — label mismatch | in `loomwright/scripts/gate-auto.sh`, delete the offered-labels-vs-catalog comparison |
| `loomwright/scripts/test-lane-policy.sh` — human-only stays human | in `loomwright/scripts/gate-auto.sh`, delete the `policy == "auto"` tier check |
| `loomwright/scripts/test-lane-policy.sh` — B9 mutation control (existing) | flip `$row.policy != "allowed"` → `false` in `loomwright/scripts/lane-policy.sh` (the test's own sed, kept matching) |
| `loomwright/scripts/test-lane-policy.sh` — (cat2) three tiers | in `loomwright/scripts/lane-policy.sh`, change the `AUT-QUEUE` row's policy to `automatic` (an unknown tier) |
| `loomwright/scripts/test-lane-policy.sh` — (cat5) exact `auto` set | in `loomwright/scripts/lane-policy.sh`, change the `LP-SAVE` row's policy from `auto` to `allowed` |
| `loomwright/scripts/test-lane-policy.sh` — LP-SAVE-NOTE refused by policy (D1) | in `loomwright/scripts/lane-policy.sh`, empty `_LP_POLICY_EXEMPT` |
| `loomwright/scripts/test-lane-policy.sh` — base-`allowed` auto codes stay policy-answerable (AC12) | in `loomwright/scripts/lane-policy.sh`, make `_lp_policy_answerable` accept `allowed` only |
| `loomwright/scripts/test-lane-policy.sh` — AUT-QUEUE / AUT-RESUME / LP-SAVE answered | in `loomwright/scripts/lane-policy.sh`, delete the `!` from the `AUT-QUEUE` row's `Process!` label (no auto label ⇒ `ask label`) |
| `loomwright/scripts/test-lane-policy.sh` — off switch from `--off`, `## Run Config` and `lane.json` | in `loomwright/scripts/gate-auto.sh`, delete the `## Run Config` `auto_gates: off` read (one leg per source; the `--off` and `lane.json` reads likewise) |
| `loomwright/scripts/test-lane-policy.sh` — `--markdown` keeps `!` (cat7) | in `loomwright/scripts/lane-policy.sh`, strip `!` in the `catalog --markdown` awk |
| `loomwright/scripts/test-classify-risk.sh` — `--paths` low-risk list ⇒ `false` | in `loomwright/scripts/classify-risk.sh`, make the `--paths` branch emit `high_risk: true` unconditionally |
| `loomwright/scripts/test-classify-risk.sh` — `--paths` unreadable list ⇒ `null` | in `loomwright/scripts/classify-risk.sh`, delete the unreadable-list ⇒ `unclassifiable` line |
| `loomwright/scripts/test-classify-risk.sh` — refs mode byte-identical | in `loomwright/scripts/classify-risk.sh`, append a `paths_mode: false` key to the refs-mode JSON |
| `loomwright/scripts/test-automate-next-step.d/01-golden-idem-gates.sh` — Q leg with `!` labels | flip `options: ["Continue","Start new","Archive"]` → `options: ["Continue!","Start new","Archive"]` in `loomwright/scripts/automate-next-step.sh` (an ask offering the raw marker instead of the label) |
| `loomwright/scripts/test-lane-policy.sh` — (cat8) control lands | in `loomwright/docs/LANE_GATES.md`, edit one AUT-QUEUE label by hand (the (cat7) drift the control proves detectable) |
| `loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh` — `auto-answered` stage mapping | in `loomwright/scripts/automate-lanes.d/status-read.sh`, delete the `auto-answered` alternation |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` — conditional lane.json `auto_gates` | in `loomwright/scripts/automate-lanes.d/create.sh`, write `auto_gates` unconditionally |
| `loomwright/scripts/test-automate-next-step.sh` — one run + `cant_ask` still stops (D8) | in `loomwright/scripts/automate-next-step.sh`, route the `cant_ask` answer to the Continue path when `auto_answer` is set |
| `loomwright/scripts/test-classify-risk.sh` — paths mode flags `agents/` | in `loomwright/scripts/classify-risk.sh`, delete the class (b) path match in the `--paths` branch |
| `loomwright/scripts/test-automate-next-step.sh` — `auto_answer` only with exactly one run | in `loomwright/scripts/automate-next-step.sh`, change the `auto_answer` branch's `resume_n` test from `= 1` to `-ge 1` |
| `loomwright/scripts/test-automate-next-step.sh` — reserved `auto-answered` prefix | delete `auto-answered` in `loomwright/scripts/automate-next-step.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Catalog `auto` tier, `gate-auto.sh` helper, `classify-risk.sh --paths` | AC6 (helper side), AC8, AC9, AC10, AC12, AC13, AC14 | 7 modify, 1 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Driver + run-file seams: AUT-RESUME `auto_answer` field, reserved prefixes, stage classifier, `auto_gates` Run Config / lane.json | AC3 (driver side), AC7 (Run Config / lane side), AC11 (driver side) | 9 modify, 0 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1) |
| 3 | Prose wiring, docs, budgets and release fragment | AC1, AC2, AC3 (coordinator side), AC4, AC5, AC6 (call sites), AC7 (flags), AC11, AC15, AC16, AC17 | 12 modify, 1 create | `skills/automate-loop/SKILL.md`, `skills/supervisor-readiness/SKILL.md` | BLOCKED (by #1, #2) |

**Subtask 1 notes:** create `gate-auto.sh` per Design D3/D4/D5 (bash 3.2-safe, `set -uo pipefail`, header comment in the house style of `lane-policy.sh`, a `--help` that prints it); extend `lane-policy.sh` per D1/D2 (move `AUT-RESUME`, `AUT-QUEUE`, `LP-SAVE`, `LP-SAVE-NOTE` to `auto`, add the `!` marker, update purposes truthfully); add `classify-risk.sh --paths` per D6; extend `check-gate-headers.sh`'s parser; regenerate the `LANE_GATES.md` table (`bash loomwright/scripts/lane-policy.sh catalog --markdown`) and rewrite its tier bullets for three tiers; add the AC14 legs and the `--paths` legs. Make `01-golden-idem-gates.sh`'s `CATJ` strip a trailing `!` (`all`) while `core` stays the labels not ending `?`. Retarget the (cat8) drift sed to the new AUT-QUEUE row text (`` `Process!` · `Stop` ``). Run `bash loomwright/scripts/test-lane-policy.sh`, `bash loomwright/scripts/test-classify-risk.sh`, `bash loomwright/scripts/check-gate-headers.sh`, `bash loomwright/scripts/test-automate-next-step.sh`.

**Subtask 2 notes:** per D8, in `ns_resume_ask` (interactive path only, `resume_n == 1`, no rebuilt line) call `gate-auto.sh decide AUT-RESUME --runfile <rf> …` (risk from the run's open PR diff when one exists, else no risk read) and add `auto_answer` / `auto_reason` to the emitted ask instruction; in every other case `auto_answer: null`. The driver writes nothing for the auto decision and never continues on its own. Extend `leg_resume_entry`: one run interactive ⇒ the ask carries `auto_answer: "Continue"`; `auto_gates: off` in `## Run Config` ⇒ `auto_answer: null`; two runs ⇒ `null`; one run + `{"cant_ask": true}` ⇒ still `resume_requires_flag_non_interactive`, `.supervisor/` byte-unchanged. Add `05-timeline-and-gate.sh` legs beside AJ1–AJ4b: `auto-answered AUT-QUEUE …` / `auto-escalated AUT-RESUME …` ⇒ stage `pick`, `auto-answered LP-SAVE-NOTE …` ⇒ `plan`; add a `01-create-to-wait.sh` leg beside A7/A8: lane.json carries `auto_gates: false` only under a parent `auto_gates: off`. Document `auto_answer` in the `ask also carries` list and the `--resume` paragraph of `docs/result-schemas/automate-run.md`, the reserved prefixes in its `progress_note` text, and `auto_gates` in its and `run-file.md`'s `## Run Config` blocks. Run `bash loomwright/scripts/test-automate-next-step.sh` and `bash loomwright/scripts/test-automate-lanes.sh`.

**Subtask 1 → D1 note:** rewrite (cat2) to accept the three tiers and (cat5) to pin the `allowed` set AND the `auto` set (each with its exact labels and its `!` label) as two closed sets.

**Subtask 3 notes:** Launch Pad Phase 6 action 3 calls `gate-auto.sh decide <LP-SAVE|LP-SAVE-NOTE> --max-severity <highest PLAN_REVIEW_RESULT issue severity> --risk-paths <the File Impact Map paths, one per line, in a scratch file> [--off]` before asking, ONLY on the can-ask path; `answer` ⇒ the "Save and exit" branch plus `gate-auto.sh record`; `ask` ⇒ record the escalation and ask exactly as today. `/automate` intake: after `queue-confirm` prints `ask`, call `gate-auto.sh decide AUT-QUEUE` (no risk read). `resume.md`: apply the driver's `auto_answer` per D8 (record, then `--result {"answers": ["Continue"]}`), only when the coordinator could ask. per-item-loop.md: print `gate-auto.sh list <runfile>` at every park and at run end. `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" states the three tiers, the `auto` triggers, the owner decision moving `LP-SAVE-NOTE`, and names the two Progress records `auto-answered` / `auto-escalated`. Add `--no-auto-gates` to the flag tables of `commands/automate.md` and `commands/launch-pad.md` (the `## Run Config` docs are Subtask 2's). Update the g5 needle in `test-lane-policy.sh` to the new Phase 6 sentence. Re-measure and, where needed, raise token budgets (`commands/launch-pad.md` has ~190 tokens of headroom; keep its addition to one flag-table row). Write `changelog.d/auto-answer-routine-question-gates.md` (`<!-- bump: minor -->`, headline `Auto-answer routine question gates`) and commit it; run `bash loomwright/scripts/build-capabilities.sh` and commit `loomwright/capabilities.json` if it changed (the new script referenced from command/skill prose changes the contract, and `bump-version.sh` refuses a stale one); then run `bash scripts/bump-version.sh`, then `bash scripts/check-version-bump.sh`, `bash scripts/check-token-budget.sh`, `bash loomwright/scripts/check-gate-headers.sh`, `bash loomwright/scripts/test-loop-inventory.sh`. Pre-push: `bash scripts/ci-local.sh --affected`.

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/gate-auto.sh"}
  - {kind: "symbol", path: "loomwright/scripts/gate-auto.sh", name: "auto-answered"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "Save and exit!"}
  - {kind: "symbol", path: "loomwright/scripts/classify-risk.sh", name: "--paths"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "| `LP-SAVE-NOTE` | auto |"}
requires: []
lanes:
  - "loomwright/scripts/gate-auto.sh"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/scripts/check-gate-headers.sh"
  - "loomwright/scripts/classify-risk.sh"
  - "loomwright/scripts/test-lane-policy.sh"
  - "loomwright/scripts/test-classify-risk.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/scripts/test-automate-next-step.d/01-golden-idem-gates.sh"
external_requires:
  - "jq, python3, git (already required by the touched scripts)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "gate-auto.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "auto-escalated"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "auto_answer"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/status-read.sh", name: "auto-answered"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/create.sh", name: "auto_gates"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/run-file.md", name: "auto_gates: off"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/gate-auto.sh"}
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/automate-lanes.d/status-read.sh"
  - "loomwright/scripts/automate-lanes.d/create.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/04-pick-resume.sh"
  - "loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh"
  - "loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/skills/automate-loop/run-file.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "gate-auto.sh decide"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/intake.md", name: "gate-auto.sh decide"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "gate-auto.sh list"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "--no-auto-gates"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "auto-escalated"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "Auto-answer routine question gates"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/gate-auto.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "Save and exit!"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "auto_answer"}
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/commands/automate.md"
  - "loomwright/skills/automate-loop/intake.md"
  - "loomwright/skills/automate-loop/resume.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/scripts/test-lane-policy.sh"
  - "changelog.d/auto-answer-routine-question-gates.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/capabilities.json"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
Subtask 1 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | YES (requires) |
| Subtask 1 | Subtask 3 | `loomwright/scripts/test-lane-policy.sh` (g5 needle only) | YES (requires — sequential sharing is legal) |
| Subtask 2 | Subtask 3 | none | YES (requires — Subtask 3's resume prose consumes the driver's `auto_answer` field) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2
- **Batch 3:** Subtask 3
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md` |
| 3 | `skills/automate-loop/SKILL.md`, `skills/supervisor-readiness/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): phase sessions route every ask to the coordinator without a policy lookup, so the relay cannot be the answer seat | MEDIUM | Design D3: the prose / driver calls `gate-auto.sh decide` BEFORE asking; the relay stays byte-identical |
| Feasibility (Phase 2.5): ~24 files exceed one worker's context | MEDIUM | `context-bound` split into three subtasks with disjoint lanes |
| Feasibility (Phase 2.5): `classify-risk.sh` has no brief mode; owner chose the literal `--paths` mode, so in this repo class (b) (`agents/`, `commands/`, `skills/`, `hooks/`) escalates most plugin-self briefs and LP-SAVE-NOTE will still be asked for them | HIGH | Accepted by the owner (this session). State it as an honest limit in `docs/LANE_GATES.md`; the refs mode and `gate-eval` condition 6 stay byte-identical (AC10) |
| A policy answering an escalated `auto` ask in a lane would bypass Scope C | MEDIUM | D1: only the three base-`allowed` codes stay policy-answerable (their behaviour is unchanged from today); `LP-SAVE-NOTE` stays refused by wave-set / resolve / decide, pinned by its own mutation row |
| A driver-side auto-Continue would bypass the can't-ask stop for a caller with no `--non-interactive` flag | HIGH | D8: the driver only annotates the ask (`auto_answer`); the caller that can ask applies it; the `cant_ask` leg and its pin mutation guard `resume_requires_flag_non_interactive` |
| A new script referenced from command/skill prose changes `capabilities.json`; `bump-version.sh` refuses a stale contract | MEDIUM | Subtask 3 runs `build-capabilities.sh` and commits it before the bump |
| The B9 mutation control seds a literal `$row.policy != "allowed"`; rewriting the policy check silently disarms it | HIGH | Touched-file invariant: change the check and the test's sed in the same commit; the B9 leg must still go red |
| `progress-append` is an unlocked read-modify-rename; a phase session's `gate-auto.sh record` writes the parent run file while the coordinator waits | LOW | The coordinator does not write during `phase-wait`; `record` is fail-SAFE, and the Progress line is the record `list` reads |
| `commands/launch-pad.md` is ~190 tokens under its budget | MEDIUM | Keep its change to one flag-table row; raise the budget with the `prompt-token-budgets.json` entry and mirror row only if re-measurement requires it (AC16) |
| `test-loop-inventory.sh` pins quoted `q:` text from the prose; rewording Phase 6 action 3 or intake.md may break rows | MEDIUM | Update rows LP-152, AL-187 and AL-213 in the same commit and run `test-loop-inventory.sh` |
| Rubber-stamp risk moves rather than vanishes (requirement Risks) | MEDIUM | The `gate-auto.sh list` block sits in the park block the owner always reads (AC4); triggers never read the model's own confidence |
| jq `// empty` collapses a boolean `false` config value (project memory ac3f1a80) | MEDIUM | Read `auto_gates` with `has("auto_gates")`; a pin mutation targets the false-collapse |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-03-auto-answer-routine-question-gates.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-04T01:27:18Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/813
- **Branch:** feature/auto-answer-routine-question-gates
- **Files changed:** 31
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Added the deterministic `auto` gate tier (catalog `!` label, gate-auto.sh decide/record/list, classify-risk.sh --paths, AUT-RESUME auto_answer, auto_gates off switch, prose wiring) as v17.29.0. Phase 4.5 fixed a HIGH in each of 3 iterations (decorated --paths read low-risk, twice; a dropped space in the /lanes Merge classifier) plus 5 red CI checks; the final fix 016c558 was not re-reviewed. 5 MEDIUM/LOW findings dismissed below the HIGH fix floor (PR comment). Pre-existing token-ledger CI flake noted (also red on main).

## Not verified
- **launch-pad.md Phase 6 and loop-inventory LP-152 against the new catalog** — Subtask 3 rewires that prose (subtask 1)
- **gate-auto.sh decide/record/list inside a real /automate or /launch-pad session** — no caller existed yet; scratch-repo runs only (subtask 1)
- **coordinator applying auto_answer (skills/automate-loop/resume.md)** — prose only (subtask 2)
- **AUT-RESUME risk read against a real GitHub PR** — only stubbed gh and local refs observed (subtask 2)
- **live /automate Launch Pad phase auto-saving LP-SAVE-NOTE** — no live run (subtask 3)
- **coordinator applying AUT-RESUME auto_answer live** — prose only (subtask 3)
- **lane engine auto-answering inside a --parallel lane** — needs a live wave (subtask 3)
