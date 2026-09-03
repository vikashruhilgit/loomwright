# Loomwright site — v2 requirements

**Date:** 2026-09-02
**Target:** `index.html` (static, no build step, GitHub Pages, `.nojekyll`)
**Source of truth for every claim below:** the plugin repo at `vikashruhilgit/loomwright`
(`/Users/vikashruhil/Documents/work/AI/ai-agent-manager`). Every number and behaviour in this
document was verified against that checkout on 2026-09-02 — file paths are given so a writer can
re-check rather than trust this file.

---

## 0. Why this change

The live site sells **machinery** ("four laws", "five stations", a policy builder). That is good
material, but it answers *how it works* before the reader has agreed there is a problem. The four
burns below are the actual reason someone switches, and today they are implied, never stated.

Four things are being added, one thing is being corrected:

| # | Section | Status | Placement |
|---|---|---|---|
| A | **The four burns** — the problems people already have | NEW | Directly under the hero, above "Four laws of the mill" |
| B | **What an agent needs to work — and what it needs to be trusted** | NEW | After "Four laws", before the pipeline figure |
| C | **The whole mill, one repo, end to end** — full setup + worked example | NEW (absorbs and replaces the current thin "Guide — first hour") | After the pipeline figure |
| D | **In progress** and **What's next** | REWRITE of the existing "Roadmap" | Where the roadmap is today |
| E | Version/count currency fix | CORRECTION | Hero stamps, footer, `PRODUCT.md` |

---

## 1. Verified ground truth (use these numbers; do not invent others)

| Fact | Value | Where verified |
|---|---|---|
| Plugin version | **15.41.0** | `loomwright/.claude-plugin/plugin.json` |
| Agent roles | 14 (9 user-facing, 5 internal) | `loomwright/agents/*.md` |
| Slash commands | 21 | `loomwright/commands/*.md` |
| Skills | 41 | `loomwright/skills/*/` |
| Quality-gate hooks | 24 | `loomwright/hooks/hooks.json` (counted per hook entry) |
| `/setup` modules | 8 — observability, memory, rules, telemetry, notifications, webhook, beads, mysql-mcp | `loomwright/commands/setup.md` |
| Sanctioned auto-merge executors | exactly **1** | `loomwright/scripts/automate-helpers.sh` `gate-eval` |
| Auto-merge conditions | **5**, all must hold, unreadable ⇒ park | `loomwright/skills/automate-loop/SKILL.md` §10 |
| Split reasons that justify fan-out | `file-conflict`, `context-bound`, `genuine-parallelism` | `loomwright/skills/supervisor-readiness/SKILL.md` §Decomposition Threshold |
| Required brief sections | 9 required + 3 optional (Feasibility, Outcomes Rubric, Executable Acceptance) | same file, §Section Requirements |
| Visual surface shipped today | **0** HTML/CSS/JS files in the plugin | `.supervisor/requirements/loom-floor-ui-overview.md` |

### E. Currency correction (do this first — it is a one-line credibility bug)

The site says **v15.37** in the hero stamps, **v15.37.0** in the footer fine print, and
`v15.37` in `PRODUCT.md` §Capabilities. The plugin is **15.41.0**. Counts (14 / 21 / 41 / 24) are
still correct.

**Requirement E1.** Update all three places to `v15.41`.
**Requirement E2.** Because this drifted once, the version string must appear in **one** place in
the HTML and be referenced from the others, or a single `<!-- VERSION: 15.41.0 -->` comment must sit
at the top of `index.html` with a note in `README.md` listing the three sites to update on a bump.
Do not add a build step for this; the site has none and should keep none.

---

## 2. Section A — "The four burns"

### Intent

The reader should recognise their own week in the first screen after the hero. No machinery, no
agent count, no metaphor. Problem, then the one mechanism that answers it.

### Copy (approved substance — polish wording, do not change claims)

> **You are not shopping for more agents. You are trying to stop getting burned the same four ways.**

**1 · The agent starts coding before anyone agrees what "done" is.**
Chat-coding jumps straight into files. You get a pile of edits and a vague "I think this works."
→ *Loomwright's first step is a brief:* feasibility verdict, file impact, subtasks, acceptance
criteria, and a rubric for the outcome. A separate Plan Reviewer passes, fails, or escalates it
**before** the brief is saved. No file moves until that exists.

