# 04 — Wave planner: `Depends on` / `Touches` + `plan-waves`

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/user-story-writing/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/agents/product-owner.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md

## Problem
Whether two queue items may run together is known today only as prose in an overview file ("03 is independent.
05 → 07 (both edit `skills/review-heal/SKILL.md` …)" in `harness-port/00-overview.md`). `resolve-folder` sorts by
filename and `resolve-backlog` follows document order; neither knows about dependencies or shared files. Phase 1.5
pre-flight cannot help: lanes start together and their PRs open hours later, so there is no sibling PR to see.

## Goal
Each requirement declares what it depends on and what it touches; a pure, read-only helper turns a queue into
waves of items that are safe to run together. The helper is used ONLY by parallel runs — the sequential path never
calls it, so it cannot reorder a sequential queue.

## Scope
1. **Two optional sections in a requirement file, strict grammar:**
   - `## Depends on` — one item id per line (`01`, `03`, or a relative path for another folder), or `none`.
   - `## Touches` — **one repo-relative path per line, nothing else on the line** (no backticks, no annotations,
     no `a|b` alternation, no prose). A trailing `/` means a directory. `unknown` means "not known".
   A line that does not parse makes the whole section `unknown` — never a partial list.
2. **`automate-helpers.sh plan-waves <runfile|item-list> --max N`** — read-only; prints `wave <k>: <item> …` and,
   for every item it could not place, `blocked <item>: waits on <id>` / `blocked <item>: depends on parked <id>`.
   Rules, in order:
   - an item is eligible only when every dependency is **merged-done**: `- [x]` WITHOUT a `# skipped:` /
     `# abandoned:` mark, or a `## Status: done` stamp that is not `done_with_escalation — ABANDONED`. A dependency
     that was skipped or abandoned blocks its dependents (they would run on work that never landed);
   - two items share a wave only when their expanded `Touches` sets do not intersect;
   - **intersection is conservative literal-prefix:** two entries intersect when one is a path-prefix of the other
     (directory boundary) or they are equal. No glob-vs-glob matching (unspecifiable in bash 3.2); an entry
     containing a glob character makes the section `unknown`;
   - **`Touches` missing or `unknown` ⇒ the item runs ALONE in its wave;**
   - **no `Depends on` section ⇒ depends on every earlier item in queue order;**
   - at most `N` items per wave; a dependency cycle or unknown id ⇒ exit 1 naming the items, nothing printed.
3. **Companion expansion (what CI forces).** Before intersecting, expand each `Touches` set with a declared table
   of files a change drags along:
   - any `loomwright/skills/*/SKILL.md` ⇒ `loomwright/skills/SKILLS_INDEX.md`;
   - any `loomwright/agents/*.md` ⇒ `loomwright/docs/prompt-token-budgets.json` and
     `loomwright/docs/ARCHITECTURE_CONTRACTS.md`;
   - a new file under `loomwright/agents/`, `commands/` or `skills/` ⇒ the doc-currency count surfaces
     (`plugin.json`, `marketplace.json`, `README.md`).
   The table is project data read from tracked config, with this repo's entries as the shipped example — the
   plugin does not hard-code this repo's paths.
4. **Never called when N = 1.** Item 05 invokes `plan-waves` only for `--parallel N>1`. State this in the skill row.
   (An earlier draft claimed "`--max 1` equals today's order"; that is false as soon as an item declares a
   dependency on a later-numbered item, so the guarantee is by not calling it.)
5. **Producers.** Product Owner / user-story-writing emit both sections in the strict grammar; an unknown touched
   set is emitted as `unknown`.
6. **Tests** (new group in `test-automate-helpers.sh`): disjoint items share a wave; prefix-intersecting items do
   not; companion expansion separates two items that each edit a different SKILL.md; dependency ordering; skipped
   / abandoned dependency ⇒ `blocked`; parked dependency ⇒ `blocked`; missing / `unknown` / malformed `Touches`
   runs alone; undeclared queue ⇒ one item per wave in queue order; cycle ⇒ exit 1; `--max` respected; the
   `harness-port` shape (03 independent, 05 before 07) from a fixture; every `Touches` section in THIS queue
   parses. **Mutation controls:** treating a missing `Touches` as empty must fail; removing the companion table
   must fail the two-SKILL.md test.

## Non-goals
Running anything in parallel (item 05). Inferring `Touches` with an LLM pass. Changing `resolve-folder` /
`resolve-backlog`. Detecting a WRONG `Touches` list — the stated limit: the planner trusts the declaration; a wrong
one surfaces as a merge conflict, which item 06 handles by parking that lane.

## Acceptance criteria
- `plan-waves --max 3` on a five-item fixture (two disjoint pairs + one dependent) prints the expected waves.
- An undeclared queue plans one item per wave in queue order.
- The helper writes nothing and runs no `git`/`gh` mutation.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** `resolve-folder` and `resolve-backlog` produce byte-identical output before and after on
   every existing queue folder with pending items (loop + `diff`, pasted). `git grep -n 'plan-waves'` shows no
   caller outside the helper, its test and the skill's reference row.
3. **Running system:** `plan-waves --max 3` on THIS queue folder and on a fixture copy of `harness-port`; paste the
   waves and the `blocked` lines, and check by hand that no wave pairs two items sharing an expanded path.
   `git status --porcelain` unchanged by the call.
4. **A failure this must catch:** the two mutation controls in Scope 6, shown failing.
5. **Rollback:** `git revert`. The two sections are ignored by everything else.

## Verified premises (re-check before starting)
- `automate-helpers.sh` `resolve_folder` (sorted `*.md`, skips done / proposed / parked) and `resolve_backlog`
  (document order, skips checked / ✅ lines).
- `harness-port/00-overview.md` §Order — the prose this replaces.
- Red-team report (not re-run by the author): `check-skills-index-sync.sh` forces `SKILLS_INDEX.md` on a SKILL.md
  edit — confirm the script name and trigger before building the companion table.
- `automate-loop/SKILL.md` §1.5: `automate-helpers.sh` is read-only toward the work it drives.

## Status: pending

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-03T13:17:52Z
- **Brief:** .supervisor/jobs/done/2026-10-03-parallel-automate-04-wave-planner.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/365
