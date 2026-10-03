# Supervisor Job: Curation / anti-rot — supersession, retraction, decay flagging, whole-stack advisory budget

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (46KB; last touched 2026-07-20)
- **Git:** clean, branch: main @ f55380b
- **Worktrees:** 1 (main checkout only — no orphans)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/twin-remediation/02-curation-anti-rot.md

## Task

**Problem:** Judgment now lives in six stores — agent memory dirs, LESSONS (`/dreaming`), `.agent/rules/`, `.agent/orientation/`, the findings→community bridge, and postmortem/churn JSONL — with no supersession, decay, or unlearning. North Star Bet 4: *"without these the advisory signal degrades and the Twin gets worse than none."* Each reader is individually bounded, but nothing budgets the SUM of advisory tokens injected per run.

**Goal:** Give the EXISTING stores a curation lifecycle — supersession, retraction (unlearning), decay flagging — plus a whole-stack advisory token budget. **No new stores.** This is the item that lifts the standing advisory-surface freeze (00-overview condition b).

**Explicitly additive / non-gating.** Every reader touched here must remain always-exit-0 fail-safe. Nothing may change a `heal_decision`, block a PR, truncate advisory context at runtime, or add a gating path. (The `write-lessons.sh` **write** side is the documented exception — it is a gate-side curation tool that FAILS LOUD by design; preserve that, do not make it fail-safe.)

**Freeze self-check (six deliverables, must hold):** this work introduces **no new advisory reader, store, or emitter**. It adds (1) supersession to **two existing readers plus one existing writer** (lessons supersession is writer-side — see rule 4), (2) retraction to two existing writers (the third already ships it), (3) one new report subsection inside an EXISTING dashboard section, (4) one additive field in an existing emitter, (5) a one-line pointer into an existing harness memory, (6) one entry in the existing `.agent/rules/` store.

## Feasibility (Phase 2.5) — CAUTION (proceed)

| # | Check | Verdict |
|---|---|---|
| 1 | Tech stack compatibility | GO — pure bash 3.2 + jq, matching the existing script surface |
| 2 | Dependency availability | GO — all 16 target files verified present on disk |
| 3 | Architecture fit | GO — advisory/fail-safe reader model is the documented house pattern |
| 4 | Scope vs Supervisor | CAUTION — 6 requirement scope items; decomposed into 6 subtasks below |
| 5 | Hard blockers | GO — none |

**CAUTION findings (feed the Risk Assessment):** the three curated stores have three *different* on-disk formats, so a "common `supersedes` field" is one concept with three encodings; and two of those encodings are constrained by already-shipped code (see the pinned contract).

## Prior art — READ THIS FIRST (v15.7.0 / merged PR #98, commit `ddb73f2`)

> Added after the Supervisor Phase 1.5 PRE-FLIGHT SYNC classified this work **OVERLAP** with already-merged code. Plan Review's 3-spawn cap was exhausted before this section was written, so it has NOT been through that gate — treat it as authoritative on facts (every claim below was verified against the tree) but scrutinize it during Phase 4.5.

`ddb73f2` — *"feat(curation): corpus curation half (retract/supersede/staleness)"* — **already shipped part of this requirement.** Do NOT rebuild any of it:

| Already merged | Where |
|---|---|
| A complete `retract`/`supersede` curation tool for the **postmortem corpus** (the 6th store) | `loomwright/scripts/curate-postmortem.sh` + `test-curate-postmortem.sh` |
| **Lessons retraction** — chain-trusted tombstone + line removal | `write-lessons.sh:217-274` |
| Lessons **staleness** (`LESSON_STALE_DAYS`, default 90) + the `RETRACTED` label | `read-lessons.sh:12-19,40-43,99,122` |
| Hiding retracted/superseded postmortem entries | `read-postmortem.sh` |
| The `## Corpus health` dashboard section | `build-insights.sh:698-760` |

