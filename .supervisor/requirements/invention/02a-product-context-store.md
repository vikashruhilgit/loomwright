# 02a — `.agent/product.json`: what this project is, who it serves, who it competes with

## Problem

Every product-shaped surface in this plugin runs without knowing what the project **is**.

`/product-owner` translates a business problem into user stories and acceptance criteria
with **no notion of who the user is** — it takes the audience from whatever the human typed
into the prompt, and forgets it the moment the run ends. `/capability-check --strategy` is
the one surface that reasons about product direction, and it is structurally
**maintainer-only**: it reads `${CLAUDE_PLUGIN_ROOT}/docs/CAPABILITY_BASELINE.json`, its own
parameter table records that `--update-baseline` is *"meaningful only in the plugin's own
repo (the install dir is read-only); a no-op notice elsewhere"*, and its grounding inputs are
`agents/` and `commands/` — the **plugin's** surface. Run on a user's payments app, it would
read Loomwright and propose directions for Loomwright.

There is nowhere to record that this repo is a B2B invoicing API whose competitors are X and
Y, that its users are finance teams, and that missing SSO is table stakes rather than a
differentiator. Measured 2026-09-06: `grep -rl "competitors"` across the repo hits three
plugin files and **zero** project-level stores.

## Goal

One committed, per-project store holding the product facts that are true of *this* repo, and
one reader for it — so a domain-aware lane has a subject, and `/product-owner` stops guessing
who it is writing for.

## Scope

1. **`.agent/product.json`** — a committed store, sibling of `.agent/rules/` and
   `.agent/orientation/`. That directory is the established home for **committed,
   tool-agnostic, per-project** knowledge: its four files are tracked (`git ls-files .agent`),
   so unlike gitignored `.supervisor/` it travels with the repo and a cloning teammate
   inherits it. Fields:
   - `domain` — what this project is, in the terms its own market uses.
   - `stance` — `product` or `tool`. **Load-bearing, see §4.**
   - `audience` — who it serves, and (honestly) whether that is evidence-backed or assumed.
   - `competitors[]` — each `{name, url, last_fetched}`. `last_fetched` is required and may
     be null, meaning *never fetched*, which a reader must render as unknown rather than old.
   - Provenance and freshness, mirroring the orientation memos' header contract:
     `written_at` (ISO-8601 UTC) and `head_sha` (the commit it was written against), so
     staleness is measurable against churn rather than guessed from elapsed time.

2. **`read-product.sh`** — a reader following the six that already exist (`read-rules.sh`,
   `read-orientation.sh`, `read-postmortem.sh`, `read-project-memory.sh`, `read-lessons.sh`,
   `read-system-contract.sh`). Same discipline: `set -uo pipefail` with no `set -e`, a
   `command -v jq` guard that skips rather than fails, **exit 0 always**, and emitting nothing
   at all when the store is absent or unparseable. It is an advisory reader; it must never
   break its caller.

3. **Bootstrap is owned by the consumer, at the moment of need — there is NO `/setup`
   module.** This was considered and rejected on the evidence of the closest precedent. The
   `rules` module seeds **portable** rules: a fixed set, identical for every repo, stamped
   `provenance.source=setup:rules-seed`, with `applies_to: null` because *"a path glob would
   assume a layout"*. That is shipped content installed into a project — a template. A product
   store is **project-specific by definition**; there is no portable seed for "who are this
   project's competitors", so the one property that earns a module has no analogue here.
   Every existing module also either writes outside the repo (user-scope `settings.json`, the
   ui directory, Docker), publishes user content behind a consent gate (the `memory` module's
   `.gitignore` negation), or runs a long-lived process (`ui serve`). This store does none of
   those: `.agent/` is already committed, there is no user-scope write, no egress, no process,
   no consent question. And the registry's own rule — *"New modules append a row here AND a
   flow section in `commands/setup.md` in the same change"*, against a dashboard **fixed at
   four options** that must not grow — is a real cost for no benefit.
   Instead: the first consumer that needs the store and does not find it **scans the project
   and proposes one** (README, manifests, docs), the user confirms or edits, and only then is
   it written. Nothing is auto-registered — the same consent posture as the ui registry's
   `scan`.

