# The QA blueprint describes the two-lane QA system

## Status: pending

Source: re-validation of `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` against main `8ec200e` / v17.35.1 (2026-11-09). Sibling of the qa-evolution stories in this folder: `01-qa-session-accounting-is-derived-never-agent-written.md`, `02-qa-findings-reach-a-consumer-propose-from-qa.md`, `03-the-qa-lane-earns-its-cost-on-the-feature-scorecard.md`, `04-verify-runs-inside-the-delivery-loop-in-shadow.md`, `05-verify-can-target-a-pull-requests-preview-deployment.md`, `07-exploratory-qa-runs-under-the-verify-environment-contract.md`, `09a-verify-targets-an-electron-app-through-playwright.md`, `09b-verify-walks-mobile-acceptance-criteria-through-a-device-driver.md` (both added 2026-11-10), `operator-run/06-dogfood-qa-accounting-and-verify-on-a-real-app.md` (`00-overview.md` was still being written when this was drafted).

**As the** owner (Vikash), deciding what QA work is worth building next,
**I want** `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` to describe the QA system that actually shipped — a verification lane and an exploratory lane sharing one environment contract — with every former maturity-ladder item marked shipped, superseded or revisit-when with a measurable trigger, and no unmeasured effort claim,
**so that** the two runtime prompts that cite it as authority point at something true, and the next QA story is argued from a measurement instead of a ladder written before `/verify` existed.

### Problem (read on main `8ec200e`)

