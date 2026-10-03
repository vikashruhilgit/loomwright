# 00 — Twin-loop queue overview (index/policy doc — NOT an implementable item)

**Origin:** 2026-08-06 owner session. The queue closes the plugin's learning loop: findings already
accumulate automatically, but nothing distils them into conventions and nothing routes those
conventions to the files they govern. Everything below is derived from measured repo state, not
from a roadmap.

## The one-paragraph problem

```
findings auto-accumulate (231)  ✅ fully automatic
        ↓
distil into rules               ❌ manual, never runs   → 1 rule exists
        ↓
route to the right files        ❌ applies_to is INERT
        ↓
inject DO-side                  ✅ wired, but only 1 rule to inject
```

Both ends work; the middle two steps do not. That is why `convention_mismatch` is **107 of 231
findings (46%)** and **57 of the 88 self-heal misses (65%)** — and why 31 of those originate at the
**worker** stage, before review ever sees the code.

## Measured baseline (verify before amending — all confirmed 2026-08-06)

> **Two figure sets exist; this table is the single authority for both.** *All-repo* figures cover
> the ledger as it stands (84 records, 3 repos). *Own-repo* figures exclude `otherhub` and are the
> ones to **plan and measure against**, because the allowlist defined in item 01 §Repo allowlist limits the committed ledger to
> `vikashruhilgit/*` for publication reasons. Any figure quoted elsewhere in this queue is all-repo
> unless explicitly marked own-repo. Applying this queue's own rule: derive from here, do not
> restate a number without saying which set it belongs to.

| Fact | Evidence |
|---|---|
| 231 findings; convention_mismatch 107 (46%) | `jq '.categories[]?' .supervisor/postmortem/results.jsonl` |
| 57 of 88 self-heal misses are convention_mismatch | same, filtered `self_heal_miss==true` |
| convention_mismatch by stage: 57 self_heal / 31 worker / 19 unknowable | same, grouped by `flow_stage` |
| `.agent/rules/` holds **exactly 1 rule**, `check: null`, `applies_to: null` | `.agent/rules/process.json` |
| `applies_to` is **INERT** — 3 occurrences, none filter | `read-rules.sh:18`, `:53`, `add-rule.sh:376` |
| `.supervisor/` and `.claude/` are **gitignored** | `.gitignore:35`, `.gitignore:34` |
| Only `.agent/rules` + `.agent/orientation` are committed | `git ls-files .supervisor .agent .claude` |
| `code-reviewer` memory: **18 entry files, 1 indexed**; `MEMORY--premigration.md` holds **16** pointers (migration replaced the index, did not merge it) | `.claude/agent-memory/loomwright-loomwright-code-reviewer/` |
| `qa-executor` 5/5 and `red-team-reviewer` 5/5 indexed (the intended shape) | same parent dir |
| **The harness injects the INDEX, not entry files** — an unindexed entry is never injected; harness path is FIXED at `.claude/agent-memory/<sanitized-id>/` and `.agent/` is not read | sentinel probe 2026-08-06, item 01 §Probe result |
| No agent is instructed to write memory; writes are hand-made and rare (**2026-08-04 / 07-06 / 06-26**) | only `rubric-grader.md:49` (a prohibition) |
| Ledger spans **3 repos** incl. `otherhub` (7); `loomwright` is **PUBLIC** ⇒ ledger must be own-repo-filtered before commit | `jq .repo`, `gh repo view --json visibility`, item 01 §Repo allowlist |
| Own-repo-only distribution: 213 findings, `convention_mismatch` **104 (49%)**, 86 misses, **57 (66%)** | filtering strengthens the premise; all 57 misses are own-repo |
| `graphify-out/graph.json` **absent**; `bridge.json` orphaned, 255 commits stale | `read-bridge.sh:124` short-circuits; verified emits nothing |
| 18 SPIKES docs, 10 frozen at one 2026-07-02 commit; 10,728 doc lines total | `loomwright/docs/` |

