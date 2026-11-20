# Supervisor Job: Dismissed follow-ups 06a — doc, header and evidence-file drift (24 findings)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (2 non-primary worktrees present: `fix-842` in a scratchpad, `fix/phase-wait-late-init-session-id` under `.claude/worktrees/` — neither is touched by this job)
- **Source requirement:** .supervisor/requirements/dismissed-followups/06a-docs-and-evidence-drift.md
- **Base commit:** 8100319b23d9371f620233e51f86feac286b15a7

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown, bash comments, one JSON budget entry, one golden fixture — the repo's own stack |
| 2 | Dependency Availability | GO | No new dependency |
| 3 | Architecture Fit | GO | Every fix is a wording, pointer or figure correction on the surface that owns it |
| 4 | Scope vs Supervisor Capability | CAUTION | 22 modified + 3 created files exceeds the 12-file `context-bound` bound; split into 2 file-disjoint subtasks |
| 5 | Hard Blockers | CAUTION | Fixes for F010, F343 (README tree), F368 and the evidence/fragment files land in paths outside the requirement's Touches — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Re-verify the 24 dismissed follow-up findings of requirement 06a on `main` and fix each doc, header-comment, fixture and evidence-file drift, recording every disposition in committed evidence files.

**Problem Statement:**
The owner and future agents need the plugin's docs, script headers and frozen evidence files to state what the code does, because agents act on this prose.
Currently, 24 findings dismissed as follow-up in earlier `/automate` runs are still present on `main` 8100319 (re-verified 2026-11-10 by Launch Pad: every quoted anchor below still `grep -F`-matches). This causes wrong pointers (e.g. `_pw_touches` located in the wrong file), stale figures (janitor's measured budget) and claims the code no longer backs (the release lane runs the bump).
Success looks like every finding either fixed in the diff or recorded with a one-line reason, with a committed evidence file per subtask listing the re-verify command and disposition.

## Acceptance Criteria

**Every finding (both subtasks)**
- [ ] AC1. Given a finding assigned to a subtask below, when its worker starts, then it re-runs that finding's anchor check on its own base (the `grep -nF` of the quoted anchor named in the AC, or in `## Touched-file invariants`), and a committed evidence file `docs/evidence/dismissed-followups-06a-<group>.md` (`scripts` for Subtask 1, `docs` for Subtask 2) contains, per finding id, the command run, its result, and exactly one disposition: `fixed` (naming the file changed) or `recorded` with a one-line reason; the PR body links to both files.
- [ ] AC2. Given the requirement's rule that every behavioral fix carries a regression leg, when the evidence files are read, then every finding is marked `doc-only` (no finding in 06a changes executed behavior: each edit is prose, a comment, a usage string, a frozen figure or a golden fixture), and no `test-*.sh` leg is added; the one executable text change (F010's usage line) is pinned by the existing golden comparison in `loomwright/scripts/test-automate-helpers-dispatch.sh` (see `## Pin mutations`).

