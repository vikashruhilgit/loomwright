# Supervisor Job: CLAUDE.md diet + a /dreaming curation pass to keep it that way

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last touched 10 hours ago)
- **Git:** clean (0 files), branch: main @ 9a791e1
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/final-state/09-claude-md-diet-dreaming.md

**Warning (non-blocking, out of scope, already flagged separately):**
`.supervisor/jobs/in-progress/2026-07-29-fix4-cheap-batch.md` is a stranded brief — item 03's
work merged as PR #118 on 2026-07-30 but its completion tail never moved the file to `done/`
and it carries no `## Outcome` block. **Do NOT fix it in this job** (reconstructing heal fields
you cannot source is worse than the leak). It is recorded as a separate task.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown + bash only; no new deps, no new runtime. |
| 2 | Dependency Availability | GO | All writers/gates already shipped: `add-rule.sh --retract`, `check-doc-currency.sh`, `validate-version.sh`, corpus tasks `doc-currency-green` + `version-consistent` (verified present in `loomwright/scripts/eval-corpus/`). |
| 3 | Architecture Fit | CAUTION | **F1 — source premise falsified.** The requirement says `/dreaming` "never touches CLAUDE.md". It does: `loomwright/commands/dreaming.md:201` §4 "Proposed CLAUDE.md Updates" is one of SIX MANDATORY report sections. The real gap is narrower — those proposals are **additive-only**, and `dreaming.md:310` deliberately excludes CLAUDE.md from sole-writer domain ("stays paste-to-apply"). Resolved by owner decision D1 (below): extend §4 in place, proposals-only. **Do not add a second CLAUDE.md section to the report.** |
| 4 | Scope vs Supervisor Capability | CAUTION | **Single subtask (Decomposition Threshold default).** A 2-way `genuine-parallelism` split was drafted and then **withdrawn on review evidence**: the version-claim surface (5 files) and the `/dreaming`↔`agent-help.md` mirror both span the proposed lane boundary, so the two halves were not independent and `loomwright/commands/agent-help.md` was wanted by both. Splitting would have created a real Criterion-16 same-wave lane overlap. One worker, one lane, no worktree. |
| 5 | Hard Blockers | GO | **F2 (informational):** the committed advisory-surface freeze in `.agent/rules/process.json` reads as active, but BOTH discharge conditions are met (twin-remediation `01-prove-the-loop.md` and `02-curation-anti-rot.md` are both `## Status: done`). Owner decision D2 retires it here. This job adds no new advisory store — it edits an existing report section — so the freeze's own "consumers of EXISTING signals are exempt" carve-out would have applied regardless. |

**Overall Verdict:** CAUTION (proceeded — both findings surfaced to the owner and resolved by explicit decision)

## Task

**Goal:** Cut CLAUDE.md by ≥50% by relocating (never deleting) its bulk to authoritative homes, and extend `/dreaming`'s existing §4 with a prune/merge/supersede curation direction so the file stops re-growing.

**Problem Statement:**
Every session pays CLAUDE.md's full size as fixed context tax, and the file grows monotonically —
release banners, restated tables, incident notes accumulate with no curation path. Currently it is
**44,392 bytes / 243 lines**, and its three largest sections (`## The 14 Agent Roles` 12,625 B,
`## Common Pitfalls` 8,325 B, `## Plugin Hooks (Quality Gates)` 7,211 B) are **63% of the file** —
while the project caps every advisory reader at ~3000 chars. This causes a permanent per-session
context cost plus a multi-surface documentation treadmill that four CI gates currently *enforce*
rather than remove. Success looks like CLAUDE.md ≤ 22,196 bytes (≥50% smaller) with every moved
section reachable by an explicit pointer, all doc gates still green and still effective, and
`/dreaming` able to propose curation candidates so the diet does not silently reverse.

### Owner decisions (taken at the Phase 2.5 gate — do not re-litigate)

- **D1 — proposals-only, paste-to-apply.** Extend `dreaming.md` §4 with curation DIRECTION
  (prune / merge / supersede candidates) under the existing per-item Accept/Reject/Edit gate.
  **Ship NO new writer script for CLAUDE.md.** `dreaming.md:310`'s "CLAUDE.md … stays
  paste-to-apply / `/dreaming` never writes those directly" stays true and must not be weakened.
  Scope item 2's phrase "same UX as the v15.14.0 store curation" means the **UX shape**
  (per-item gating, never bulk), NOT "must have a mechanized sole writer". This is consistent
  with the source rubric's own bullet 2, which already says **flag-only**.
