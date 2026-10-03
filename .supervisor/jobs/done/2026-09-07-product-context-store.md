# Supervisor Job: `.agent/product.json` — a committed per-project product-context store, one advisory reader, and a propose-only bootstrap

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (15 worktrees present, several belonging to other sessions — none on the paths this brief touches)
- **Source requirement:** .supervisor/requirements/invention/02a-product-context-store.md
- **Base commit:** b6f52a6f75c393b8a178c0645597d53e00765569

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq, the same shape as the existing `read-*.sh` advisory readers. No new runtime, no new dependency. |
| 2 | Dependency Availability | GO | `jq` is already a soft dependency in this reader family. **Measured, not generalized:** of the six `read-*.sh` readers, three reference `jq` (`read-rules.sh`, `read-postmortem.sh`, `read-system-contract.sh`) and **two carry the `command -v jq` skip-not-fail guard** (`read-rules.sh`, `read-postmortem.sh`). Those two are the precedent the new reader follows. Nothing new is added. |
| 3 | Architecture Fit | GO | `.agent/` is the established home for committed, tool-agnostic, per-project knowledge — `git ls-files .agent` returns 4 tracked files across `rules/` and `orientation/`. A flat `product.json` sibling fits that convention exactly. |
| 4 | Scope vs Supervisor Capability | CAUTION | **15 files (10 modify + 5 create) is OVER the `> 12` file bound**, and the line estimate crosses the other predicate too: five new shell files at roughly 120–220 lines each is ~900 new lines against a bound of `> 800`. `context-bound` therefore fires on **both** predicates, and the brief splits into 2 sequential subtasks. **This CAUTION is resolved by the split, not carried into Risk Assessment** — a split brief is the threshold's prescribed answer to exceeding it. See `## Configuration` → Split reason. |
| 5 | Hard Blockers | CAUTION | `loomwright/scripts/*` is classified **CORE at allowance 0** in `docs/vendor-coupling-manifest.json`, so each new script carrying a literal vendor token breaches the ratchet unless an allowance row is added **in the same PR**. Measured baseline at plan time: **610 references / 78 files / 0 breaches**. |

**Overall Verdict:** CAUTION

## Task

**Goal:** Add one committed per-project store (`.agent/product.json`) recording what this project is, who it serves and who it competes with; one fail-safe advisory reader for it; and a propose-only bootstrap that writes nothing without explicit confirmation — then wire `/product-owner` to read it and to say so, loudly, when it is missing.

**Problem Statement:**
Every product-shaped surface in this plugin needs to know what the project *is*, and none of them can find out. `/product-owner` takes its audience from whatever the human typed into the prompt and forgets it the moment the run ends. `/capability-check --strategy` is structurally maintainer-only — it reads `${CLAUDE_PLUGIN_ROOT}/docs/CAPABILITY_BASELINE.json` and grounds on `agents/`/`commands/`, so run against a user's payments app it would read Loomwright and propose directions for Loomwright.

Currently there is nowhere to record that this repo is a B2B invoicing API whose competitors are X and Y, that its users are finance teams, and that missing SSO is table stakes rather than a differentiator. Measured 2026-09-06: `grep -rl "competitors"` hits three plugin files and **zero** project-level stores.

This causes a domain-aware lane to have no subject at all, and it makes `/product-owner` guess who it is writing for on every single run.

Success looks like: a project can state its identity in one committed place that travels with the repo, a reader emits it, and the store's *absence* is named at the point of use rather than silently skipped.

## Acceptance Criteria

