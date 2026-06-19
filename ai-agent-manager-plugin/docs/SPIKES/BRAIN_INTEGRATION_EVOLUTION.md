# Brain Integration — Evolution Design Doc

> **Status:** design doc / proposal (authored 2026-06-16). Not yet a brief. The arc for fusing
> `personal-brain` (knowledge substrate) and `ai-agent-manager` (execution layer) into one
> closed-loop product. Owner controls all three repos (`personal-brain`, `sports-management`,
> `ai-agent-manager`), so boundaries can be redrawn, not just bridged.
>
> **Relationship to other docs:**
> - `SYSTEM_TWIN_ROADMAP.md` — the Twin is the plugin's *internal* answer to "a structured model
>   of this codebase." This doc argues `personal-brain` is the **more-mature substrate that the
>   Twin pillar was reaching toward** — adopt it, don't rebuild it.
> - `ENHANCEMENT_PLAN_v15_DRAFT.md` — knowledge axis (memory/flywheel). The write-back path here
>   is the cross-repo extension of that flywheel.

---

## ⚑ DIRECTION UPDATE — 2026-06-19 (local-first Twin) — READ BEFORE THE PHASES BELOW

A design review refined this plan. The **endgame is unchanged** (Twin = brain, one artifact; advisory → measure → promote; "point at repo → own this"), but **two route decisions below are now superseded**, plus one resequencing. **Where this block and the original sections conflict, this block wins**; the original prose is kept as historical reasoning, not current intent.

1. **Substrate is LOCAL-FIRST, not personal-brain-first.** §0's "adopt `personal-brain` *as* the substrate" is reframed: adopt the *Graphify-graph + wiki/community/freshness **pattern***, but the **substrate is built locally, per repo**. Each repo's Twin = its own `graphify-out/graph.json` (structure) **+ the plugin's own `.supervisor/` findings as the rationale layer** (LESSONS, the postmortem churn ledger, Twin contracts, done-brief `## Outcome` blocks). A single repo needs **no external brain**. `personal-brain` is **demoted to an optional cross-repo *federation* tier** (named global brains, cross-repo notes, draft write-back) — an extension layered on top, never a dependency. The plugin's own findings *are* the local wiki.

2. **Measurement is SELF-HOSTED and artifact-derived, not a hand-authored `sports-management` corpus.** The §"Phase 0" / §6-Q4 ten-item hand-authored corpus (stalled at 2/10, external repo) is superseded by **measuring on the plugin's own run history**: harvest the heal signal from the ~120 done-brief `## Outcome` blocks across all repos, backfill outcome labels from the live PRs via `/pr-postmortem`, and **join on PR URL → a confusion matrix** (catch-rate / false-positive per signal). No external repo, no hand-authoring. This same artifact is the **M3 trust-threshold instrument** (see `SYSTEM_TWIN_ROADMAP.md` §7).

3. **`/setup brain` (Phase 2 below) is resequenced to LAST** — gated behind the local loop being *measured* and the advisory→gating flip. It is the federation tier, built on proof; not the early/next step. (The original `/autonomous` "Phase 5 = `/setup brain`" ask is correspondingly deferred.)

**Sequenced path now:** ① measure (own-run confusion matrix) → ② standing instrument + human-verify labels → ③ produce a local graph where the findings live → ④ bridge findings → graph communities, re-measure (the real "graph-first beats baseline" gate) → ⑤ feed graph-linked context into Launch Pad / Phase 4.5 (APPLY), re-measure → ⑥ flip advisory → gating (Twin M3) → ⑦ federate via `/setup brain`.

> **The full *gated* execution path** — per-step action/output + the gate at each rung, the label-quality ladder, the step↔milestone mapping, and the Step-1 spec — is **`LOCAL_TWIN_PATH.md`** (the ordered "how"). This block is the *why*; that doc is the *order*.