- **D2 — retract the discharged freeze rule** in this PR, via the shipped path.

## Acceptance Criteria

- [ ] Given CLAUDE.md at its measured 44,392-byte baseline, when the diet lands, then CLAUDE.md is **≤ 22,196 bytes** (≥50% reduction) and the PR description records the exact before/after byte count and the delta.
- [ ] Given each section moved out of CLAUDE.md, when a reader looks for it, then CLAUDE.md carries an explicit one-line pointer to its new authoritative home and **no content is lost from the repo** (relocation only, never deletion).
- [ ] Given the relocation, when `bash scripts/check-doc-currency.sh` runs on the integrated branch, then it exits 0 **and** any new doc file that still carries a scanned current-state claim has been added to that script's `FILES` array in the same commit.
- [ ] Given the doc-currency gate post-diet, when a stale count claim is seeded **into one of the nine files the gate actually scans, in the working tree** (e.g. rewrite `.claude-plugin/README.md:503`'s `24 hooks centralized` to `23 hooks centralized`), then `bash scripts/check-doc-currency.sh` reports `DRIFT [hook-count]` on that file and exits non-zero; the seed is then reverted with `git checkout -- <file>` and the gate re-run to confirm it exits 0 again. Record both results in the PR description and leave no seeded claim behind.
- [ ] Given each moved section's old anchors, when the repo is grepped for them, then there are **zero orphaned references** anywhere in the repo (run the sweep after every cut, per the sweep-grep-gate-variants discipline, including hyphenated and bare-number variants).
- [ ] Given `loomwright/commands/dreaming.md` §4 "Proposed CLAUDE.md Updates", when it is extended, then it additionally directs prune / merge / supersede candidates with per-item Accept/Reject gating, **without adding a new report section** and **without introducing any writer for CLAUDE.md**.
- [ ] Given `dreaming.md`'s Read-Only Contract, when §4 is extended, then the existing "CLAUDE.md … stays paste-to-apply" clause at `dreaming.md:310` remains true, and its **mirror** at `loomwright/commands/agent-help.md:633-635` is synced in the same commit.
- [ ] Given `.supervisor/requirements/twin-remediation/04-claude-md-diet.md`, when this job completes, then it carries a `## Status:` stamp recording that it is superseded by `final-state/09-claude-md-diet-dreaming.md`.
- [ ] Given the discharged advisory-surface freeze rule, when it is retired, then it is removed via `add-rule.sh --retract … --confirm` (NOT a hand-edit of `process.json`), and `read-rules.sh` no longer returns it.
- [ ] Given that the retraction empties the rules store, when the replacement house rule is authored via `add-rule.sh … --confirm` in the same PR, then `read-rules.sh` emits ≥1 valid rule (so `session-resume.sh`'s no-house-rules nudge does not begin firing every session).
- [ ] Given the version bump to the next minor, when the doc surface is checked, then `plugin.json` and `marketplace.json` agree, **every prose restatement of the version has been deleted** (not re-bumped) per the DELETE-over-gate rule, and the four counts (14 agents / 21 commands / 41 skills / 24 hooks) are **unchanged** by this job.

## Outcomes Rubric

<!-- Copied VERBATIM from the source requirement per the preserve-verbatim contract. Do not
     reword, do not expand to fill the 3-7 band — the author's yardstick stays as written.
     NOTE for the PR description (not a reason to edit this): bullet 3 asserts the outcome of
     EXECUTING a gate, which the read-only rubric grader cannot confirm from a diff alone. A
     rubric FAIL on bullet 3 is an artifact of that, not a regression. -->
- Diet executed with byte-count delta recorded
- /dreaming CLAUDE.md pass shipped, human-gated, flag-only
- All doc gates green post-diet

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | CLAUDE.md diet + /dreaming curation direction + provenance retirement | AC1–AC11 | 14 modify, 2 create | `skills/claude-md-validation/SKILL.md`, `skills/rules/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask contract

```yaml
# Subtask 1 — the whole job (LAUNCHABLE, Single-Agent Path)
provides:
  - {kind: "file", path: "loomwright/docs/PITFALLS.md"}
  - {kind: "file", path: "loomwright/docs/HOOKS.md"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md", name: "## Hook Table"}
  - {kind: "symbol", path: "loomwright/docs/PITFALLS.md", name: "## Common Pitfalls"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "## Agent Invariants"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "## Claim Duplication Rule"}
  - {kind: "symbol", path: ".supervisor/requirements/twin-remediation/04-claude-md-diet.md", name: "## Status:"}
requires: []
lanes:
  - "CLAUDE.md"
  - "AGENT_GUIDELINES.md"
  - "CHANGELOG.md"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "scripts/check-doc-currency.sh"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - ".claude-plugin/README.md"
  - "loomwright/commands/dreaming.md"
  - "loomwright/commands/agent-help.md"
  - ".supervisor/requirements/twin-remediation/04-claude-md-diet.md"
  - ".agent/rules/process.json"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/scripts/stamp-requirement-status.sh"
external_requires: []
```

> **Lane note (Criterion 16).** Single subtask ⇒ no mutually-unreachable pair exists ⇒ no
> same-wave lane overlap is possible. This is deliberate: the earlier 2-way split put
> `loomwright/commands/agent-help.md` in both halves (it carries BOTH a version annotation and the
> `/dreaming` read-only-contract mirror), which is exactly the authoring defect Criterion 16 exists
> to catch. Collapsing to one lane removes the hazard rather than papering over it.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| — | — | n/a (single subtask) | n/a |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/claude-md-validation/SKILL.md`, `skills/rules/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Implementation Notes — the diet plan

Measured section sizes (authoritative baseline, `awk` over CLAUDE.md at 9a791e1; the eight rows
sum to exactly 44,392):

| Section | Bytes | Disposition |
|---|---:|---|
| `## The 14 Agent Roles` | 12,625 | **Relocate the per-agent invariants column** into a new `## Agent Invariants` section in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`. Keep in CLAUDE.md a compact 14-row name/type/one-line-purpose list + pointer. Target ≤ 2,000 B. |
| `## Common Pitfalls` | 8,325 | **Relocate** into a new `loomwright/docs/PITFALLS.md` under the exact heading `## Common Pitfalls`. Keep in CLAUDE.md only the 3–4 that bite every session — the stale-branch / "already merged" trap is **non-negotiable**, it is the incident that motivated Phase 1.5 — plus a pointer. Target ≤ 1,400 B. |
| `## Plugin Hooks (Quality Gates)` | 7,211 | **Relocate the full 24-row table** into a new `loomwright/docs/HOOKS.md` under the exact heading `## Hook Table` (this exact string is a `provides` symbol — prose and contract must agree), and move the "authoritative" claim with it. Keep in CLAUDE.md a short prose stanza (the `\|\| true` convention + the never-`\|\| true`-a-blocking-gate rule) + pointer. Target ≤ 900 B. |
| `## Project Overview` | 3,167 | Collapse the release-narrative paragraph into a 3-line "current version + counts + one-line what-changed" stanza; the narrative belongs in `CHANGELOG.md`, which already holds it. Target ≤ 700 B. |
| `## Adding or Modifying Agents` | 3,950 | Keep the checklist; compress the doc-currency essay to its rule + pointer. **The "Hook gotcha" paragraph is KEEP** — `loomwright/docs/IMPROVEMENTS_ROADMAP.md:24` cites it by name (`CLAUDE.md §"Adding or Modifying Agents" ("Hook gotcha")`); retaining it keeps that pointer valid without pulling another file into the lane. Target ≤ 2,000 B. |
| `## Structured Contracts (v9.0.0)` | 1,869 | Compress to pointers into `docs/RESULT_SCHEMAS.md`. Target ≤ 600 B. |
| `## Failure-Mode Invariants` | 3,226 | **KEEP** (bimodal failure philosophy + the single-merge-executor invariant are load-bearing and not derivable elsewhere). Light trim only. |
| Everything else | 4,019 | Keep as-is. |

Targets sum to ≈ 14,845 B — a ~67% cut, comfortably inside the ≥50% bar with headroom.

### The version-claim surface (load-bearing — this is what failed Plan Review attempt 1)

`scripts/check-doc-currency.sh` runs **five** version patterns (lines 96, 97, 98, 112, 113), not
one. A bump to the next minor makes **every** prose restatement drift. The complete set of live
hits across the gate's nine scanned FILES, verified by running all five patterns:

| File:line | Text | Action |
|---|---|---|
| `CLAUDE.md:26` | `plugin.json` (v15.20.0) | **DELETE the annotation** |
| `.claude-plugin/README.md:430` | `# Plugin manifest (v15.20.0)` | **DELETE the annotation** |
| `loomwright/commands/agent-help.md:1082` | `# Plugin metadata (v15.20.0)` | **DELETE the annotation** |
| `.claude-plugin/marketplace.json:10` | `"description": "Loomwright v15.20.0 — …"` | **BUMP in place** (real manifest data) |
| `loomwright/.claude-plugin/plugin.json:4` | `"description": "Loomwright v15.20.0 — …"` | **BUMP in place** (real manifest data) |

The three annotations are **prose restatements inside directory-tree diagrams** — textbook
DELETE-over-gate: the number adds nothing a reader of `plugin.json` doesn't already have, and a
number that lives in one place cannot drift. Deleting them is **safe for enforcement**:
`scripts/validate-version.sh` independently diffs `plugin.json` against `marketplace.json`
(`check-doc-currency.sh:7-8` says so explicitly), so manifest-version consistency stays gated even
when the prose surface goes to zero.

**Also fix the stale pointer inside both manifest descriptions:** each ends *"Full version history
lives in CLAUDE.md."* — which this diet makes false. Change to **CHANGELOG.md** in the same commit
(an AC5 orphaned-reference instance). Per CLAUDE.md's anti-rebloat rule, update the `vX.Y.Z` string
and the four counts **in place**; never append another version clause to the description.

**Do NOT touch** the deliberately frozen, version-agnostic example values (sample `session_end` /
`POSTMORTEM_RESULT` records, `e.g. "X.Y.Z"` placeholders). CLAUDE.md documents that they are
intentionally unscanned; "fixing" them is a known review-churn trap.

### Inbound pointers that BREAK (AC5 — repair these two, they are in the lane)

A repo-wide sweep of cross-file pointers into CLAUDE.md sections classified each against the
disposition table. The `## Failure-Mode Invariants` KEEP decision already protects eight of them
(`.github/workflows/ci.yml:104`, `TELEMETRY.md:307`, `agents/supervisor.md:65`,
`result_block_parser.py:51`, `validate-worker-result.py:90`, `emit-progress-event.sh:20`,
`reconcile-resume-state.sh:29`, `stamp-requirement-status.sh:39`), and the
`## Adding or Modifying Agents` heading survives for `check-skills-index-sync.sh:5` and
`agents/rubric-grader.md:30`. **Exactly two break, and both are now in the lane:**

| Pointer | Why it breaks | Repair |
|---|---|---|
| `loomwright/docs/TELEMETRY.md:206-207` — *"see CLAUDE.md §\"Plugin Hooks (Quality Gates)\" for the authoritative, current count"* | The disposition moves the table **and the authoritative claim** to `HOOKS.md`, so this sentence's claim goes false even though a stub heading would keep the anchor resolving. | Repoint to `loomwright/docs/HOOKS.md`. |
| `loomwright/scripts/stamp-requirement-status.sh:18-19` — cites `CLAUDE.md §"Common Pitfalls"` for the inline-main-thread-workflow fact | `## Common Pitfalls` relocates wholesale, retaining only 3–4 items, and this is not among the retained ones. | Repoint to `loomwright/docs/PITFALLS.md`. |

**Explicitly OUT of scope (an AC5 sweep false positive — do not "fix" it):**
`loomwright/skills/workflow-management/SKILL.md:328` carries its own `## Plugin Hooks (Quality
Gates)` heading. That is **that skill's own section**, not a pointer into CLAUDE.md — it references
nothing and nothing breaks when CLAUDE.md's same-named section shrinks. It will surface in the AC5
anchor sweep; leave it alone.

### Gate-coverage rule (AC3 + AC4)

Prefer **deleting** a restated count over relocating it — a hook table does not need to also say
"24 hooks", because the table *is* the list. Where a scanned claim genuinely must move, **add its
new home to `check-doc-currency.sh`'s `FILES` array in the same commit.** Losing gate coverage
silently is the failure mode AC3 exists to prevent; AC4's seeded-stale-claim probe is what proves
it did not happen.

**No count category loses coverage in this diet — verified, not assumed.** The only count claim the
diet removes from a scanned file is `CLAUDE.md:128`'s `24 hooks centralized`. Every category still
has live coverage on other scanned surfaces afterwards, enumerated by running each `check_count`
pattern across all nine FILES:

| Category | Surviving scanned surfaces |
|---|---|
| hook-count | `README.md:57`, `.claude-plugin/README.md:441`, `.claude-plugin/README.md:503`, `marketplace.json:10`, `plugin.json:4` |
| agent-count | `CLAUDE.md:13` (retained in the compressed stanza), `README.md:57`, `.claude-plugin/README.md:3`, both manifests, `agent-help.md:23` |
| command-count | `README.md:57`, `README.md:727`, `.claude-plugin/README.md:9`, both manifests |
| skill-count | both manifests |

This job changes **no** count (no agent/command/skill/hook is added or removed), so every count
claim stays valid as written — only the version moves. AC4's probe therefore has a live target
post-diet; `.claude-plugin/README.md:503` is the recommended seed site (in the lane and in FILES).

**Document the rule.** Add a `## Claim Duplication Rule` section to `AGENT_GUIDELINES.md` stating
the priority order: (a) a count/claim lives in exactly ONE authoritative machine-readable place;
(b) every other surface derives it or drops the number entirely; (c) a sync-checking gate is the
LAST resort.

## Implementation Notes — /dreaming + provenance

- **Extend `### 4. Proposed CLAUDE.md Updates` IN PLACE** (`dreaming.md:201`). It currently lists
  only additive proposals ("additions or revisions"). Add curation direction: each proposal may
  also be a **prune** (section no longer earns its context cost), a **merge** (two sections
  restating each other), or a **supersede** (a claim whose authoritative home moved), carrying the
  same per-item Accept / Reject / Edit gate and the same **PENDING USER APPROVAL** label the
  section already uses. **Add no seventh report section** — §4 already exists and the report's
  "six sections, in this order" contract at `dreaming.md:181` must remain literally true.
- **Preserve the paste-to-apply boundary.** `dreaming.md:310` ("CLAUDE.md … proposals stay
  paste-to-apply. `/dreaming` never writes those directly") stays as written. The new curation
  actions PROPOSE only. Re-read `dreaming.md:299–313` after editing and confirm the Read-Only
  Contract still reads consistently — a curation proposal that implies a write would contradict it.
- **Sync the mirror.** `loomwright/commands/agent-help.md:633-635` restates that same contract
  ("`/dreaming` does not modify code, agent memory, or `CLAUDE.md`" and "CLAUDE.md and legacy
  agent-memory proposals stay paste-to-apply"). `scripts/check-command-sync.sh` covers **only**
  `commands/code-reviewer.md` (verified), so this drift passes every mechanical gate — sync it by
  hand in the same commit. This is the `agent-command-mirror-drift-on-fixes` failure mode.
- **Repo-root-only** is already the governing rule for `/dreaming` (`dreaming.md:285–289`); do not
  restate or re-derive it, and do not add a worktree guard for a path that never writes.
- **Retract the discharged rule** with the verified invocation (`--replacement` is ALWAYS rejected
  on retract, exit 2; `--confirm` is required or it dry-run prints and exits 0):
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh" --retract \
    --target "process-advisory-surface-freeze-no-new-advisory-readers-stores-emitters-memos-ledgers-lenses-bridges-may-ship-until-a-at-least-one-real-before-after-measurement-has-run-and-b-supersession-decay-unlearning-exists-for-the-existing-stores-bugfixes-and-consumers-of-existing-signals-are-exempt" \
    --reason "Discharged: both conditions met — twin-remediation 01-prove-the-loop.md and 02-curation-anti-rot.md are both '## Status: done'. Retired by final-state 09." \
    --confirm
  ```
  The writer prints the provenance line to stdout (there is no in-store home for it); **capture
  that line into the commit message** — the commit is the durable record.
- **Then author the replacement house rule (AC10 — do not skip).** `.agent/rules/process.json`
  holds **exactly one** rule object, so the retraction empties the store to `[]`.
  `loomwright/scripts/session-resume.sh` gates its no-house-rules SessionStart nudge on
  `read-rules.sh` emitting **EMPTY stdout**, not on file presence — so an empty store makes that
  advisory nudge start firing at every session start in this repo (24h-debounced; opt-out only via
  `LOOMWRIGHT_RULES_NUDGE`). Author the DELETE-over-gate rule as its replacement so the store stays
  non-empty and the project's own new convention is enforceable at the worker DO-side seam:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh" \
    --category process \
    --statement "A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see plugin.json', never '24 hooks'. A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy." \
    --enforcement advisory \
    --source ".supervisor/requirements/final-state/09-claude-md-diet-dreaming.md §DELETE-over-gate" \
    --confirm
  ```
  Flags verified against `add-rule.sh:79-80` and its arg parser (`:114-124`): `--category` and
  `--statement` are the two required ADD flags; `--enforcement` defaults to `advisory` (`:97`) but
  is passed explicitly rather than relying on the default. **`--source` is not optional in
  practice:** it defaults to the literal `"/rules add"` (`add-rule.sh:100`), which would leave the
  rule un-attributed and break the store's own convention — the rule being retired carries
  `provenance.source` naming its originating requirement document (`process.json:9`). Passing the
  requirement path keeps the replacement attributable to the same requirement that retired its
  predecessor.
  Verify with `read-rules.sh` that exactly this rule (and not the retracted one) comes back.
- **Stamp twin-remediation 04** with `## Status: superseded-by final-state/09-claude-md-diet-dreaming.md`
  (idempotent — do not add a second stamp if one already exists).

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Source premise F1 taken literally → a duplicate CLAUDE.md section bolted onto `/dreaming` | HIGH | AC6 forbids a new section explicitly; the notes point at `dreaming.md:201` as the edit target. Reviewer should confirm the six-section contract at `dreaming.md:181` still reads "six". |
| Version bump drifts a prose restatement the gate scans | HIGH | The version-claim table above enumerates **all five** live hits found by running all five gate patterns (attempt-1 Plan Review FAILed on exactly this — two of them were missing). Three are deleted, two bumped in place. |
| A moved count claim silently loses doc-currency coverage | HIGH | AC3 (add new home to `FILES` in the same commit) + AC4 (seeded-stale-claim effectiveness probe). Prefer deleting the restated count outright. |
| Retraction empties the rules store → SessionStart nudge fires every session | MEDIUM | AC10 authors a replacement rule in the same PR. This is a real user-visible side effect of D2, recorded rather than discovered later; the retraction decision itself is settled. |
| `/dreaming` ↔ `agent-help.md` mirror drift | MEDIUM | AC7 requires the sync in the same commit. `check-command-sync.sh` covers only `code-reviewer.md`, so no gate catches this — it is a review-and-discipline item by construction. |
| Orphaned references to moved sections | MEDIUM | AC5 repo-wide sweep after EVERY cut, including hyphenated and bare-number variants — a green doc-currency run is necessary but NOT sufficient. The sweep was run at plan time and its results are pre-recorded above: exactly TWO inbound pointers break (`TELEMETRY.md:206-207`, `stamp-requirement-status.sh:18-19`), eight are protected by the `Failure-Mode Invariants` KEEP, one (`workflow-management/SKILL.md:328`) is a declared false positive. Plus both manifest descriptions' "Full version history lives in CLAUDE.md". |
| AC4's gate-effectiveness probe silently proves nothing | MEDIUM | `check-doc-currency.sh:22-23` `cd`s to its OWN repo root and scans a FIXED nine-entry repo-relative `FILES` array, so a "scratch copy" of one file is scanned by nothing and the gate exits 0 — false confidence in exactly the property the probe exists to establish. AC4 now names the mechanism (seed in the working tree, assert `DRIFT [hook-count]` + non-zero exit, `git checkout --` revert, re-assert exit 0) and a seed phrase known to match a live pattern. This was proven at plan time: seeding `23 hooks centralized` produced `DRIFT [hook-count] CLAUDE.md:128` and a failing gate; the revert restored green. |
| File count (16) crosses the `context-bound` >12 predicate | LOW | A split is newly *justifiable* but not required, and remains **wrong** here: `agent-help.md` carries both a version annotation and the `/dreaming` contract mirror, so any split re-creates the Criterion 16 overlap that forced this collapse. Single-agent stands; the work is uniform prose editing with one shared thesis. |
| Aggressive cut loses a load-bearing invariant | MEDIUM | `## Failure-Mode Invariants` is explicitly KEEP. Relocation is never deletion (AC2). The stale-branch pitfall must survive in CLAUDE.md itself. |
| Retract targets the wrong rule id | LOW | The full id is pinned verbatim above and matches `process.json` byte-for-byte; `add-rule.sh` fails loud (exit 2) on a not-found target and writes nothing. |
| CHANGELOG.md is 255 KB — a careless rewrite is expensive | LOW | Append a release entry only; the narrative already lives there and needs no restructuring. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-03-claude-md-diet-dreaming.md
```

---

## Outcome

- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/122 (OPEN — safe mode, never auto-merged)
- **Branch:** feature/claude-md-diet-dreaming (7 commits, off origin/main @ 9a791e1)
- **Version:** 15.20.0 → 15.21.0 | **Counts:** UNCHANGED (14 agents / 21 commands / 41 skills / 24 hooks)
- **heal_loop_ran:** true | **heal_decision:** PASS | **heal_iterations:** 1 | **heal_remaining_issues:** 0
- **rubric_score:** 3/3
- **Result:** CLAUDE.md 44,392 → 15,618 bytes (64.8% cut; bar was ≥50% / ≤22,196)
- **Owned drain:** READY (engine-owned, inline; suppression verified effective — no
  `.supervisor/review-dispatch/` marker for PR #122 and no live `review-pr-runner`, so exactly ONE
  drain existed). 7 external review rounds; converged when round 7 reported zero new findings.
- **until_mergeable_dispatched:** false (deliberate — `.auto_review:false` suppressed the default
  detached dispatch for the whole RUN phase per automate-loop §7; the engine owned the only drain)

### What the review rounds actually caught (all validated against the branch before acting)

1. **Plan Review ×3 (FAIL, FAIL, PASS).** Two lane/closure gaps: a version bump broke the
   doc-currency gate on two files in no lane, and AC5's repo-wide sweep forced edits to two more.
   Both were the same class — an AC with repo-wide reach against a narrower lane.
2. **Phase 4.5 (PASS, 2 findings).** `HOOKS.md` restated a count while being outside the gate's
   FILES — a hand-restated count with zero coverage in the file this PR promotes to authoritative.
3. **External rounds 1–6.** The one genuine AC2 violation: the "two review lenses" invariant was
   **deleted, not relocated**, and `Earned Fallback Review` / `no_review_lens_posted` returned zero
   hits post-diet — undiscoverable from a cold read. Restored as a one-line invariant pointer.
   Plus a 4th missed inbound hook pointer, a stale byte figure, a stale PR title, and the
   `/dreaming` mirror under-reporting six sections as four.

### The recurring irony, recorded because it is the lesson

This PR introduced a Claim Duplication Rule and then violated it **six times in its own diff** —
`HOOKS.md`, `AGENT_GUIDELINES.md`, the rule's own anti-example, `agent-help.md`, `PITFALLS.md`, and
the `.agent/rules/` copy of the rule itself (which hardcoded "24 hooks" — the rule forbidding
hardcoded counts contained one). Every instance was ungated: none matched a `check-doc-currency.sh`
regex. **The gates verify that claims are CURRENT; nothing verifies a claim is DERIVED rather than
restated, or that an invariant is still REACHABLE.** That gap is the actual finding of this job.

### Owed / not done

- AC4's specified revert step (`git checkout -- <file>`) is **wrong for a dirty tree** — it
  discarded an uncommitted worker edit when run. The probe itself is sound; only the revert is
  unsafe. Use cp-to-backup + restore. This survived 3 adversarial Plan Review rounds.
- No `WORKER_RESULT` block was ever emitted (the worker hit its turn limit twice). The deterministic
  gate was run directly against disk by the supervisor thread instead — stronger evidence than a
  self-report, but the schema artifact is genuinely absent, not synthesised.