**2 · Two agents, one repo, a merge mess.**
Parallel agents overwrite each other and you spend the afternoon untangling branches.
→ *Fan-out is the exception, not the default.* Work splits only for a named reason — file
conflict, too big for one context, or genuine parallelism. When it does split, each worker runs in
its own git worktree, overlapping files wait, merges are sequential behind a pre-merge safety gate,
and you get one PR per pass instead of five conflicting branches.

**3 · You cannot walk away, and you also cannot trust auto-merge.**
Babysit it, or let it merge garbage. Both feel stupid.
→ *Default: it parks a reviewed PR and tells you a human is required.* Auto-merge exists in exactly
one place in the whole plugin, is off unless you pass `--auto-merge`, and fires only when all five
trusted conditions hold. Anything false — or anything it cannot read — parks the PR and notifies.
It does not silently ship.

**4 · The mill forgets your house. Every run starts cold.**
Review keeps catching the same nits. The next teammate has no idea what was decided.
→ *You write the rules once (`/rules`) and workers read them while writing, not after review catches
them.* `/setup` and a committed config make the mill behave the same on a fresh clone. `/dreaming`
proposes lessons from your own session logs and hands them to you as a pull request; you accept
item by item. It gets smarter. It never self-trusts.

**Then, as the product sentence:**

> **A messy goal in. A reviewed pull request out. You only show up when it actually needs you.**

### Honesty constraints (non-negotiable — these keep the page defensible)

- **A2.1** Immediately after the product sentence, state the cost of the promise in one line:
  *"'When it needs you' is three places: approve the brief, answer the rubric, merge the PR. This is
  foreground-assisted, not fire-and-forget."* The site already says this in the guide; it must not
  be contradicted by the new headline.
- **A2.2** Burn 2 must **not** claim parallel-by-default. Single-agent is the current default
  (owner decision D3, `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md`) precisely because forced fan-out
  measured 6.4× the cost of bare Claude Code for the same defect outcome. Saying "we run four agents
  at once" would be selling the thing that was removed.
- **A2.3** Burn 3 must name `--trust-unprotected` in the same breath as `--auto-merge`, as the
  user's copy already does. A branch with no enforceable protection does not auto-merge unless you
  say you trust it.

### Design requirements

- **A3.1** Four cards or four numbered rows, each carrying the existing lane colour
  (madder / chartreuse / indigo / copper) so the burns visually pre-map onto the four laws below.
- **A3.2** Two-tier type inside each item: the burn in the reader's voice (plain, present tense),
  the answer in product voice. Visually distinguish them — the current site has no pattern for this
  and needs one.
- **A3.3** Must read as a full-width band, not a card grid squeezed under the hero. This is the
  strongest section on the page; give it room.
- **A3.4** No animation on entry beyond the existing `off-stage` intersection pattern. Respect
  `prefers-reduced-motion` the way the current script already does.

---

## 3. Section B — "What an agent needs to work, and what it needs to be trusted"

This is the section that does not exist anywhere on the site today and is the real differentiator.
Split it into two halves under one heading.

### Half 1 — Five things any coding agent needs to actually work

Each item: the need, the mechanism, and where it lives on disk. Keep the on-disk path — it is what
makes this readable as engineering rather than marketing.

| # | What it needs | What Loomwright gives it | On disk |
|---|---|---|---|
| 1 | **A definition of done** it can be measured against | Launch Pad brief: 9 required sections, plus an optional Outcomes Rubric and an Executable Acceptance surface | `.supervisor/jobs/pending/<date>-<slug>.md` |
| 2 | **Your house rules at DO time, not review time** | `.agent/rules/` is committed and read at three seams — by the worker while implementing, in the Phase 4.5 review, and as a session-start nudge | `.agent/rules/*.json` |
| 3 | **A base that is actually current** | Phase 1.5 pre-flight sync reconciles the goal against recent `origin/<base>` commits and open PRs: CLEAR, OVERLAP, or SUPERSEDED. Brief staleness is measured by churn over the anticipated file set, not by elapsed time | `.supervisor/state.md`, brief `Base commit` stamp |
| 4 | **Isolation with explicit lanes** | git worktrees per worker, ordered merges, `WorktreeCreate`/`WorktreeRemove` hooks, overlap detection that fails closed in CI | `.claude/worktrees/`, `loomwright/hooks/hooks.json` |
| 5 | **A way to prove it, not vibes** | a deterministic `outputs_verified` gate plus tests and lint per subtask (zero model tokens), then one integrated LLM review after merge | `.supervisor/worker-summaries/`, `.supervisor/logs/*.jsonl` |

