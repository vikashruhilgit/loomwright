# Supervisor Job: Items the planner can actually parallelise — `plan-waves --explain` / `--lint`, writers emit `Touches` / `Depends on`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/w1-10
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 tracked changes), branch: main @ 95e8601 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/parallel-automate/10-touches-backfill-lint-and-explain.md
- **Base commit:** 95e86013e2f6511f37540de499d7b95816b71303

> **Warning (1):** a sibling lane checkout (`../w1-08`, item `parallel-automate/08-shared-ci-slots`) runs at the same
> time from its own directory. Its declared Touches (`ci-slot.sh`, `scripts/ci-local.sh`, `AGENT_GUIDELINES.md`) do not
> intersect this brief's lanes. Never `cd` outside this checkout; never use bare `git stash`.
> Branch mode is ON (`loomwright-meta-w1`): `.supervisor/requirements/**` lives on the metadata branch and is
> gitignored on `main` — this PR must not commit any requirement file.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD awk + python3 (draft writer) + markdown — the existing surface. No new dependency. |
| 2 | Dependency Availability | GO | `jq`, `awk`, `python3`, `git` present. |
| 3 | Architecture Fit | GO | Read-only flags on an existing read-only helper; writers only gain two sections. The planner's safety rules are unchanged (non-goal). |
| 4 | Scope vs Supervisor Capability | CAUTION | One subtask, ~15 lanes. The requirement's own `## Touches` names `commands/propose.md` for the `/propose` drafts, but those drafts are written by three scripts (`propose-work.sh`, `propose-domain.sh`, `propose-from-verify.sh`) — they are added to the lanes here. `agents/product-owner.md` is added too (the requirement's verified premise asks for it to be aligned). |
| 5 | Hard Blockers | CAUTION | Scope 3 (intake prints a lint summary under `--parallel N>1`) depends on item 05, which has NOT merged — `/automate` has no `--parallel` flag today. Delivered here as the documented intake contract (what item 05's intake must print, and the `plan-waves --lint` call it makes); no engine flag is added. |

**Overall Verdict:** CAUTION (2 findings carried into Risk Assessment)

## Task
**Goal:** Make every item's `## Touches` / `## Depends on` trustworthy and explainable: add `plan-waves --explain` and `plan-waves --lint` (both read-only), make every requirement writer emit parsable sections, and document how `--parallel` intake (item 05) surfaces the lint.

**Problem Statement:**
The wave planner (`automate-helpers.sh plan-waves`, item 04) ran over the 26 open items on 2026-10-04 and produced 24 waves of at most 2 items. 16 items have no `## Touches`, several carry prose in it (which makes the whole section unknown), 16 have no `## Depends on` (read as "depends on every earlier item"), new writers still default to run-alone, and the planner never says why two items landed in different waves.
Success looks like: a lint that names the exact bad line, an explain block that names the exact conflicting path or rule, and writers that emit real sections from now on.

## Acceptance Criteria
- [ ] AC-1 Given any input and `--max N` WITHOUT the new flags, when `plan-waves` runs, then stdout and exit code are byte-identical to `main` on every existing `test-automate-helpers.sh` plan-waves fixture (asserted by diffing old vs new output on those fixtures, or by the unchanged existing assertions all still passing).
- [ ] AC-2 Given `--explain`, when `plan-waves` runs, then after the unchanged `wave`/`blocked` lines it prints one block per item NOT in wave 1, each naming every reason that kept it out of an earlier wave, in these exact shapes: `conflicts with <item> on <path> (declared)`, `conflicts with <item> on <path> (companion: <when>)`, `depends on <item>`, `runs alone: Touches unknown (missing)`, `runs alone: Touches unknown (unparsable line <N>: "<text>")`, `runs alone: Touches unknown (declared unknown)`, `runs alone: Depends on missing ⇒ depends on every earlier item`. `<N>` is the 1-based line number in the item file. A test asserts each shape on a fixture that produces it.
- [ ] AC-3 Given `--lint <item|dir>`, when it runs, then it prints one line per item — `ok`, `ok (declared unknown)`, or the exact unparsable line with its line number and the reason (missing section; duplicated section; parenthetical/prose; comma list; `- ` bullet; backticks; leading `/`; `.`/`..` segment; `//`; `unknown` mixed with paths; empty section) — for BOTH `## Touches` and `## Depends on`. `## Depends on`-only failure shapes get their own reasons: `none mixed with ids`, `none repeated`, `not an id or *.md path` (plus missing / duplicated / empty, shared with Touches). **Exit code:** 1 when EITHER section of any item is MISSING or UNPARSABLE — a bad `## Touches` makes the item run alone, a bad `## Depends on` makes it depend on every earlier item, and both are lint failures; exit 0 otherwise. A sole `unknown` in `## Touches` and a sole `none` in `## Depends on` are legal (exit 0). A fixture with valid Touches and NO `## Depends on` asserts exit 1. A directory input lints every `*.md` the folder intake would enqueue (`resolve_folder`). `--lint` never needs `--max`.
- [ ] AC-4 Given the malformed shapes seen in today's backlog — a parenthetical `(only if a test exposes a defect)`, a comma list `a, b`, a `- ` bullet, `(part B)` — when `--lint` runs, then each is flagged with its line; a sole `unknown` is reported `ok (declared unknown)` and does NOT set exit 1. Mutation control: make `--lint` accept a parenthetical line ⇒ a named test fails; the reverted hunk and the failing test's name/output are recorded in `WORKER_RESULT` and the PR body.
- [ ] AC-5 Given `--lint` and `--explain`, when they parse a section, then they use the SAME grammar as the planner (`_pw_touches` / `_pw_depends` — a shared parser or the same awk, never a second hand-copied grammar), so lint `ok` ⇔ the planner reads the section as known. A test asserts lint and planner agree on every fixture shape.
- [ ] AC-6 Given a dismissed-finding draft written by `automate-dismissed.sh` (per-finding AND summary), when it is parsed, then it carries `## Depends on` = `none` and `## Touches` = the repo-relative file path(s) the finding's `source` or text names that pass the Touches path grammar AND exist under the repo root, else `unknown`; and `plan-waves --lint` on that draft prints `ok` or `ok (declared unknown)`. The sections sit where an H2 ends them (before the `## Finding` heading), never after an `###`/fenced block. Finding text stays untrusted data: no path extraction from it may execute or open anything beyond an existence test.
- [ ] AC-7 Given a `/propose` draft from each of `propose-work.sh`, `propose-domain.sh` and `propose-from-verify.sh`, when it is parsed, then it carries `## Depends on` = `none` and `## Touches` = the file(s) the candidate names when it names them (grammar-valid), else `unknown`, and `--lint` reports it `ok`/`ok (declared unknown)` — one assertion per writer in its existing test file.
- [ ] AC-8 Given `skills/user-story-writing/SKILL.md`, when read, then it instructs the writer to FILL `## Touches` from its own file-impact reasoning (paths named in Scope), to use `unknown` only when it truly cannot, to put conditions in Scope (never prose in the section), and to ALWAYS write `## Depends on` (`none` when none); and `agents/product-owner.md`'s persist step agrees with it (no instruction left that omits `## Depends on` — when the PO cannot tell, it lists every earlier story of the same batch by path, which keeps the conservative behaviour while staying lint-clean). Its token budget entry stays within `check-token-budget.sh`.
- [ ] AC-9 Given `skills/automate-loop/SKILL.md` (the ONLY place the shapes are written — `commands/automate.md` gets at most a one-line pointer, per its "does not restate those contracts" rule), when read, then the `plan-waves` row documents `--explain` and `--lint` (inputs, output shapes, exit codes, read-only), and §2 intake states that folder/backlog intake under `--parallel N>1` (item 05) runs `plan-waves --lint` on the resolved Queue and prints `<k> of <n> items will run alone: …` before the Queue is confirmed, while sequential runs are unchanged (no new gate). No `--parallel` flag is added to the engine in this PR.
- [ ] AC-10 Given the running system, when `plan-waves --lint .supervisor/requirements/` and `plan-waves --explain` (over today's open item list, `--max 10`) run from this branch, then their real output is pasted into the PR body (Validation 3). The backlog backfill itself is NOT part of this PR (requirement Scope 5 — an operator step on `loomwright-meta`).
- [ ] AC-11 Given the whole change, when `bash scripts/ci-local.sh` runs, then it is green (doc-currency, citation drift, token budget, every `loomwright/scripts/test-*.sh`); the PR carries a `changelog.d/parallel-automate-10-touches-backfill-lint-and-explain.md` fragment and does NOT hand-edit `plugin.json` / `marketplace.json` / `CHANGELOG.md`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `plan-waves --explain` / `--lint`, writers emit Touches/Depends on, intake contract docs | ALL (AC-1 … AC-11) | 16–18 modify, 1 create | `quality-checklist`, `unit-testing`, `error-handling` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1 — the whole change (LAUNCHABLE; no siblings)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "--explain"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "--lint"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "ok (declared unknown)"}
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "## Touches"}
  - {kind: "symbol", path: "loomwright/scripts/propose-work.sh", name: "## Touches"}
  - {kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "## Touches"}
  - {kind: "symbol", path: "loomwright/scripts/propose-from-verify.sh", name: "## Touches"}
  - {kind: "symbol", path: "loomwright/scripts/automate-dismissed.sh", name: "## Depends on"}
  - {kind: "symbol", path: "loomwright/scripts/propose-work.sh", name: "## Depends on"}
  - {kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "## Depends on"}
  - {kind: "symbol", path: "loomwright/scripts/propose-from-verify.sh", name: "## Depends on"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "plan-waves --lint"}
  - {kind: "file", path: "changelog.d/parallel-automate-10-touches-backfill-lint-and-explain.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/propose-work.sh"
  - "loomwright/scripts/test-propose-work.sh"
  - "loomwright/scripts/propose-domain.sh"
  - "loomwright/scripts/test-propose-domain.sh"
  - "loomwright/scripts/propose-from-verify.sh"
  - "loomwright/scripts/test-propose-from-verify.sh"
  - "loomwright/commands/propose.md"
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/agents/product-owner.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/parallel-automate-10-touches-backfill-lint-and-explain.md"
external_requires: []
```

**Exact-name mandate:** `--explain` and `--lint` are the literal flag names on `automate-helpers.sh plan-waves`; `ok (declared unknown)` is the literal lint verdict text; the drafts carry literal `## Touches` and `## Depends on` H2 headings; the automate-loop SKILL documents the literal string `plan-waves --lint`. `prompt-token-budgets.json` / `ARCHITECTURE_CONTRACTS.md` / `SKILLS_INDEX.md` are companion lanes — touch them ONLY when the gate needs it (product-owner budget, skill version rows).

## Parallelism Analysis

### Dependency Graph
Single subtask — no graph.

### File Overlap Matrix
Not applicable (one subtask). A split would manufacture overlap: `--lint` is used by the writer tests (AC-6, AC-7) and the docs (AC-9) describe its output shapes.

### Batch Plan
One batch, one worker.

## Implementation Notes (for the worker)
- **Grammar reuse (AC-5):** refactor `_pw_touches` / `_pw_depends` so ONE awk produces both the planner's verdict and a diagnostic (line number, text, reason) — e.g. a mode variable that additionally prints `bad\t<N>\t<reason>\t<text>` rows. The default (planner) output must stay byte-identical.
- **`--explain` needs the reason recorded where the decision is made:** in the step-7 wave loop, when `_pw_intersect` refuses an item, record WHICH placed item and WHICH entry intersected, and whether that entry came from the item's own Touches (`declared`) or a companion rule (`companion: <when>` — keep the rule's `when` alongside each added path in `_pw_expand`). Dependency waits and the unknown/missing reasons come from `DEPJ`, `TS` and the `_pw_depends` verdict.
- **Exit-code / stdout contract unchanged for the planner path:** exit 1 with empty stdout on the existing error cases still holds with `--explain`; `--lint` has its own contract (AC-3).
- **Bash 3.2 / BSD:** no `declare -A`, no `${arr[@]}` on an empty array under `set -u`, no GNU-only `sed`/`awk` flags; pass multi-line values to awk via `ENVIRON`, never `-v`.
- **Mutation control (AC-4):** gate the mutant on non-empty + differs-from-original + `bash -n` before trusting it (repo lesson fa32a308).
- **No requirement file is committed** (branch mode). Test fixtures live in the test scripts' own temp dirs.
- **Running-system paste (AC-10):** run from the branch checkout against `.supervisor/requirements/` (present locally, gitignored).

