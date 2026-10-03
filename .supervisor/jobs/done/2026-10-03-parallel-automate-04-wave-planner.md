# Supervisor Job: Wave planner — `Depends on` / `Touches` sections + `automate-helpers.sh plan-waves`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (only this run's gitignored `.supervisor/automate/` run file changed)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (3 linked worktrees from other sessions under `.claude/worktrees/` — not this run's, left alone)
- **Source requirement:** .supervisor/requirements/parallel-automate/04-wave-planner.md
- **Base commit:** 1f32d169b992912265b2aa82a0b0b9daa23771cb

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe + `jq`, beside the other `automate-helpers.sh` subcommands; same stack. |
| 2 | Dependency Availability | GO | `jq` is already a hard dependency of the helper (`JQ="${LOOMWRIGHT_JQ_BIN:-jq}"`); the tracked-project-config precedent exists (`classify-risk.sh` reads committed `<root>/.agent/risk.json`, strict shape, add-only). |
| 3 | Architecture Fit | GO | A pure, read-only subcommand of the existing helper library (`skills/automate-loop/SKILL.md` §1.5: the helper is read-only toward the work it drives). Nothing in the sequential loop calls it — item 05 is its only future caller. |
| 4 | Scope vs Supervisor Capability | GO | One subcommand + one test group + two producer prose edits + one skill row + one config file. Single worker. |
| 5 | Hard Blockers | CAUTION | Three items in this queue already declare sections in the strict grammar (05, 06, 07 — all `## Status: parked`), with blank lines inside sections and `../<folder>/<file>.md` path ids; the grammar MUST accept blank lines and doc-relative paths or Scope 6's "every `Touches` section in THIS queue parses" fails. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Give each requirement two optional, strictly-parsed sections — `## Depends on` and `## Touches` — and add a pure, read-only `automate-helpers.sh plan-waves <runfile|dir|item-list> --max N` that turns a queue into waves of items safe to run together (dependency-ordered, disjoint expanded `Touches` sets, at most N per wave), plus a tracked companion table, producer guidance (Product Owner / user-story-writing), a skill reference row and a test group with two mutation controls. Nothing on the sequential path calls it.