**B1.1 — required honest limit, printed on the page, not hidden:**
> `contract_conformance_status: skipped` means **unverified**, not clean. A green `heal_decision: PASS`
> does not mean the PR is reviewer-clean. We print both rather than round them up.

That single caveat does more for credibility than any other paragraph on the site. Do not cut it
for length.

### Half 2 — Six guarantees that make it trustable

These are invariants in the codebase, not aspirations. Each one is enforced and each one has a test
or a grep that proves it.

1. **Failure has two modes, on purpose.** Correctness gates fail **closed** — an unreadable
   condition blocks. Side-effect emitters (telemetry, webhooks, the observability probe) fail
   **safe** and always exit 0. Inverting either is treated as a security regression, not a bug.
2. **One merge door.** Exactly one code path in the entire plugin executes `gh pr merge --squash`.
   `/review-pr`, `/supervisor`, and the heal loop **never** merge — they terminate with the PR open.
   The invariant is verified by a grep in CI, not by convention.
3. **Advisory can propose. Only a human promotes.** Lessons, house rules, project memory, and the
   System Twin are all advisory and subordinate to `CLAUDE.md`. Nothing writes itself in.
4. **One writer per store, with provenance.** Memory and Twin contracts have a sole writer and
   hash-chained provenance; the index keys on a content hash, so a hand-edited entry is detectable
   rather than silently trusted.
5. **Every loop is bounded and the bound is recorded.** The review drain writes a rounds ledger and
   terminates with a stated reason, so "it converged" is a record, not a claim.
6. **Local by default, three opt-ins, all off.** Your logs, memory, Twin, insights, and the
   Obsidian vault never leave the machine. The observability module points Claude Code's **own**
   OpenTelemetry at a collector in Docker on your box — the plugin emits no spans of its own. The
   three things that can go outward — GitHub-issue telemetry, gate webhooks, and version-controlling
   your memory stores — are each off until someone turns them on, and telemetry fails **closed** on
   a privacy match rather than posting.

**B2.1** Reuse the existing `assets/data-boundary.svg` and `assets/control-plane.svg` here — they
already illustrate guarantees 3 and 6 and are currently buried in the teams section. Consider
moving them up rather than drawing new art.

**B2.2 — the measurement paragraph (strongly recommended, optional if it feels too inside-baseball).**
Loomwright measured its own overhead at **6.4× the cost and 4× the wall clock of bare Claude Code for
the same defect outcome** on one corpus entry, published the finding, and rebuilt the defaults around
it — that is why single-agent is now the default. State the scope limit in the same sentence: one
corpus entry, not a benchmark suite. A product that publishes a bad number about itself is the
cheapest trust signal on this page.

### Design requirements

- **B3.1** Half 1 is a table or a definition list; Half 2 is six short blocks. Do not render both
  as the same card grid — the page already leans heavily on one card pattern and this section will
  disappear into it.
- **B3.2** Every guarantee gets a monospace tag naming the enforcement (e.g. `fails closed`,
  `one executor`, `human-gated`, `sole writer`, `bounded`, `off by default`).
- **B3.3** Section must be linkable: `id="trust"`, and add it to the in-page navigation if one is
  added (see §6).

---

## 4. Section C — "The whole mill, one repo, end to end"

### Intent

One continuous worked example on one repo, from empty machine to merged PR to a lesson that
persists. The current "Guide — first hour" is five stubs; this replaces it. Every step must answer
three things: **what you type**, **what appears**, and **what it solved**.

### Structure — 9 steps

