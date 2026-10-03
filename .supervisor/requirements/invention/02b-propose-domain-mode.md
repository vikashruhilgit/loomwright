# 02b — `/propose --domain`: what a competent app in this domain does, and we don't

## Problem

`/propose` shipped the inward half of intake: it reads the churn ledger through
`floor.json` and proposes work derived from **our own recorded mistakes**. It is honest about
its scope — its own words are *"the intake side of a mill that invents its own work"*.

But a project's most valuable missing work is usually not in its churn ledger. It is the
capability the domain expects and the app does not have: the invoicing tool with no
multi-currency, the API with no rate limits, the B2B product with no SSO. Nothing in the
plugin looks outward. `/capability-check --strategy` is the only outward-looking surface and
it is maintainer-only and plugin-scoped (see 02a §Problem). `/product-owner` looks outward
only after a human has already named the thing to look at — `--brainstorm deep` researches a
problem you have **already stated**.

So the gap is discovery: *what should we be asking about that nobody has asked about?*

## Goal

A second basis for `/propose` — the domain instead of the ledger — emitting the same kind of
artifact into the same folder under the same contract, so one triage surface serves both.

## Scope

1. **A `--domain` flag on `/propose`.** Not a new command. Both bases produce the same
   artifact (an evidence-carrying draft in `.supervisor/requirements/proposed/`), obey the
   same contract (propose-only, never queues, never ranks, human decides at dequeue), and land
   in the same folder the human already triages. Note `/propose` currently has **zero flags**
   (it is env-var tuned), so this is its first.

2. **The two bases NEVER run in one invocation, and `--domain` is never implicit.** The
   precedent is `/capability-check`, which runs two modes emitting two distinct report types
   with an explicit "never mixed in one run" rule. The reason here is sharper than symmetry:
   the default basis is local `jq` over a local file and costs nothing, while `--domain`
   spends fetch budget and emits judgment-class output. Someone running bare `/propose` must
   never trigger a network call.

3. **Three inputs, and each one's evidence class travels with it:**
   - **The product store** (02a) — domain, stance, competitors. Absent ⇒ say so and offer the
     bootstrap; never a silent skip (02a §5).
   - **Our capability inventory** — what this app already does, from the project's own code
     and docs plus the committed `.agent/orientation/` memos, which carry `head_sha` and
     `areas:` prefixes so their staleness is measurable. **Derived.**
   - **The domain expectation set** — what competent apps in this domain do, fetched from the
     store's `competitors[]` and domain sources under a stated budget, each carrying its URL
     and fetch date. **External, and the weakest input** — competitor marketing overstates.

4. **Do NOT build a code graph for the inventory.** The graphify tier was retired 2026-08-17
   on measurement, not taste: `graphify-out/graph.json` absent after a single 2026-06-22
   build, its bridge surviving as an orphan **255 commits** behind HEAD, `read-bridge.sh`
   emitting nothing, `brain_context` appearing **zero times across every session log**, and
   the 71% validation shown to have no control arm — every "strict hit" anchored by a shared
   file path a plain grep would also have found. Rebuilding it here walks back into the
   staleness trap the north-star names by name. The inventory is direct reads plus orientation
   memos.

5. **Every gap is classified `TABLE-STAKES` / `DIFFERENTIATOR` / `NOT-FOR-US`, and the
   default action comes from the store's `stance`** (02a §4). `stance: product` ⇒ table stakes
   is the highest-priority build. `stance: tool` ⇒ table stakes defaults to *record and skip*,
   honouring "no vendor-parity chasing". A `NOT-FOR-US` gap is recorded so a later run does not
   re-raise it — the same dedup discipline `/propose` already implements through its token line
   and `## Status: done` supersession scan.

6. **"We don't have X" is the claim this lane will get wrong, so it must show where it
   looked.** Every gap states the surfaces searched and the terms used. **Unverified is not
   absent**: a capability the inventory could not confirm either way is reported as
   *unverified*, never as missing. This is the same rule `floor.json` already enforces —
   absent evidence is an omitted field, never a plausible default — applied to the input this
   lane is most likely to fabricate.

7. **Same emitted shape as the default basis, different namespace.** Title, dedup token,
   basis lines, `## Problem` / `## Goal` / `## Scope` / `## Acceptance criteria` /
   `## Evidence`, and a per-source citation list — matching what `propose-work.sh` already
   emits. Filenames namespaced (`domain--<slug>.md`) so the two bases can never collide in
   `proposed/`.

8. **Bounded and dated.** One stated fetch cap, shared across the run, mirroring
   `--max-fetches` (default 5). A run that exhausts it reports **partial coverage** and names
   what it did not reach. Every cited source carries its fetch date, and a source older than a
   stated threshold is named as stale rather than quietly used.

## Non-goals

- **No user stories.** This lane stops at *"here is the gap and why"*, exactly as the default
  basis stops at intake. Turning a chosen gap into stories with acceptance criteria is
  `/product-owner`'s job — the handoff is `/propose --domain` → human picks → `/product-owner`
  → `/automate`.
- **No demand claims dressed as findings.** "Users would love X" is judgment; it may be
  emitted, but labelled, and never rendered as a derived finding.
- **No ranking, scoring, or prioritisation.** Classification is not a score.
- **No auto-queue.** `proposed/` remains deliberately not an `/automate --folder` target.
- **No new command, agent, hook, or skill** — one flag on an existing command.
- **No writes outside `.supervisor/requirements/proposed/`.**

## Depends on

**02a merged** (hard) — this reads its store and has no subject without it.

## Acceptance criteria

- [ ] Bare `/propose` performs **zero** network calls — asserted by running it under a
      network-denying stub and observing no attempt, not by reading the code.
- [ ] `--domain` with no product store present emits the named "no product context" message
      and the bootstrap offer, writes nothing, and exits 0.
- [ ] Given a fixture store and a stubbed domain source, at least one gap is emitted; every
      emitted gap carries its classification, its evidence class (derived vs judgment), the
      surfaces searched, and each source's URL and fetch date — asserted by parsing the
      emitted file.
- [ ] A capability the inventory cannot confirm either way is emitted as **unverified**, never
      as missing — asserted on a fixture built to be ambiguous.
- [ ] The same fixture under `stance: product` and `stance: tool` produces the same
      classifications with **different default actions** — asserted by diffing the two outputs.
- [ ] A `NOT-FOR-US` gap recorded once is not re-emitted on a second run, and the suppression
      is reported with its basis.
- [ ] With the fetch cap set to 1, exactly one external call is made and the output reports
      partial coverage naming what was not reached.
- [ ] Given a source older than the staleness threshold, it is named as stale in the output
      rather than cited silently.
- [ ] Emitted filenames are namespaced so a `--domain` run and a default run cannot overwrite
      each other in `proposed/` — asserted by running both and listing the directory.
- [ ] No file outside `.supervisor/requirements/proposed/` is created or modified — asserted
      by hashing the tree before and after.
- [ ] No emitted gap contains a score, rank, or priority field — asserted by grepping the
      emitted files.

## Outcomes Rubric

- The system can say what the domain expects that this app does not do, with sources and dates.
- Derived and judgment are visibly different classes; a gap never claims more than it verified.
- "We don't have it" is backed by where it looked, and unverified is never reported as absent.
- Stance decides the default action, so one lane serves a product and a tool honestly.
- One command, two bases, one triage folder, no new surface.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-09-09-propose-domain-mode.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