- **One commit, April-era content.** `git log -- loomwright/docs/QA_SYSTEM_BLUEPRINT.md` shows exactly one commit (`708ae41`, 2026-07-02, the rebrand carry-over). Its §"Level 1" opens "Included (v10.2.0 — 13-phase protocol, split architecture, topology-aware)". It is 362 lines. The word "verify" appears twice — §"Phase D — Merge, Verify & Gate" and its "Self-verification" bullet — and `/verify` never.
- **Still cited as authority.** `agents/qa-strategist.md` §"Integration Notes", last bullet: "Reference: `docs/QA_SYSTEM_BLUEPRINT.md` — full architecture and maturity levels"; `skills/qa-strategy/SKILL.md` §"See Also", same wording; `docs/ARCHITECTURE.md` §"Key References"; `README.md`'s doc list ("QA system architecture"); `CLAUDE.md` §"References"; the tree listings in `.claude-plugin/README.md` and `docs/command-parts/agent-help/guide.md`; `docs/vendor-coupling-manifest.json` with allowance 1 (the `hook_protocol` token `SubagentStop` at §"Level 4").
- **Nothing mechanical watches it.** `scripts/check-doc-currency.sh`'s `FILES=( … )` block lists `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, the two manifests, `commands/agent-help.md`, `docs/ARCHITECTURE.md`, `docs/ARCHITECTURE_CONTRACTS.md` — not the blueprint.
- **The ladder contradicts settled invariants:**
  - L4 "Supervisor Phase 3.5 QA Gate (post-merge, pre-PR)" and "`--skip-qa` flag for Supervisor": no such phase or flag exists (`grep -rn "skip-qa\|Phase 3.5" loomwright/agents/supervisor.md loomwright/commands/supervisor.md` → 0 hits, 2026-11-09), and it conflicts with CLAUDE.md §"Failure-Mode Invariants" (two review lenses, no per-subtask LLM reviewer) and `verify-walkthrough/00-overview.md` decision V6 "Advisory, never gating".
  - L4 "Plugin hooks (SubagentStop for qa-executor)" **shipped**: `loomwright/hooks/hooks.json` matcher `loomwright:qa-executor` → `validate-qa-result.py`.
  - L5 "Memory schema (structured)" JSON and "Memory decay: Max 200 entries/project" vs the shipped sole-writer: `agents/qa-executor.md` §"Agent memory write permission" (proposals under `.supervisor/agent-memory-proposals/`, the one writer `write-agent-memory.sh` under `--confirm`; commit `fb0ae5a`, 2026-10-27).
  - L5 "Production feedback (batch import from `.qa/production-feedback/`)" and the Key Design Decisions row "Production feedback | Batch import | CLI agent can't monitor production" vs the owner's Studio event-trigger / on-call direction (owner-stated; not yet in a repo doc).
  - "Estimated QA effort eliminated: 60-70%" (L1) and "Estimated: 55-65% / 75-85% / 85% / 90-95%" (L2–L5): unmeasured — `docs/feature-scorecard.json` has no QA or verify row (grep `verify`, `qa_` → 0 hits), and no evidence doc exists.
  - §"Level Transition KPIs" L4→L5 "QA gate runs on 10+ PRs. No false-positive blocks." assumes gating. L1→L2 "L1 tested on 2-3 real repos": one real-repo run is on record (memory `qa-l1-validated-on-sports-management`, cited by `CHANGELOG.md` v15.74.0 and `verify-walkthrough/00-overview.md` V3).
  - §"Environment Control": "URL detection order: playwright.config.ts baseURL -> .env vars -> ask user" — the agent never asks (`needs_human`, `base_url_unresolved`; `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" row "qa-executor URL fallback"). `README.md` §"QA Workflow" repeats "→ ask user".
  - §"Structured Output Blocks" restates `QA_RESULT` and `GRAPHQL_RISK_OVERRIDES`, which `docs/RESULT_SCHEMAS.md` owns (§QA_RESULT, §GRAPHQL_RISK_OVERRIDES; CLAUDE.md: "single source of truth — this file no longer restates them"). `STRATEGIST_VERDICT` is not in `RESULT_SCHEMAS.md` at all; its shape lives in `agents/qa-strategist.md`.
- **The lane the blueprint does not know.** `/verify <ticket>` (`commands/verify.md`; protocol `skills/verify-walkthrough/SKILL.md`: Playwright from Bash, four verdicts, the V7 mutation carve-out, "the plugin never types, stores, or logs a credential", §9 impact pass, §10 `--folder` queue); `verify-run.sh preflight` with the fail-closed `assert-non-prod`; `verify-helpers.sh` (append-only `evidence.jsonl`, derived `summary.md`); `propose-from-verify.sh`; schemas VERIFY_ENV / VERIFY_EVIDENCE / VERIFY_RESULT / VERIFY_QUEUE in `RESULT_SCHEMAS.md`; the README row "Verify (command)". `verify-walkthrough` 01–07 are all `## Status: done`.
- **Market (owner-supplied web research, 2026-11-09):** Devin's QA primitive is "Test the app" after the PR (runs locally, drives the browser, 15–45 s annotated recording on the PR; the feature built, not a regression suite — docs.devin.ai/work-with-devin/testing-and-recordings); Playwright ships planner / generator / healer Test Agents (playwright.dev/docs/test-agents), covering L3's flaky self-healing and much of L1 generation; Momentic, Octomind, QA Wolf and Meticulous own full-suite generation; Cursor's Agent SDK replays real PRs as eval fixtures (cursor.com/docs/agent-sdk/evals); Shiplight ships a Claude Code plugin with a `/verify` skill — a plugin-level competitor. Conclusion: per-change verification with evidence attached to the PR is the market's QA shape; suite-generation depth is not where an orchestration plugin wins.

### Scope

Docs-only. The file is rewritten in place; the heading names below are the ones the acceptance criteria grep for.

- **`## The two lanes`** — the verification lane (`/verify <ticket>`: ticket-scoped, one evidenced verdict per AC, advisory, in-loop per story `04`, environment contract) and the exploratory lane (`/qa-executor`, the Level-1 boundary: discovery, generation, strategist gate audit, on demand; the same environment contract per story `07`). Each lane: entry command, what it reads, what it emits, what it never does. "L1" survives only as the exploratory lane's boundary name (the agent's §"LEVEL 1 BOUNDARIES" is unchanged); L2–L5 as a roadmap are gone.
- **`## Shared parts`** — the environment contract (`.agent/verify.json`, reader / executor / bootstrap), derived counts (never agent-written), the sinks (`propose-from-verify.sh`, `.supervisor/requirements/proposed/`), the scorecard rows `verify_result` / `qa_result` (story `03`), preview-deployment resolution for `/verify` (story `05`), the SubagentStop validator. Anything not yet on main is labelled "planned (qa-evolution NN)".
- **`## Measured next steps`** — a table replacing §"Maturity Levels": one row per former L2–L5 item, columns `former level`, `item`, `status`, `because / revisit when`. Statuses: `shipped`, `superseded`, `revisit-when`. Rows and defaults:
  - L2 State modeling engine — revisit-when: ≥ 2 more real-repo exploratory runs exist AND story `02`'s drafts show the exploratory lane finding bugs the verification lane misses.
  - L2 User-journey generator — revisit-when: same trigger.
  - L2 Fuzz tests — revisit-when: same trigger.
  - L2 Full coverage & gap analysis — revisit-when: same trigger (the 4-tier gap analysis of L1 stays).
  - L2 Full 3-round debate — revisit-when: a measured miss rate of the single-round audit justifies it (`qa_result` row).
  - L3 Security tests (full) — revisit-when: a real-repo run records an auth-boundary bug the L1 probes missed.
  - L3 Performance tests + k6 config — revisit-when: a ticket's AC is a latency or load number the verification lane marks NOT_VERIFIABLE twice.
  - L3 Visual regression + accessibility — revisit-when: a ticket's AC is visual and NOT_VERIFIABLE twice.
  - L3 Flaky analyzer + self-healing — superseded: Playwright's healer Test Agent.
  - L3 Reporting / quality score / release readiness — superseded: the feature scorecard rows and the derived `summary.md`.
  - L4 Supervisor Phase 3.5 QA gate — superseded: advisory in-loop verify (story `04`); nothing gates.
  - L4 Plugin hooks (SubagentStop for qa-executor) — shipped: `hooks.json` → `validate-qa-result.py`.
  - L4 Contract validation (OpenAPI schema comparison) — revisit-when: two real-repo runs discover an OpenAPI document.
  - L4 `--skip-qa` flag — superseded: there is no gate to skip.
  - L5 Production feedback batch import — superseded: Studio event triggers / on-call direction (owner).
  - L5 Test-suite optimisation — revisit-when: a repo accumulates ≥ 30 generated spec files.
  - L5 Risk-model refinement — revisit-when: the strategist's memory store holds ≥ 10 accepted proposals for one project.
  - L5 Agent memory growth / memory schema / memory decay — shipped as the sole-writer proposal flow; the blueprint's own JSON schema and decay rule are superseded by it.