4. **`stance` decides the default action of a gap, and must not be hard-coded.** For a
   **tool** with an "own the primitives" position, a parity gap defaults to *do not build* —
   this repo's own north-star carries "no vendor-parity chasing" as a standing NO. For a
   **product**, a table-stakes gap is the *highest*-priority thing to build. Hard-coding
   either default would make the lane tell a payments app to skip its missing fraud checks
   because parity is a NO. The store carries the stance; the lane reads it.

5. **Absent means absent, and it must SAY SO where it is needed.** No-op-when-absent is the
   right read-side behaviour, but **silent** no-op-when-absent is a documented feature-killer
   in this repo: `brain-context` was read-path-only and opportunistic with no bootstrap path,
   and the result was `graphify-out/graph.json` absent, its bridge orphaned **255 commits**
   stale, and `brain_context` appearing **zero times across every session log**. A consumer
   that finds no store must name it and offer the bootstrap — never skip quietly and exit 0
   as though nothing were missing.

## Non-goals

- **No `/setup` module** (§3), no dashboard change, no `commands/setup.md` edit.
- **No new command, agent, hook, or skill.** Counts stay where they are; `check-doc-currency.sh`
  sees no change.
- **No change to `/capability-check`.** It stays a maintainer tool reasoning about the plugin
  versus the platform. Bending it into per-project work was considered and dropped: two
  different subjects, two different commands, and leaving it alone removes the per-project
  write problem instead of solving it.
- **No network.** This item defines and reads a store; fetching anything is 02b's problem.
- **No auto-detection of competitors.** Proposed on scan, written only on confirmation.
- **No `.gitignore` change.** `.agent/` is already tracked; nothing needs un-ignoring.

## Depends on

Nothing. `.agent/` exists and is committed.

## Acceptance criteria

- [ ] `read-product.sh` emits the store's fields for a well-formed `.agent/product.json`, and
      every emitted value is traceable to a key in the file — asserted against a fixture, not
      by reading the code.
- [ ] Given an absent store, a malformed store, and `jq` unavailable (three separate cases),
      the reader emits nothing, names the reason on stderr, and exits 0 in each.
- [ ] A `competitors[]` entry with `last_fetched: null` renders as **never fetched**, never as
      a date and never as "stale" — asserted on a fixture carrying both null and dated entries.
      (This is the nullable-required shape: assert key **presence** with `has()`, and test the
      missing-key and explicit-null cases separately.)
- [ ] `stance` is read, not assumed: a fixture with `stance: "product"` and one with
      `stance: "tool"` produce different reported defaults, and a store missing `stance`
      reports it as unset rather than defaulting to either.
- [ ] The bootstrap proposes and does not write: running it against a project with no store
      produces a proposal and leaves the working tree byte-identical until an explicit
      confirmation — asserted by hashing the tree before and after.
- [ ] A consumer invoked with no store present emits a named, actionable "no product context"
      message. Asserted by mutation: delete the message and the test fails.
- [ ] Nothing outside `.agent/product.json` is written by the bootstrap — asserted by hashing
      the tree, not by reading the code.
- [ ] The vendor-coupling ratchet is measured before and after and the delta reported,
      whatever it is.

## Outcomes Rubric

- A project can state what it is, who it serves, and who it competes with, in one committed
  place that travels with the repo.
- The store's absence is visible at the point of use, never silent.
- Stance is data, so the same lane serves a product and a tool without being told twice.
- One reader, matching the six that already exist; nothing new to learn.
- Nothing is fetched, auto-detected, or written without confirmation.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-07-product-context-store.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