- [ ] **AC1** — Given a well-formed `.agent/product.json` fixture, when `read-product.sh` runs, then it emits the store's fields and **every emitted value is traceable to a key in the file** — asserted against the fixture, not by reading the code.
- [ ] **AC2 (operative rule for absent/malformed/jq-missing — Design Constraints 2 and 5 defer to this)** — Given each of three separate cases — an absent store, a malformed store, and `jq` unavailable (PATH-stubbed) — when `read-product.sh` runs, then it emits **nothing on stdout**, names the reason on **stderr**, and **exits 0** in each case. (Note the precedent is split: `read-postmortem.sh` writes to stderr at its `jq` guard but is silent on an absent corpus. AC2 is the rule for this reader — a stderr diagnostic in **all three** cases. "Silent" everywhere in this brief means *silent on stdout*, never "no stderr".)
- [ ] **AC3** — Given a fixture whose `competitors[]` carries both a `last_fetched: null` entry and a dated entry, when the reader runs, then the null entry renders as **never fetched** — never as a date and never as "stale". Assert key **presence** with jq `has()`, and test the **missing-key** and **explicit-null** cases as **two separate cases** (nullable-required shape — do not collapse them).
- [ ] **AC4** — Given three fixtures (`stance: "product"`, `stance: "tool"`, and a store with **no** `stance` key), when `read-product.sh` runs, then it emits the derived field **`stance_default_action`** (see Design Constraint 4 for its exact two-value mapping and its emitted-not-stored status) with a **different value** for `product` than for `tool`, and for the stance-less fixture emits `stance: unset` and **`stance_default_action: unset`** — substituting **neither** default. Asserted against the three fixtures by field name, not by reading the code.
- [ ] **AC5** — Given a project with no store, when `propose-product.sh` runs **without** `--confirm` and without a TTY, then it **prints a proposal and writes nothing** — asserted by hashing the working tree before and after and comparing byte-identical. **Write containment (binding, see AC7):** run this inside a `mktemp -d` + `git init` throwaway tree, never the real repo.
- [ ] **AC6** — Given no store present, when `/product-owner` reaches its `### Context Setup (REQUIRED FIRST)` step, then its prose emits a **named, actionable "no product context"** message naming both `.agent/product.json` and the bootstrap command. **The assertion lives in the new `loomwright/scripts/test-product-seam.sh`** (a static grep test over the two markdown seam files, following the precedent of `loomwright/scripts/test-rules-seams.sh`, whose own header records that a markdown seam has nothing to execute and only a grep can assert the prose still hands the reader the right thing). **Asserted by mutation:** delete the message from either seam file and the test must fail. Gate the mutant on non-empty + differs-from-original before trusting the run.
- [ ] **AC7** — Given `propose-product.sh` runs **with** `--confirm` **inside a `mktemp -d` + `git init` throwaway tree**, then `.agent/product.json` is created there and **nothing outside `.agent/product.json`** is written — asserted by hashing the throwaway tree before and after, not by reading the code. **The test MUST NOT run `--confirm` against this repo:** the repo root IS the primary checkout, so `propose-product.sh`'s worktree guard (the `.git`-is-a-FILE test that `add-rule.sh` carries) does **not** protect it, and a `--confirm` run here would create a real `.agent/product.json` in a tracked directory. Additionally assert the developer's real `.agent/` is untouched. Precedent: `loomwright/scripts/test-add-rule.sh`, whose header records that it uses `mktemp -d` + `git init` so it never touches the real repo's `.agent/rules/`.
- [ ] **AC8** — The vendor-coupling ratchet is run **before and after**, the delta is reported in the PR body whatever it is, **and the after-run reports 0 breaches**. Baseline recorded at plan time: **610 references across 78 files, 0 breaches**.

## Outcomes Rubric

- A project can state what it is, who it serves, and who it competes with, in one committed
  place that travels with the repo.