- **`## What is measured`** — replaces §"Level Transition KPIs" and every effort estimate: the scorecard rows `verify_result` and `qa_result` (story `03`, planned), the count of real-repo exploratory runs on record (today: 1), and a named next instrument: a replay eval over past `/verify` runs, listed as revisit-when, not claimed.
- **`## Invariants`** — six, each one line with its source: no new agent (`00-overview.md` V1); Playwright from Bash, no desktop or browser MCP (V1 / skill §"Playwright-from-Bash only"); advisory, never gating (V6; CLAUDE.md §"Failure-Mode Invariants"); counts derived, never written (V5); the plugin never touches credentials (V8; skill §8); mutations only in `--verify` mode after the non-prod assertion passed in this run (V7; skill §4).
- **`## Modules by lane`** — the 14-module list kept, with a `lane / status` column (verification, exploratory, shared, or the next-steps row it maps to). The 4-macro-layer sketch is kept only where a module still exists.
- **`## Governance & Safety Controls`** — kept; the "URL detection order … ask user" line in §"Environment Control" is replaced by today's behaviour (`needs_human`, `base_url_unresolved`) and the planned resolver (story `07`, labelled planned).
- **`## Structured output blocks`** — pointers only: `docs/RESULT_SCHEMAS.md` §QA_RESULT, §VERIFY_RESULT, §GATE_VERDICT, §MISSING_FUNCTIONALITY_REPORT, §GRAPHQL_RISK_OVERRIDES, and `agents/qa-strategist.md` for STRATEGIST_VERDICT. No block is restated.
- **`## Positioning (2026-11)`** — one paragraph: the market shape followed (per-change verification with evidence on the PR), the lane not competed in (full-suite generation), the dated sources above.
- **Runtime references** — `agents/qa-strategist.md` and `skills/qa-strategy/SKILL.md` lines change from "full architecture and maturity levels" to "two-lane architecture and measured next steps"; nothing else in either file changes.
- **`README.md`** — §"QA Workflow": "DETECT URL: … → ask user" becomes "… → needs_human (base_url_unresolved)" and the diagram gains the `/verify` lane as a second column or a second block; §"QA System (Level 1)" is retitled "QA System (two lanes)" with its five bullets kept where true and one added for `/verify`. No count or version sentence is touched.
- **`docs/ARCHITECTURE.md`** — §"QA Pipeline" gains the verification lane (`/verify <ticket> → preflight (assert-non-prod) → qa-executor --verify → VERIFY_RESULT`).
- **`docs/SPIKES/QA_AND_DURABILITY_BACKLOG.md`** — §1 "QA maturity ladder" gets one line: the ladder was replaced by the blueprint's "Measured next steps" (date, pointer). The `## Status: backlog` stanza and §2–§5 are unchanged.
- `changelog.d/qa-blueprint-two-lanes.md` (`patch`).

