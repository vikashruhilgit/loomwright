# 01 — One extractor for the brief's source-requirement pointer

## Problem

Two scripts parse the same field on a Supervisor brief — the `- **Source requirement:** <path>`
line Launch Pad stamps under `## Environment` — and they parse it differently. The older one is
hardened; the newer one is a bare `sed` that fails on the pointers real briefs actually carry.

Measured on this checkout 2026-09-10, against the three briefs currently stranded in
`.supervisor/jobs/in-progress/`:

| brief | pointer shape | `reconcile-jobs.sh:133` | `stamp-requirement-status.sh:130-135` |
|---|---|---|---|
| `2026-09-03-archive-views.md` | backticks **+ trailing prose** | does not resolve | **does not resolve** |
| `2026-09-04-ui-command-and-projects.md` | bare path | resolves | resolves |
| `2026-09-05-floor-ui-redesign.md` | backticks only | **does not resolve** | resolves |

`reconcile-jobs.sh` strips the label and nothing else:

```
sed -n 's/^- \*\*Source requirement:\*\*[[:space:]]*//p' "$1" | head -1
```

so the value it hands to `safe_requirement_path` still carries its markdown backticks. That
function's **first** guard is `case "$p" in "$REQ_ROOT"/*)`, which a string beginning with a
backtick fails, and the brief is classified `unknown`.

`stamp-requirement-status.sh` does better — case-insensitive match, then a strip of leading and
trailing delimiters:

```
req="$(printf '%s' "$req" | sed -E 's/^[SET]+//; s/[SET]+$//')"
```

where `[SET]` is the character class holding backtick, double quote, single quote and space. But
that trailing strip only removes those characters at the very end of the line. The Sep 3
pointer ends in `)`, so the annotation
`(amended at intake 2026-09-03 — …)` survives, containment still passes (the string does start
with `.supervisor/requirements/`), and the `-f` test fails. **Both lifecycle reconcilers are
blind to that brief.**

**This is not cosmetic.** `2026-09-05-floor-ui-redesign.md` corresponds to PR #185, merged
2026-09-05 — genuinely shipped, and stranded for five days because of a backtick. Per
`reconcile-jobs.sh`'s own header a stale `in-progress/` entry is a half-satisfied active-session
signal that four independent consumers read as "Supervisor is mid-run"
(`hook-dispatch-on-pr-create.sh`, `session-resume.sh`, `notify-desktop.sh`, `send-webhook.sh`),
and because `stamp-requirement-status.sh` reads `jobs/done/` exclusively, a brief stranded in
`in-progress/` structurally blocks requirement close-out as well.

**Root cause is mirror drift, not a typo.** The field has one producer
(`agents/launch-pad.md:476`, contract in `skills/supervisor-readiness/SKILL.md:129`) and two
independent consumers written months apart. The producer contract says "repo-root-relative path"
and says nothing about styling — yet 2 of 3 real briefs carry backticks and one carries a
parenthetical. Briefs are agent-written prose, so tightening the producer cannot retire the
existing corpus and would be the same unreliable-bookkeeping bet the repo has already measured
and rejected. The consumers must be tolerant, and there must be **one** of them.

## Goal

A single shared extractor for the source-requirement pointer, tolerant of every shape the real
brief corpus carries, used by both consumers, with no loss of the containment hardening
`stamp-requirement-status.sh` already has.

## Scope

1. **One extractor, defined once**, resolving a brief path to either a validated requirement path
   or nothing. It subsumes both current implementations. Whether it lives in a shared sourced
   helper or is defined in one script and reused is an implementation choice — what is required is
   that **there is exactly one parsing rule and both call sites go through it**, verifiable by a
   grep that finds no second independent `Source requirement` parse.

2. **Tolerance, stated as the shapes it must accept:** bare path; path wrapped in backticks,
   single quotes or double quotes; path followed by whitespace and a trailing annotation
   (parenthetical or prose); the label written with different capitalisation or leading
   whitespace; the label with or without its leading `- `. The path is taken as the pointer's
   **first whitespace-delimited token after delimiter stripping** — annotations are separated from
   the path by whitespace in every observed case, which makes this rule sufficient without
   guessing at prose structure.

3. **The containment guards are preserved in full, not re-derived.** The shared extractor must
   keep every check `stamp-requirement-status.sh` performs today: reject absolute paths, reject
   any `..` segment, require the path to sit under `.supervisor/requirements/`, reject a symlinked
   final component (`-L`), and reject a symlinked directory component via physical resolution of
   the parent compared with `pwd -P`. A brief is untrusted input that a script reads and then
   writes against; the symlink guard exists because a reproduced attack got past the lexical
   checks alone. **Weakening any of these to unify the two call sites is a regression, not a
   simplification.**

4. **`reconcile-jobs.sh` keeps its current verdict vocabulary and its detect-vs-repair split.**
   This item changes only what the pointer resolves to. A brief whose pointer now resolves may
   still classify `unknown` for lack of evidence — that is correct and must not be papered over.