- The store's absence is visible at the point of use, never silent.
- Stance is data, so the same lane serves a product and a tool without being told twice.
- One reader, matching the six that already exist; nothing new to learn.
- Nothing is fetched, auto-detected, or written without confirmation.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Store contract + the advisory `read-product.sh` reader | AC1, AC2, AC3, AC4 | 1 modify, 2 create | `skills/rules/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Propose-only bootstrap, the `/product-owner` consumer seam, and the release surfaces | AC5, AC6, AC7, AC8 | 9 modify, 3 create | `skills/rules/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — store contract + advisory reader (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/read-product.sh"}
  - {kind: "file", path: "loomwright/scripts/test-read-product.sh"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "## PRODUCT_CONTEXT"}
requires: []
lanes:
  - "loomwright/scripts/read-product.sh"
  - "loomwright/scripts/test-read-product.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
external_requires:
  - "jq (soft dependency — the reader must skip, not fail, when absent)"

# Subtask 2 — bootstrap + consumer seam + release surfaces (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/propose-product.sh"}
  - {kind: "file", path: "loomwright/scripts/test-propose-product.sh"}
  - {kind: "file", path: "loomwright/scripts/test-product-seam.sh"}
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "Load Product Context"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "Load Product Context"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "propose-product.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/read-product.sh"}
lanes:
  - "loomwright/scripts/propose-product.sh"
  - "loomwright/scripts/test-propose-product.sh"
  - "loomwright/scripts/test-product-seam.sh"
  - "loomwright/agents/product-owner.md"
  - "loomwright/commands/product-owner.md"
  - "AGENT_GUIDELINES.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "README.md"
  - "CLAUDE.md"
external_requires: []
```

> **Why Subtask 2 owns `vendor-coupling-manifest.json` alone, including the allowance rows for Subtask 1's scripts.** The manifest is deliberately in Subtask 2's lanes only, so the two subtasks share **no** file and the "sequential sharing grants visibility, not preservation" hazard never arises. The consequence is explicit and accepted: at the end of Subtask 1 the branch may carry scripts with no allowance row. That is not a red CI signal — both subtasks land in one PR on one feature branch, and `scripts/check-vendor-coupling.sh` runs against that PR, by which point Subtask 2 has added every row. Subtask 2's AC8 is the check that closes this.

## Design Constraints (binding — these are the requirement's own decisions, do not re-litigate)

1. **Store shape — `.agent/product.json`**, a flat committed file, sibling of `.agent/rules/` and `.agent/orientation/`. **Stored** fields:
   - `domain` — what this project is, in the terms its own market uses.
   - `stance` — exactly `"product"` or `"tool"`. **Load-bearing** (see constraint 4).
   - `audience` — who it serves, and honestly whether that is evidence-backed or assumed.
   - `competitors[]` — each `{name, url, last_fetched}`. **`last_fetched` is required and may be `null`**, meaning *never fetched*, which the reader MUST render as unknown rather than old.
   - `written_at` (ISO-8601 UTC) and `head_sha` — mirroring the orientation memos' header provenance contract, so staleness is measurable against churn rather than guessed from elapsed time.

   **Emitted-but-not-stored:** `stance_default_action` (constraint 4). It is a reader output only; it is **never** a key in the JSON and `propose-product.sh` must never write it.

2. **Reader discipline.** Two properties, with their precedent stated exactly as measured (do not widen the claim):
   - **True of all six existing readers** (`read-rules.sh`, `read-orientation.sh`, `read-postmortem.sh`, `read-project-memory.sh`, `read-lessons.sh`, `read-system-contract.sh`): `set -uo pipefail` with **no `set -e`**, **exit 0 always**, and emitting nothing **on stdout** when the store is absent or unparseable. **`AC2` is the operative rule for what reaches stderr** — this reader names the reason on stderr in all three cases; "emits nothing" here means stdout only.
   - **The `command -v jq` skip-not-fail guard** is carried by **`read-rules.sh` and `read-postmortem.sh`**; those two are the precedent `read-product.sh` follows.

   The reader is advisory — it must never break its caller.

3. **NO `/setup` module, and no new command / agent / hook / skill.** The requirement considered and rejected a module on the evidence of the closest precedent (`rules` seeds *portable* content; a product store is project-specific by definition, so the one property that earns a module has no analogue here). Counts stay at **14 agents / 23 commands / 41 skills / 27 hooks** and `check-doc-currency.sh` sees no count change. The five new scripts are **uncounted plain scripts**.

4. **`stance` decides the default action of a gap, and MUST NOT be hard-coded — resolved explicitly, because the requirement's own wording admits two readings.**
   - The hazard constraint 4 names is a lane carrying **one fixed policy regardless of the project**: "Hard-coding either default would make the lane tell a payments app to skip its missing fraud checks because parity is a NO."
   - The resolution: `read-product.sh` emits a derived **`stance_default_action`** field via a **two-entry lookup keyed on the stored `stance`** — `product` ⇒ `build-highest-priority`, `tool` ⇒ `do-not-build-by-default`. This is the *opposite* of the forbidden hard-coding: the output is a function of project data, not a constant. **When `stance` is absent the reader emits `unset` and substitutes neither value** — it never guesses.
   - **The lane still owns the decision.** The reader *reports* the default; nothing in this brief acts on it. The consuming lane is 02b and is out of scope here (see Non-goals).
   - Put the two-entry mapping in exactly **one** named place in `read-product.sh` and document it under `## PRODUCT_CONTEXT` in `RESULT_SCHEMAS.md`, so 02b reads it rather than re-deriving it.