## Acceptance Criteria

Each check is a command the PR body lists with its output; all run from the repo root.

- [ ] **Two lanes present:** `grep -cE "^## (The two lanes|Shared parts|Measured next steps|What is measured|Invariants|Modules by lane|Governance & Safety Controls|Structured output blocks|Positioning \(2026-11\))$" loomwright/docs/QA_SYSTEM_BLUEPRINT.md` prints `9`; §"The two lanes" names `/verify <ticket>` and `/qa-executor` each with entry, reads, emits and never-does.
- [ ] **Ladder gone:** `grep -cE "^### Level [1-5]|Maturity Levels|Level Transition KPIs" loomwright/docs/QA_SYSTEM_BLUEPRINT.md` prints `0`.
- [ ] **Every former item has a status:** the §"Measured next steps" table has exactly 18 rows (the list in Scope), each with `status` ∈ {`shipped`, `superseded`, `revisit-when`}, and every `revisit-when` row's last column contains a number, a rate or a scorecard row name. The L4 hooks row reads `shipped` and names `hooks.json`.
- [ ] **No unmeasured effort claim:** `grep -ciE "effort eliminated|^\*\*Estimated" loomwright/docs/QA_SYSTEM_BLUEPRINT.md` prints `0`; every remaining `%` in the file is a budget knob (budget zones, vision page share), listed line by line in the PR body with that classification.
- [ ] **KPIs are measurements:** §"What is measured" names `verify_result` and `qa_result` as story `03`'s scorecard rows (labelled planned), states the real-repo run count with its source, and lists the replay eval as revisit-when.
- [ ] **Invariants:** `grep -c` finds each of the six phrases in §"Invariants": `no new agent`, `Playwright from Bash`, `advisory, never gating`, `derived, never written`, `never touches credentials`, `after the non-prod assertion`.
- [ ] **Restated schemas removed:** `grep -cE "^## (QA_RESULT|STRATEGIST_VERDICT)$|^\s*schema_version:" loomwright/docs/QA_SYSTEM_BLUEPRINT.md` prints `0`; `grep -c "RESULT_SCHEMAS.md" loomwright/docs/QA_SYSTEM_BLUEPRINT.md` is ≥ 1.
- [ ] **No "ask user":** `grep -ci "ask user" loomwright/docs/QA_SYSTEM_BLUEPRINT.md README.md` prints `0` for both files.
- [ ] **Planned work is labelled:** every mention of `qa-env-resolve`, `environment_name`, `verify_result`, `qa_result`, preview-deployment resolution or in-loop verify in the blueprint sits on a line containing `planned`; `grep -n` output in the PR body.
- [ ] **Runtime references reworded, budgets green:** `grep -c "maturity levels" loomwright/agents/qa-strategist.md loomwright/skills/qa-strategy/SKILL.md` prints `0` for both; `bash scripts/check-token-budget.sh` passes (the `qa-strategist`, `qa-executor` and `qa-strategy` rows re-baselined to measured + ~10% with their mirror rows only if it trips).
- [ ] **No history reference enters a prompt:** `bash scripts/check-prompt-history-refs.sh` passes with `loomwright/agents/qa-strategist.md` at ≤ 2 and `loomwright/skills/qa-strategy/SKILL.md` at 0.
- [ ] **README and ARCHITECTURE match:** `README.md` §"QA Workflow" shows both lanes and §"QA System (two lanes)" exists; `docs/ARCHITECTURE.md` §"QA Pipeline" names `/verify <ticket>` and `VERIFY_RESULT`; `bash scripts/check-doc-currency.sh` passes.
- [ ] **Spike pointer:** `grep -c "Measured next steps" loomwright/docs/SPIKES/QA_AND_DURABILITY_BACKLOG.md` prints `1`, on a line in §1; the file's `## Status: backlog` stanza is unchanged (`git diff` shows the one added line only).
- [ ] **Vendor coupling does not rise:** `bash scripts/check-vendor-coupling.sh` passes with no allowance change for `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` (count ≤ 1).
- [ ] **Gates:** `bash scripts/ci-local.sh --affected` passes; `bash scripts/check-version-bump.sh` passes with the fragment; no version file is hand-edited.