## Skill References

| Skill | Why |
|---|---|
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |
| `skills/unit-testing/SKILL.md` | Assertion structure, fixture-per-shape |
| `skills/error-handling/SKILL.md` | Read-only helper exit-code discipline |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Refactoring the parser changes the planner's default output | HIGH | AC-1: every existing plan-waves assertion must pass unchanged; diff old/new output on the fixtures |
| Lint and planner drift into two grammars | HIGH | AC-5: one parser, and a test that asserts lint `ok` ⇔ planner `known` on every fixture |
| Requirement Touches under-declared: `/propose` drafts are written by three scripts, not `commands/propose.md` (Feasibility (Phase 2.5)) | MEDIUM | Lanes include `propose-work.sh` / `propose-domain.sh` / `propose-from-verify.sh` and their tests; the concurrent lane w1-08 does not touch them |
| Scope 3 depends on item 05 (`--parallel`), not merged (Feasibility (Phase 2.5)) | MEDIUM | AC-9 delivers the documented intake contract only; no engine flag added; the PR body says so |
| Path extraction from untrusted finding text in dismissed drafts | MEDIUM | AC-6: only grammar-valid tokens that exist under the repo root; existence test only; finding text remains `> `-quoted data |
| Draft content change breaks content-addressed rewrite/retire logic in `automate-dismissed.sh` | MEDIUM | The new `## Touches` depends on the finding AND on which named files exist when the draft is written (AC-6's existence test), so a file added/removed between passes changes the rendered body. The draft's identity must not depend on it: the h8 name and ledger decision come from origin/source/finding only. Add a test that re-renders the same finding after its named file is removed and asserts the same draft name and the same ledger decision; `test-automate-dismissed.sh` otherwise stays green unchanged |
| `agents/product-owner.md` edit exceeds its token budget | LOW | `check-token-budget.sh` runs in `ci-local.sh`; raise the declared budget in `prompt-token-budgets.json` + `ARCHITECTURE_CONTRACTS.md` only if needed |
| Skill version bump drifts from `SKILLS_INDEX.md` | LOW | Bump the frontmatter `version`/`lastUpdated` of each edited skill and its index row in the same commit |
| Acceptance criteria 1–2 of the requirement (≥1 wave of 5; `--lint` exit 0 on the backlog) need the operator backfill on `loomwright-meta`, which this PR does not do | MEDIUM | AC-10 pastes the real `--lint` / `--explain` output; the backfill is the follow-up operator step named in the requirement |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-04-touches-lint-and-explain.md

## Outcome
- **Status:** completed
- **Completed:** 2026-10-04T11:44:25Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/377
- **Branch:** feature/parallel-automate-10-touches-lint-and-explain
- **Files changed:** 18
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** plan-waves --lint/--explain (one shared grammar, default output byte-identical); dismissed + 3 /propose writers emit Depends on/Touches; user-story-writing + both product-owner prompt copies aligned; automate-loop SKILL documents both flags and the --parallel intake contract. Heal: iteration 1 FAIL (HIGH mirrored-prompt drift in commands/product-owner.md) → fix f0979ff → iteration 2 PASS. Ground truth 2/2.

## Not verified
- **/automate --parallel N>1 intake printing the lint summary** — item 05 has not merged; only the documented contract ships (subtask 1)
- **Product Owner / user-story-writing producing lint-clean stories in a live session** — prompt-text change; no agent was run against a real goal (subtask 1)