5. **Absent means absent, and it MUST SAY SO where it is needed.** No-op-when-absent is the right *read-side* behaviour, but **silent** no-op-when-absent is a documented feature-killer in this repo: `brain-context` was read-path-only with no bootstrap path, and the result was `graphify-out/graph.json` absent, its bridge orphaned **255 commits** stale, and `brain_context` appearing **zero times across every session log**. The consumer that finds no store MUST name it and offer the bootstrap — never skip quietly and exit 0 as though nothing were missing. **The division of labour is deliberate:** the *reader* emits **no user-facing output** on absent — nothing on stdout, a stderr diagnostic only, per AC2 (it is advisory and must not break callers); it is the **consumer seam** in `product-owner.md` that must speak.

6. **Bootstrap is propose-only, confirm-gated, and owned by the consumer at the moment of need.** Follow `add-rule.sh`'s established shape: with no `--confirm` and no interactive TTY, **print the planned write and do not write**; write only on `--confirm` or an interactive TTY confirmation. Refuse to write from a linked worktree or submodule (the same red-team guard `add-rule.sh` carries — top-level `.git` being a FILE). Nothing is auto-registered.

7. **`propose-product.sh` does NOT use `validate-entry.sh`, and `AGENT_GUIDELINES.md` must say so.** That shared validator's three blocking checks — contradiction, duplicate, provenance — are defined against an append-only store of *curated prose entries*; `.agent/product.json` is a **single structured object**, where "duplicate" and "contradiction against an existing entry" have no referent. `propose-product.sh` validates **shape** instead: required keys present, `stance` in the two-value enum, `competitors[]` entries carrying `last_fetched` as a **present key** (jq `has()`, null permitted). The confirm gate is unchanged and still required. **State the reason correctly:** do NOT invoke the section's `git ls-files <store-path>` test on `.agent/product.json` — that command returns empty today *and after this PR*, because this brief deliberately does not create the store (the bootstrap creates it per-project at runtime), so the literal test would yield "not tracked ⇒ no gate", the opposite of the truth. The correct derivation is that the store lands in the **tracked `.agent/` tree** (no `.gitignore` entry covers it) and is **committed by design**, so it falls on the committed side of the rule and gates.

   The `AGENT_GUIDELINES.md` §"Sole-writer confirm gates (committed-vs-gitignored rule)" edit is therefore, exactly:
   - add a table row: `| propose-product.sh | .agent/product.json | yes | **required** |`;
   - update the restated count **above** the table, "Which side each of the **six** sole writers falls on", to **seven**;
   - update the restated count **below** the table, "All **six** writers share `validate-entry.sh`", to say that **six of the seven** share it and that `propose-product.sh` deliberately does not, for the reason above.

   **No CI gate covers these restated counts** (`check-doc-currency.sh` verifies `plugin.json`/`hooks.json`/directory counts, not this prose), so an incomplete edit lands silently. Diff all three parts.

