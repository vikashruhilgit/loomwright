# 03 — Implement `applies_to` path routing (BLOCKER for items 04 and 05)

> **This item gates the two after it.** Harvesting rules before routing exists would actively make
> the plugin worse. Do not reorder.

## Problem
`read-rules.sh` emits **every rule to every agent, on every task**, regardless of which files are
touched. The `applies_to` field exists in the schema but does nothing — three occurrences repo-wide,
none of which filter:

```
read-rules.sh:18   #  applies_to (optional)  RESERVED for slice 3b-ii enforcement filtering — INERT in v1.
read-rules.sh:53   #  `applies_to` is inert in v1.
add-rule.sh:376        applies_to: null          ← the writer hardcodes null
```

Today this is invisible: the store holds **exactly one rule**. It stops being invisible the moment
item 05 harvests the `convention_mismatch` findings (**104 own-repo**, 107 all-repo — see
00-overview §Measured baseline). Fifty rules injected into every agent on
every task produces two failures at once — token bloat at three seams, and the advisory-prose-gets-
ignored effect that caused the 57 self-heal misses this queue exists to fix. A rule that fires
everywhere is indistinguishable from a rule that fires nowhere.

## Goal
A rule fires only for the files it governs. `applies_to` becomes a real path filter, honoured by the
reader at all three existing seams, with unmatched-or-unknown failing **open** (rule still emitted)
so routing can never silently suppress knowledge.

## Evidence — the three seams that consume the reader
Verify each against the file before editing; do not trust this list alone:
- **Worker DO-side** — `agents/supervisor.md:735` (Single-Agent path) and
  `agents/execute-manager.md:190` (parallel path). Both pass touched paths as **arguments, never
  stdin** (an args-bearing call can never block).
- **Phase 4.5 review** — `skills/self-heal-advisory/SKILL.md:534`, on the integrated-diff scope.
- **SessionStart nudge** — `scripts/session-resume.sh:197`, gated on the reader emitting EMPTY.

All three already pass the touched-file set. **No seam changes are required** — the paths arrive at
the reader today and are discarded. This item makes the reader use them.

## Scope
1. **Define `applies_to` semantics**: `null`/absent ⇒ applies repo-wide (preserves today's behaviour
   for the one existing rule — no migration, no behaviour change on upgrade). A non-empty array of
   glob patterns ⇒ the rule is emitted only when at least one touched path matches at least one
   pattern.

   **Use the shell-side `case` idiom the reader already has — do NOT invent a dialect or implement
   glob matching in `jq`.** `read-rules.sh:303` already parses line-by-line with `case "$line" in`,
   and `add-rule.sh` does path matching too. Native bash `case` globs are portable to 3.2 by
   construction, need no `shopt`, and avoid emulating glob semantics inside a `jq` program. Verify
   both call sites before building on them, then extend that idiom rather than adding a second
   matching mechanism alongside it. Document the supported pattern syntax explicitly (what `*` and
   `**` do at a path boundary) — `case` globs do not treat `/` specially, which is a real difference
   from `.gitignore` semantics and will surprise a rule author who assumes otherwise.
2. **Implement the filter in `read-rules.sh`.** Preserve every existing invariant: always exit 0,
   EMPTY stdout when no rule qualifies (never a "no rules" sentinel), inputs cross into `jq` via
   `--arg`/`--argjson` only, and a rule's `check` remains **DATA — never executed** by the reader.
3. **Fail OPEN on ambiguity.** Malformed `applies_to`, an unparseable pattern, or an empty touched-path
   set ⇒ emit the rule anyway. Routing is an optimisation; suppressing a real convention because a
   glob was mistyped is the worse failure. Log nothing to stdout on this path.
4. **Teach `add-rule.sh` to set it.** Accept `--applies-to <glob>` (repeatable); default stays `null`.
   Validate patterns at write time and reject traversal-style patterns, mirroring the existing
   hostile-category rejection.
5. **Retire the INERT comments** at `read-rules.sh:18` and `:53` and anywhere else the field is
   described as reserved — grep the repo for `applies_to` and for "inert"/"reserved" prose before
   claiming the sweep is complete.
6. **Extend `test-read-rules.sh`** (and the seam invariant test) with: match, non-match, multi-pattern,
   `null` (repo-wide), malformed (fails open), empty path set (fails open), and a traversal pattern
   (rejected at write). Prove non-match actually SUPPRESSES — a test that only asserts "emits" cannot
   distinguish working routing from the current no-op.

## Non-goals
No new seams, no new gates, no change to `rules-check.sh`'s execution trust boundary (unattended
`check` execution stays gated via `--no-cmd`), no rule authoring — item 05 owns that.

## Acceptance criteria
- A rule with `applies_to: ["loomwright/scripts/**"]` is emitted for a script path and **absent** for
  an unrelated doc path — both asserted, non-match proven by absence.
- A rule with `applies_to: null` is emitted for every path (no regression for the existing rule).
- Malformed / unparseable `applies_to` and an empty path set both emit the rule (fail open), exit 0.
- All three seams observably receive the filtered set — traced end-to-end on a fixture run, a dynamic
  trace and not only a static read.
- `add-rule.sh --applies-to` writes valid patterns and rejects traversal; both paths tested.
- `read-rules.sh` still: always exits 0, EMPTY on no-qualifier, `--arg`-only, never executes `check`.
- Every "INERT"/"reserved" claim about `applies_to` removed repo-wide.

## Outcomes Rubric
- Routing implemented; non-match suppression proven, not just match emission
- Fail-open on malformed/empty, exit 0 preserved
- All three seams traced dynamically end-to-end
- Writer support with traversal rejection
- Stale INERT prose swept repo-wide

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-09-applies-to-path-routing.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