**Step 0 · Before you start.** A git repo. `gh` authenticated if you want PRs. A `CLAUDE.md` (run
`/init` if there is none). Say plainly that Loomwright reads your repo where it already is and
creates `.supervisor/` for state.

**Step 1 · Install.** Link to the existing per-app install tabs; do not duplicate them. Keep the
`/plugin`-is-not-a-shell-path warning.

**Step 2 · `/setup` — see what is wired.** A dashboard, not a wizard. Show the 8 modules with one
line each on *what problem the module solves*:

| Module | Solves |
|---|---|
| observability | you cannot see where a long run spent its time |
| memory | your Twin/lesson stores live outside version control and die with the machine |
| rules | conventions live in one person's head and are only enforced at review |
| telemetry | opt-in, off by default; nothing posts without consent |
| notifications | you miss the moment a run needs a human decision |
| webhook | a gate fired and nobody was at the keyboard |
| beads | issue tracking for the planning agents (optional) |
| mysql-mcp | read-only DB access when the work needs schema truth |

**Step 3 · `/rules` — write the house down once.** Show a real `add` and what lands in
`.agent/rules/`. State the payoff explicitly: a worker reads this while writing the code, which is
the difference between a rule and a review nit.

**Step 4 · `/launch-pad "<goal>"` — GATE 1.** Show the brief structure that comes back
(Environment, Feasibility verdict, Task, Acceptance Criteria, Subtask Structure, Parallelism
Analysis, Skill References, Risk Assessment, Configuration, Handoff) and that a Plan Reviewer
gates the save with PASS / NEEDS_HUMAN / FAIL. **This is where you approve or refine.** Solved:
burn 1.

**Step 5 · `/supervisor job: …` (or `/autonomous "<goal>"` to chain 4 and 5).** Show the phase
sequence, the worktrees appearing, the sequential merge, the PR opening. Note the honest default:
most goals stay single-agent; fan-out happens when the brief names a split reason. Solved: burn 2.

**Step 6 · Phase 4.5 self-heal + rubric — GATE 2.** One integrated review over the merged diff,
bounded fix loop, rubric graded N/M. **This is where you answer the rubric.** Show a real
`heal_decision` line and the caveat from B1.1.

**Step 7 · `/review-pr --until-mergeable <url>` — GATE 3.** Bounded review → fix → re-review until
`READY`. **`READY` still means open.** You read the diff. You merge. Solved: burn 3.

**Step 8 · Week two — the loop that compounds.** `/insights` weekly, `/pr-postmortem` on any PR
that took four review rounds, `/handoff` when someone new arrives, `/dreaming` monthly →
proposes lessons and harvested conventions as a pull request you review like any other. Solved:
burn 4.

### Requirement C1 — the artifact table

At the end of the walkthrough, one table showing what now exists on disk and who writes it. This is
the single most convincing element for an engineer evaluating the tool, because it proves the state
is inspectable and file-based rather than hidden.

| Path | What it holds | Written by |
|---|---|---|
| `.supervisor/jobs/{pending,in-progress,done,failed}/` | briefs through their lifecycle | Launch Pad, Supervisor |
| `.supervisor/state.md` | current phase and progress | derived from the append-only log by a hook — one writer |
| `.supervisor/logs/<session>.jsonl` | append-only session events | hooks |
| `.supervisor/worker-summaries/` | what each worker actually did | workers |
| `.supervisor/drain-rounds/` | review-drain rounds and termination reason | review-heal loop |
| `.supervisor/memory/LESSONS.md` | accepted lessons, provenance-indexed | `/dreaming`, human-gated |
| `.supervisor/twin/contracts/` | per-subsystem System Contracts | Twin writer, hash-chained |
| `.agent/rules/` | committed house rules | `/rules`, human-added |
| `.supervisor/config.json` | committed policy that binds unattended runs | you |

### Requirement C2 — one command block per step

Copyable, with a copy button consistent with the existing `#copy-btn` / `#policy-copy` pattern. Do
not introduce a third copy interaction style.

### Requirement C3 — do not fabricate output