**Problem Statement:**
The owner (and item 05's future `/automate --parallel N` coordinator) needs to know which queue items can run at the same time.
Today that knowledge exists only as prose in overview files (`harness-port/00-overview.md` §Order: "03 is independent. 05 → 07 (both edit `skills/review-heal/SKILL.md` …)"); `resolve-folder` sorts by filename and `resolve-backlog` follows document order, and Phase 1.5 pre-flight cannot see sibling lanes whose PRs are not open yet.
Success looks like: a deterministic planner whose every wave is provably free of shared (companion-expanded) paths and unmet dependencies, that fails closed (runs an item alone) whenever a declaration is missing or malformed, and that the sequential path never invokes.

## Acceptance Criteria
- [ ] AC1 (section grammar): Given a requirement file, when `plan-waves` reads it, then it locates `^## Depends on$` and `^## Touches$` headings OUTSIDE fenced code blocks (a ```` ``` ```` fence toggles; headings inside a fence are ignored), takes each section's body up to the next `^# ` / `^## ` heading or EOF, and IGNORES blank lines. **`## Touches`:** each non-blank line is exactly one repo-relative path, nothing else on the line — allowed characters `[A-Za-z0-9._/@+-]` only (so a backtick, space, `|`, `#`, `:`, `,`, any glob character `* ? [ ] { }` is a parse failure), no leading `/`, no `..` segment, no `//`; a trailing `/` marks a directory. The single line `unknown` means "not known". ANY line that does not parse, `unknown` mixed with other lines, an empty section, or the heading appearing twice ⇒ the WHOLE section is `unknown` (never a partial list). **`## Depends on`:** each non-blank line is `none` (only as the sole line), a 1–3 digit item id (`01`, `3`), or a relative path ending in `.md` in the same character set; a section that does not parse is treated exactly like a MISSING section (AC4 implicit rule).
- [ ] AC2 (id resolution): Given a dependency line, when it is resolved, then a numeric id `NN` resolves to the single `NN-*.md` (exact prefix up to the first `-`, with numeric equality so `3` and `03` both match `03-x.md`) in the DEPENDENT item's own directory; a path resolves relative to the dependent item's directory (so 05's `../agnostic-phase1/04-non-interactive-gates.md` resolves). Zero matches, more than one match, or a path that is not an existing regular `*.md` file ⇒ `plan-waves` exits 1 with `plan-waves: unknown dependency <id> in <item>` on stderr and prints NOTHING on stdout. **One comparison key everywhere:** every resolved dependency, every plan-set item and every run-file `## Queue` row is compared by its PHYSICAL ABSOLUTE path — `"$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"` (Queue rows and item-list lines resolved relative to `--root`) — for plan-set membership, the AC3(a) Queue lookup and cycle detection alike; items are still PRINTED as written in the input. A test covers a `../other/NN-x.md` dependency that IS in the plan set and must order the waves.
- [ ] AC3 (merged-done): Given a resolved dependency, when eligibility is decided, then it counts as **merged-done** ONLY when: (a) the input is a run file and the dependency appears in its `## Queue` as `- [x] <path>` with NO `# skipped:` / `# abandoned:` mark, OR (b) the dependency file carries a done stamp. **Closed-out requirement files carry TWO `## Status:` headings** (the original `## Status: pending` and, below it, the close-out `## Status: done` / `done_with_escalation` — e.g. `parallel-automate/01-version-bump-script.md`), so never read only the first heading: the file is done when ANY `^## Status:` line matches the existing `is_done` predicate (reuse it, do not re-implement it), and it is ABANDONED (never landed) when ANY `## Status:` line contains `done_with_escalation — ABANDONED` (abandoned wins over done); parked/proposed come from the existing `is_not_ready` and apply only when the file is not done. A W. fixture carries a `pending` heading followed by a close-out `done` heading and must count as merged-done. A dependency checked off `# skipped:`/`# abandoned:`, or stamped `done_with_escalation — ABANDONED` ⇒ its dependents print `blocked <item>: waits on <id> (<skipped|abandoned> — never landed)`; a dependency stamped `## Status: parked` or `proposed` ⇒ `blocked <item>: depends on <parked|proposed> <id>`; a dependency that is neither done nor in the plan set (e.g. a pending file in another folder) ⇒ `blocked <item>: waits on <id>`. A dependency that is itself in the plan set orders the waves (AC5). A dependent of a blocked item is blocked too (`waits on <its id>`).
- [ ] AC4 (implicit dependency): Given an item with NO `## Depends on` section (or one that does not parse), when planned, then it depends on EVERY earlier item of the PLAN SET in input order — not on already-checked queue entries (those are done or deliberately skipped, and the sequential engine does not wait on them either). So an undeclared queue plans one item per wave, in queue order.
- [ ] AC5 (wave building): Given the plan set, when waves are built, then wave `k` is filled greedily in input order from items whose every in-plan-set dependency sits in a wave `< k` and every out-of-set dependency is merged-done; an item joins wave `k` only when its EXPANDED `Touches` set (AC6) intersects no item already in wave `k` and wave `k` holds fewer than `N` items. **An item whose `## Touches` is missing or `unknown` runs ALONE** — it is placed only into an empty wave, and that wave then takes no other item. Intersection is conservative literal-prefix on normalized entries (trailing `/` stripped): `a` and `b` intersect iff `a == b`, or `a` starts with `b/`, or `b` starts with `a/`. No glob-vs-glob matching.
- [ ] AC6 (companion expansion — tracked project data, not hard-coded): Given `<root>/.agent/companions.json` (committed, strict shape `{"schema_version":1,"companions":[{"when":"<case glob>","add":["<path>",…]} | {"when":"<case glob>","new":true,"add":[…]}]}`, read with `jq`, `when` matched with an UNQUOTED bash `case` pattern — so `*` crosses `/` and `loomwright/agents/*.md` also matches nested files (conservative) — and matched CASE-SENSITIVELY, unlike `classify-risk.sh`, which lowercases both sides), when an item's `Touches` set is expanded, then every rule whose `when` matches a FILE entry adds its `add` paths (a `"new": true` rule fires only when that entry does NOT exist under `<root>` — a file the item will create); a DIRECTORY entry `D/` fires a rule — `new` rules included, regardless of whether `D/` exists (conservative) — when the rule's literal prefix (the `when` text up to its first glob character) starts with `D/` or `D/` starts with that prefix. Expansion is ONE pass (added paths are not themselves re-expanded — stated in the header). File absent ⇒ no expansion and ONE stderr line `plan-waves: no <root>/.agent/companions.json — no companion expansion`; file present but not that shape, or `jq` absent while the file exists ⇒ exit 1 `plan-waves: companions_malformed <reason>` and nothing on stdout (fail CLOSED — a silently ignored table would let two items that both drag `SKILLS_INDEX.md` share a wave; this deliberately DEPARTS from `classify-risk.sh`, which ignores a malformed `risk.json` and exits 0 — copy its `case` matching, never its malformed-file handling). This repo commits `.agent/companions.json` with: `loomwright/skills/*/SKILL.md` ⇒ `loomwright/skills/SKILLS_INDEX.md`; `loomwright/agents/*.md` ⇒ `loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md`; and `"new": true` rules for `loomwright/agents/*`, `loomwright/commands/*`, `loomwright/skills/*` ⇒ EVERY surface in `scripts/check-doc-currency.sh`'s `FILES` array (verified at base commit: `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`, `loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — a new command also forces a `### /<cmd>` section in `agent-help.md`). `check-doc-currency.sh`'s `FILES` array is the AUTHORITY for that set (house rule "restated list updated in the same change"): the skill row says so, and a W. assertion parses the `FILES=(` array out of the real `scripts/check-doc-currency.sh` and fails when any entry is missing from the shipped `new` rules' add-set, so the copy cannot drift silently. The automate-loop skill row documents the file's shape and names this repo's file as the shipped example; the helper itself contains NO path under `loomwright/`.
- [ ] AC7 (output + exit codes): Given `automate-helpers.sh plan-waves <input> --max N [--root <checkout>]`, when it succeeds, then stdout is exactly `wave <k>: <item> <item> …` lines (k from 1, items as written in the input) followed by one `blocked <item>: …` line per unplaced item, and it exits 0. `<input>` is: a run file (`is_run_file`) ⇒ the plan set is its unchecked `- [ ]` Queue items, and checked rows feed AC3(a); a directory ⇒ the plan set is `resolve_folder`'s output (done / proposed / parked files excluded, so parked files only ever appear as dependencies); any other regular file ⇒ one item path per non-blank, non-`#` line. `--max` missing or not a positive integer, a missing input, or an unknown option ⇒ exit 1 with usage. A dependency CYCLE among plan-set items (explicit or via AC4) ⇒ exit 1, `plan-waves: dependency cycle: <items>` on stderr naming every item in the cycle, NOTHING on stdout — the whole plan is computed before anything is printed. `--root` defaults to `git rev-parse --show-toplevel` (read-only), else `$PWD` — do NOT reuse the helper's `_meta_root` (it runs `git worktree list --porcelain`, outside AC8's allowance); an option-shaped `--root` value is refused (same rule as `meta-entry`).
- [ ] AC8 (read-only): Given any `plan-waves` call, when it runs, then it writes no file (temp files only under `mktemp -d`, removed by a trap), and runs no `git` command other than the read-only `rev-parse --show-toplevel` and no `gh` at all; `git status --porcelain` of the checkout is byte-identical before and after (Validation 3 pastes both).
- [ ] AC9 (never on the sequential path): Given the finished branch, when checked, then `git grep -n 'plan-waves' -- loomwright` lists only `loomwright/scripts/automate-helpers.sh` (the function, dispatch arm and header line), `loomwright/scripts/test-automate-helpers.sh`, and `loomwright/skills/automate-loop/SKILL.md` (its §1.5 reference row, whose text says it is called ONLY for `--parallel N>1` by item 05 and never when N = 1 — the guarantee is by not calling it, since `--max 1` is NOT equal to queue order once an item depends on a later-numbered one). `CHANGELOG.md` / the `changelog.d/` fragment may name it (a release note, not a caller). `resolve-folder` and `resolve-backlog` are unchanged.
- [ ] AC10 (producers): Given `loomwright/skills/user-story-writing/SKILL.md` and `loomwright/agents/product-owner.md`, when this item lands, then the story template carries `## Depends on` and `## Touches` sections with the strict grammar spelled out (one id/path per line, nothing else, `none` / `unknown` sentinels, no backticks, no bullets, no globs), and Product Owner's Beads-absent file-fallback step 2 (the "**Persist** each new story as `.supervisor/requirements/{YYYY-MM-DD-HHMMSS}-{slug}.md`" step) says each persisted story file carries both sections in that grammar — `unknown` when the touched set is not known — as H2 headings regardless of the surrounding template's heading depth. Both edits state how the new sections relate to the existing prose `### Dependencies` / `#### Dependencies` block: `## Depends on` / `## Touches` are the machine-read declarations; the prose block stays for humans and is never parsed. The skill's `version:`/`lastUpdated:` frontmatter is bumped (minor) and its `SKILLS_INDEX.md` row updated (`scripts/check-skills-index-sync.sh` green). `product-owner` stays within its declared budget (`bash scripts/check-token-budget.sh`); if it does not, re-measure and update `loomwright/docs/prompt-token-budgets.json` AND the mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" in the same commit.
- [ ] AC11 (skill row): Given `loomwright/skills/automate-loop/SKILL.md` §1.5, when this item lands, then it gains ONE `plan-waves` table row (purpose, input shapes, rules in one line each, exit codes, the `.agent/companions.json` shape with this repo's file as the shipped example, "read-only; called only by `--parallel N>1` (item 05); never called when N = 1; the sequential loop never calls it") and the helper header's Subcommands list gains the matching line. The skill's `version:` / `lastUpdated:` are bumped (minor) and its `SKILLS_INDEX.md` row updated. No other SKILL.md prose changes (the "diff confined to new sections" invariant of `00-overview.md`).
- [ ] AC12 (tests — new group `W.` in `loomwright/scripts/test-automate-helpers.sh`, fixtures in `mktemp -d` with `--root` pointing at a fixture root, no network, no `gh`): disjoint items share a wave; prefix-intersecting items (`a/` vs `a/b.sh`, `a/b` vs `a/b`) do not; companion expansion separates two items that each edit a DIFFERENT `x/skills/<s>/SKILL.md` (fixture companions file); a `"new": true` rule fires for a missing path and not for an existing one; dependency ordering across waves; skipped / abandoned dependency (run-file `# skipped:` row AND an `ABANDONED` stamp) ⇒ `blocked … never landed`; parked dependency ⇒ `blocked … depends on parked`; out-of-set pending dependency ⇒ `blocked … waits on`; transitive blocked; missing / `unknown` / malformed (backtick, glob, `a|b`, trailing prose, bullet) `Touches` runs alone; undeclared queue ⇒ one item per wave in queue order; explicit cycle AND implicit-rule cycle ⇒ exit 1, stdout empty, items named; unknown id (zero match, two matches) ⇒ exit 1, stdout empty; `--max` respected (three mutually disjoint items, `--max 2` ⇒ waves of 2 + 1); companions file absent ⇒ stderr note + plan proceeds, malformed ⇒ exit 1; fenced `## Touches` ignored; the `harness-port` shape from a fixture copy (01→04→06, 02, 03 independent, 05→07 sharing `skills/review-heal/SKILL.md`) ⇒ 03 never shares a wave with an item it intersects and 07 lands strictly after 05; the five-item acceptance fixture (two disjoint pairs + one dependent, `--max 3`) prints the expected waves byte-for-byte; and EVERY `## Touches` section under `.supervisor/requirements/parallel-automate/` in the REAL repo parses (not `unknown`) — read through a small test-only seam or a `plan-waves` item-list run, stated in the test. **Mutation controls (gated: mutant non-empty + differs from the original + `bash -n`, per lesson `[fa32a308]`):** (i) a copy of the helper where a missing `Touches` is treated as an EMPTY set MUST turn the "missing Touches runs alone" assertion red; (ii) a run with the companion table removed (no `.agent/companions.json` in the fixture root) MUST turn the two-SKILL.md separation assertion red. The test asserts each control turns red and that the real helper stays green.
- [ ] AC13 (bump, P7): Given this PR, when it is finalized, then its LAST commit is the output of `bash scripts/bump-version.sh` with this item's fragment `changelog.d/parallel-automate-04-wave-planner.md` (first line `<!-- bump: minor -->`); the three fragments already pending on `main` (`curation-status-test-json-stderr-split.md`, `harvest-c3-path-independent.md`, `twin-scrub-test-branch-mode.md`) fold into the same entry, which is legal per `changelog.d/README.md`. Never hard-code a target version.

## Validation (must pass before merge — evidence goes in the PR body)
1. **Baseline, before and after:** `bash scripts/ci-local.sh` on the untouched base commit AND on the finished branch (it runs every `loomwright/scripts/test-*.sh`, the root `scripts/test-*.sh` and the `check-*` gates in one pool); record `<passed>/<total>` and the count of `SKIP` lines for both. No existing assertion may be edited.
2. **Unchanged path:** for every queue folder under `.supervisor/requirements/` with pending items, `resolve-folder` output on base vs branch is byte-identical (loop + `diff`, pasted); `resolve-backlog` likewise on every `_BACKLOG.md` present (or "none present" stated); AC9's `git grep` pasted.
3. **Running system:** `plan-waves .supervisor/requirements/parallel-automate --max 3` and `plan-waves .supervisor/automate/automate-2026-10-01-142337.md --max 3` on THIS repo, and `plan-waves --max 3` on a scratch copy of `harness-port` with the sections added from its `00-overview.md` §Order and the `## Status:` stamps reset to pending; paste the waves and `blocked` lines, check by hand that no wave pairs two items sharing an expanded path, and paste `git status --porcelain` before and after (identical). **Honest limit, stated in the PR body:** both in-repo runs plan exactly ONE item by construction (the folder's `resolve-folder` set is only 04 — 00–03 done, 05–07 parked — and the run file's only unchecked row is 04), so multi-item evidence comes from the `harness-port` scratch copy and the W. fixtures. `operator-run/` files are not scanned by AC12's "every `Touches` parses" check (S1's `## Depends on` holds `M1`, which is not an id and would read as a missing section — harmless while S1 is parked and declares no `Touches`).
4. **A failure this must catch:** the two AC12 mutation controls, shown failing.
5. **Rollback:** `git revert`. The two sections are ignored by everything else; `.agent/companions.json` is read only by `plan-waves`.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | plan-waves + companions table + producers + skill row + tests + this PR's own bump | all | 8 modify (loomwright/scripts/automate-helpers.sh, loomwright/scripts/test-automate-helpers.sh, loomwright/skills/automate-loop/SKILL.md, loomwright/skills/user-story-writing/SKILL.md, loomwright/skills/SKILLS_INDEX.md, loomwright/agents/product-owner.md, CHANGELOG.md + 2 manifests via the bump; prompt-token-budgets.json + ARCHITECTURE_CONTRACTS.md only if AC10 requires), 1 create (.agent/companions.json) + 1 fragment created then folded | `skills/unit-testing/SKILL.md`, `skills/user-story-writing/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |

**Fixed in-subtask order (commit after each step):** (a) baseline `bash scripts/ci-local.sh` on base (Validation 1) + capture `resolve-folder`/`resolve-backlog` base outputs (Validation 2) into the scratchpad; (b) `plan_waves` in `automate-helpers.sh` (function + dispatch arm + header line) + `.agent/companions.json` + test group `W.` with both mutation controls → `bash loomwright/scripts/test-automate-helpers.sh` green under `/bin/bash`; (c) producer edits (user-story-writing template + version/index row, product-owner persistence step) → `check-skills-index-sync.sh` + `check-token-budget.sh` green; (d) automate-loop §1.5 row + version/index row; (e) Validation 2–4 evidence; full `bash scripts/ci-local.sh` green on the branch; (f) write `changelog.d/parallel-automate-04-wave-planner.md` with `<!-- bump: minor -->`; (g) `bash scripts/bump-version.sh` — its result is the PR's LAST commit.

### Subtask Contracts

```yaml
# Subtask 1 — whole item, single-agent (LAUNCHABLE)
provides:
  - {kind: "file", path: ".agent/companions.json"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "plan_waves"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "plan-waves"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "companions_malformed"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "plan-waves"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "plan-waves"}
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "## Touches"}
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "## Touches"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/agents/product-owner.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - ".agent/companions.json"
  - "changelog.d/*.md"
  - "CHANGELOG.md"
  - ".claude-plugin/marketplace.json"
  - "loomwright/.claude-plugin/plugin.json"
external_requires:
  - "jq, bash 3.2 (macOS) and GNU bash (CI)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/user-story-writing/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Existing queue declarations use blank lines inside a section and `../<folder>/<file>.md` ids (05's `## Depends on`) (Feasibility (Phase 2.5) #5) | MEDIUM | AC1 ignores blank lines; AC2 resolves paths relative to the dependent item's directory; AC12 asserts every real `parallel-automate` `Touches` section parses. |
| A silently ignored or partially read companion table lets two items that both drag a shared index file share a wave | HIGH | AC6 fails CLOSED on a malformed table or missing `jq` (exit 1, nothing printed); absence is legitimate but announced on stderr; mutation control (ii) proves the table is load-bearing. |
| Reading only the FIRST `## Status:` heading of a closed-out requirement (pending, then done) reports merged work as pending (Plan Review attempt 1, MEDIUM) | MEDIUM | AC3 reuses `is_done` over ANY heading; a W. fixture carries both headings. |
| Comparing dependency paths as text: `../other/x.md` never equals a repo-relative Queue row (Plan Review attempt 1, MEDIUM) | MEDIUM | AC2's single physical-absolute-path key for membership, Queue lookup and cycles; a W. test with an in-set `../` dependency. |
| `.agent/companions.json` restates `check-doc-currency.sh`'s `FILES` list and can drift (house rule; Plan Review attempt 1) | MEDIUM | AC6 names `FILES` as the authority and a W. assertion fails when any `FILES` entry is missing from the shipped `new` rules. |
| Fail-open defaults: treating a missing/unknown `Touches` as empty, or a malformed `Depends on` as "no deps" | HIGH | AC1/AC4/AC5: missing/unknown `Touches` runs alone, malformed `Depends on` falls back to the implicit "every earlier item" rule; mutation control (i). |
| Directory entries and glob companion patterns: glob-vs-glob matching is unspecifiable in bash 3.2 | MEDIUM | AC5 literal-prefix intersection only; AC6 literal-prefix rule for directory entries (conservative — may over-separate, never under-separate); globs inside `Touches` are a parse failure. |
| Cycle via the implicit rule (an earlier item explicitly depending on a later undeclared one) | MEDIUM | AC7 computes the full plan before printing; AC12 tests the implicit-rule cycle. |
| `git grep plan-waves` hitting `CHANGELOG.md` after the bump fold reads as "a caller" | LOW | AC9 scopes the grep to `loomwright/` and states the CHANGELOG mention is a release note. |
| `product-owner` prompt growth exceeding its token budget (776 proxy tokens of headroom at base) | LOW | Keep the PO edit to the persistence step; AC10 re-measure path if `check-token-budget.sh` fails. |
| Prose-is-program: the new SKILL.md row and PO/skill text are read by agents as instructions | MEDIUM | Confine prose to one new row + the template/persist-step lines; no change to existing §6 loop prose (the `00-overview.md` "diff confined to new sections" invariant). |
| bash 3.2 / BSD userland (no assoc arrays, empty arrays under `set -u`, `sed -i`) | MEDIUM | Parallel indexed arrays or temp files + `grep -F`; guard `"${arr[@]}"` (project memory `[ead04b14]`); run the test under `/bin/bash` on macOS. |
| Vendor coupling: `automate-helpers.sh` / its test / SKILL text are core class | LOW | Add no vendor token (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/`); `scripts/check-vendor-coupling.sh` runs in `ci-local.sh`. |
| The bump version depends on `main` at bump time (lesson `[6e0baac1]`) | LOW | The bump is the LAST commit and reads the live `plugin.json`; if `main` moves before merge, drop the bump commit, rebase, re-run `bash scripts/bump-version.sh`. |

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

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-03-parallel-automate-04-wave-planner.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-03T13:17:52Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/365
- **Branch:** feature/parallel-automate-04-wave-planner
- **Files changed:** 13
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** read-only `automate-helpers.sh plan-waves` (strict `## Depends on` / `## Touches` grammar, merged-done deps with row-mark precedence, companion-expanded disjoint waves, fail-closed) + `.agent/companions.json` + producer sections + automate-loop §1.5 row + W. tests (329/0); 2 heal fix iterations (row-mark precedence and `.` segments; re-bump so bump-version.sh is the last commit); v15.120.0. Phase 4.5 PASS on iteration 3; 6 findings dismissed (marker round=3); risk_classification high_risk=true (advisory).

## Not verified
- **item 05 --parallel N>1 coordinator reading plan-waves output** — item 05 does not exist yet (subtask 1)
- **W. tests under GNU bash/mawk on CI Ubuntu** — only run on macOS bash 3.2 locally (subtask 1)