**Status fact:** Learning Loop **Phase 4 (churn ledger) SHIPPED in v14.36.0 (PR #69)** — the "Phase 4 not started" rows in `LEARNING_LOOP_ROADMAP.md` are stale (corrected there).

---

## 0. The strategic reframe (read this first)

The plugin already declares this north star (`SYSTEM_TWIN_ROADMAP.md`):

> *Keystone — the System Twin: a living, structured, agent-maintained, continuously-verified model
> of this specific codebase (architecture graph, contracts, data flows, decision history) … that
> planning reads, verification checks against, and the flywheel writes to. Endgame: point at repo → "own this."*

**`personal-brain` is that artifact, already built and in daily use** — just externally, by hand, for four repos:

| System Twin pillar (planned) | personal-brain (shipping) |
|---|---|
| architecture graph | Graphify `graph.json` (sports-management graph is ~8k nodes / ~17k edges — counts illustrative, read live from the graph, never hard-coded) |
| contracts / decision history | `wiki/` atomic notes with `source`/`confidence`/`last_verified` provenance |
| "planning reads it" | the 3-step query rule (graph → wiki → raw) |
| "the flywheel writes to it" | `/wiki-ingest` + `harvest-chats.mjs` (raw transcripts today) |
| "point at repo → own this" | symlink + 3-step rule = a repo "owned" by the brain |

**Conclusion:** do not build the Twin's graph/knowledge layer a second time. **Adopt Graphify + the
brain's wiki as the Twin's substrate.** The plugin keeps what it does best — *execution-era*
semantics (contracts, conformance, benchmark deltas, run telemetry) — layered *on top of* the
brain's structural graph. One graph engine (Graphify), two semantic layers (code structure + Twin
execution facts), one wiki for rationale.

This is the difference between "two products that talk" and "one product whose memory happens to
live in a separate repo."

---

## 1. The closed loop (the product)

```
  brain (graph + wiki)
        │  READ  (Phase 1)
        ▼
  plan / execute / review / QA / self-heal   ← ai-agent-manager
        │  structured run results
        ▼
  draft brain notes  (Phase 3 write-back)
        │  PR review (brain governs promotion)
        ▼
  trusted knowledge ──► better next run  (loop closes)
```

Today the loop is **open at both ends**: agents don't read the brain (they grep), and the brain
doesn't see the plugin's structured run output (it scrapes raw chat transcripts). Closing it is the
entire product thesis: *an engineer who's been on the team for years and gets better every week.*

---

## 2. Non-negotiable invariants (these constrain every phase)

These are derived from the plugin's existing contracts and the brain's trust model. Violating any
one is a regression, not a feature.

1. **Brain integration is ADVISORY and fails SAFE.** Brain *read* enriches context; brain *write*
   is a side-effect. Neither may ever block a run or change a `heal_decision`. A missing, broken, or
   stale graph ⇒ silently fall back to grep/read and continue. This matches the plugin's bimodal
   rule (correctness gates fail closed; side-effect emitters fail safe — brain is the latter).
2. **The graph is authoritative for *pre-existing* structure, NEVER for code the current session is
   editing.** Graphify reflects the last commit; the plugin edits in uncommitted worktrees. Any file
   the session will touch is read raw. (See §3, the staleness rule — this is the #1 correctness
   trap.)
3. **The brain governs promotion.** The plugin only ever writes *drafts* into `wiki/_drafts/`.
   Trusted-note promotion stays a human PR review in the brain repo. No plugin path writes a trusted
   note.
4. **Match the brain's actual draft convention — verified, not assumed.** Draft notes use the
   brain's real frontmatter (`id, tags, source, owner, last_verified, confidence`) **plus
   `draft: true`** and land in `wiki/_drafts/`. (Verified: `personal-brain/.claude/skills/wiki-ingest/SKILL.md:37`
   writes `confidence: low` + `draft: true` into `wiki/_drafts/`. An earlier draft of this doc wrongly
   claimed the brain had no `draft:` field — corrected.) `wiki/_drafts/` is excluded from the trusted
   catalog (`index.md`); the plugin never adds drafts to the index — promotion is a brain-side PR.
5. **Counts/docs stay current.** Every phase that adds a skill or `/setup` module bumps the
   doc-currency counts; update claims in the same change or CI (`check-doc-currency.sh`) fails.

---

## 3. The staleness rule (the correctness keystone)

A graph-first agent that trusts a stale graph is *worse* than a grep-first one. The rule, to be
encoded verbatim in the `brain-context` skill:

- **Use the graph for:** "what connects to what", "where does concept X live", "blast radius of
  changing Y", "what calls Z" — over the **committed** codebase.
- **Do NOT use the graph for:** the current state of any file this session has edited or will edit.
  Those are read raw, every time. Worktree edits are invisible to the graph.
- **Fallback triggers (read raw / grep):** (a) no `graphify-out/graph.json` present; (b) graph query
  returns empty or low-confidence; (c) you are about to edit the file.