## Non-goals (from the requirement — do not expand scope)

- **No `/setup` module**, no dashboard change, no `commands/setup.md` edit.
- **No new command, agent, hook, or skill.** Counts stay where they are.
- **No change to `/capability-check`.** It stays a maintainer tool reasoning about the plugin versus the platform.
- **No network.** This item defines and reads a store; fetching anything is 02b's problem.
- **No auto-detection of competitors.** Proposed on scan, written only on confirmation.
- **No `.gitignore` change.** `.agent/` is already tracked.
- **No consuming lane.** Nothing here acts on `stance_default_action`; that is 02b.

## File Impact Map

| Group | Subtask | Files to Modify | Files to Create | Confidence |
|-------|---------|----------------|-----------------|------------|
| reader | 1 | — | `loomwright/scripts/read-product.sh`, `loomwright/scripts/test-read-product.sh` | HIGH |
| store contract | 1 | `loomwright/docs/RESULT_SCHEMAS.md` | — | HIGH |
| bootstrap | 2 | — | `loomwright/scripts/propose-product.sh`, `loomwright/scripts/test-propose-product.sh` | HIGH |
| consumer seam | 2 | `loomwright/agents/product-owner.md`, `loomwright/commands/product-owner.md` | `loomwright/scripts/test-product-seam.sh` | HIGH |
| gates | 2 | `loomwright/docs/vendor-coupling-manifest.json`, `AGENT_GUIDELINES.md` | — | HIGH |
| release surfaces | 2 | `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `README.md`, `CLAUDE.md` | — | HIGH |

> **Validator-owned surfaces:** this brief's acceptance depends on `scripts/check-doc-currency.sh` (via `corpus-task: doc-currency-green`) and `scripts/check-vendor-coupling.sh`. Files scanned by those validators may need updates to keep them green — in particular `vendor-coupling-manifest.json` must gain allowance rows for **every** new script carrying a literal vendor token (`loomwright/scripts/*` is CORE at allowance 0), **in this same PR**. Note also that CI's anti-drift self-test loop globs `loomwright/scripts/test-*.sh` **only** — all three new tests live there and are picked up automatically.

**Total estimated files:** 10 modify + 5 create = **15** (Subtask 1: 1 modify + 2 create; Subtask 2: 9 modify + 3 create). This total is what makes `context-bound` fire on the file predicate as well as the line predicate — see Feasibility row 4.

### Blast-Radius / Impact Prediction

Omitted — no touched subsystem has a verified System Twin contract and `twin-graph.sh` returns empty groups (the store is provenance-gated and currently emits nothing; recorded lesson `2d56232f`).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (disjoint lanes by construction — see the note under Subtask Contracts) | YES (2 requires 1) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md` (advisory-reader precedent), `skills/unit-testing/SKILL.md` |
| 2 | `skills/rules/SKILL.md` (confirm-gated sole-writer precedent), `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn on touched paths (postmortem ledger): `CHANGELOG.md` (47), `CLAUDE.md` (46), `plugin.json` (46), `README.md` (35), `RESULT_SCHEMAS.md` (16); recurring classes `drain_churn` (33), `convention_mismatch` (27), `quality_gap` (16); **a `self_heal_miss` recurred on these paths**. Source: Prior churn (postmortem ledger) | HIGH | These are the release surfaces. Enumerate and diff **all** version-bump surfaces before declaring PASS (recorded lesson `a642885b`: both manifests, CHANGELOG paragraph, CLAUDE.md banner rotation keeping only the 2 most recent, README dated banner ADD, plugin.json annotations, agent-help, marketplace description edited **in place**). Treat a green `check-doc-currency.sh` as necessary but **not sufficient** (lesson `0d7865dc`) — grep the OLD version string repo-wide. |
| `last_fetched` is a **nullable-required** field — a present-but-wrong-type guard silently accepts a MISSING key when `null` is also legal (recorded repo lesson from PR #84's `read-rules.sh` `check`, which Phase 4.5 review *and* a 6/6 rubric both missed). | HIGH | AC3 mandates jq `has()` presence assertion plus **separate** missing-key and explicit-null test cases. Do not collapse them into one case. |
| `loomwright/scripts/*` is CORE at **allowance 0** in the ratchet, so a new script's first literal vendor token fails CI unless an allowance row lands in the same PR. Source: Feasibility (Phase 2.5) | MEDIUM | Subtask 2 owns the manifest and runs the ratchet after **all five** scripts exist; AC8 requires the after-run to report 0 breaches. |
| The consumer's "no product context" message is prose a reviewer reads past — the repo's recurring "a claim no check backs" defect class. | MEDIUM | AC6 pins the assertion to a named artifact (`test-product-seam.sh`) and mandates a **mutation control**. Gate the mutant on non-empty + differs-from-original before trusting the run (lesson `fa32a308`). |
| The three restated counts in `AGENT_GUIDELINES.md` §"Sole-writer confirm gates" are covered by **no** CI gate, so a partial edit lands silently. | MEDIUM | Design Constraint 7 enumerates all three edits verbatim; the `provides` symbol `propose-product.sh` in `AGENT_GUIDELINES.md` gives `outputs_verified` something to check. |
| Agent↔command mirror drift: editing `agents/product-owner.md` without syncing `commands/product-owner.md` passes every gate — `check-command-sync.sh` does not cover prose. | MEDIUM | Both are `provides` symbols on Subtask 2 and both are grepped by `test-product-seam.sh`, so the mutation control fails if either loses the message. |
| `outputs_verified` is worker-SELF-REPORTED — a worker that dies before emitting `WORKER_RESULT` leaves the gate with no input and nothing flags it. | MEDIUM | The `provides` names above are exact and file-addressable; re-verify on disk at Phase 4.5 rather than trusting the gate's silence. |
| Concurrent writer: another Claude session is live in `~/Documents/work/AI/loomwright-stateloop`, which `git worktree list` shows is a worktree of this same repo sharing the remote. It can advance `main` or open its own PR mid-run. | MEDIUM | Verify merge/PR state from `gh`/`git`, never from memory or in-session belief, before claiming anything landed. Phase 1.5 PRE-FLIGHT SYNC runs unskipped. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-07-product-context-store.md
```

---

## Outcome

- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/204
- **Branch:** feature/product-context-store (4 commits: 1da2d97, 71bb984, 091adb1, b446586)
- **heal_decision:** PASS (Phase 4.5, 2 fix iterations of 3 — iteration 1 cleared a HIGH; iteration 2 cleared 4 non-gating findings by choice)
- **rubric_score:** 5/5
- **ground_truth:** pass — 2/2 (corpus-task doc-currency-green, corpus-task version-consistent) at commit b446586. Ran, not skipped.
- **Tests:** 121 assertions across three new suites (read-product 52, propose-product 41, product-seam 28), all green.
- **Vendor-coupling ratchet (AC8):** 610 → 613 references, 78 → 79 files, **0 breaches**. The 3 added references are the `${CLAUDE_PLUGIN_ROOT}` invocations in the two seam mirrors.
- **Until-mergeable dispatched:** false — deliberately suppressed by the `/automate` engine's config toggle (`auto_review: false`), which owns exactly one inline drain instead. Reconciled from the on-disk marker, not from control flow.
- **Files:** 13 changed, 8 modify + 5 create. The brief predicted 10 modify; README.md and CLAUDE.md correctly needed no edit — README now defers all per-release narrative to CHANGELOG.md and CLAUDE.md is deliberately version-free, so the brief's release-surface estimate was based on a convention that has since changed.