## Non-goals
- Any code, prompt-behaviour or schema change. `agents/qa-executor.md` (including §"LEVEL 1 BOUNDARIES") is not edited.
- Adding the scorecard rows (story `03`), the in-loop verify (story `04`) or the resolver (story `07`) — described as planned, by number.
- Adding the blueprint to `check-doc-currency.sh`'s scanned set (after the rewrite it carries no version or count claim to scan — PO default below).
- Editing the tree-listing comments in `.claude-plugin/README.md` and `docs/command-parts/agent-help/guide.md` ("QA system architecture" stays true) or `CLAUDE.md` §"References".
- A new `docs/evidence/` file or any CHANGELOG narrative beyond the fragment.
- Deciding the Studio event-trigger design; the blueprint names it as the owner's direction, nothing more.

## Owner decisions
- 2026-11-09 (Vikash, re-validation brief): **Not approved to build — requirements only.** The item passes the owner's test as a documentation hole in shipped code: two runtime prompts cite a document that describes a gate that was never built and a lane-less system.
- 2026-11-09 (Vikash, in the brief): two lanes with shared parts; the ladder replaced by measured next steps with superseded / revisit-when statuses and the triggers given for L2 depth and multi-round debate; every "QA effort eliminated N%" removed; the KPI becomes the scorecard rows and the replay evals; the owner invariants folded in; the 14-module taxonomy and governance table kept where true; runtime references updated only if their wording changes; README and ARCHITECTURE updated; the spike gets a one-line pointer.
- PO default, pending owner review (third status): `shipped` is added beside `superseded` / `revisit-when`, because the L4 SubagentStop hook and the L5 memory flow are on main and would otherwise be misfiled.
- PO default, pending owner review (restated schemas): the `QA_RESULT` / `GRAPHQL_RISK_OVERRIDES` restatements become pointers to `RESULT_SCHEMAS.md` (CLAUDE.md's single-source rule); `STRATEGIST_VERDICT` points at `agents/qa-strategist.md`, where its shape lives today, rather than being added to `RESULT_SCHEMAS.md` (a schema addition is out of a docs-only story).
- PO default, pending owner review (runtime reference wording): "two-lane architecture and measured next steps" — same length class as the old phrase; re-measured only if the budget gate trips.
- PO default, pending owner review (revisit-when triggers not given in the brief): the L3 / L4 / L5 triggers in Scope are the PO's; each is a count the repo can produce.
- PO default, pending owner review (README scope): the §"QA Workflow" diagram and the §"QA System (Level 1)" section are the only README edits; the `/verify` command row already exists and is not touched.
- PO default, pending owner review (doc currency): the blueprint is not added to `check-doc-currency.sh`; a prose doc with no counts has nothing for it to verify.

## Priority: MVP
**Rationale:** docs-only, but the stale doc is cited as authority by two runtime prompts (`agents/qa-strategist.md`, `skills/qa-strategy/SKILL.md`) and by `README.md`, `CLAUDE.md` and `docs/ARCHITECTURE.md`; every later QA story would otherwise argue against a ladder that contradicts CLAUDE.md's invariants.

## Assumptions
- right-size (run 2026-11-09, `bash loomwright/scripts/automate-helpers.sh right-size <file>`, defaults small ≤ 3 / large > 30): `qa-evolution/08-the-qa-blueprint-describes-the-two-lane-qa-system: ok (9 files, 14 scope items, 15 criteria)`.
- `qa-strategy` is preloaded by both `qa-strategist` and `qa-executor` (frontmatter `skills:`), so its one-line reword moves three budget rows; headroom today: `qa-strategy` 5444 / 5989, `qa-strategist` 22017 / 24219, `qa-executor` 48483 / 53332 (`docs/prompt-token-budgets.json`). A same-length phrase fits.
- `.agent/companions.json` adds `prompt-token-budgets.json` and `ARCHITECTURE_CONTRACTS.md` for any `loomwright/agents/*.md` edit; both are listed below anyway.
- `scripts/check-vendor-coupling.sh` "never requires exact equality" (its header): dropping the `SubagentStop` mention pays down the blueprint's allowance of 1; keeping it is also fine. Adding any token of the manifest's classes would breach.
- `check-doc-currency.sh` scans `README.md` and `docs/ARCHITECTURE.md` for version and count claims; the edits here touch neither kind of sentence.
- Shared files with siblings (read from their `## Touches` on 2026-11-09): `docs/QA_SYSTEM_BLUEPRINT.md` is also edited by `04` (one line in §"Level 4" saying QA-in-loop lands as `/automate`'s advisory verify pass); `ARCHITECTURE_CONTRACTS.md` and `prompt-token-budgets.json` by `01`, `03`, `04`, `05`, `07`. If a sibling's number or slug changes, the blueprint's "planned (qa-evolution NN)" labels follow it.
- One real-repo exploratory run is on record (sports-management); no other is.

## Dependencies
- Depends on: none. It describes `03-the-qa-lane-earns-its-cost-on-the-feature-scorecard.md`, `04-verify-runs-inside-the-delivery-loop-in-shadow.md`, `05-verify-can-target-a-pull-requests-preview-deployment.md` and `07-exploratory-qa-runs-under-the-verify-environment-contract.md` as planned, by filename, without requiring them.
- Blocks: nothing. Later QA stories cite it instead of the ladder.

## Risks
- **Planned reads as shipped.** Mitigation: the "labelled planned" AC; the `## Status` of each sibling story is the truth, not the blueprint.
- **The reworded skill line shifts two agent budgets.** Mitigation: same-length phrase; re-baseline rule in the AC.
- **A README diagram edit trips doc-currency** if a count sentence is touched. Mitigation: the AC confines the edit to the diagram and one section; `check-doc-currency.sh` is in Validation.
- **Owner's market conclusion ages.** Mitigation: the paragraph is dated and sourced; "Positioning (2026-11)" carries its date in the heading.
- **Story `04` adds one line to the blueprint's §"Level 4", which this rewrite removes.** Whichever lands second re-homes that sentence to the "L4 Supervisor Phase 3.5 QA gate" row of §"Measured next steps" (its `because` column already says the same thing). No dependency either way.
- **Five sibling stories touch `ARCHITECTURE_CONTRACTS.md` and `prompt-token-budgets.json`** (`01`, `03`, `04`, `05`, `07`). They serialise in a wave; none blocks another.

## Validation (must pass before merge)
1. **Static — doc currency:** `bash scripts/check-doc-currency.sh` passes.
2. **Static — prompt history refs:** `bash scripts/check-prompt-history-refs.sh` passes with no baseline raise for `loomwright/agents/qa-strategist.md` or `loomwright/skills/qa-strategy/SKILL.md`.
3. **Static — budgets and coupling:** `bash scripts/check-token-budget.sh` and `bash scripts/check-vendor-coupling.sh` pass, with no blueprint allowance raise.
4. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes; `bash scripts/check-version-bump.sh` passes with `changelog.d/qa-blueprint-two-lanes.md`.
5. **Static — the grep checks:** every `grep` in Acceptance Criteria is run from the repo root and its output pasted in the PR body.

## Depends on
none

## Touches
loomwright/docs/QA_SYSTEM_BLUEPRINT.md
loomwright/docs/SPIKES/QA_AND_DURABILITY_BACKLOG.md
loomwright/docs/ARCHITECTURE.md
README.md
loomwright/agents/qa-strategist.md
loomwright/skills/qa-strategy/SKILL.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/qa-blueprint-two-lanes.md
