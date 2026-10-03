# The invention half — overview (updated 2026-09-06)

Master overview for the items in `.supervisor/requirements/invention/`.

**This file is the overview only — do NOT feed it to `/automate`.** It lives as a sibling of
the folder, not inside it, precisely so `--folder` never enqueues it (the folder source
enqueues *every* `.md` in the directory). The per-item requirement files are each
self-contained.

## Why this queue exists

Every item this system had ever executed was typed by a human — `/automate`'s three intake
sources (a prompt via `/product-owner`, `--folder`, `--backlog`) are all human-seeded. The
north star is a mill that invents its own work; this queue is the intake half of that.

Two streams, and they are **not symmetric** — which is why they are separate items rather
than one "two kinds of requirements" feature. Forcing one mechanism onto both would break the
half that has evidence.

| | Stream | Evidence | Direction | Status |
|---|---|---|---|---|
| **01** | gaps · issues · bugs, from our own churn | **Derivable** — the classified ledger, pre-aggregated in `floor.json` | inward | **SHIPPED** — `/propose`, PR #200, merged 2026-09-06 |
| **02a** | what this project is, who it serves, who it competes with | project facts, stated once, committed | — | queued |
| **02b** | what the domain expects that this app lacks | **Mixed** — a derived capability inventory against external, dated sources | outward | queued, hard dep on 02a |

## What 01 established (do not re-derive)

`/propose` reads `floor.json` and writes evidence-carrying drafts to
`.supervisor/requirements/proposed/`, which is deliberately **not** an `/automate --folder`
target. It emits a dedup token line, basis lines naming `generated_at_epoch`, then
Problem / Goal / Scope / Acceptance criteria / Evidence with per-entry citations and a
citation cap. It suppresses below a threshold, below a minimum citation count, when the basis
is stale, and when an evidence set is already covered by an existing draft or by any
requirement file stamped `## Status: done`. **02b emits the same shape from a different
basis** — match that contract rather than coining a second one.

## The 02 split, and why it is a split

02 was originally one item, scoped as "add competitors to the strategy lane's
`sources_to_check`". That was **wrong twice**, and both corrections are load-bearing:

1. **Wrong subject.** `/capability-check --strategy` reads
   `${CLAUDE_PLUGIN_ROOT}/docs/CAPABILITY_BASELINE.json` — the read-only install dir — and its
   `--update-baseline` is documented as *"a no-op notice elsewhere"*. It is structurally a
   maintainer tool reasoning about **the plugin** versus the platform. Putting competitors in
   its shipped baseline would have made every user of the plugin inherit *this repo's*
   competitor list. `/capability-check` is now explicitly left alone.
2. **Wrong shape.** The real thing wanted is per-project and domain-specific: *what does our
   app already do, what does this domain expect, where are we lacking.* That needs a store
   (02a) and a lane that reads it (02b).

Consequence worth stating: 02 is **no longer blocked on owner inputs.** The two blanks it
used to carry — the competitor set and the audience — stopped being blanks in a requirement
file and became **fields in a per-project store**, answered once per project. This repo's own
instance is just one more project.

## Order and `/automate` handling

```
01 (done)  →  02a  →  02b
```

- **01** is stamped `## Status: done` and is excluded from any folder resolution.
- **02a** is unblocked and is a normal code-change item.
- **02b** has a **hard** dependency on 02a merged — it reads that store and has no subject
  without it. Do not queue them in one run.

## Decisions already made — do not re-open

- **No `/setup` module for the product store.** Considered and rejected on the `rules` module
  precedent: that module seeds **portable** rules, identical for every repo (`applies_to:
  null` because *"a path glob would assume a layout"*). A product store is project-specific by
  definition — nothing shippable, so the property that earns a module is absent. Every module
  also either writes outside the repo, publishes user content behind consent, or runs a
  process; this store does none. Bootstrap is owned by the consumer, at the moment of need.
- **No code graph for the capability inventory.** The graphify tier was retired 2026-08-17 on
  measurement — graph absent, bridge 255 commits stale, `brain_context` zero across every log,
  and the 71% validation without a control arm. The committed `.agent/orientation/` memos plus
  direct reads are the substrate.
- **No new command for the domain lane.** It is a `--domain` flag on `/propose` — same
  artifact, same folder, same contract, different basis. The two bases never run in one
  invocation and `--domain` is never implicit (the `/capability-check` two-mode precedent).
- **Silent no-op is banned.** No-op-when-absent is correct read-side behaviour; doing it
  *silently* is what killed `brain-context`. A consumer that finds no store names it and
  offers the bootstrap.

## Constraints inherited from decisions already made

- **Nothing gating.** Advisory / fail-safe throughout.
- **Nothing ranked or scored.** Classification is not a score; a view that ranks becomes a view
  that decides.
- **Absent evidence is omitted, never defaulted**, and **unverified is not absent**.
- **The human gate sits at dequeue.** `proposed/` is not an `/automate --folder` target.

## Deliberately NOT in this queue

- **Unattended landing** — the fail-closed gates under `--non-interactive`, the drain exiting
  before a slow `claude-review` posts, and the `/autonomous` TTY false positive. Invention
  gives the mill something to chew on overnight; it does not make the overnight run land
  without a human. Separate track.
- **Going and getting users.** If a project's audience turns out to need real user signal,
  that is a different project and does not belong in a requirement file here.
