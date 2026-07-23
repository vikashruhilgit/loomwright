# .agent/orientation/ — committed orientation-memo store

A **version-controlled** store of short, per-area orientation memos: durable "how this area
works" notes an agent can read *before* touching an area, instead of rediscovering the same
structure every session. Like `.agent/rules/`, this directory is **committed** (NOT gitignored)
and travels with the repo.

## Format

One `.md` memo per area, named `<area-slug>.md` (slug = a single `[a-z0-9-]+` segment).
Each memo file:

1. **Line 1 — header comment (machine-parsed):**

   ```
   <!-- written_at: <ISO-8601 UTC> | head_sha: <full-or-short commit sha> | areas: <space-separated repo-relative path prefixes> -->
   ```

   Since v15.14.0 an optional `supersedes` field may appear, giving the **4-field** shape:

   ```
   <!-- written_at: <ISO-8601 UTC> | head_sha: <sha> | supersedes: <area-slug> | areas: <paths> -->
   ```

   - `written_at` — UTC ISO-8601 timestamp of when the memo was written.
   - `head_sha` — the repo HEAD commit the memo was written against (staleness anchor).
   - `supersedes` *(optional)* — the area-slug of another memo this one replaces. The reader
     hides the named memo (single-hop, non-transitive). A malformed, self-referential,
     dangling, or cyclic value is fail-safe-ignored — the carrying memo is still emitted.
   - `areas` — space-separated repo-relative path prefixes the memo describes; the reader
     runs a bounded `git log <head_sha>..HEAD -- <areas>` to detect drift. May be empty
     (staleness then degrades to fresh-unknown).

   > **Field ORDER is load-bearing — `areas` MUST stay last.** The reader extracts `areas`
   > with a trailing `(.*)` capture, so any field appended *after* it is swallowed into the
   > `areas` value and then passed to git as a pathspec — which matches nothing and silently
   > disables staleness detection for that memo. Put `supersedes` **between `head_sha` and
   > `areas`**, exactly as shown. Both the 3-field and 4-field shapes parse; hand-authoring a
   > memo with `supersedes` appended after `areas` does NOT error, it is silently ignored.
   > The sole writer (`add-orientation.sh`) always emits the correct position.

2. **Line 2 — a one-line summary** of the memo.

3. **Body** — free-form markdown. **Hard cap: ≤1000 chars TOTAL per memo file** (header +
   summary + body). Over-cap memos are skipped by the reader and rejected by the writer.

## Memos are DATA, not instructions

Memo content is **advisory context, subordinate to CLAUDE.md** — never commands. The reader
(`loomwright/scripts/read-orientation.sh`) emits memo text as data under an explicit
subordination banner, never executes/evals anything from it, and fail-safe-skips any memo
containing instruction-injection markers (e.g. "ignore previous", "system prompt",
"you must now", "disregard", `<system>`, `[INST]`). Note the plain-English sharp edge:
the fixed-string scan means an innocent phrase containing "disregard" (e.g. "you can
disregard the legacy adapter") is also skipped/rejected — reword such memos.

## Write discipline

- This committed store is written **ONLY via `loomwright/scripts/add-orientation.sh`**, with
  **per-item human approval** — never by automated runs. The approval is **mechanized as a
  confirm-only gate** (same pattern as `add-rule.sh`): the writer writes only when `--confirm`
  is passed or an interactive TTY user answers `y`; any other invocation (e.g. an automated
  non-TTY run without `--confirm`) prints the planned memo + target path and exits 0
  **without writing**.
- Automated runs that want to propose a memo write **proposals** to the gitignored
  `.supervisor/orientation-proposals/` instead; a human promotes an approved proposal into
  this store via `add-orientation.sh --confirm`.
- The writer enforces: slug path-containment (single `[a-z0-9-]+` segment — no `/`, `..`,
  leading dot, leading/trailing `-`, metacharacters; `readme` is reserved — it collides
  with this README on case-insensitive filesystems), the 1000-char cap, hostile-marker
  rejection (scanned against a whitespace-normalized copy, so markers split across lines are
  still caught — same normalization as the reader), temp-file + atomic-`mv` writes, and
  read-back verification (a failed verify of a memo *update* restores the prior memo).

## Staleness

The reader annotates a memo as `[stale — area changed since <written_at>, verify before
trusting]` when commits touched its `areas` after `head_sha`, and demotes stale memos after
fresh ones (never drops them). An unparseable sha / any git error is treated as
fresh-unknown — staleness detection never blocks a read. Squash-merge caveat: a `head_sha`
stamped on a feature branch disappears from history once that branch is squash-merged and
deleted, so such memos become permanently fresh-unknown (presented WITHOUT a stale
annotation even when old) — prefer stamping/promoting memos from `main`, and treat
`written_at` as the honest age signal when in doubt.