Where the walkthrough shows a result line, it must be a real shape from the plugin's result schemas
(`loomwright/docs/RESULT_SCHEMAS.md`), not invented text. If a real sample cannot be sourced, show
the field names and omit the values rather than making them up. `PRODUCT.md` principle 5 applies:
no numbers we do not have.

### Requirement C4 — keep the existing five-step guide's warnings

The three warnings currently in the guide (do not paste `/plugin` into zsh; do not start three lanes
at once; a healed PR is still an open PR) must survive the rewrite. They read like they were written
after someone got it wrong, which is exactly why they are worth keeping.

---

## 5. Section D — "In progress" and "What's next"

### The problem with the current roadmap

It has five beads (`Now / Next / Then / Later / North star`) and reads as a schedule. Two of those
beads are genuinely honest ("Not started. Highest-risk rung. Intentionally last."), and the honesty
is the best thing on it. But the page cannot currently distinguish *"a person is working on this
right now"* from *"we intend to do this in some order."* Split it.

### D1 — "In progress" (what is actually moving, today)

Every item carries a **state label** from a fixed vocabulary, and the vocabulary is printed:

`shipped` · `in progress` · `queued` · `probed — NO-GO` · `not started`

Verified content as of 2026-09-02:

**1. The Loom Floor — giving the mill a face.** *in progress.*
Loomwright has **zero** visual surface today: no HTML, CSS, or JS anywhere in the plugin. Five work
items are scoped. Item 01 (a spawn-side event so the log records *lives*, not only deaths) was
probed and **closed NO-GO** — the spawn payload carries no joinable agent id, so the "who is working
right now" field is unsatisfiable rather than merely unbuilt. Item 02 (an opt-in status line) is
briefed and queued, and ships *without* the active-agent field because of that NO-GO.
**Print the NO-GO.** A roadmap that shows a probe returning "no" is worth more than one that only
shows wins — and this project treats a NO-GO as a pass, because it cost hours instead of a week.

