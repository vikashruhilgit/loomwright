# 01 — Make the Twin committable: gitignore negation, repo allowlist, `/setup memory`

> **This item is PLUGIN CAPABILITY — it must work in any repo the plugin runs in.** Applying it to
> *this* repo's data (moving nothing, but scrubbing, filtering and re-indexing what we already have)
> is **item 01b**. Acceptance here is proven in a scratch fixture repo; 01b is the first real-repo
> proof. Do not conflate them: criteria written against this repo would pass for a plugin that does
> nothing in a user's repo.

## Problem
The Twin's accumulated judgment is **not in version control**. `.gitignore:34` ignores `.claude/`
and `.gitignore:35` ignores `.supervisor/`; `git ls-files .supervisor .agent .claude` returns only
three files — two `README.md`s plus `.agent/rules/process.json` — i.e. **one rule and ZERO memos**
(the orientation store holds only its README; `/insights` Corpus health independently reports
`orientation: 0 memos`). Everything else — the findings ledger, session logs, `LESSONS.md`,
`PROJECT_MEMORY.md`, and the agent-memory stores — exists only on one machine with no recovery path.

These stores are **per-repo, in the user's repo**, not plugin-local: `add-rule.sh:137` resolves
`GITROOT="$(git rev-parse --show-toplevel)"` and writes `$GITROOT/.agent/rules`. `/setup` states the
same — *"Twin artifacts are per-repo, not per-user config."* So this is a capability every repo
needs, not a one-off fix here.

Two consequences, both load-bearing for "the plugin owns the repo":
1. **A fresh clone gets almost nothing.** CI, a second machine, or a new contributor starts cold.
2. **Deletion is irreversible.** There is no `git checkout` to undo a bad curation pass, and
   re-derivation is not a fallback — lessons are distilled *from* session logs, which are themselves
   gitignored and only partially retained.

## The mechanism: negation in place — NOT a move (measured, 2026-08-06)

An earlier draft of this item proposed moving the stores into `.agent/` and bridging back to the
harness path with a symlink or generated copy. **That was wrong, and the probe that seemed to
require it actually rules it out.**

**Probe result (re-run it; do not trust this summary):** sentinel entry files were placed under both
the harness path `.claude/agent-memory/<sanitized-agent-id>/` and a candidate `.agent/` path, then a
`memory: project` agent was spawned and asked to report from spawn-injected context only, zero tool
calls. The harness injected a store and named the `.claude/…` path; **the `.agent/` copy was never
read.** Two conclusions:

1. **The harness path is FIXED.** A committed `.agent/` copy is not injected — so a plain `git mv`
   would silently sever every agent from its memory **while leaving the whole test suite green.**
2. **The harness injects the INDEX, not the entry files.** The sentinel sat in the correct directory
   and was still invisible because `MEMORY.md` did not list it. The index is the injection
   mechanism, not a convenience.

**The correct inference from (1) is "don't move it."** Un-ignoring the stores where they already sit
makes the constraint disappear — no symlink, no generated copy, no refresh hook, no drift, and
nothing to prove about injection because nothing moved.

**The naive negation SILENTLY FAILS and must be tested, not commented.** Git cannot re-include a
file whose parent directory is excluded:

```gitignore
.claude/
!.claude/agent-memory/          # ← does NOT work; check-ignore still matches `.claude/`
```

The working form excludes *contents* rather than the directory:

```gitignore
.claude/*
!.claude/agent-memory/
.supervisor/*
!.supervisor/memory/
```

Verified in a fixture: `agent-memory/**` and `.supervisor/memory/**` commit; `.claude/worktrees/`,
`.claude/settings.local.json` and `.supervisor/logs/` stay ignored. **Dotfile sidecars survive** —
`.provenance.jsonl` and `.lessons-provenance.jsonl` (the read-side provenance gate `read-lessons.sh`
depends on) both commit correctly, as does `PROJECT_MEMORY.md`. Both properties are silent-failure
classes and need assertions, not prose.

**Bonus, worth stating:** committed files exist inside `git worktree` checkouts; gitignored ones do
not. This closes a real gap — workers in worktrees currently cannot see lessons or agent memory.

## Scope

1. **Gitignore-negation logic**, applied idempotently and never blind-overwriting a user's
   `.gitignore`. Must handle: an existing `.claude/`-style line (rewrite to `/*` form), an already-
   correct file (no-op), and an unparseable/absent file (fail safe, report, change nothing).

