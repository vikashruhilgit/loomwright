# Supervisor Job: Archive views — the accumulated judgement, made browsable

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-09-03; its "Latest change" paragraph describes the `/setup ui` release this brief extends)
- **Git:** branch `main` @ `8aa70b0` == `origin/main` (PR #176 merged 10:49Z, verified with `git merge-base --is-ancestor`). **One modified tracked file: `.supervisor/postmortem/results.jsonl`.** It is a TRACKED file (`git check-ignore` reports NOT ignored, `git ls-files .supervisor/` lists it) even though most of `.supervisor/` is gitignored — the engine's `learning-emit` appends to it every tick. It is NOT part of this work: do not stage it, do not revert it, and do not let a `git add -A` sweep it into a commit.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 — `git worktree list` shows 5 entries under `.claude/worktrees/` (Claude Code's own isolation worktrees, three detached, none a Supervisor worktree; harmless under a `--sequential` run, which creates none)
- **Source requirement:** `.supervisor/requirements/loom-floor-ui/05-archive-views.md` (amended at intake 2026-09-03 — see the note under `## Problem` and the measurement appended to the second AC; the numbers below were measured here, not copied from the requirement)

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Same surfaces as items 03/04: bash 3.2 + `jq` for the projector, framework-free HTML/CSS/JS for the bundle. No new dependency, no bundler, no Node. |
| 2 | Dependency Availability | GO | Every input already exists on disk and is already COUNTED by the projector: `rules` (2 category files), `postmortem` (89 lines), `drain_rounds` (519), `worker_summaries` (117). This item adds `detail` to two of them; it adds no store, no emitter and no new input. |
| 3 | Architecture Fit | GO | `add_surface` already takes a `detail_json` argument and three surfaces already use it (`agents.roster`, `sessions.current`, `state.subtasks`). Extending `rules` and `postmortem` the same way is the established additive pattern, not a new mechanism. `schema_version` stays 1. |
| 4 | Scope vs Supervisor Capability | CAUTION | Three scope items across three distinct surfaces (projector · bundle · handoff), touching files that are already large (`build-floor.sh` 659 lines, `test-build-floor.sh` 1860, `floor.js` 533, `test-setup-ui.sh` 1456). ⇒ `context-bound` split into 3 strictly sequential subtasks. Precedent: item 04's worker hit its 40-turn limit and was resumed via SendMessage rather than respawned — expect the same and do the same. |
| 5 | Hard Blockers | CAUTION | Two measured data facts make naive readings of the ACs wrong; both are pinned into ACs below rather than left for a reviewer to find. (a) The rules store holds **3 rules in 2 category files**, and **zero** of them carry `supersedes` — so the supersedes half of any check is fixture-only or it is vacuous. (b) The postmortem ledger carries **two different flow-stage representations that disagree on 26 of 89 lines** — see AC-churn-basis. |

**Overall Verdict:** CAUTION (two findings carried into Risk Assessment)

## Task

**Goal:** Add three read-only views over the existing `floor.json` contract — a rules browser, a churn view over the postmortem ledger, and an opt-in publish path for `/handoff`'s digest — extending the surfaces items 03 and 04 built rather than adding any new store, ledger or emitter.

**Problem Statement:**
Item 04 answers "what is happening now". The larger asset is what the system has already *learned*, and it is readable today only by opening files: the committed `.agent/rules/` store is machine-readable and human-hostile (ids are long slugs derived verbatim from the statement text), and `.supervisor/postmortem/results.jsonl` is the single best record of *why* this system produces churn with nothing displaying it. `/insights` aggregates some of this into rates and `/obsidian` links it for reading; neither lets you ask "which rule keeps getting violated" or "what class of finding dominates our review rounds" — the questions that would actually change how the system is run. Success looks like: the projector carries the rules and churn detail honestly (omitting what it cannot read rather than defaulting it), the served page renders both as browsable views that never present a correlation as a score, and `/handoff` can publish its existing digest as a shareable snapshot without its default output changing by a single byte.

## Measured facts this brief is built on

Every number below was measured on this checkout at intake on 2026-09-03. They are **dated evidence, not a spec**: the source requirement deliberately refuses to pin live-store counts because the loop that reads it appends to those same stores (`results.jsonl` is modified in the working tree right now). **No AC keys off any live count** — every check is fixture-based — so a drifted number here falsifies a claim in this table and nothing else. They are recorded so the worker does not re-derive them and so a reviewer can falsify them.

| Fact | Measured value | How |
|---|---|---|
| Rules store shape | one JSON **array** per category file, not an object with a `rules` key | `jq 'keys'` returns `[0]`; `jq '.rules'` errors |
| Rules total | **3** rules across **2** category files (`documentation.json` 1, `process.json` 2) | `jq 'length'` per file |
| Rule field set (union) | `applies_to, category, check, enforcement, id, provenance, statement` | `jq -s 'add\|map(keys)\|add\|unique'` |
| Rules carrying `supersedes` | **0** | field absent from the union above |
| Rules with `applies_to: null` | **1** (a `process` rule) — the key is PRESENT with value `null` | `jq '.[]\|{applies_to}'` |
| Postmortem lines | **89** | `wc -l` |
| Lines with non-empty `categories` | **82** of 89 | `jq -s` select |
| Root-cause classes | `convention_mismatch` 107, `quality_gap` 46, `execution_bug` 36, `drain_churn` 31, `missing_context` 5, `plan_gap` 3, `scope_too_large` 2 | `jq -r '.categories[]?.class' \| sort \| uniq -c` |
| Category object key set | `class, evidence, flow_stage, round, self_heal_miss` | `jq -s` union |
| Category objects carrying `evidence` | **230 of 230** — every one | `jq` select non-null |
| Per-category `flow_stage` totals | `self_heal` 118, `worker` 88, `unknowable` 19, `launch_pad` 5 | `jq -r '.categories[]?.flow_stage'` |
| **Counter-vs-category disagreement** | **26 of 89 lines** — ALL of them `source: "automate_drain"` (26 of that source's 33); **0** on `manual_postmortem` (10) and **0** on source-absent (46) | compare `.flow_stages` against a `reduce` over `.categories[].flow_stage` |
| Projector surfaces today | 14, of which `agents`, `sessions`, `state` carry `detail`; `rules` and `postmortem` carry `count` only | `jq -r '.surfaces\|to_entries[]'` on a fresh `build-floor.sh` run |

## Acceptance Criteria

### Projector (subtask 1)

- [ ] **AC-rules-detail:** Given a fixture `.agent/rules/` directory seeded into the test fixture (never the real one — see AC-suite-hermetic), when `build-floor.sh` runs, then `surfaces.rules` keeps its existing `status`/`count` semantics and gains a `detail.rules` array — **built in a shell variable named exactly `rules_detail`**, matching this script's abbreviated local convention (`st_detail`, `sess_detail`, `agents_detail`), because the `outputs_verified` gate is self-reported against these literal names — in a deterministic order, each element carrying `id`, `category`, `statement`, `enforcement`, `provenance` and — **only when present in the source** — `applies_to`, `check` and `supersedes`. A field absent from the source is **OMITTED** from the row, never defaulted. `applies_to` is a genuine **tri-state** and all three states are distinguishable in the output: the key **absent**, the key present with value **`null`**, and a **non-empty array**. The fixture MUST contain one rule of each of those three shapes, because the live store today has only the middle one (measured: 1 rule with `applies_to: null`, 0 with the key absent among the 3). **`check` gets the identical three-shape treatment for the identical reason:** all **3** live rules carry `check: null` — present-with-null — and `read-rules.sh` types it `check (string | null)`. A worker emitting `check` only when truthy would collapse "declared, deliberately no runnable check" into "absent", which is the nullable-required-field defect this repo already recorded against this very field. The `check` string is emitted as DATA and is NEVER executed, matching `read-rules.sh`'s pinned rule. `count` continues to mean **category files** (2 today), not rules — if the detail array's length is also exposed it is a separate, differently-named field, because silently redefining `count` would change a number three other surfaces already publish under the same name.
- [ ] **AC-rules-supersedes (deliberate divergence — read this before conforming):** Given a fixture rule carrying `supersedes` that names another fixture rule's `id`, the projector detail preserves the pointer and the chain is resolvable **in order, transitively**; given a `supersedes` naming an id that does not exist in the merged set, the row is emitted and the dangling pointer is **reported as dangling**. **This deliberately DIVERGES from `read-rules.sh`, and the divergence must be stated in the code comment and the schema doc rather than discovered by a reviewer.** That reader's `SUPERSESSION` header block is marked *"normative encoding contract — PINNED, do not redesign"* and specifies the opposite on all three points: a live `supersedes` **HIDES** the rule it names, resolution is **"single-hop only, NEVER transitive/chased"**, and a dangling target is **"a no-op: the field is IGNORED and the CARRYING entry is still emitted normally"**. Those semantics are correct for a *routing* reader answering "which rules apply to this diff"; they are wrong for a *browser* whose whole purpose is to show the curation history including what was retired and what points nowhere. **Reuse `read-rules.sh`'s FIELD SCHEMA only** (`supersedes` is an optional non-null string, never self-referential) — do **not** inherit its hide/single-hop/ignore-dangling routing behaviour, and do not modify `read-rules.sh`. **But DO inherit its termination property, which is not optional here:** dropping single-hop for a transitive walk drops the very thing that made the traversal safe. `read-rules.sh` documents cycles in this exact field as a **real, found defect** (its `CYCLE DETECTION IS GENERAL, NOT PAIRWISE-ONLY` block, a bot-review HIGH-1 fix covering cycles of ANY length, not just mutual pairs) and states its safety comes from *"a single BOUNDED, non-recursive pass (a fixed `range(0; edge_count)` walk per node — never an open-ended/recursive graph traversal), so an arbitrarily malformed / cyclic `supersedes` graph can never loop or hang the reader"*. `build-floor.sh` runs against the **real store**, so an unbounded walk here is fail-UNSAFE, not merely a fixture gap. The chain walk MUST therefore be **bounded by the total edge count** in the same non-recursive construction, and a **cycle fixture** (an A→B→C→A chain) is REQUIRED, with assertions that the projector terminates, reports the cycle as a cycle, and emits every member rather than dropping any. **This half is fixture-only by measurement:** the live store carries `supersedes` on **zero** of its three rules, so a check written against the real store alone would go silently green.
- [ ] **AC-rules-unparseable:** Given a fixture `.agent/rules/` containing one file that is not valid JSON and one that is, `surfaces.rules` names the unparseable file and its reason, still reports the valid file's rules, and its status distinguishes "read some, could not read others" from both "read everything" and "read nothing". The unparseable file is never silently skipped and never counted as clean — the requirement's phrasing is that "could not examine" must be displayed as such and never as "examined and clean". Pinned by a **mutation control**: revert the reporting branch and show the assertion going red, because a test that only ever sees well-formed fixtures cannot tell the two apart.
- [ ] **AC-churn-detail:** Given a fixture ledger, `surfaces.postmortem` keeps its existing `status`/`count` (count = **valid lines**, as today) and gains a `detail` — **built in a shell variable named exactly `pm_detail`**, following this surface's existing `pm_basis` / `pm_ok` / `pm_bad` prefix, NOT `postmortem_detail` — carrying the distribution by root-cause class and by flow stage, plus the per-category `evidence` string that each entry was derived from. Malformed lines are counted and named as malformed, never folded into a class. No rate, score, ranking or ordering-by-desirability is emitted — the distribution is the value, and a total is not a rate.
- [ ] **AC-churn-basis (the finding this item exists to not repeat):** The ledger carries **two** flow-stage representations that do **not** agree: a per-line `flow_stages` counter object `{launch_pad, worker, self_heal, unknowable}`, and one `flow_stage` per element of `categories[]`. Measured on this checkout they disagree on **26 of 89 lines, every one of them `source: "automate_drain"`** (0 of 10 `manual_postmortem`, 0 of 46 source-absent) — because `learning-emit` derives the counter from `fix_cycles` while emitting a single category object. **The basis is PINNED, not a worker choice: it MUST be `.categories[].flow_stage`.** The reason is denominator coherence, and it is forced by the neighbouring AC rather than by taste — AC-churn-detail requires the per-category `evidence` string, and `evidence` is a field ON the category object, so the class distribution is necessarily computed over the **230 category objects**. Picking `.flow_stages` for the flow-stage half would publish, inside one `detail` object, a class distribution with denominator 230 and a flow-stage distribution whose denominator on `automate_drain` lines is `fix_cycles` (up to 7) against a single category object — two different denominators side by side in the one view whose entire premise is honest basis. The projector MUST also **emit the basis as a literal named field, `flow_stage_basis`, whose value is the exact string `.categories[].flow_stage`** (that literal, not a variant — not `categories[].flow_stage`, not `.categories[]?.flow_stage`), and the schema block MUST document that the two representations exist and disagree. Emitting a flow-stage number whose basis is undocumented is the "a recorded value rendered as if it were the only value" class that items 03 and 04 both hit. A test asserts the chosen basis on a fixture containing at least one disagreeing line, and asserts the basis field is present in the output.
- [ ] **AC-correlation-evidence:** Where a rule and the churn ledger are correlated, the correlation is emitted **with the evidence it was derived from** and is labelled an observation, not a measurement. No correlation is emitted as a rate, score, ranking, or "top N". If the projector cannot establish a correlation for a rule it omits it rather than emitting zero — a zero here reads as "measured no violations" when the truth is "no correlation was computable", which is the fabricated-zero defect PR #174 already fixed once in this same script.
- [ ] **AC-suite-hermetic (the premise here is narrower than it looks — do not add an env seam):** Every new assertion runs against a fixture. **`rules` and `postmortem` are ALREADY hermetic and need no injection**: `run_build()` is `( cd "$1" && FLOOR_AGENTS_DIR="$1/agents" bash "$BUILD" )` — it `cd`s into the fixture — and `build-floor.sh` reads `.agent/rules` and `.supervisor/postmortem/results.jsonl` as **cwd-relative** paths, which is why `EXP_RULES=2` already works through the fixture today. `FLOOR_AGENTS_DIR` exists **only** because the agents directory resolves from `$0`/the install path, and the comment above `run_build` says exactly that. **Do NOT add a `FLOOR_RULES_DIR`/`FLOOR_POSTMORTEM` override** — it would be a redundant seam. What IS required: seed the new fixture data under the fixture cwd, and assert that the **EMPTY** fixture still yields `absent` for both surfaces so `test-build-floor.sh`'s existing anti-vacuity control ("no section on the empty fixture reaches status counted") stays green. The existing suite passes unchanged, and its fixed surface-list and count literals move together if the surface set changes.
- [ ] **AC-schema-additive:** The `## FLOOR_PROJECTION` block in `loomwright/docs/RESULT_SCHEMAS.md` documents the new optional `detail` sub-keys for `rules` and `postmortem` as annotated YAML lines marked optional, and documents the two-flow-stage-representation caveat from AC-churn-basis. `schema_version` stays **1** (additive, optional). The per-schema Version History gains a dated entry — every other additive-without-a-bump change there carries one, and its omission was a real review finding on PR #176. **Case (h)'s detail-sub-key check is a HARD-CODED list — `for k in roster current subtasks` at `test-build-floor.sh` (the `missing_detail` loop) — so new sub-keys fall outside it and can ship undocumented behind a fully green (h).** (The comment above that loop explains something else — that the six-space lines are invisible to the two- and four-space parsers — so it is NOT evidence for this gap; the gap is a property of the loop's literal list, which is the only thing cited here.) Subtask 1 MUST extend that loop with the new sub-key names, pinned by a **mutation control** that removes a name from the schema block and shows the assertion going red. Case (h) also still parses the required-key set out of the block and still rejects each required key by name; determinism, the single wall-clock read and containment all still pass.

### Bundle (subtask 2)

- [ ] **AC-views-render:** Given committed fixtures, the served page renders a **rules browser** (grouped by category and by `applies_to` path, showing statement, provenance and any supersedes chain) and a **churn view** (distribution by root-cause class and by flow stage). Both are read from the projection only. Each view states the basis of its numbers, including the flow-stage basis from AC-churn-basis. **Static half (CI):** `test-setup-ui.sh` asserts the required literals and structure in the bundle. **Browser half (Phase 4.5):** the Supervisor loads the served fixtures in a real browser, reads the **DOM** (not a screenshot), reads the **console**, and records the values in a `## Browser verification` block in the PR body — one line per browser-verified AC. On a non-interactive run these halves are recorded **UNVERIFIED**, never as passed.
- [ ] **AC-views-four-states:** Each new view distinguishes the same four states item 04 established, and they stay four distinct renders: **absent** (the surface is not in the projection), **empty** (present and counted with nothing in it), **unavailable** (present but the projector named a reason it could not read it), and **stale** (the projection itself is older than the freshness threshold). Never a blank region, never a spinner, never a console error, and never an em-dash standing in for a value the projection actually recorded. In particular an unparseable rules file (AC-rules-unparseable) renders as "could not examine", visibly distinct from "examined and clean".
- [ ] **AC-no-scoring:** No view ranks, scores, sorts-by-desirability, or presents a correlation as a rate. Where a correlation is shown its evidence is shown with it. Asserted statically (the bundle contains no ranking/scoring construct over rules) and confirmed in the browser half. This is a requirement-level Non-goal — "a view that ranks rules becomes a view that retires them" — not a style preference.
- [ ] **AC-still-read-only:** The bundle gains **no** new endpoint and **no** write path. **Measured: there is NO existing `POST`/`PUT`/`DELETE` assertion — the token count is 0 in `test-setup-ui.sh` and 0 across all three bundle files — so this AC must CREATE that assertion, not inherit it** (a clause saying an absent check "still passes" is tickable with zero work). The read-only posture is genuinely guarded today by two other mechanisms, and both must keep passing: the egress scanner over all three files with its mutation control, and the single-fetch literal `fetch('floor.json', { cache: 'no-store' })`. The egress scan (all three bundle files, with its mutation control) still passes: no `http://`, `https://`, protocol-relative `//`, `@import`, `preconnect`, or non-`data:` `url(`. The single-timer budget from item 04 is **unchanged** — still exactly ONE `setInterval` in the bundle, asserted by **occurrence count** (a grep for the string passes on a page full of them), with the mutation control that adds a second timer still red. New views must not add a timer.
- [ ] **AC-motion-a11y-theme-preserved:** The new views honour the existing `@media (prefers-reduced-motion: reduce)` block, are legible without colour, and render correctly in both themes under the established `:root` / `prefers-color-scheme` / `[data-theme]` token scheme. Browser-verified in both themes.

### Handoff publish (subtask 3)

- [ ] **AC-handoff-byte-identical:** `/handoff`'s existing default output is **byte-identical** before and after this change, proven by capturing real output from the pre-change script and `diff`-ing it against post-change output on the same inputs — not by inspection and not by asserting the flag is "additive". The publish path is reachable **only** via an explicit opt-in flag; absent that flag, no new code path executes.
- [ ] **AC-handoff-publish:** With the opt-in flag, `build-handoff.sh` emits its existing digest as a shareable snapshot carrying what shipped, what was decided, what was tried and rejected, with provenance and freshness. It is a **snapshot, not live** — it states the time it was generated and does not poll. `commands/handoff.md` documents the flag; the agent/command mirror is updated in the SAME commit (mirror drift passes every gate and is caught only by a consistency audit).
- [ ] **AC-no-writes:** No view and no publish path writes to `.agent/`, `.supervisor/postmortem/`, or any other store. Asserted by **hashing the trees with `find` before and after** a full exercise of every new path — the item-04 residue precedent — with an **anti-vacuity check that the exercise actually ran**, since a containment assertion also passes when nothing happened at all. The one permitted write (the projector's own `.supervisor/floor/floor.json`) is named explicitly and scoped, and the exercise runs with the working directory inside a fixture git repo so that write lands there, not in this checkout.

### Release surface (subtask 3)

- [ ] **AC-version-lockstep:** `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` bump in lockstep with the `vX.Y.Z` inside each `description` updated **in place** (no appended version clause); `CHANGELOG.md` gains the top entry; `CLAUDE.md`'s "Latest change" paragraph is REPLACED with a **version-free, count-free** summary. Agent/command/skill/hook counts are unchanged unless a file was actually added — measure them from the directories and `hooks.json`, never restate them from memory.
- [ ] **AC-ratchet-measured:** `bash scripts/check-vendor-coupling.sh --print-allowances` is run **after `git add`** of every new file, the delta versus the manifest is recorded whatever it is, and `loomwright/docs/vendor-coupling-manifest.json` declares the **measured** allowance for every path that moved — never hand-typed. Current allowances for paths in scope, all four verified against the manifest: `build-handoff.sh` **5**, `test-build-handoff.sh` **11**, `setup-ui.sh` **3**, `FLOOR_UI.md` **4** — **plus `loomwright/docs/RESULT_SCHEMAS.md` at 3**, which subtask 1 modifies and which an earlier draft of this brief omitted. Word any addition there to DESCRIBE a vendor token rather than quote it, so the allowance does not self-raise. A number that appears in more than one place (the PR body, the manifest note, the CHANGELOG) must be the same number in all of them — the allowance drifting onto a fourth surface cost PR #176 three separate review rounds.
- [ ] **AC-suite-green:** Every `loomwright/scripts/test-*.sh` exits 0 locally (the CI hard-gate loop) and **all SEVEN** repo gates under `scripts/check-*.sh` exit 0 — measured, and named so none is silently skipped: `check-command-sync.sh`, `check-contract-parity.sh`, `check-doc-currency.sh`, `check-shared-prefix.sh`, `check-skills-index-sync.sh`, `check-token-budget.sh`, `check-vendor-coupling.sh`.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Projector: `rules` + `postmortem` detail, flow-stage basis named, hermetic fixtures | 3 modify, ~4 create | LAUNCHABLE |
| 2 | Bundle: rules browser + churn view, four states preserved, still read-only | 4 modify, ~3 create | BLOCKED — needs 1 |
| 3 | Handoff publish + release surface | 3 modify + release surfaces | BLOCKED — ordering after 1 and 2 (`ordering_after`, NOT artifact consumption: `build-handoff.sh` consumes nothing 1 or 2 produce, so its `requires` is deliberately empty rather than carrying fabricated entries) |

- **Split reason:** `context-bound`

### Subtask 1 — Projector extension (LAUNCHABLE)

Files:
- modify `loomwright/scripts/build-floor.sh` — extend the `rules` and `postmortem` surfaces with `detail` via the existing `add_surface` `detail_json` argument. Emit `flow_stage_basis` as a literal field. Both surfaces stay cwd-relative (no new env override — see AC-suite-hermetic).
- modify `loomwright/scripts/test-build-floor.sh` — new cases for rules detail / tri-state `applies_to` and `check` / supersedes chain + dangling / unparseable-file reporting (with its mutation control) / churn detail / `flow_stage_basis` presence and value / correlation-evidence; **extend case (h)'s hard-coded `for k in roster current subtasks` loop** with the new sub-key names plus a mutation control. Baseline measured by execution on `main` @ `8aa70b0`: **265 passed, 0 failed, 0 skipped** — every one of those keeps passing.
- modify `loomwright/docs/RESULT_SCHEMAS.md` — document the new optional `detail` sub-keys for `rules` and `postmortem`, the `flow_stage_basis` field, and the two-flow-stage-representation caveat; add the dated `### Version History` entry (that section already carries two FLOOR_PROJECTION entries — follow their shape). `schema_version` stays 1. This file is COUPLED with allowance **3**: describe any vendor token, never quote it.
- create fixtures under `loomwright/scripts/fixtures/` — a `.agent/rules/` fixture tree carrying one rule with `applies_to` ABSENT, one with `applies_to: null`, one with a non-empty array, the same three shapes for `check`, a `supersedes` chain, a dangling `supersedes`, a **cycle** (A→B→C→A, per AC-rules-supersedes), and one file that is not valid JSON; plus a postmortem ledger fixture containing at least one line where `.flow_stages` disagrees with a reduce over `.categories[].flow_stage`.

```yaml
# Subtask 1 — projector extension (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "flow_stage_basis"}
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "rules_detail"}   # pinned by AC-rules-detail
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "pm_detail"}   # pinned by AC-churn-detail
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "flow_stage_basis"}
  - {kind: "symbol", path: "loomwright/scripts/test-build-floor.sh", name: "EXP_RULES_DETAIL"}
requires: []
lanes:
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/fixtures/*"
external_requires: []
```

### Subtask 2 — Bundle views (BLOCKED by #1)

Files:
- modify `loomwright/scripts/floor-ui/index.html`, `floor.css`, `floor.js` — the rules browser and churn view, reading ONLY the projection fields subtask 1 emits. Each view prints its basis, including the `flow_stage_basis` value read from the projection rather than restated as a literal. No new timer (the single-`setInterval` budget is unchanged), no new fetch, no new endpoint.
- modify `loomwright/scripts/test-setup-ui.sh` — static halves for both views, the four-state renders, the no-scoring assertion, and the **newly created** no-`POST`/`PUT`/`DELETE` assertion. Baseline measured by execution on `main` @ `8aa70b0`: **119 passed, 0 failed, 0 skipped**.
- create `loomwright/scripts/fixtures/floor-ui/` fixtures for the new views — including an absent-surface case, an empty-but-counted case, an unavailable/unparseable case, and a stale case, so all four renders are exercised.

```yaml
# Subtask 2 — bundle views (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.js", name: "renderRules"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.js", name: "renderChurn"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "no_write_verbs"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "flow_stage_basis"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "rules_detail"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "pm_detail"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "flow_stage_basis"}
lanes:
  - "loomwright/scripts/floor-ui/*"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/scripts/fixtures/floor-ui/*"
external_requires: []
```

### Subtask 3 — Handoff publish + release surface (runs LAST; ordering, not consumption)

Files:
- modify `loomwright/scripts/build-handoff.sh` (allowance **5**) — the opt-in publish flag only; the default path must not change by a byte.
- modify `loomwright/scripts/test-build-handoff.sh` (allowance **11**) — the byte-identical diff proof and the publish-path cases.
- modify `loomwright/commands/handoff.md` — document the flag in the SAME commit (mirror drift passes every gate and is caught only by a consistency audit).
- release surfaces: `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (version in place), `CHANGELOG.md` (top entry incl. the measured ratchet delta), `CLAUDE.md` (Latest-change paragraph, version-free and count-free), `loomwright/docs/vendor-coupling-manifest.json` (measured allowances only).

```yaml
# Subtask 3 — handoff publish + release surface (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "loomwright/scripts/build-handoff.sh", name: "publish"}
  - {kind: "symbol", path: "loomwright/commands/handoff.md", name: "publish"}
  - {kind: "symbol", path: "loomwright/scripts/test-build-handoff.sh", name: "default_byte_identical"}
  - {kind: "symbol", path: "loomwright/scripts/test-build-handoff.sh", name: "publish"}   # measured 0 occurrences on main; the manifest key "build-handoff.sh" is NOT usable here — it already exists at vendor-coupling-manifest.json:73, so a grep-based gate would pass with zero work done
requires: []
# ORDERING (not consumption): subtask 3 runs LAST. `build-handoff.sh` consumes nothing
# subtasks 1 and 2 produce - the dependency is that the release surface must DESCRIBE what
# 1 and 2 actually shipped, and the CHANGELOG/CLAUDE.md entries cannot be written before
# then. Expressed as a note rather than as fabricated `requires` entries, which would claim
# an artifact consumption that does not exist.
ordering_after: ["1", "2"]
lanes:
  - "loomwright/scripts/build-handoff.sh"
  - "loomwright/scripts/test-build-handoff.sh"
  - "loomwright/commands/handoff.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires: []
```

## Parallelism Analysis

sequential (no fan-out — every subtask after the first is BLOCKED)

- **Recommended workers:** 1
- **Mode:** single-agent, strictly sequential

File-overlap matrix (derived from the three `lanes:` blocks above — the reason no two subtasks may run concurrently is *ordering*, not lane collision):

| Subtask | Lanes | Overlaps | Blocked by |
|---|---|---|---|
| 1 | `build-floor.sh`, `test-build-floor.sh`, `RESULT_SCHEMAS.md`, `fixtures/*` | with 2 only under `fixtures/` (1 seeds `fixtures/`, 2 seeds `fixtures/floor-ui/`; disjoint subtrees, and they are transitively ordered anyway) | — (LAUNCHABLE) |
| 2 | `floor-ui/*`, `test-setup-ui.sh`, `fixtures/floor-ui/*` | none with 3 | 1 |
| 3 | `build-handoff.sh`, `test-build-handoff.sh`, `commands/handoff.md`, both manifests, `CHANGELOG.md`, `CLAUDE.md`, `vendor-coupling-manifest.json` | none | ordering after 1, 2 |

No lane is shared between two subtasks that could otherwise run at the same time, so the serialization is imposed by the dependency chain (2 consumes 1's projector fields; 3 must describe what 1 and 2 shipped), not by write contention.

## Skill References

| Subtask | Skills | Why |
|---|---|---|
| 1 | `skills/quality-checklist`, `skills/unit-testing` | The projector is bash + `jq` with a 265-assertion suite; the gates that matter here are mutation controls and anti-vacuity, both of which the quality checklist enumerates. |
| 2 | `skills/frontend-ui` (scoped to the WCAG 2.1 AA / accessibility rules ONLY — there is no React/Vue/design-system in this bundle, so the component-reuse half does not apply), `skills/quality-checklist` | The new views must stay legible without colour and honour the existing reduced-motion block. |
| 3 | `skills/supervisor-readiness`, `skills/commit`, `skills/quality-checklist` | The release surface is the version-lockstep + ratchet-measurement discipline this repo enforces across ~8 doc surfaces. |

All three subtasks additionally inherit the Shared Agent Contract and the repo-wide conventions in `AGENT_GUIDELINES.md` and `CLAUDE.md`; `skills/context-setup` applies at each subtask's start.

## Configuration

- **Split reason:** context-bound
- **Mode:** single-agent, strictly sequential
- **Recommended workers:** 1
- **Execution:** `--sequential` (Single-Agent Path, no worktrees)
- **Base branch:** `main`
- **Base commit:** `8aa70b0`

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| A check written against the real `.agent/rules/` or real ledger passes vacuously | HIGH | Feasibility (Phase 2.5) #5 | Fixture-inject both paths the way `FLOOR_AGENTS_DIR` already is (AC-suite-hermetic); the empty fixture must still yield `absent`, keeping the existing anti-vacuity control green. The supersedes half is fixture-only **by measurement** — 0 of 3 live rules carry it. |
| The churn view publishes a flow-stage number whose basis is undocumented | HIGH | Measured at intake | AC-churn-basis: pick one basis, name it in the output, document the disagreement in the schema, and test against a fixture containing a disagreeing line. Measured disagreement is 26/89, all `automate_drain`. |
| A correlation is read as measured causation | MEDIUM | Requirement Non-goal | AC-correlation-evidence: evidence travels with every correlation; nothing is ranked or scored; an uncomputable correlation is omitted, never emitted as zero. |
| Worker exhausts its turn limit mid-subtask | MEDIUM | Feasibility #4 | Three sequential subtasks; on turn exhaustion **resume via SendMessage to the returned agentId**, never respawn — the item-04 precedent. |
| `/handoff`'s default output changes by accident | MEDIUM | Requirement AC | AC-handoff-byte-identical: capture real pre-change output and `diff` it, rather than reasoning that the flag is additive. |
| A `git add -A` sweeps the uncommitted `results.jsonl` into the PR | MEDIUM | Environment | It is TRACKED and currently modified by the engine. Stage explicitly by path; never `git add -A`/`-u` from the repo root. |
| A count claim drifts across surfaces | LOW | PR #176 history | The same number must read the same in the manifest, its note, the PR body and the CHANGELOG; measure once, then verify each surface. |

## Handoff

/supervisor job: .supervisor/jobs/pending/2026-09-03-archive-views.md

## Outcomes Rubric

- The system's accumulated judgement is browsable by the questions worth asking of it.
- Nothing is scored, ranked, or auto-curated; every correlation shows its evidence.
- Unparseable input is named, never silently treated as clean.
- Strictly additive: existing outputs and stores are provably untouched.

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/177
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** vcs merge commit d81e826 on origin/main — subject [Merge pull request #177 from vikashruhilgit/feature/archive-views] — attributed by branch-slug match, committed on/after the brief date; git refs on disk only, no fetch, no forge call (https://github.com/vikashruhilgit/loomwright/pull/177)
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