**Subtask 1 — script headers, engine docs and contracts (`scripts`)**
- [ ] AC3 (F106, F319). Given `changelog.d/README.md`'s `Parallel wave` bullet, when read, then it no longer says `The release lane runs the bump once for the whole wave.` and instead says `automate-wave.sh wave-build`'s release step runs `scripts/bump-version.sh` and commits the fold as the wave branch's last commit (lanes still write fragments only).
- [ ] AC4 (F010). Given the `meta-entry` usage row in `loomwright/scripts/automate-helpers.d/meta.sh`, when read, then `writes nothing under .supervisor/automate/` is replaced by `writes nothing itself; the meta-sync pull it runs may update managed .supervisor/automate/ files`, and `loomwright/scripts/fixtures/automate-helpers-help/meta.golden` carries the identical text so `bash loomwright/scripts/test-automate-helpers-dispatch.sh` passes.
- [ ] AC5 (F053). Given the grammar-copy comments in `loomwright/scripts/automate-dismissed.sh` (`Grammar copy 2 of 3`) and `loomwright/scripts/propose-from-verify.sh` (`Grammar copy 3 of 3`), when read, then each locates the authority as the `PW_TOUCHES_GRAMMAR` line in `automate-helpers.d/plan-waves.sh` (`_pw_touches`), not `automate-helpers.sh`; no code line in either file changes.
- [ ] AC6 (F093). Given `loomwright/scripts/test-reconcile-jobs.sh`'s header, when read, then the leg-11 bullet says it checks `is_done()` against the format the live writers stamp (closeout, `automate-trail.d/closeout.sh`) and names cases `11a-11f`; the phrase `the completion tail STAMPS` is gone and no test leg changes.
- [ ] AC7 (F104). Given `loomwright/docs/PITFALLS.md`'s "Where the ONLINE repair now happens" paragraph, when read, then it says that at both seams the engine runs `closeout`, whose step 2 is `automate-helpers.sh brief-repair <item> <pr_url>`; the phrase `At both seams it calls` is gone.
- [ ] AC8 (F126, F127). Given `loomwright/docs/CORE_CONTRACT.md` §CLI table, when read, then the `run-lock.sh` row's release argv reads `release --owner <label> \| --session-id <id> [--root <dir>] [--force-unlock]` (matching `run-lock.sh`'s usage header), and the `verify-provides.sh` row says consumers fail CLOSED on `missing`, while `unverifiable` routes per `agents/supervisor.md` Single-Agent step 3 (some reasons fall back to the worker's self-report).
- [ ] AC9 (F128, F129). Given CORE_CONTRACT.md §5.3's Cursor bullet, when read, then it states that Cursor's common input `transcript_path` matches the ladder key in `PAYLOAD_TRANSCRIPT_KEYS` while the subagent transcript field's name is not given by the cited docs, so whether it matches is UNVERIFIED; and given §5.2, then Codex run-in-background is classified (under `Could not be re-verified`, since the 2026-08-22 row's wording is not available to compare), naming the detach primitive the §5.1 matrix marks UNVERIFIED.
- [ ] AC10 (F085). Given `loomwright/scripts/read-token-ledger.sh`'s honest-limits comment, when read, then the under-count pointer names `read_transcript`'s docstring in `emit-token-ledger.sh` (not "emit-token-ledger.sh header"), and that docstring is not edited.
- [ ] AC11 (F096). Given `loomwright/docs/HOOKS.md`, when read, then the D1 bullet and the host-mode table row for `guard-test-integrity.sh` both state that an unresolvable D1 gate root under host mode makes the guard deny every Write/Edit/Bash call (`guard_unavailable`), even in an unarmed session; the row no longer says the inert path is unchanged without that exception.
- [ ] AC12 (F143). Given `loomwright/skills/automate-loop/lanes.md`'s coordinator wave-lock acquire and `loomwright/skills/automate-loop/per-item-loop.md`'s closeout **Concurrency** bullet, when read, then each carries the clause that a `run_lock_degraded` stderr line is noted once and is not a park (the wording `per-item-loop.md`'s PICK-time acquire already uses).

**Subtask 2 — user-facing docs, budgets and frozen evidence (`docs`)**
- [ ] AC13 (F343, F347, F348). Given the `commands/` trees in `.claude-plugin/README.md` and `loomwright/docs/command-parts/agent-help/guide.md`, when read, then each tree is labelled an excerpt and points at `loomwright/commands/` as the full list (no count restated), so `backlog.md`, `handoff.md`, `janitor.md`, `propose.md` and `rules.md` need not be listed.
- [ ] AC14 (F356). Given `loomwright/docs/prompt-token-budgets.json` `.commands.janitor` and its mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", when read, then both carry the measured value `bash scripts/check-token-budget.sh` prints for `janitor` on the worker's base (1427 at 8100319), the budget stays 1470, and `check-token-budget.sh` passes.
- [ ] AC15 (F368). Given `loomwright/skills/quality-checklist/SKILL.md`'s module-shape item, when read, then its heading reads `(\`module_shape\` — every caller; the MODULE-SHAPE ADVISORY facts line is Supervisor Phase 4.5 only)`, matching `agents/code-reviewer.md` step 5d; the body is unchanged.
- [ ] AC16 (F050). Given README.md §"Running /autonomous in CI / unattended", when read, then it names Launch Pad's can't-ask outcomes (`saved_on_pass_non_interactive` among them) and the PR-base verify skip, and points at `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" as the full list.
- [ ] AC17 (F118). Given `loomwright/docs/RULES_BASELINE.md`'s supporting commands, when read, then one command derives the `distinct PRs` baseline from the `5293d06` ledger (`git show 5293d06:.supervisor/postmortem/results.jsonl | jq …`) with its output as a trailing comment; if it does not print 70 (Launch Pad's probe of distinct `.number` printed 71), the cell is corrected to the derived value and the evidence file records both numbers and why.
- [ ] AC18 (F144, F146). Given `docs/evidence/af39b-run-lock-holder.md`, when read, then its provenance line names the pre-fix commit (`463dc37`) and states the `pid_start` values are local time captured before the `env TZ=UTC0 LC_ALL=C ps -o lstart=` pin (`4cf6a58`), so the shipped form is UTC; no captured value is altered.
- [ ] AC19 (F310). Given `docs/evidence/as19-split-lanes-and-trail-scripts.md`, when read, then §3's AC3 sentence points at §9/§10 for the current base pin (`087b9e4`, `BASE_SHA` in `test-automate-lanes-modules.sh`) and the line-7 "Pre-merge vs. merged tree" note mentions §10 as well as §9.
- [ ] AC20 (F231). Given `docs/evidence/review-gate-rounds.md`, when read, then a footnote under the table states that `not recorded (… no Plan Review N/M)` cells (#222, #455 and any other) mean the extractor reads only `N/M` forms, that cap-less `Plan Review attempt N` text was not read, and that the run files are not in this checkout.

**Recorded by the worker, not fixed (Subtask 1 or 2 evidence file)**
- [ ] AC21. Given a finding the worker's re-verify shows already fixed on its base, when the evidence file is read, then it is `recorded` with the command output that shows the fix; no edit is made for it.

**Validation**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes for each subtask's files, including `check-prompt-history-refs.sh` (no finding id, PR number or incident story added to `lanes.md`, `per-item-loop.md`, `quality-checklist/SKILL.md` or `guide.md`), `check-token-budget.sh` (`automate-loop` 3890, `quality-checklist` 209, `agent-help` 1018 tokens of headroom at base), `test-citation-drift.sh` (no bare `file:N` in new prose), `test-automate-helpers-dispatch.sh`, `test-loop-inventory.sh`, `test-module-shape-facts.sh`, `test-build-capabilities.sh` and `check-doc-currency.sh`.
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/dismissed-followups-06a-docs-drift.md` and no hand-edited version file.

## Scope widening
- docs/evidence/dismissed-followups-06a-docs.md
- docs/evidence/dismissed-followups-06a-scripts.md
- loomwright/scripts/automate-helpers.d/meta.sh
- loomwright/scripts/fixtures/automate-helpers-help/meta.golden
- loomwright/skills/quality-checklist/SKILL.md
- accepted: LP-SCOPE 2026-11-10

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| scripts (Subtask 1) | `changelog.d/README.md` (80), `loomwright/scripts/automate-helpers.d/meta.sh` (86 — one `#:` usage row), `loomwright/scripts/fixtures/automate-helpers-help/meta.golden` (2 — the golden of that row), `loomwright/scripts/automate-dismissed.sh` (1109 — one comment line; appending nothing), `loomwright/scripts/propose-from-verify.sh` (250 — one comment line), `loomwright/scripts/test-reconcile-jobs.sh` (986 — header comment only; appending nothing), `loomwright/docs/PITFALLS.md` (92), `loomwright/docs/CORE_CONTRACT.md` (349), `loomwright/scripts/read-token-ledger.sh` (651 — one comment line; appending nothing), `loomwright/docs/HOOKS.md` (127), `loomwright/skills/automate-loop/lanes.md` (110), `loomwright/skills/automate-loop/per-item-loop.md` (123) | `docs/evidence/dismissed-followups-06a-scripts.md` | HIGH |
| docs (Subtask 2) | `.claude-plugin/README.md` (612 — one tree label edited in place; appending nothing), `loomwright/docs/command-parts/agent-help/guide.md` (421), `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — one mirror-row cell; appending nothing), `loomwright/skills/quality-checklist/SKILL.md` (188), `README.md` (771 — one bullet in the existing §"Running /autonomous in CI / unattended"; the single home for that list's README copy), `loomwright/docs/RULES_BASELINE.md` (300), `docs/evidence/af39b-run-lock-holder.md` (78), `docs/evidence/as19-split-lanes-and-trail-scripts.md` (317), `docs/evidence/review-gate-rounds.md` (497 — one footnote appended under its table; the frozen record of that measurement) | `docs/evidence/dismissed-followups-06a-docs.md`, `changelog.d/dismissed-followups-06a-docs-drift.md` | HIGH |

New responsibilities get no new module: every fix is an in-place wording, pointer or figure edit on the surface that owns the claim; no helper is added or copied. Not modified although listed in the requirement's Touches: `loomwright/commands/backlog.md`, `handoff.md`, `janitor.md`, `propose.md` (named only as the files the trees omit, and janitor.md as the measured file), `loomwright/scripts/automate-helpers.sh` (the usage row lives in `automate-helpers.d/meta.sh`), `automate-wave.sh`, `emit-token-ledger.sh`, `guard-test-integrity.sh`, `meta-sync.sh`, `run-lock.sh`, `test-automate-lanes-modules.sh` (each the code the corrected prose describes; read, not edited), `loomwright/skills/autonomous-loop/SKILL.md` (F050 points at ARCHITECTURE_CONTRACTS instead), `scripts/bump-version.sh`.

> **Validator-owned surfaces:** `scripts/check-token-budget.sh` (the JSON entry and its ARCHITECTURE_CONTRACTS mirror row must agree; prompt files' headroom), `scripts/check-doc-currency.sh` (README.md, `.claude-plugin/README.md`, ARCHITECTURE_CONTRACTS.md are scanned — no count is added), `scripts/check-prompt-history-refs.sh` (skill and command-part files), `loomwright/scripts/test-citation-drift.sh` (committed prose) and `loomwright/scripts/test-automate-helpers-dispatch.sh` (the help goldens) — all folded into the map above or V1.

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

## Touched-file invariants

> Grounded at base `8100319b23d9371f620233e51f86feac286b15a7`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.d/meta.sh` + `loomwright/scripts/fixtures/automate-helpers-help/meta.golden`** — keep: the row's closing contract `; always exits 0` and the segment header's fixture pointer; mirror: the golden must equal the help output of the `#:` rows byte-for-byte (the golden currently quotes `writes nothing under .supervisor/automate/; always exits 0`); pinned by: `loomwright/scripts/test-automate-helpers-dispatch.sh` (`GOLDEN_DIR="$HERE/fixtures/automate-helpers-help"`). Only the usage text changes; `meta-entry`'s code is untouched.
- **`loomwright/scripts/automate-dismissed.sh`, `loomwright/scripts/propose-from-verify.sh`** — keep: the comment blocks' three-copy contract (`Grammar copy 2 of 3, sharing no code` / `Grammar copy 3 of 3, sharing no code`) and every code line (`PATH_TOK`, `BAD_SEG`, `vt_touches`); mirror: the authority is `automate-helpers.d/plan-waves.sh`'s line tagged `# PW_TOUCHES_GRAMMAR`; pinned by: `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` §X7 (`X7 grammar drift on`), which a comment-only edit must leave green.
- **`loomwright/scripts/test-reconcile-jobs.sh`** — keep: every leg, including `11f (control)`; only the header bullet that reads `vs the format the completion tail STAMPS` changes.
- **`loomwright/scripts/read-token-ledger.sh`** — keep: the honest-limits list and all code; mirror: the pointer target `def read_transcript(path):` in `loomwright/scripts/emit-token-ledger.sh` (not edited). The old text is `(parallel-automate/24 F8, emit-token-ledger.sh header)`.
- **`loomwright/docs/HOOKS.md`** — keep: the §"Host mode" table header `| Script / leaf | Class | Under host mode |`, the `guard-test-integrity.sh` row's backticked key (first cell) and its Class cell `redirects (gate)`; edit only that row's third (Under host mode) cell and the D1 bullet's prose, and never split or add a row; mirror: `loomwright/scripts/build-capabilities.sh` parses this table fail-CLOSED (`the class is the Class cell's first word`; a row with no key or a duplicate key exits 1) into `capabilities.json`'s `hooks[].host_mode`; pinned by: `loomwright/scripts/test-build-capabilities.sh` (the regeneration staleness check) — `capabilities.json` must be byte-unchanged.
- **`loomwright/skills/automate-loop/lanes.md`, `loomwright/skills/automate-loop/per-item-loop.md`** — keep: the quoted spans `**The primary is locked for the whole wave:**` (lanes.md) and ``**Concurrency:** steps 3–7 run under `run-lock.sh acquire --owner automate-closeout:<run_id>` `` (per-item-loop.md) intact on one line each; add AC12's `run_lock_degraded` clause after them, never inside; mirror: `loomwright/docs/loop-inventory/automate-loop.md` rows `AL-446` and `AL-371`, whose `q:` anchors must remain a substring of one line; pinned by: `loomwright/scripts/test-loop-inventory.sh` (`anchor not found in`).
- **`loomwright/skills/quality-checklist/SKILL.md`** — keep: the heading prefix ``**Module shape (`module_shape` `` and, on the same line, `never read absence as clean` (the line must not gain `does not apply`); only the parenthesised scope text changes, the body is unchanged; pinned by: `loomwright/scripts/test-module-shape-facts.sh` G9 (`grep -F '**Module shape (`module_shape`'`).
- **`loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: `"budget": 1470` and the entry's `"note"`; mirror: `scripts/check-token-budget.sh` requires the mirror row's measured cell to equal `.measured` (`whose measured cell, when both sides record`); the row today reads ``| `janitor` | 1470 | 1336 |``.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-helpers-dispatch.sh` — `meta.golden` comparison | flip `writes nothing itself` → `writes nothing under` in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `scripts/check-token-budget.sh` — janitor mirror-row sync | flip `"measured": 1427` → `"measured": 1336` in `loomwright/docs/prompt-token-budgets.json` |

If AC14's measured value on the worker's base is not 1427, the worker replaces `1427` in this row with that value before Phase 4.5 applies it.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Script headers, engine docs and contracts (F106 F319 F010 F053 F093 F104 F126 F127 F128 F129 F085 F096 F143) | AC1, AC2, AC3–AC12, AC21, V1 | 12 modify, 1 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | User-facing docs, budgets and frozen evidence + release fragment (F343 F347 F348 F356 F368 F050 F118 F144 F146 F310 F231) | AC1, AC2, AC13–AC20, AC21, V1, V2 | 10 modify, 2 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-06a-scripts.md"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/meta.sh", name: "writes nothing itself"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help/meta.golden", name: "writes nothing itself"}
  - {kind: "symbol", path: "loomwright/docs/CORE_CONTRACT.md", name: "--session-id <id> [--root <dir>] [--force-unlock]"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/lanes.md", name: "run_lock_degraded"}
requires: []
lanes:
  - "changelog.d/README.md"
  - "loomwright/scripts/automate-helpers.d/meta.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/meta.golden"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/propose-from-verify.sh"
  - "loomwright/scripts/test-reconcile-jobs.sh"
  - "loomwright/docs/PITFALLS.md"
  - "loomwright/docs/CORE_CONTRACT.md"
  - "loomwright/scripts/read-token-ledger.sh"
  - "loomwright/docs/HOOKS.md"
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "docs/evidence/dismissed-followups-06a-scripts.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-06a-docs.md"}
  - {kind: "file", path: "changelog.d/dismissed-followups-06a-docs-drift.md"}
  - {kind: "symbol", path: "loomwright/skills/quality-checklist/SKILL.md", name: "every caller; the MODULE-SHAPE ADVISORY facts line is Supervisor Phase 4.5 only"}
  - {kind: "symbol", path: "README.md", name: "Question-gate inventory"}
requires: []
lanes:
  - ".claude-plugin/README.md"
  - "loomwright/docs/command-parts/agent-help/guide.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/quality-checklist/SKILL.md"
  - "README.md"
  - "loomwright/docs/RULES_BASELINE.md"
  - "docs/evidence/af39b-run-lock-holder.md"
  - "docs/evidence/as19-split-lanes-and-trail-scripts.md"
  - "docs/evidence/review-gate-rounds.md"
  - "docs/evidence/dismissed-followups-06a-docs.md"
  - "changelog.d/dismissed-followups-06a-docs-drift.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
Subtask 2 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel — both have empty `requires`, zero file overlap)
- **Recommended workers:** 2
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |

### Cited-line premise check

| ref | resolves | premise | deciding line | as of |
|-----|----------|---------|----------------|-------|
| `automate-dismissed.sh:348` | yes (`loomwright/scripts/automate-dismissed.sh`) | HOLDS (moved to 457) | `# automate-helpers.sh (_pw_touches); copy 3 is vt_touches in propose-from-verify.sh. Change all three` | tip 43 minutes ago, fetched <1h |
| `propose-from-verify.sh:125` | yes (`loomwright/scripts/propose-from-verify.sh`) | HOLDS | `# automate-helpers.sh (_pw_touches); copy 2 is PATH_TOK / BAD_SEG beside touches_of in` | tip 43 minutes ago, fetched <1h |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 22 modify + 3 create exceeds one worker's 12-file bound | MEDIUM | Split into two file-disjoint subtasks (`context-bound`) |
| Feasibility (Phase 2.5): fixes land outside the requirement's Touches (`meta.sh` + golden, `.claude-plugin/README.md`, `quality-checklist/SKILL.md`, evidence files, fragment) | MEDIUM | Feasibility row 5; the owner decides at Launch Pad's Phase 6 `LP-SCOPE` question, which records accepted paths in `## Scope widening` |
| Prior churn (postmortem ledger): ARCHITECTURE_CONTRACTS.md, `.claude-plugin/README.md`, README.md, prompt-token-budgets.json, per-item-loop.md carry heavy prior churn (drain_churn, convention_mismatch, self_heal_churn; self_heal_miss recurred) | HIGH | Edit only the cell / label / bullet named by the AC; grep each OLD phrase repo-wide after the edit (a green doc-currency run is not sufficient) |
| F118's baseline 70 does not reproduce from a plain distinct-`.number` count (71 at `5293d06`) | MEDIUM | AC17: derive, and correct the cell to the derived value with the reason recorded, rather than adding a command that disagrees with the figure |
| F356's measured figure moves if `janitor.md` changes before the worker runs | LOW | AC14 takes the value `check-token-budget.sh` prints on the worker's base, not a fixed 1427 |
| `lanes.md` / `per-item-loop.md` / `quality-checklist/SKILL.md` / `guide.md` are prompt surfaces: a finding id or PR number would trip `check-prompt-history-refs.sh` | MEDIUM | V1; finding ids live only in the evidence files and the changelog fragment |
| A concurrent session in this checkout can sweep uncommitted edits (project memory) | LOW | Workers run in their own worktrees; commit per finding group |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 1
- **Base Branch:** main
- **Split reason:** context-bound
- **Note:** Subtask 1 still touches 13 files, but nearly every edit is a one-line comment or prose change (far under 800 changed lines), so it fits one worker.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-10-dismissed-followups-06a-docs-drift.md
```


## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-10T11:14:08Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/873
- **Branch:** feature/dismissed-followups-06a-docs-drift
- **Files changed:** 32
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** 24 dismissed 06a findings re-verified and fixed/recorded (2 parallel subtasks, evidence in docs/evidence/dismissed-followups-06a-{scripts,docs}.md), release v17.35.3 folded. Phase 4.5: 3 rounds, each reviewer PASS + one new MEDIUM (stale meta.sh header comment; stale 'wave release lane' in test-release-refold.sh; loop-inventory AL-446/AL-371 missing the run_lock_degraded clause), each fixed; the round-3 fix (0837d99) was not re-reviewed, hence escalation. Driver parked at execute-stop on an early Execute Manager checkpoint; resumed in-session via SendMessage and finished Phase 4 on the legacy path.

## Not verified
- **review-gate-rounds.md Commands block 3 full re-run** — needs meta-synced .supervisor run files (subtask 2)