- **"Low-confidence" defined for Graphify output** (so (b) is testable, not vibes): treat a graph
  answer as low-confidence — and fall back to raw read — when ANY of: the query returns **no nodes**;
  the traversal is **too broad** (a generic term like `match`/`court`/`score` that collides across
  repos — scope by `--graph <repo>` first, per the brain's `hot.md` warning); the matched nodes carry
  **no cited `source_location`/`source_file`** (Graphify stamps `source_*` on nodes — their absence
  means a node hit isn't anchored to real code); or the governing `confidence`/`confidence_score` is
  weak (Graphify stamps `confidence: EXTRACTED` + a numeric `confidence_score`). **Read confidence from
  whichever element the answer rests on, per the graph's actual schema** — for relationship/path
  answers it typically sits on the **relationship/path edges** rather than the nodes (node hits are
  judged by their `source_*` anchoring). Inspect `graph.json` to confirm where `confidence` lives
  before trusting a numeric threshold; the brief pins the exact threshold against real query output.
- **Staleness signal (use the graph's own metadata, NOT `git log` on the file).** The graph file is
  gitignored + symlinked in a configured-brain layout, so `git log graphify-out/graph.json` tracks
  nothing in the app repo. Instead read the graph's embedded `built_at_commit` field (verified
  present: `graph.json` ends with `"built_at_commit": "<sha>"`) and compare it to the repo's current
  HEAD / commits touching the queried path: if HEAD has advanced past `built_at_commit` for that path,
  downgrade graph answers to "hint" and verify against source. The comparison **branches by wiring
  mode** (§Phase 2): local graph file, symlink target, configured `BRAIN_ROOT`, or MCP — resolve the
  graph location accordingly, never assume it's a tracked path in the app repo. (Advisory — never an
  error.)

---

## 4. Phased plan

Sequencing differs from the draft in one way: **a baseline eval runs BEFORE Phase 1**, so "graph-first
helps" is provable, not asserted. ("Measure before expanding" can't sit at the end.)

### Phase 0 — Baseline eval harness (do first)

Build the eval corpus and capture current (grep-first) numbers against the sports-management graph:

- **5 structural questions** (e.g. "what calls `reservationCreate`?", "blast radius of changing
  `lib/session.ts`?") — score correctness + count Grep/Read calls to answer.
- **3 implementation tasks** + **2 review/QA tasks** — score correctness, missed-context incidents,
  tool-call count.
- Measurement is **self-contained** — `/insights` does NOT capture time/tokens (that's `ccusage`),
  so the harness records its own tool-call counts and a manual correctness rubric.
- Output: `.supervisor/eval/brain-baseline.jsonl` — a **separate** file from the existing
  `.supervisor/eval/results.jsonl` (written by `run-eval.sh`, consumed by `/insights`' eval
  fitness-function section). Define its own schema (one record per corpus item: `id`, `mode`
  baseline|graph-first, `correct`, `tool_calls`, `missed_context`). `/insights` **ignores** the
  baseline file in v1 (don't pollute the fitness-function trend) — wire it in only if we later want a
  brain-lift panel.

**Corpus location & scoring (the brief must pin these down):**
- **Corpus specs** live in-repo as version-controlled fixtures:
  `ai-agent-manager-plugin/scripts/brain-baseline-corpus/*.md` (a sibling of `eval-corpus/`; one file
  per item — the question/task, the expected answer or rubric, and the target repo/graph). Checked in
  so runs are reproducible and the corpus is reviewable. (Deliberately **not** under `.supervisor/`,
  which is gitignored. The harness's *output* history — `.supervisor/eval/brain-baseline.jsonl` — is a
  runtime artifact and correctly stays gitignored; only the input fixtures are tracked.)
- **Manual correctness** is recorded per-item by the human running the spike: a `correct` boolean +
  a one-line `note` written into the `brain-baseline.jsonl` record alongside the auto-captured
  `tool_calls`/`missed_context`. (No auto-grader in v1 — the corpus is small by design; a grader is a
  later step only if the corpus grows.)

**Exit criteria for the whole initiative:** graph-first must beat baseline on correctness AND reduce
grep/read calls on structural questions, with no regression on edit tasks. If it doesn't, stop here.

### Phase 1 — Read path (`brain-context` skill)

New skill: `ai-agent-manager-plugin/skills/brain-context/SKILL.md`. **Read-on-demand, NOT preloaded**
into agent frontmatter (mirror `self-heal-advisory` — preloading into 6+ agents is spawn-time token
bloat). Agents read it at context-setup when a brain is detected.

The skill defines:
- **Detection:** `graphify-out/graph.json` present in cwd? `AI_AGENT_MANAGER_BRAIN_ROOT` set and
  valid? (Either, both, or neither — degrade gracefully.)
- **Query order:** the 3-step rule (graph → wiki → raw), with the §3 staleness rule inline.
- **Wiki access:** when `BRAIN_ROOT` is set, search `wiki/` for rationale (`source`, `confidence`,
  `last_verified`); when the brain's own wiki concept-graph exists (`graphify-out/graph.json` at the
  brain root) query it for symbol→rationale hops.
- **Freshness as a signal:** a wiki note with stale `last_verified` or a broken `source:` anchor is
  treated as **low-confidence** context — surfaced as a caution, not a fact.
- **Fail-safe:** any detection/query failure ⇒ fall back to existing grep/read flow, exit clean.

Wire it into (prompt edits, on-demand read — no frontmatter preload):
- `context-setup` (the shared entry point — biggest leverage)
- Launch Pad Phase 2 (codebase analysis — grep-heavy today)
- Code Reviewer (blast-radius / consistency-audit context)
- Supervisor Phase 1.5/2 and the Phase 4.5 self-heal review context

**Do not depend on the grep-before-graph hook** — it lives in the brain owner's *global*
`~/.claude/settings.json`, not in either repo and not shippable. The behavior lives in the skill
prompt; `/setup brain` may *optionally* install the hook for users who want the nudge.

### Phase 2 — `/setup brain` module

Productize the bespoke sports-management wiring. Implement the `/setup` module contract (five phases:
check / report / offer / apply / verify; idempotent; registry row + `commands/setup.md` flow section
in the same change).

**UX-contract conflict (must resolve — flagged in review).** The no-arg dashboard's `AskUserQuestion`
is at its 4-option cap, and option 3 ("Other integrations") currently folds **guidance-only** modules
(`beads`, `mysql-mcp`) that mutate **no** state. `brain` is a *state-mutating* module (writes
settings, optionally a symlink/MCP registration) — so it does **not** belong in the guidance-only
bucket. Resolution for v1: **`brain` is a direct-only module** — invoked explicitly via `/setup brain`
(which runs the full check/offer/apply/verify flow), while the no-arg dashboard only *mentions* it
("run `/setup brain` to wire a knowledge brain") without offering an apply action inline. This mirrors
how `/setup telemetry` delegates rather than mutating from the dashboard. (Alternative if we want it
in the dashboard: redesign the no-arg UX beyond 4 options — out of scope for v1.)

Module capabilities:
- **check:** is `graphify` installed? is there a `graphify-out/graph.json`? is `BRAIN_ROOT` set and
  does it contain `wiki/`, `wiki/hot.md`, `graphify/<repo>/graph.json`?
- **offer / apply (wiring options, robust → simple):**
  1. **Config-pointed path** (recommended, portable): write `AI_AGENT_MANAGER_BRAIN_ROOT` +
     per-repo area to settings; no symlink. Survives marketplace install and arbitrary layouts.
  2. **MCP** (for shared/remote brains): `graphify <brain>/graphify/<repo> --mcp` stdio server,
     registered as an MCP source. No filesystem coupling. **Note: registering an MCP source is itself
     a state-mutating write** (to `~/.claude/settings.json` or `.mcp.json`) — so it is governed by the
     `/setup` module contract (backup-first, idempotent jq deep-merge, never duplicate an existing
     server entry). The brief must name the concrete target file and the merge owner; this is *not* a
     guidance-only step.
  3. **Symlink** (simplest local default): `graphify-out -> <brain>/graphify/<repo>` — the
     sports-management pattern, but offered knowingly as the fragile/local option.
- **verify:** run one canned graph query end-to-end; print graph-first status in the `/setup`
  dashboard.

This is the concrete realization of "point at repo → own this" — one command wires any repo to a
brain.

### Phase 3 — Write path (close the loop)

Two halves, both fail-safe, both draft-only.

**3a. `/dreaming --target brain`** — accepted lessons emit **draft** notes into
`<BRAIN_ROOT>/wiki/_drafts/` in the brain's real schema (matching
`personal-brain/.claude/skills/wiki-ingest/SKILL.md` exactly, incl. `draft: true`):
```yaml
---
id: <kebab-slug>
tags: [<reuse existing brain vocabulary>]
source: <PR URL from SUPERVISOR_RESULT.pr_url, or commit sha>
owner: <git user>
last_verified: <today>
confidence: low
draft: true
---
```
Like `/wiki-ingest`, the note flags what still needs verifying against live code and is NOT added to
the trusted catalog (`index.md`).
Cross-repo write boundary (the trap the draft missed): `/dreaming`'s sole-writers
(`write-lessons.sh`) enforce a worktree guard at the *current* repo root and cannot write into a
different repo. So the brain write is a **separate, explicitly-bounded writer** that:
- writes ONLY under `<BRAIN_ROOT>/wiki/_drafts/` (path-guarded, `test -d` first);
- is **same-machine only** in v1 (the brain may live on another machine — cross-machine handoff is
  deferred; see Open Questions);
- is fail-safe (any error ⇒ logged no-op, never fails the `/dreaming` run);
- never touches trusted `wiki/` — promotion stays a brain-side PR.

**3b. `personal-brain/bin/harvest-plugin-runs.mjs`** — a brain-side ingester (lives in the brain
repo, Node/ESM, no deps, like the existing `harvest-chats.mjs`). Reads the plugin's **structured**
artifacts directly instead of scraping raw transcripts:
- `.supervisor/logs/*.jsonl` (`session_end` events), `.supervisor/jobs/done/*.md`,
  `.worker-summary.md`, and the result blocks (`SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`,
  `QA_RESULT`, self-heal outcome, Twin conformance/benchmark deltas).
- Stages into a new `runs/<repo>/` folder for `/wiki-ingest` to distill.
- **Caveat (verified, corrected from an earlier overstatement):** `.supervisor/` is gitignored in the
  *plugin* repo. In sports-management it's only **partially committed** — ~8 historical files
  (`state.md`, old `jobs/*.md`, `user-journeys.md`) are tracked, but `logs/` and current run artifacts
  are **untracked/local-only**. So: same-machine harvest works from the filesystem regardless;
  **cross-machine harvest sees only whatever is explicitly tracked** (which today excludes the run
  logs the harvester most wants). Decide per-repo whether to track run artifacts or require
  same-machine harvest.

### Phase 4 — Twin ↔ Graphify unification (the deeper evolution)

Do **not** collapse into one graph. Keep the layers, link them:
- **Graphify** owns code structure + community detection.
- **System Twin** owns execution-era facts: contracts, observed conformance, benchmark drift.
- **The wiki** links them: each note's `Code: [[_COMMUNITY_*]]` line ties rationale to a code
  community; Twin contracts annotate the community nodes they constrain.

New projection: `/obsidian --target brain` (or `/brain sync`) projects Twin contracts as draft notes
/ community cross-links into the brain instead of a throwaway vault — turning the existing one-way
projection into a contribution.

### Phase 5 — Freshness feedback (make `/freshness` actionable)

Let the plugin *consume* the brain's freshness signal:
- stale wiki notes ⇒ low-confidence context in `brain-context` (already in Phase 1);
- broken `source:` anchors ⇒ caution flag in Launch Pad feasibility;
- Code Reviewer flags "decision note stale against changed code" when a touched file's community has
  a note whose `last_verified` predates the change.

---

## 5. Re-measure & gates

After Phase 1, re-run the Phase 0 corpus. Ship Phase 2+ only if the exit criteria (§Phase 0) hold.
Each phase is independently shippable and independently revertible (all advisory/fail-safe).

---

## 6. Open questions (decide before the Phase 1 brief)

1. **Cross-machine brain.** The brain may live on a different machine than the consumer repo.
   v1 assumes same-machine (`BRAIN_ROOT` is a local path). Is a remote/shared brain (Graphify MCP
   over the network, or a git-synced brain checkout) in scope for the shippable product, or deferred?
2. **Wiring default.** Config-pointed path (portable) vs symlink (simple) vs MCP (shared) — which is
   the documented default for `/setup brain`? (Recommendation: config-pointed path.)
3. ~~Draft schema.~~ **Resolved** (verified against `wiki-ingest/SKILL.md`): brain drafts use
   `wiki/_drafts/` + `confidence: low` + `draft: true`; the plugin writer matches exactly, no
   brain-side change needed.
4. ~~**Who owns the eval corpus** — does it live in the plugin repo (`.supervisor/eval/`) or the brain?~~
   **Resolved (Phase 0 landing):** corpus *input fixtures* are version-controlled in the plugin repo at
   `ai-agent-manager-plugin/scripts/brain-baseline-corpus/` (a sibling of `eval-corpus/`); only the
   harness's *output history* `.supervisor/eval/brain-baseline.jsonl` stays gitignored. **Status:** the
   harness is landed, but the corpus is **seeded with 2 of the planned 10 items** (5 structural + 3
   implementation + 2 review/QA) — so the §Phase 0 "graph-first beats baseline" exit criterion is NOT
   yet evaluable; the baseline numbers are not decision-grade until the corpus is populated (follow-up).

---

## 7. First brief

Phase 0 + Phase 1 as a single Launch Pad brief: "Make plugin agents brain-aware (read path) behind a
detected `brain-context` skill, with a baseline+after eval proving it helps, fail-safe throughout."
Everything downstream depends on the read path landing and measuring well.