## Order (LOAD-BEARING — getting this wrong makes things worse)

```
01 → 01b → 02 → 03 → 04 → 05 → 06 → 07
```

- **03 (routing) MUST precede 04 and 05.** `read-rules.sh` emits **every** rule to **every** agent
  regardless of touched paths. Harvest 50 rules before routing exists and each agent receives all 50
  on every task: token bloat **plus** the advisory-prose-gets-ignored failure that produced the 57
  misses in the first place. This is the single most important constraint in the queue.
- **01 before 01b** — 01 builds the capability, 01b applies it to our data. 01b is also the
  capability's first real-repo proof, on the only fixtures that exist with a genuinely rotted index
  and genuinely contaminated data.
- **01/01b before 04/05** — the writers validate against the *committed* store and share 01's repo
  allowlist.
- **06 and 07 are independent cleanup** and may run any time after 01b, but are placed last because
  07 (`DECISIONS.md`) is cheaper to write once 01–06 have settled the decisions it records.

## Plugin capability vs this-repo migration (state it per item — do not leave it implicit)

The first draft of item 01 mixed the two and its acceptance criteria tested only this repo, so a
plugin that worked here and did nothing in a user's repo would have passed. These stores are
**per-repo, in the user's repo** — `add-rule.sh:137` resolves `git rev-parse --show-toplevel`.

| Item | Kind | Acceptance proven where |
|---|---|---|
| 01, 02, 03, 04, 05 | **plugin capability** | scratch **fixture repo** (this repo alone is not evidence) |
| 01b | this-repo data migration | this repo; ships nothing |
| 06 | mixed — seam removal ships; deleting our orphaned bridge is local | both, stated per part |
| 07 | **plugin-repo only** — `DECISIONS.md` records *this* project's decisions; do not generalise | this repo |

## Non-negotiable invariants carried by every item

- **Advisory stays advisory.** Nothing in this queue adds a gate, a blocking hook, or a
  `heal_decision` input. House rules remain subordinate to CLAUDE.md (on conflict, CLAUDE.md wins).
- **No autonomous deletion of distilled stores.** See item 06 for the D9 refinement — derived
  artifacts may auto-delete, distilled ones may not.
- **Fail-safe emitters always `exit 0`.** Every new probe/reader follows the existing convention.
- **Counts are CI-enforced.** Any item adding a script/command/skill updates the authoritative
  source and every mirror; `check-doc-currency.sh` fails otherwise. New `scripts/test-*.sh` are
  auto-registered by the `ci.yml` glob and must be Ubuntu-clean (BSD-vs-GNU `stat`/`date`/`sed -i`).
- **Derive, never restate.** `.agent/rules/process.json` already says a claim lives in exactly one
  authoritative place. It binds this queue too: item 02 derives two of three last-run times instead
  of storing them, and item 01's allowlist has one definition read by two consumers.
- **Never guess a string form when the data already holds the vocabulary.** Two independent audits
  returned a **false clean** on the same file because both grepped `/hub` while the real text reads
  `otherhub #146`. What worked was deriving search terms from the ledger's own `repo` values. Any sweep
  in this queue derives its terms from existing data and records the method, not just the result —
  a green check over the wrong pattern is the exact failure class this queue exists to remove.
- **Check what the repo already does before specifying a mechanism.** Five findings in review were
  the same mistake: the gitignore negation (no move needed), the derivable timestamps, the existing
  `case`-glob idiom in `read-rules.sh`, the writers' zero-sharing structure, and `/dreaming`'s
  execution model were each one grep away, and each simpler than what was designed.

## /automate handling

Every item is a normal code-change item — none require an operator-run eval or an external repo.
Item 07 is docs-only but is **not** lower scrutiny: skill/agent/command markdown is executable
logic and gets a state-trace, not just a consistency read.