## Non-goals

- **Not** changing the producer to forbid styled or annotated pointers. The existing corpus would
  still be unreadable, and an instruction is exactly the mechanism this repo has measured as
  unreliable.
- **Not** adding any new repair, auto-move, or lifecycle transition. `--repair` semantics,
  evidence rules and the `unknown`-is-never-repaired invariant are untouched.
- **Not** making `reconcile-jobs.sh` online. It is offline by construction because
  `session-resume.sh` runs it on every resume; no forge call may be introduced here.
- **Not** repairing the three currently stranded briefs as part of the change. Reconciliation is
  the mechanism; a hand-run of `--repair` afterwards is an operator action.

## Depends on

Nothing. Cut from `origin/main` at `2cf4609`.

---

## Release-surface obligations

- `loomwright/docs/PITFALLS.md` — the stranded-brief entry describes the reconciler's evidence
  rules; if its wording implies the pointer is read literally, correct it.
- `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the `.supervisor/jobs/in-progress/` and
  `jobs/done/` rows name both reconcilers and their read/write split; update only if the change
  alters who reads what.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump. Update the
  `description` counts **in place**; never append another version clause.
- **Citations:** any new `file.ext:N` in committed prose must carry `` [pins: `<literal>`] `` or
  use a descriptive anchor — `test-citation-drift.sh` fails a new bare citation. The line numbers
  quoted in this requirement (`reconcile-jobs.sh:133`, `stamp-requirement-status.sh:130-135`)
  are intake evidence and will drift; do not copy them into committed prose unpinned.
- No hook is added or removed, so the `hooks.json`-derived counts do not move.

**Honest limit to document, not to paper over:** the first-token rule cannot read a pointer whose
annotation is not whitespace-separated from the path (`…05-archive-views.md(amended)`). No such
brief exists in the corpus. State the limit; do not add a heuristic to guess around it.

---

## Acceptance criteria

**AC-1 (bare path, regression).** A brief whose pointer is an unstyled repo-root-relative path
resolves exactly as it does today, through both call sites. This is the shape that already works
and it must not change.

**AC-2 (backticks).** A brief whose pointer is wrapped in backticks resolves to the same path as
the identical unstyled pointer. Fixture-based, asserted through `reconcile-jobs.sh` — the call
site that fails today.

**AC-3 (backticks plus trailing annotation).** A brief whose pointer is wrapped in backticks and
followed by a parenthetical annotation resolves to the path alone. Asserted through **both** call
sites, because both fail this shape today.

**AC-4 (label variants).** Pointers differing only in label capitalisation, leading whitespace, or
the presence of the leading `- ` all resolve identically.

**AC-5 (absent pointer).** A brief with no pointer line is a silent no-op at both call sites — no
verdict, no stamp, no error. Pre-feature briefs and direct `/supervisor task:` runs carry no
pointer and must stay unaffected.

**AC-6 (containment preserved, one case per guard).** Each of these is refused, with the refusal
distinguishable from "resolved": absolute path; path containing a `..` segment; path outside
`.supervisor/requirements/`; symlinked final component; symlinked directory component whose
target is outside the containment root. **The symlink cases must assert the target file is
unmodified**, not merely that the call returned non-zero — the original suite was green precisely
because it tested the attacks that were thought of.

**AC-7 (single parsing rule).** A grep over `loomwright/scripts/` finds no second independent
implementation of the pointer parse. The check is stated positively and pinned in the test, so a
future third consumer that re-coins its own parser fails it.

**AC-8 (mutation control).** Reverting the delimiter-stripping logic turns AC-2 and AC-3 red.
Asserted explicitly, because a fixture corpus that happens to contain only unstyled pointers would
pass every criterion above with the mechanism deleted.

**AC-9 (real corpus).** Run against the three briefs in `.supervisor/jobs/in-progress/` on this
checkout: all three pointers **resolve** (`did not resolve` disappears from the output for every
one). Their final verdicts are **not** asserted — resolution is what this item owns, and a brief
may legitimately remain `unknown` for want of evidence. Record the resulting verdicts in the PR
body as measured evidence, not as a pass condition.

## Outcomes Rubric

- One parsing rule exists where there were two, and the weaker one is gone rather than patched.
- Every containment guard the hardened consumer had is still present and still demonstrably fires.
- The tolerated shapes are the ones the real corpus carries, established by measurement rather
  than by imagination.
- The delimiter handling is mutation-controlled, so the suite cannot pass with the fix removed.
- A brief that resolves but lacks evidence still reports `unknown`; nothing became more confident
  than the disk warrants.
- Nothing in the change can block a run, and no forge call entered the resume path.
- The unreadable-pointer limit is documented rather than guessed around.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-10T15:33:35Z
- **Brief:** .supervisor/jobs/in-progress/2026-09-10-brief-pointer-extraction.md (stranded — completion tail never ran; stamped at /automate RESUME 2026-09-11)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/208
