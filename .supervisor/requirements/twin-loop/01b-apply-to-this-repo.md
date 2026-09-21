# 01b — Apply the capability to this repo: scrub, filter, re-index, commit

> Depends on **01** (the capability). This item is **this repo's data migration** — it ships nothing.
> Its value beyond the local fix: it is the capability's first proof against a real repo with a
> genuinely rotted index and genuinely contaminated data. Those are the only such fixtures we have.

## Problem
Item 01 makes the Twin committable anywhere. This repo's own stores are not yet in a state where
that can be switched on: one memory entry cites a work repo, the ledger carries foreign records, and
the largest memory index is missing 17 of its 18 entries.

`vikashruhilgit/loomwright` is **PUBLIC** (`gh repo view --json visibility`). Committing before the
scrub publishes work-repo engineering data.

## Scope

1. **Apply the negations** to this repo's `.gitignore` (`.claude/` → `.claude/*` + `!.claude/agent-memory/`;
   `.supervisor/` → `.supervisor/*` + `!.supervisor/memory/`), then assert every intended and
   unintended path, including the two dotfile sidecars.

2. **Seed the allowlist with BOTH historical slugs** — `vikashruhilgit/ai-agent-manager` (42
   records, pre-rename) and `vikashruhilgit/loomwright` (35). Seeding only the live remote would
   drop the older, larger half. Filter `otherhub` (7) out of the committed ledger.

3. **Redact the one contaminated memory entry.**
   `.claude/agent-memory/loomwright-loomwright-code-reviewer/project_self_heal_rubber_stamp.md:8`
   reads `Across 8 recent session_end records (otherhub #146/#129/#133/#139 + this repo #24/#26/#36/#41)`.

   **Redact, do not drop.** The finding — `heal_decision: PASS` with `heal_iterations: 0` did not
   predict review-clean — is repo-independent, genuinely valuable, and part of what motivates this
   whole queue. Replace the foreign citation with a **non-numeric** form (e.g. *"another repo, 4
   PRs"*); do NOT renumber, because bare PR numbers stay ambiguous across repos and would recreate
   the problem quietly. The `this repo #24/#26/#36/#41` half stays — own-repo and already public.

   **This entry proves a ledger-only scrub is insufficient — record that reasoning, it is the
   justification for item 04's fifth check.** The ledger's `otherhub` records are PRs
   `133 139 146 154`, but the memory file cites **`#129`, which is not in the ledger at all**. Agent
   memory is distilled from session logs, and those sessions span repos, so a reflection pass can
   introduce a cross-repo reference that never passed through the ledger's `repo` field. No
   ledger-side filter could have caught this one.

   **Sweep method matters more than the result.** Two independent audits previously returned a
   **false clean** on this exact file: both grepped `/hub` (slash-prefixed) while the real string is
   `otherhub #146` — no slash, a space before the `#`. Derive search terms from data that already exists
   (the ledger's own `repo` values → org and short names, matched case-insensitively as whole
   words), never from a guessed string form. Re-run the sweep with that method rather than trusting
   this item's finding of exactly one file.

4. **Merge `code-reviewer`'s `MEMORY.md`.** `MEMORY--premigration.md` holds **16 pointers with
   already-curated hooks** against the current index's **1** — a migration replaced rather than
   merged, and nothing noticed. Start from the premigration list, then **reconcile against the files
   on disk**: 16 pointers vs 18 entry files means ≥2 were never indexed even before the migration
   and need hooks derived fresh from their `description:` frontmatter. End state is one
   `- [Title](file.md) — hook` line per entry file, no orphans in either direction.

   **"Delete `MEMORY--premigration.md`" is NOT an option** — it holds curation that cannot be
   regenerated (the source sessions are gitignored and partly gone). Remove it only *after* its
   content is merged, and record that it was merged, not discarded.

   Verify the other two stores are already correct (`qa-executor` 5/5, `red-team-reviewer` 5/5) —
   they show the intended shape and should need no change.

5. **Commit, and check what actually landed.** After staging, review the full diff for anything the
   negations pulled in unintentionally. `git add -A` on a newly-un-ignored tree is exactly where an
   unintended file slips through.

## Non-goals
No capability work (item 01). No new rules, no curation beyond the single redaction, no deletion of
any entry. Content is otherwise preserved byte-for-byte.

## Acceptance criteria
- `git ls-files` shows the agent-memory stores, `LESSONS.md`, `PROJECT_MEMORY.md`, both provenance
  sidecars, and the filtered ledger; `logs/`, `jobs/`, `worktrees/`, `settings.local.json` remain ignored.
- **The committed ledger contains ZERO records outside the allowlist**, asserted by a test and
  re-asserted after a simulated foreign-repo append.
- Records under **both** historical slugs are retained — count them, don't assume.
- A whole-word, case-insensitive sweep for foreign org/repo/product terms across every committed
  store returns **zero** hits — with the search terms **derived from the ledger's `repo` values**,
  and the method recorded so the next sweep can reproduce it.
- The redacted entry retains its finding, its **Why** and its **How to apply**, and carries no
  foreign PR numbers.
- `code-reviewer`'s index lists all 18 entry files; no orphan pointers; premigration merged then removed.
- A `memory: project` agent still receives its store — sentinel probe re-run, not inferred.
- The staged diff was reviewed file-by-file before commit.

## Outcomes Rubric
- Negations applied; intended/unintended/dotfile paths all asserted
- Both historical slugs retained; foreign records excluded and test-guarded
- Contaminated entry redacted with the finding intact; sweep method recorded, not just its result
- Index merged from premigration + disk reconcile; no orphans either direction
- Staged diff reviewed before commit; probe re-run after

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-07-twin-01b-apply-to-this-repo.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