**Verb-shape guidance (per-file — there is NO single house convention; #98 shipped TWO shapes):**

1. **`curate-postmortem.sh`** (`:32-34`) uses: `<action> --target <key> --reason <text> [--replacement <x>] [--confirm]`, with `--replacement` **REQUIRED on `supersede`** (`:105`) and **REJECTED on `retract`** (`:102`), validate-before-write, fail-loud exit 2. Its stated rationale is load-bearing and should be honored everywhere: *"a supersede without a replacement would be an indistinguishable synonym for retract."*
2. **`write-lessons.sh retract`** (`:45-46`) uses a DIFFERENT shape: positional `retract <category> <lesson-text>` or `retract --hash <content_hash>`, plus `--source`.

**Therefore:**
- **ST-3 (lessons):** the new `supersede` verb MUST mirror **`write-lessons.sh`'s own `retract` shape** (intra-file consistency — positional/`--hash` target selection), and MUST additionally require a `--replacement` per rationale (1). Do not import `--target` into this file.
- **ST-1 / ST-2 (rules, orientation):** these files have no existing curation verb, so follow **`curate-postmortem.sh`'s** shape — `--target` / `--reason` / `--replacement`-required-on-supersede / `--confirm`. Reuse its validate-before-write and fail-loud discipline.
- **ST-4:** lessons staleness and `## Corpus health` already exist — EXTEND, never duplicate. The remaining new work here is the whole-stack advisory budget.

**Scope actually remaining after this reconciliation:** supersede for lessons/rules/orientation; retraction for rules/orientation; the whole-stack advisory budget (requirement item 4); the harness pointer (item 5); the freeze rule (item 6). Requirement item 2 (unlearning) is **already satisfied for lessons and the postmortem corpus** — only rules and orientation remain.

## Normative encoding contract (PINNED — verified against shipped code, do NOT re-design per subtask)

> Every row below was checked by reading the actual implementation. A first draft of this brief pinned encodings that Plan Review proved unimplementable; these are the corrected ones. **Workers implement this contract; they do not invent one.**

### Supersession

| Store | Encoding | Why this shape (verified constraint) |
|---|---|---|
| `.agent/rules/*.json` | optional `"supersedes": "<rule-id>"` member on the rule object | `read-rules.sh` tolerates extra members on id-keyed objects |
| `.agent/orientation/*.md` | optional `\| supersedes: <area-slug>` inserted **BETWEEN `head_sha` and `areas`** in the line-1 header | `read-orientation.sh:168-170` captures `areas: (.*) -->$` **greedily**. A field appended AFTER areas is swallowed into `areas`, which is then passed as git pathspecs (`:201-203`) — matching nothing and **silently disabling staleness detection**. It must go before `areas`. A line-3 marker is also disallowed: `:216` emits `tail -n +2` verbatim, so it would render into advisory output. |
| `.supervisor/memory/LESSONS.md` | **writer-side only** (see rule 4): a `supersedes=<8-char-hash>` key inside the **EXISTING** HTML-comment trailer, with `last_verified=` kept FIRST | `read-lessons.sh:118` strips `<!-- last_verified=.*-->` **greedily**, so a trailer that still begins with `last_verified=` is stripped correctly with **no regex change**. A `supersedes`-only trailer would NOT be stripped, would pollute the hashed text, and the lesson would be silently DROPPED as untrusted. |

### Retraction

| Store | Status | Encoding |
|---|---|---|
| `.supervisor/memory/LESSONS.md` | **ALREADY SHIPS — do NOT re-implement** | `write-lessons.sh retract` (`:45-46`, `:217-274`): a chain-trusted, provenance-tombstoned atomic rewrite that REMOVES the entry line (`awk` at `:264`); `read-lessons.sh:82-92,120-129` honors it with a distinct `RETRACTED` label. Fails loud (exit 2/4). |
| `.agent/rules/*.json` | TO BUILD | `add-rule.sh retract --target <rule-id> --reason <text> --confirm` (curate-postmortem shape, per Prior art). Removes the rule object from the array; the writer **PRINTS** a one-line provenance reason to stdout. |
| `.agent/orientation/*.md` | TO BUILD | `add-orientation.sh retract --target <area-slug> --reason <text> --confirm` (same shape). Removes the memo file; the writer **PRINTS** a one-line provenance reason to stdout. |
| `.supervisor/postmortem/results.jsonl` | **ALREADY SHIPS — out of scope** | `curate-postmortem.sh retract\|supersede` (`ddb73f2`). Do not touch. |

**Unified semantics: retraction REMOVES + leaves an auditable trail.** This matches the shipped lessons verb rather than contradicting it. There is no `retracted: true` in-place marker anywhere — an earlier draft proposed one and it would have shipped two divergent retraction mechanisms on the lessons store.

**Where the retraction reason lives (decided — do not re-litigate):** rules and orientation have **no in-store home** for a post-deletion reason, verified — `.agent/rules/` keeps `provenance` as a field INSIDE each rule object (`README.md:24`, stamped by `add-rule.sh:169-185`), so deleting the object deletes its provenance; `.agent/orientation/` has no provenance file at all (the directory holds only `README.md`), and a memo is self-describing via its line-1 header, which is deleted with the file. Only lessons has a sidecar (`.supervisor/memory/.lessons-provenance.jsonl`) — and **adding sidecars to the other two would violate this brief's own freeze self-check.** Therefore: the writer **prints** the reason (tests assert on that output), and the **commit** is the durable record. Do NOT add a provenance sidecar, and do NOT keep a tombstone object in-store.

**Common rules (normative):**
1. **(rules + orientation only)** A reader SKIPS any entry named as the target of a live entry's `supersedes`. **This rule does NOT apply to lessons** — there, supersession is writer-side (rule 4), so the superseded entry is already gone from `LESSONS.md` and there is nothing for the reader to skip. Do not build a reader-side skip for lessons; it would be a second, divergent supersession mechanism on a store that already has one.
2. **Demote-never-crash:** a malformed / self-referential / cyclic / dangling `supersedes` is IGNORED (the entry is read normally) and never aborts the reader. Readers stay exit-0 unconditionally.
3. Supersession is **single-hop, not transitive** in v1 — A supersedes B hides B; it does not chase B's own `supersedes`. Cycles cannot loop by construction. Document the limit.
4. **Lessons supersession reuses shipped machinery — ORDER IS LOAD-BEARING: PRE-CHECK → RETRACT → ADD.** A new `write-lessons.sh supersede` verb — signature mirroring this file's own `retract` (positional `<category> <lesson-text>` or `--hash`, plus `--source`) and additionally **REQUIRING `--replacement`** per the Prior-art rationale — MUST:
   1. **Pre-check** that the target is present and chain-trusted (reuse the existing walk at `:233-257`). If not: **fail loud and leave the store byte-identical** — never a partial write.
   2. **Retract** the superseded entry via the EXISTING retract flow.
   3. **Add** the new lesson carrying `supersedes=<hash>` in its trailer.

   **Add-then-retract is FORBIDDEN and would destroy an unrelated lesson.** Verified at `write-lessons.sh:331-341`: the add path gathers the category's entries, appends the new one, then evicts from the **FRONT** (oldest first) until `<= MAX_PER_CAT` (3). Trace a full category `[A(oldest), B, C]` where new lesson `D` supersedes `B`: add yields `[A,B,C,D]` = 4 > 3, so **A is evicted**; the retract then removes `B`; the category ends `[C,D]` — and `A`, which was never superseded or retracted, is **gone**. Retract-first keeps the category at 3→2→3 so eviction never fires.

   **Partial-completion bound (be precise — do not overclaim):** the pre-check plus retract-first ordering eliminates the partial-write cases that would leave BOTH entries live. It does not make the verb fully atomic: a failure in the ADD half *after* a successful retract still half-completes (`:368-371` exits 2 on a failed rename; the dedup guard at `:200-203` exits 0 without writing if an identical lesson already exists). In that window the superseded entry is gone and the replacement never lands — the direction of loss matches user intent, and provenance records both halves. **Recovery:** re-run the plain `add`; the retract is already recorded in the provenance chain. Document this in the verb's usage block.

   This design deliberately avoids building an in-place trailer-mutation path — `write-lessons.sh:188-192` documents that none exists ("a stored `last_verified` is effectively write-once until the entry is evicted"), and only 4 of 10 live entries carry a trailer at all.

## Acceptance Criteria
- [ ] Given a live entry declaring `supersedes: X` in **rules** or **orientation**, when its reader runs, then entry X is absent from reader output (mechanical test per store).
- [ ] Given a MALFORMED / self-referential / dangling `supersedes`, when the reader runs, then the field is ignored, the entry is still emitted, and the reader exits 0 (adversarial falsification — do not test only the happy path).
- [ ] Given an orientation memo carrying `supersedes`, when `read-orientation.sh` runs, then its `areas` value and **staleness detection remain correct** (regression test for the greedy-capture hazard).
- [ ] Given a lesson written via the new `supersede` verb, when `read-lessons.sh` runs, then the new lesson is emitted with its trailer stripped from the hashed text and the superseded one is labeled `RETRACTED`.
- [ ] **Given a FULL 3-entry category, when a `supersede` targets the MIDDLE entry, then the other two entries both survive** (the add-time evict-oldest-from-front regression — this test is mandatory, not optional).
- [ ] Given a `supersede` whose target is absent or not chain-trusted, when the verb runs, then it fails loud and `LESSONS.md` + the provenance chain are **byte-identical** to before.
- [ ] Given a fixture entry, when the retract path is exercised end-to-end for **rules** and **orientation**, then the entry is removed and the writer **prints** a one-line provenance reason the test asserts on; the shipped lessons retract path is left unchanged.
- [ ] Given a real run, when `/insights` is built, then the EXISTING `## Corpus health` section additionally flags entries whose `head_sha`/basis no longer resolves or whose age exceeds the documented threshold — **flag only, never auto-delete**.
- [ ] Given a real run, when the token ledger is emitted, then a per-run TOTAL advisory-context size across memos+rules+bridge+brain-context is recorded, `/insights` reports it against a documented target, and its relationship to the pre-existing era-bucket `advisory_tokens` proxy is documented.
- [ ] Given `/dreaming` Accepts a LESSON, then `commands/dreaming.md` documents an idempotent one-line pointer write to the repo's Claude-harness memory, executed **at repo root** (never from a worker worktree).
- [ ] The standing advisory-surface freeze is committed as a `.agent/rules/` entry via `add-rule.sh … --confirm`.
- [ ] All touched readers remain always-exit-0 fail-safe; `write-lessons.sh` retains its fail-loud write side; counts / doc-currency / token-budget CI gates green.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Rules store: supersession + retraction (reader **and** writer) | 6 modify | LAUNCHABLE |
| 2 | Orientation store: supersession + retraction + header-parse fix | 4 modify | LAUNCHABLE |
| 3 | Lessons store: supersession via new `supersede` verb (retraction already ships) | 4 modify | LAUNCHABLE |
| 4 | Insights `## Corpus health` staleness + whole-stack advisory budget | 4 modify | BLOCKED (by #3) |
| 5a | Command/skill surfaces + harness pointer | 4 modify | BLOCKED (by #1, #2, #3) |
| 5b | Freeze rule + doc currency | 3 modify, 1 create | BLOCKED (by #5a) |

### Subtask contracts

**ST-1 — rules store** (LAUNCHABLE)
- `provides:`
  - `- {kind: behavior, path: loomwright/scripts/read-rules.sh, name: skips-superseded-rule}`
  - `- {kind: flag, path: loomwright/scripts/add-rule.sh, name: --supersedes}`
  - `- {kind: flag, path: loomwright/scripts/add-rule.sh, name: --retract}`
- `requires:` *(none — the pinned contract above is self-contained)*
- Files: `loomwright/scripts/read-rules.sh`, `loomwright/scripts/add-rule.sh`, `loomwright/scripts/test-read-rules.sh`, `loomwright/scripts/test-add-rule.sh`, `loomwright/scripts/test-rules-seams.sh`, `loomwright/scripts/test-rules-check.sh`.
- Preserve `add-rule.sh`'s existing hostile-category REJECT and traversal guards.
- `test-rules-seams.sh` asserts the reader's wiring at the worker / Phase 4.5 / SessionStart seams and `test-rules-check.sh` covers `rules-check.sh` — both are CI-run and are in scope because ST-1 changes reader behavior. Verify neither asserts an exact reader output shape that supersession changes.

**ST-2 — orientation store** (LAUNCHABLE)
- `provides:`
  - `- {kind: behavior, path: loomwright/scripts/read-orientation.sh, name: skips-superseded-memo}`
  - `- {kind: behavior, path: loomwright/scripts/read-orientation.sh, name: per-key-header-parse}`
  - `- {kind: flag, path: loomwright/scripts/add-orientation.sh, name: --supersedes}`
  - `- {kind: flag, path: loomwright/scripts/add-orientation.sh, name: --retract}`
- `requires:` *(none)*
- Files: `loomwright/scripts/read-orientation.sh`, `loomwright/scripts/add-orientation.sh`, `loomwright/scripts/test-read-orientation.sh`, `loomwright/scripts/test-add-orientation.sh`.
- **The header parse must be converted to a per-key extraction** tolerating BOTH the legacy 3-field header and the new 4-field one (backward compatibility is mandatory — memos already exist in the committed store). Re-verify every existing staleness test.
- Preserve the hostile-marker skip, the staleness demote-never-drop, the ≤3000-char output cap, and `add-orientation.sh`'s slug-containment / injection REJECT + confirm gate.

**ST-3 — lessons store** (LAUNCHABLE)
- `provides:`
  - `- {kind: subcommand, path: loomwright/scripts/write-lessons.sh, name: supersede}`
  - `- {kind: contract, path: .supervisor/memory/LESSONS.md, name: trailer-keeps-last_verified-first}`
- `requires:` *(none)*
- Files: `loomwright/scripts/write-lessons.sh`, `loomwright/scripts/read-lessons.sh`, `loomwright/scripts/test-read-lessons.sh`, `loomwright/scripts/test-lessons.sh`.
- **Do NOT touch the shipped `retract` verb's semantics** — `supersede` composes with it via the pinned PRE-CHECK → RETRACT → ADD order (rule 4). Add-then-retract is forbidden.
- **Do NOT add a reader-side superseded-skip for lessons** (rule 1) — the superseded entry is already removed by the writer. `read-lessons.sh` changes here are limited to whatever the `RETRACTED` labeling and trailer handling already require.
- The ≤3-active-per-category bound is unchanged; retract-first means the bound is never transiently exceeded, so no bound rework is needed.
- **`read-lessons.sh` HAS a live consumer:** `agents/supervisor.md:140` runs it as an EXECUTE-phase advisory read. A supersession bug here degrades a live Supervisor path — this is the HIGH risk in the table below, not a theoretical one.

**ST-4 — insights + ledger** (BLOCKED by ST-3)
- `requires:`
  - `- {from: ST-3, kind: contract, path: .supervisor/memory/LESSONS.md, name: trailer-keeps-last_verified-first}`
  - `- {from: ST-3, kind: subcommand, path: loomwright/scripts/write-lessons.sh, name: supersede}`
- `provides:`
  - `- {kind: section, path: loomwright/scripts/build-insights.sh, name: corpus-health-staleness}`
  - `- {kind: field, path: loomwright/scripts/emit-token-ledger.sh, name: advisory_total}`
- Files: `loomwright/scripts/build-insights.sh`, `loomwright/scripts/emit-token-ledger.sh`, `loomwright/scripts/test-insights.sh`, `loomwright/scripts/test-token-ledger.sh`.
- **EXTEND the existing `## Corpus health` section — do NOT add a parallel `## Stale knowledge` section.** `build-insights.sh:685-695` already renders corpus health, already computes lessons staleness against `LESSON_STALE_DAYS`, and already keys curation counts off `action == "retract"` provenance lines. That keying is the documented cross-subtask curation contract and is exactly why ST-4 is BLOCKED by ST-3.
- **Reconcile with the pre-existing `advisory_tokens` proxy** (`build-loop-evidence.sh:550,553`, rendered at `build-insights.sh:367`). Either supersede it or document the two as distinct measures — do NOT ship two divergent advisory numbers on one dashboard.
- Mirror the `orientation_source` convention exactly: invalid/unset ⇒ field OMITTED, never invented; always exit 0.

**ST-5a — command/skill surfaces + harness pointer** (BLOCKED by ST-1, ST-2, ST-3)
- `requires:`
  - `- {from: ST-1, kind: flag, path: loomwright/scripts/add-rule.sh, name: --supersedes}`
  - `- {from: ST-1, kind: flag, path: loomwright/scripts/add-rule.sh, name: --retract}`
  - `- {from: ST-2, kind: flag, path: loomwright/scripts/add-orientation.sh, name: --supersedes}`
  - `- {from: ST-2, kind: flag, path: loomwright/scripts/add-orientation.sh, name: --retract}`
  - `- {from: ST-3, kind: subcommand, path: loomwright/scripts/write-lessons.sh, name: supersede}`
- `provides:`
  - `- {kind: doc, path: loomwright/commands/rules.md, name: retract-path-documented}`
  - `- {kind: doc, path: loomwright/commands/dreaming.md, name: dreaming-supersede-action}`
  - `- {kind: doc, path: loomwright/commands/dreaming.md, name: dreaming-retract-action}`
  - `- {kind: doc, path: loomwright/commands/dreaming.md, name: harness-pointer-documented}`
- Documented invocations must be REAL (copied from the ST-1/ST-2/ST-3 writers), never invented. `/dreaming` gains per-item **Supersede** and **Retract** actions alongside Accept/Reject/Edit — same per-item human gate, no bulk-accept, Reject never writes.
- Files: `loomwright/commands/dreaming.md`, `loomwright/commands/rules.md`, `loomwright/skills/rules/SKILL.md`, `loomwright/scripts/test-rules-docs.sh`.
- **Fix the stale claim at `commands/dreaming.md:86`** ("no agent invokes it yet") — `supervisor.md:140` is a live consumer.
- The harness pointer is a **signpost, not a sync**: one idempotent line per repo. `.claude/` is gitignored and workers run in worktrees, so this write must be documented as happening at `/dreaming` runtime from the repo root — never attempted from a worker worktree.

**ST-5b — freeze rule + doc currency** (BLOCKED by ST-5a)
- `requires:` `- {from: ST-5a, kind: doc, path: loomwright/commands/rules.md, name: retract-path-documented}`
- `provides:` the committed freeze rule; green doc-currency.
- Files: `CLAUDE.md`, `loomwright/skills/SKILLS_INDEX.md`, `README.md`, + one new `.agent/rules/` entry (written via `add-rule.sh … --confirm`, category `process`, enforcement `advisory`).
- Doc currency: version bump + the ~8 lockstep surfaces. **Grep the OLD values repo-wide** — a green `check-doc-currency.sh` is necessary but NOT sufficient (it does not scan phase enumerations, per-run frontmatter field lists, budget numbers, or dashboard section enumerations).

## Skill References

| Subtask | Skills |
|---|---|
| ST-1 | `skills/rules/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| ST-2 | `skills/brain-context/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| ST-3 | `skills/memory-tool/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| ST-4 | `skills/monitoring-observability/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| ST-5a | `skills/rules/SKILL.md`, `skills/memory-tool/SKILL.md` |
| ST-5b | `skills/quality-checklist/SKILL.md`, `skills/commit/SKILL.md` |
| All | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Parallelism Analysis
- **Batch 1:** ST-1, ST-2, ST-3 — fully parallel, **zero file overlap** (each owns its store's reader + writer + co-located tests).
- **Batch 2:** ST-4 (needs ST-3's retraction/trailer contract).
- **Batch 3:** ST-5a. **Batch 4:** ST-5b.
- **Recommended workers:** 3.

Pairing each store's reader WITH its own writer (rather than splitting readers-vs-writers) is deliberate: it keeps every producer/consumer contract inside a single worktree, avoiding the documented worktree-isolation cross-file review false positive where a per-subtask reviewer cannot see a sibling worktree and returns a spurious NEEDS_HUMAN.

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Three stores, three encodings — parallel workers diverge on the "common" field | HIGH | Feasibility (Phase 2.5) | Encoding contract pinned normatively above, each row verified against shipped code |
| A supersession bug silently hides a live rule/lesson/memo — the exact degradation Bet 4 exists to prevent | HIGH | Analysis | Malformed/dangling/self-ref must fail-safe to "read it anyway", never "hide it"; adversarial test required per store |
| ST-3 touches a LIVE Supervisor advisory path (`supervisor.md:140`) | HIGH | Plan Review (verified) | Reader stays exit-0; regression tests before behavior change |
| Orientation greedy-capture: a misplaced `supersedes` silently disables staleness detection | HIGH | Plan Review (verified `read-orientation.sh:168-170`) | Field pinned BEFORE `areas`; per-key parse; staleness regression test mandatory |
| Two divergent retraction mechanisms on the lessons store | HIGH | Plan Review (verified `write-lessons.sh:217-274`) | Shipped `retract` is authoritative; `supersede` composes with it; no in-place `retracted:` marker anywhere |
| A `supersedes`-only trailer pollutes hashed text ⇒ lesson silently DROPPED | HIGH | Plan Review (verified `read-lessons.sh:118`) | `last_verified=` stays FIRST in the trailer so the greedy strip still matches |
| **Add-then-retract supersede destroys an unrelated lesson** via add-time evict-oldest-from-front | HIGH | Plan Review round 2 (verified `write-lessons.sh:331-341`) | Order pinned PRE-CHECK → RETRACT → ADD; mandatory full-category regression test |
| A composite `supersede` half-completes, leaving both entries live | MEDIUM | Plan Review round 2 | Pre-check target present + chain-trusted BEFORE any write; fail loud, store byte-identical |
| No in-store home for a rules/orientation retraction reason; a sidecar would violate the freeze | MEDIUM | Plan Review round 2 (verified) | Writer PRINTS the reason (asserted by test); the commit is the durable record — no sidecar, no tombstone object |
| Two divergent advisory-token numbers on one dashboard | MEDIUM | Plan Review (verified `build-loop-evidence.sh:550`) | ST-4 must reconcile with or supersede the existing proxy |
| `build-insights.sh` is 50KB; a new section risks its always-exit-0 contract | MEDIUM | Analysis | Extend the existing section only; keep fail-safe; extend `test-insights.sh` |
| `write-lessons.sh` ≤3-per-category bound miscounts retracted/superseded | MEDIUM | Analysis | Bound counts only live entries — explicit test |
| Harness pointer written from a worktree would be lost (`.claude/` gitignored) | MEDIUM | Plan Review | Documented as a repo-root-only runtime write; criterion restated as diff-checkable |
| Doc-currency drift across ~8 lockstep surfaces | MEDIUM | Lessons store | ST-5b owns currency; grep OLD values repo-wide |
| Scope is 6 requirement items in one PR | MEDIUM | Analysis | 6 subtasks, 3 parallel; ST-5a/5b are the integration + doc tail |

## Configuration
- Base branch: `main`
- Feature branch: `feature/curation-anti-rot`
- Mode: parallel
- Cost profile: default (`inherit`) — `--cheap` NOT passed
- Self-heal: enabled (Phase 4.5 default, `--heal-iterations 3`)

## Outcomes Rubric
- Supersession honored by all three curated-store readers
- Human-gated retract path exists and is tested
- Per-run whole-stack advisory token total is recorded and reported
- Freeze rule committed to .agent/rules/

> **Interpretation note for the Rubric Grader (rubric text above is verbatim from the requirement and must NOT be edited).** Item 1 is satisfied end-to-end for all three stores, but by two different mechanisms. For **rules** and **orientation** the reader skips the superseded entry. For **lessons** the superseded entry is absent from `read-lessons.sh` output because the `supersede` verb **retracted** it (normative rule 4) — not because the reader skips it; `read-lessons.sh` deliberately contains no supersession logic (see ST-3). Grade item 1 on the observable outcome — a superseded entry is absent from reader output — not on the presence of reader-side skip code in all three readers.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-23-curation-anti-rot.md