2. **Repo allowlist — a LIST, not a string, and not the live remote.** The committed ledger carries
   only records whose `repo` is in the allowlist. Two facts force the shape:
   - **It cannot key on the current remote.** This repo's remote is `vikashruhilgit/loomwright`, but
     the ledger holds **42** records under `vikashruhilgit/ai-agent-manager` — the pre-rename name —
     against **35** under the current slug. A live-slug filter would silently drop the larger, older
     half. **A repo rename is the documented reason this field is a list.**
   - **It cannot be hardcoded to `vikashruhilgit/*`.** The plugin ships to other users; their repos
     would be filtered out entirely. Default the allowlist to the current remote on a fresh install,
     and let it be extended in config.

3. **`/setup memory` module**, following the established module contract
   (**check → report → offer → apply → verify**, idempotent, never blind-overwrite):
   - **check/report** — what is currently tracked vs ignored; index health; allowlist contents.
   - **offer** — the commit/ignore split, with an **honest explanation of what becomes
     version-controlled**. This is consent-bearing and must never be a silent default: a user's
     agent memory can contain proprietary architecture, internal service names, or client detail,
     and committing it publishes it wherever the repo goes.
   - **apply** — write the negations; seed the allowlist.
   - **verify** — assert each intended path's ignore status, including a dotfile.
   - **`remove` is REQUIRED here**, unlike the `twin` module where it is documented N/A. Un-committing
     is a real operation a user will want — most likely on realising something proprietary was
     published. It must state plainly that **git history retains what was already pushed**; removal
     stops future tracking, it does not unpublish.

   Implementation constraints found in `commands/setup.md`, both real edits:
   - **The `AskUserQuestion` ≤4-option set is already saturated** (`setup.md:97` forbids one option
     per module — four are already folded into one). An 8th module means reworking that fixed set.
   - **`## Constraints` enumerates every module's writes** (`setup.md:312`). This module writes to
     `.gitignore`, a write class no existing module has — give it its own explicit constraint line.

4. **Tracked-directory write risk — state it here, mitigate it in item 04.** Once
   `.claude/agent-memory/` is tracked, every memory write becomes a working-tree modification: it
   appears in `git status`, can be swept into an unrelated commit by `git add -A` (the exact failure
   already recorded in project memory about concurrent heal loops), and `MEMORY.md` becomes a
   conflict surface under parallel workers. Today this is near-theoretical — three writes in six
   weeks, all by hand. **Item 04 makes it routine**, so the mitigation is 04's: agent writes go to
   the gitignored proposal queue, and only `/dreaming`-promoted entries touch the tracked store.

5. **Two committed store locations — the right shape, stated rather than apologised for.**
   `.claude/agent-memory/` is **vendor-owned**: the harness defines the path and the injection
   mechanism, so vendor-specific state belongs on the vendor path. `.agent/` is the **portable**
   store, placed outside `.claude/` deliberately for the ports-and-adapters direction. Honest
   caveat: under a different harness, agent-memory does not port — it is Claude-Code-shaped by
   construction, and the portable judgment is what graduates to `.agent/rules/` via item 05.

## Non-goals
**No move, no symlink, no generated copy, no bridge of any kind.** No migration of this repo's own
data (item 01b). No curation or deletion. No index-integrity enforcement — that is a continuous
invariant and belongs to item 04's writer, never to a one-time setup step: an index that can rot
between setups is exactly how `code-reviewer` reached 18 files / 1 pointer.

## Acceptance criteria
Proven in a **scratch fixture repo**, not against this one:
- The naive `.claude/` + `!` form is asserted to **fail**, and the `/*` form to succeed — the silent
  failure is the point; a comment is not a test.
- Intended paths commit (`agent-memory/**`, `.supervisor/memory/**`) and unintended ones stay
  ignored (`worktrees/`, `settings.local.json`, `logs/`), asserted per path via `git check-ignore`.
- **Dotfile sidecars commit** — `.provenance.jsonl`, `.lessons-provenance.jsonl` — asserted
  explicitly, since their absence would silently strip provenance from a fresh clone.
- The allowlist is a list; a fixture with a renamed repo retains records under **both** slugs; a
  foreign-repo record is excluded; a fresh install defaults to the current remote.
- `/setup memory` is idempotent (second run is a no-op), never blind-overwrites a hand-edited
  `.gitignore`, and `remove` works and says history is retained.
- The module's writes are enumerated in `setup.md` `## Constraints`; the ≤4-option set is reworked.
- Nothing moved: agent-memory is still at the harness path, and a `memory: project` agent still
  receives its store — **proven by re-running the sentinel probe**, not by a green suite.

## Outcomes Rubric
- Negation-in-place; zero move/symlink/copy machinery
- Naive-form failure and dotfile survival both asserted by test
- Allowlist is a list; rename case covered; portable to other users
- `/setup memory` follows the module contract, with a real `remove` and honest consent copy
- Tracked-write risk stated and explicitly handed to item 04

## Status: brief-shipped

Job `.supervisor/jobs/done/auto-2026-08-06-180006-setup-memory-committable-twin.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