**2. Cost discipline — making a small task cost small money.** *shipped, still landing.*
The forced-fan-out default is gone; single-agent is the default and fan-out needs a named reason.
Four review passes collapsed to two lenses. Preloaded prompt inventory is now routed on demand
(measured: one agent's spawn-time weight fell from ~51.8k to ~21k). Remaining: unify the tool lists
so spawns share a cache prefix.

**3. State that cannot lie.** *shipped.*
One hook writer for progress state, `state.md` derived from the append-only log, resume reconciled
against git ground truth. This existed because the state file once reported a job as running that
had fully merged.

**4. Portability out of one vendor.** *queued.*
82% of the plugin's scripts are already vendor-neutral; the lock-in is a thin seam. The intent is
ports-and-adapters so the core runs beyond Claude Code, with vendor-native adoptions living in the
adapter. A coupling ratchet is in place to stop the seam growing.

**5. QA spin-off (Selvedge).** *queued.* Seven items to move the QA agents, commands, and skills
into a sibling plugin so Loomwright's core stays a mill, not a suite.

### D2 — "What's next" (ordered, with the condition that unblocks each)

Keep the existing roadmap's best instinct — **trust is earned, not scheduled** — and make it
structural: each item states *what has to be true before it starts*, not a date.

| Next | What it is | Unblocked by |
|---|---|---|
| **Ground-truth verification** | run the software in the heal pass — Playwright for web apps, headless loops against a corpus. A hard pass/fail, not a score | nothing; this is the current front |
| **Workers get shared context and explicit file lanes** | Launch Pad's file-impact analysis handed to workers instead of thrown away, so each one stops re-acquiring the codebase cold | the runner work below, which composes the spawn prompt |
| **The runner substrate** | the SDK runner becomes the execution core; the judgment layers (Twin, lessons, rules, review lenses) ride on top | fixing it forward — it is a chosen substrate, not an experiment |
| **Twin starts enforcing** | flip advisory conformance to a real gate | only after the benchmark has caught real regressions without a false-positive habit. **No calendar flip** |
| **A proactive mill** | a watcher that can open PRs unprompted | four guardrails first — cadence expiry, per-run budget, circuit breaker, heartbeat. Not started. Highest-risk rung. Deliberately last |
| **A standalone application** | the mill wrapped around the runner, beyond a single vendor's plugin format | only after the runner proves itself end to end |

Keep the **north star** bead as it stands — "Point at the repo. Own this." — it is the best copy on
the current page.

### D3 — the rule that keeps this section honest

**Every roadmap item must carry the condition that would make us drop it.** Two already do (Twin
enforcement, the proactive mill). Extend it to all of them. This is the roadmap equivalent of the
`skipped ≠ clean` caveat, and it is the same argument for trust.

### D4 — do not claim

No dates. No quarters. No "coming soon". No implied team size. No customer logos, testimonials, or
benchmark numbers — none exist (`PRODUCT.md` §Evidence on Hand).

---

## 6. Cross-cutting requirements

- **X1 · No build step.** Static HTML/CSS/JS in `index.html`, as today. No framework, no bundler, no
  npm. The page must still work opened from `file://`.
- **X2 · Page weight.** The page already carries seven images. Adding four sections must not add
  more than one new image; prefer reusing `control-plane.svg`, `data-boundary.svg`, `merge-gate.svg`
  by relocating them. Keep `loading="lazy"` and explicit `width`/`height` on every image.
- **X3 · Navigation.** The page is now long enough to need one. Add a sticky, minimal in-page nav
  with anchors: `#burns`, `#trust`, `#walkthrough`, `#teams`, `#progress`, `#roadmap`, `#install`.
  It must collapse to a single row on mobile and must not obscure the hero.
- **X4 · Accessibility.** Match the existing standard, which is genuinely good: `aria-pressed` on
  every toggle, `aria-live` on swapped panels, real `<button>` elements, full `alt` text on every
  figure, and `prefers-reduced-motion` honoured. Any new interactive element inherits all of it.
- **X5 · Voice.** Short declaratives. Second person. No exclamation marks. Name the limitation in
  the same paragraph as the capability — that is the page's existing register and the reason it
  reads as credible.
- **X6 · Anchor stability.** `#install`, `#guide`, `#plays`, `#teams`, `#roadmap` are live links
  that may already be shared. If `#guide` is absorbed into the walkthrough, keep `id="guide"` on the
  new section so existing links do not 404 to the top of the page.

---

## 7. Acceptance criteria

- [ ] Hero stamps, footer fine print, and `PRODUCT.md` all read **v15.41**; counts remain 14 / 21 / 41 / 24.
- [ ] Section A exists directly under the hero, states all four burns in the reader's voice, and its
      answer to burn 2 does **not** claim parallel-by-default.
- [ ] The "three human gates" line appears within one screen of the "you only show up when it
      actually needs you" sentence.
- [ ] Section B exists at `id="trust"`, with five needs and six guarantees, and prints the
      `skipped ≠ clean` / `PASS ≠ reviewer-clean` caveat verbatim in substance.
- [ ] Section B names `--auto-merge` as the single opt-in merge door, off by default, five
      conditions, unreadable ⇒ park.
- [ ] Section C walks 9 steps on one repo, each with what-you-type, what-appears, and what-it-solved,
      and ends with the on-disk artifact table.
- [ ] Every command shown in Section C exists in `loomwright/commands/` (check by name).
- [ ] No output block in Section C shows an invented value; field names only, where no real sample
      exists.
- [ ] "In progress" and "What's next" are separate sections; every item carries a state label from
      the printed vocabulary; the Loom Floor **NO-GO** is shown, not hidden.
- [ ] Every "What's next" row states an unblocking condition; no row states a date.
- [ ] In-page nav present, anchors resolve, `#guide` still resolves.
- [ ] Page opens correctly from `file://`, with no console errors, and no new external requests.
- [ ] Lighthouse accessibility ≥ the current score; no regression in `alt`/`aria` coverage.
- [ ] No fabricated logos, testimonials, benchmarks, user counts, or dates anywhere.

---

## 8. Out of scope

- Any change to the plugin itself. This is a site change.
- Dark mode, a blog, docs hosting, or a component/design system rebuild.
- Replacing the illustration style. The sunlit millwright loft is an approved brand commitment
  (`PRODUCT.md` §Brand Commitments) — new sections inherit it.
- Live data on the page (no fetching run stats, no GitHub API calls). The site stays static.
