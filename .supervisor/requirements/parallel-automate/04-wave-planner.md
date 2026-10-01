# 04 — Wave planner: `Depends on` / `Touches` + `plan-waves`

## Depends on
none

## Touches
`loomwright/scripts/automate-helpers.sh` (new `plan-waves` subcommand), `loomwright/scripts/test-automate-helpers.sh`,
`loomwright/skills/automate-loop/SKILL.md` (§1.5 table row + §2 note), `loomwright/skills/user-story-writing/SKILL.md`
and `loomwright/agents/product-owner.md` (emit the two sections), `loomwright/docs/prompt-token-budgets.json` (if
product-owner grows)

## Problem
Whether two queue items may run together is known today only as prose in an overview file ("03 is independent.
05 → 07 (both edit `skills/review-heal/SKILL.md` …)" in `harness-port/00-overview.md`; "run sequentially, never in
parallel" in `agnostic-phase1/00-overview.md`). `resolve-folder` sorts by filename and `resolve-backlog` follows
document order; neither knows about dependencies or shared files. A parallel run needs that as data.

## Goal
Each requirement declares what it depends on and what it touches; a pure, read-only helper turns a queue into
waves of items that are safe to run together.

## Scope
1. **Two optional sections in a requirement file:**
   - `## Depends on` — item ids from the same folder (`01`, `03`), or `none`.
   - `## Touches` — repo-relative paths or globs, comma- or line-separated.
   Parsing is tolerant in the same way `brief-pointer.sh` is (backticks, trailing annotations) and lives in ONE
   function.
2. **`automate-helpers.sh plan-waves <runfile|item-list> [--max N]`** — read-only, prints one line per wave:
   `wave <k>: <item> <item> …`. Rules, in order:
   - an item is eligible only when every `Depends on` id is done (checked `- [x]` or `## Status: done`);
   - two items share a wave only when their `Touches` sets do not intersect (glob-aware; a directory entry
     intersects everything under it);
   - **an item with no `Touches` section runs ALONE in its wave** (unknown ⇒ assume it overlaps everything);
   - an item with no `Depends on` section is treated as depending on every EARLIER item in queue order — i.e. an
     undeclared queue plans exactly as today's sequential order;
   - at most `N` items per wave (default 1);
   - a dependency cycle or an unknown id ⇒ exit 1 naming the items (fail CLOSED, nothing printed).
3. **`--max 1` output equals today's queue order**, one item per wave. Pin this as a test: it is the proof that the
   planner cannot change sequential behaviour.
4. **Ignore list for ever-shared files.** A small declared list of paths that never count as an intersection —
   empty by default. (After item 01 the version files no longer need it; do not pre-populate it.)
5. **Producers.** Product Owner / user-story-writing emit both sections for generated requirement files; when the
   touched set is not known they emit `## Touches` as `unknown`, which the planner treats as "runs alone".
6. **Tests** (in `test-automate-helpers.sh`, new group): disjoint items share a wave; intersecting items do not;
   dependency ordering; missing-`Touches` runs alone; undeclared queue ⇒ sequential; cycle ⇒ exit 1; `--max`
   respected; glob vs literal intersection; the `harness-port` shape (03 independent, 05 before 07) reproduced
   from a fixture. **Mutation control:** treating a missing `Touches` as empty must fail a test.

## Non-goals
Running anything in parallel (item 05). Inferring `Touches` with an LLM pass — a follow-up if the pilot shows
authors do not fill it in. Changing `resolve-folder` / `resolve-backlog` ordering.

## Acceptance criteria
- `plan-waves --max 3` on a fixture of five items (two disjoint pairs + one dependent) prints the expected waves.
- `plan-waves --max 1` on any existing queue folder prints that folder's current order, one item per wave.
- The helper writes nothing and runs no `git`/`gh` mutation.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body.
2. **Unchanged path:** for EVERY existing queue folder under `.supervisor/requirements/` that has pending items,
   `plan-waves --max 1` prints the same items in the same order as `resolve-folder` does today (a loop comparing
   the two, output pasted). `resolve-folder` and `resolve-backlog` produce byte-identical output before and after
   the change on those same folders. Nothing in the per-item loop calls `plan-waves` yet (`git grep` proves it).
3. **Running system:** run `plan-waves --max 3` on THIS queue folder (`parallel-automate`, whose items carry real
   `Depends on` / `Touches`) and on `harness-port`; paste the waves and confirm by hand that no wave pairs two
   items sharing a file. Confirm `git status --porcelain` is unchanged by the call (read-only).
4. **Rollback:** `git revert` of the PR. The two new requirement-file sections are ignored by everything else, so
   requirement files that already carry them need no change.

## Verified premises (re-check before starting)
- `automate-helpers.sh` `resolve_folder` (sorted `*.md`, skips done / proposed / parked) and `resolve_backlog`
  (document order, skips checked / ✅ lines).
- `harness-port/00-overview.md` §Order and `agnostic-phase1/00-overview.md` §Order — the prose this replaces.
- `automate-loop/SKILL.md` §1.5: `automate-helpers.sh` is read-only toward the work it drives; `plan-waves` must
  keep that property.

## Status: pending
