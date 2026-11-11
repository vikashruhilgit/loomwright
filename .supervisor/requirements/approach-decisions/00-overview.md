# 00 — Approach decisions set: overview (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now

The pipeline checks that an implementation fits our patterns, can be done, and works — nowhere does it ask whether the chosen approach, library or tool is the best, or among the best, of the available ways. Verified on main `8ec200e` / v17.35.1, 2026-11-10 (the checkout's working tree is on `feature/dismissed-followups-03-lanes-meta-sync` at `bb51310`; `git diff --stat 8ec200e HEAD` over every file cited below is empty, so the line numbers hold on both):

- **Fit, not comparison:** Plan Reviewer Criterion 2 "Pattern Alignment" (`agents/plan-reviewer.md` lines 64–68) asks whether the approach matches CLAUDE.md; Launch Pad Phase 2.5 FEASIBILITY (`agents/launch-pad.md` lines 154–219) rates a new major dependency `CAUTION` and carries it to Risk Assessment; the Product Owner's Reality Check (`agents/product-owner.md` lines 227–240) asks "does it fit the current design".
- **A dangling contract:** the brief template's `## Task` (`skills/supervisor-readiness/SKILL.md` lines 148–154) is Goal + Problem Statement, and §"Section Requirements" (line 428) lists nine optional sections, none an approach section — yet Plan Reviewer Criterion 17a/17c (lines 219, 221) already read "`## Task`, Design decisions, acceptance criteria". Nothing writes the section the reviewer names.
- **Excluded or orthogonal elsewhere:** `skills/brainstorming/SKILL.md` line 34 excludes "Pure technical decisions"; the Orchestrator uses Context7 to use a chosen library correctly (`agents/orchestrator.md` lines 117–122, 194); Red Team vector 1 (`agents/red-team-reviewer.md` lines 149–157) attacks how code fails, never whether a different tool avoids the code; `.agent/rules/documentation.json` and `process.json` carry no rule on dependency or approach choice.
- **No baseline:** the six postmortem classes (`skills/pr-postmortem/SKILL.md` lines 27–38) have no approach bucket, so "why not use X / the platform already does this" is filed as `missing_context` or `plan_gap`; across the 232 records in `.supervisor/postmortem/results.jsonl` (2026-11-10) no approach-caused rework rate exists. Owner rule: no item without a baseline — story `01` IS the baseline.
- **No product context:** `.agent/product.json` is absent (`read-product.sh` emits nothing); framing was taken from the gap brief and the repo. To record it once: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-product.sh"` (propose-only; re-run with `--stance product|tool` and `--confirm`).

## Owner decisions
- 2026-11-10 (Vikash): "Yes, write it" — approves WRITING these requirements, not building them. Every story here is `## Status: pending` and says "Not approved to build — requirements only" in its own Owner decisions.
- 2026-11-10 (Vikash, standing invariants, not reopened): no new agent; advisory never gating except through the existing stamped-countable house-rule mechanism (`skills/rules/SKILL.md` §7–§8 — a `must` rule with a `check` needs `prove-rule-check.sh` PROVEN, else it is offered as advisory); every new script gets a hermetic `test-*.sh`; every changed agent/command/skill re-measures `loomwright/docs/prompt-token-budgets.json` plus its ARCHITECTURE_CONTRACTS.md mirror row; `changelog.d/<slug>.md` per PR; prompts carry no history (`check-prompt-history-refs.sh`); only humans update CLAUDE.md (agents propose).
- 2026-11-10 (Vikash, this set): `01` is a per-round boolean mirroring `self_heal_miss` (not a 7th class) plus a one-shot read-only heuristic baseline script that never writes back; `02` is an optional `## Design decisions` brief section on a closed five-trigger list, a Launch Pad Phase 2.7 (≤ 25 agent lines, protocol in a split file), Plan Reviewer Criterion 23 (23c HIGH ⇒ FAIL; 23d NEEDS_HUMAN, never FAIL), one Red Team bullet, no Worker change, a house rule proposed advisory and never written here; metric = `01`'s flag rate, revisit after 20 PRs.

## Order

| # | Item | Delivers | Depends on | Priority |
|---|---|---|---|---|
| 1 | `01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md` | optional per-round `approach_challenged` boolean + `approach_challenges` counter in POSTMORTEM_RESULT (`schema_version` stays 1); `read-postmortem.sh` tallies it; read-only `postmortem-approach-baseline.sh` prints a guessed TSV + summary over the 232 records (never writes); the number committed in `docs/evidence/approach-baseline.md` | none | **MVP** |
| 2 | `02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md` | optional `## Design decisions` brief section (closes the Criterion 17a/17c dangling reference); `skills/supervisor-readiness/design-decisions.md` split file; Launch Pad Phase 2.7 APPROACH with the `LP-APPROACH` gate (tie or T1 only; can't-ask ⇒ `status: unconfirmed`); Plan Reviewer Criterion 23 (23a–23d, `approach_unjustified` / `approach_reinvents`); Red Team vector-1 bullet; advisory house rule proposed in the evidence file | none hard — by owner rule after `01` (the baseline must exist) | P1 |

**Why this order:** `02`'s success metric is `01`'s flag rate; the owner's rule queues no approach item without that baseline. The two share only the two budget docs (declared), which a sequential run serialises; `02` declares `## Depends on: none` because no file of `01` is read by `02` — the ordering is a human rule, which `--lint` cannot see.

## Run

```
/automate --folder .supervisor/requirements/approach-decisions
```

- Mode: safe (no `--auto-merge`). **No `--parallel`** — N = 1, sequential, `01` then `02`. Not run here: nothing is approved. `--folder` lists `*.md` non-recursively and skips this file's `## Status: done` stamp.
- `plan-waves --lint .supervisor/requirements/approach-decisions` (2026-11-10, verbatim):
  ```
  .supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md: Touches ok; Depends on ok
  .supervisor/requirements/approach-decisions/02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md: Touches ok; Depends on ok
  0 of 2 items will run alone: none
  0 of 2 items depend on every earlier item: none
  ```
- `plan-waves --explain --max 2 .supervisor/requirements/approach-decisions` (2026-11-10, verbatim):
  ```
  wave 1: .supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md
  wave 2: .supervisor/requirements/approach-decisions/02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md
  explain .supervisor/requirements/approach-decisions/02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md (wave 2):
    conflicts with .supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md on loomwright/docs/ARCHITECTURE_CONTRACTS.md (declared)
    conflicts with .supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md on loomwright/docs/prompt-token-budgets.json (declared)
  ```
- `right-size` (advisory, 2026-11-10, verbatim): `01: ok (12 files, 13 scope items, 13 criteria)` · `02: large (31 files) — will not fit one PR: split by Part`. **Cause of `02`'s count (read with `plan-waves <02> --touches`):** 16 declared paths become 31 because `.agent/companions.json`'s `{"when": "loomwright/skills/*", "new": true, …}` rule fires on the NEW split file `loomwright/skills/supervisor-readiness/design-decisions.md` and adds the nine new-*skill* surfaces (`CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`, `loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md`, `loomwright/docs/command-parts/agent-help/` — the directory counted as its files). A new file under an existing skill dir is not a new skill; none of those nine is edited by `02`. Kept as one story per the owner's three-file instruction; **the owner's call:** split by Part (Parts 1–2 Launch Pad + template · Parts 3–4 Plan Reviewer + Red Team · Parts 5–6 evidence) with `automate-helpers.sh merge-items` in reverse if later re-joined, or narrow the companions rule to new skill DIRECTORIES (a hygiene item, not queued here).
- **Hotspots** (both items): `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/prompt-token-budgets.json` (budget rows; different rows). One owner per wave since N = 1.

## Open questions (index; full text in the stories)
- OQ-A1 (01): the baseline number is committed in `docs/evidence/approach-baseline.md` and linked from the PR body (Criterion 20), not PR-body-only as the gap brief said.
- OQ-A2 (01): the new tally line lives in `read-postmortem.sh`, not `/insights` (`build-insights.sh` never reads `categories[]`).
- OQ-A3 (01): `recorded:<bool>` rows counted apart from guessed rows so before/after rates never mix.
- OQ-A4 (02): section position — after `## Task`, before `## Acceptance Criteria`.
- OQ-A5 (02): 23d = MEDIUM `approach_unjustified` + a dedicated NEEDS_HUMAN matrix row; `unconfirmed` T2–T5 = LOW note.
- OQ-A6 (02): `LP-APPROACH` options `Keep <chosen>` · `Switch to <runner-up>` · `Decide later`; a fourth "Drop the dependency" is the alternative.
- OQ-A7 (02): T2 is re-checked once after Phase 3 action 13 (or move the whole phase to 3.5 — the alternative).
- OQ-A8 (02): the "22" criteria pins move to "23" inside the three seam tests (`check-doc-currency.sh` does not scan them).
- OQ-A9 (set): the companions `new: true` skills rule inflates `02`'s size; split by Part or narrow the rule — owner's call.

## Considered and not queued

| Candidate | Status | Revisit when |
|---|---|---|
| A 7th postmortem class `approach_mismatch` | **REJECTED** | never — `skills/pr-postmortem/SKILL.md` line 46 settled it: additive per-round booleans, the class set stays six |
| A `must` house rule on new dependencies | **REJECTED** | its check would read a brief, not the tree — `prove-rule-check.sh` cannot prove it; `02` Part 5 proposes the advisory form |
| A merge-gate condition or `heal_decision` input reading `## Design decisions` | **REJECTED** | the seven gate conditions are closed (CLAUDE.md §"Failure-Mode Invariants") |
| A 5-lens brainstorm per subtask | **REJECTED** | `skills/brainstorming/SKILL.md` line 34 excludes pure technical decisions; the five fixed axes replace it |
| Greenfield stack choice for a no-CLAUDE.md project | **REVISIT WHEN** | a project without CLAUDE.md asks for one (shape below) |
| Narrowing the companions `new: true` skills rule to new skill directories | deferred (hygiene) | OQ-A9: when the owner decides `02`'s split |

## Revisit when
- 20 agent PRs have merged after `02`: rerun `postmortem-approach-baseline.sh`, compare `recorded:` rows against the guessed baseline in `docs/evidence/approach-baseline.md`.
- A project with no CLAUDE.md asks for a greenfield stack choice: run the same Design decisions block ONCE for the stack (T1 for every dependency, the five axes) and propose the result into CLAUDE.md for the human — a separate item, not queued (shape only, recorded here).
- A fourth "22"-criteria pin or a `category` validator enum appears: `02`'s Assumptions name the greps to re-run.
- The owner wants the Red Team bullet or Criterion 23c to become a stamped `must` rule: it needs a `check` that reads the committed tree and a PROVEN counterexample — not this set.

## Checklist
- [ ] .supervisor/requirements/approach-decisions/01-approach-challenged-rounds-are-counted-in-the-postmortem-ledger.md
- [ ] .supervisor/requirements/approach-decisions/02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md
