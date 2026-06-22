# Local Twin — Execution Path (the ordered "how")

> **Status:** execution plan (authored 2026-06-19). This is the **single source of truth for the *ordered, gated* path** toward the Twin/brain endgame. It does not restate *why* or *what* — it sequences the *how*.
>
> **Relationship to the other SPIKES docs (no duplication):**
> - **Why / design** — `BRAIN_INTEGRATION_EVOLUTION.md` (esp. its §"⚑ DIRECTION UPDATE — 2026-06-19 (local-first Twin)", which this doc operationalizes).
> - **Milestones / north star** — `SYSTEM_TWIN_ROADMAP.md` (M0–M5 ladder + advance-gates). The step↔milestone mapping is below.
> - **Knowledge-layer phases** — `LEARNING_LOOP_ROADMAP.md` (Phases 0–6; Phase 5/6 are reframed local-first here).
>
> Where any of those conflict with this doc on *sequence*, **this doc wins** for execution order.

---

## 0. The direction in one line

> Build a **self-contained, measured "local Twin"** — **graphify** for structure + the plugin's **own accumulated `.supervisor/` findings** for rationale — **bridged and proven on the plugin's own PR history**; with **`personal-brain` as an optional cross-repo federation tier**, not the substrate.

The Twin of a repo = *that repo's* graph + *that repo's* findings (lives locally, per repo). `personal-brain` is the shared toolchain (Graphify + wiki/community/freshness pattern) and the cross-repo federation home — **not** the Twin itself.

---

## 1. The gated ladder

Each rung climbs **only when the prior rung's numbers earn it.** Every rung is independently useful and independently revertible.

```
✅0 DOCS → ①MEASURE ─gate─▶ ②INSTRUMENT ▶ ③GRAPH ▶ ④BRIDGE ─gate─▶ ⑤APPLY ─gate─▶ [5.5 label upgrade] ▶ ⑥FLIP=M3 ▶ ⑦FEDERATE → M4 ▶ M5
           └──────────── cheap, own-run history ────────────┘            └─ pull M2b in only here ─┘
```

### ✅ Step 0 — Reconcile the docs — **DONE 2026-06-19**
The three SPIKES docs were made non-contradictory (local-first direction stated once in `BRAIN_INTEGRATION_EVOLUTION.md`; phase-status fixes + pointer banners elsewhere). CI gates green.

### Step 1 — MEASURE (own-run confusion matrix) — ✅ DONE (2026-06-19)
- **Do:** a **read-only** script — harvest the heal signal from done-brief `## Outcome` blocks across all repos → backfill outcome labels via `/pr-postmortem` on the live PRs → **join on PR URL → a confusion matrix** for the heal signal (catch-rate, false-positive, with the false-negative candidates surfaced).
- **Out:** one report (gitignored scratch) + a *directional* catch-rate. Label source = churn (cheapest rung of the label ladder).
- **GATE:** is heal-`PASS` correlated with reality at all?
  - **Noise → STOP.** The problem is upstream (Launch Pad / worker); you saved the downstream spend. (The honest off-ramp the design demands.)
  - **Signal-with-gaps (expected) → continue**, now knowing *which* miss-classes slip + a baseline to beat.
- **Spec:** see §4.
- **✅ Result (2026-06-19, directional — `ai-agent-manager`, N=8 joined):** GATE = **CONTINUE (signal-with-gaps)**. **Recall 0%** (heal escalated on 0/8), **FN 6/8** (PASS PRs that then absorbed 1–6 self-heal-class rework rounds), FP 0%; PASS is non-discriminative (spans 2→7 review rounds, 0→6 misses). **54% of joined churn attributes to the self_heal stage** — the catchable churn is in heal's own lane, exactly where Steps ④–⑤ aim. **Baseline to beat: recall 0% / FN 6/8 / self_heal-stage share 54%.** **Step 2a DONE (2026-06-19): all 6 FN candidates human-verified as real misses** → the 0% recall is a **trusted** baseline, not a labeling artifact (2 were outright behavioral bugs — an inert safety gate (#67) + a masked error (#62); 4 were doc/consistency misses the review should have flagged). Remaining caveats: coverage 10% (84 heal-signal PRs, 8 labeled+joined); single repo. Full report + FN worksheet: `.supervisor/scratch/local-twin-step1/` (gitignored).

### Step 2 — INSTRUMENT + verify labels
- **Do:** make harvest→join→matrix **repeatable across repos**; wire it into `/insights` (the MEASURE leg); **close the churn-counter blind spots** (CI-check-channel churn invisible to `review_rounds`; repo-shape commit-regex gaps); **human-verify the false-negative set** into a trusted holdout.
- **Out:** a standing, reusable fitness instrument + a verified baseline. Closes the Twin roadmap's "benchmark is *real*, not a canary" open decision.
- **✅ Step 2a DONE (2026-06-19):** all 6 FN candidates human-verified as real misses → the recall-0% baseline is **trusted**, not a labeling artifact (worksheet: `.supervisor/scratch/local-twin-step1/fn-verification-worksheet.md`).
- **✅ Step 2b DONE (2026-06-19, v14.40.0):** the throwaway Step-1 script is graduated into a permanent, re-runnable tool — **`scripts/measure-heal-signal.{sh,py}` + `scripts/test-measure-heal-signal.sh`** (13 self-test cases). Same confusion-matrix + JSONL output shape as Step 1, with the repo list **parameterized** (default: current repo; overridable via `--repo` / `$AI_AGENT_MANAGER_HEAL_SIGNAL_REPOS` / `.supervisor/config.json`). READ-ONLY toward measured repos; writes only under `--out` (default `.supervisor/heal-signal/`). **Label blind-spots addressed:** floor-RAISING dedup takes the per-field MAX across re-gathers (so #47-style 0→6 corrections win) + label-quality diagnostics (model-guessed / explicit-zero-signal / floor-raised) make the floor visible; fully closing the gather regex gaps stays `pr-postmortem-gather.sh`'s domain. **`/insights` MEASURE leg wired:** a `## Heal-signal catch-rate (MEASURE)` section trends recall/coverage/self-heal-share, suppressed when no scored data. **Coverage backfill is a bounded human DECISION** — `--backfill N` prints a plan + cost and STOPS (never auto-dispatches `/pr-postmortem`); the ~3-hour bulk backfill is deliberately NOT run. Re-running on `ai-agent-manager` reproduces the trusted baseline (recall 0% / FN 6/8 / self_heal-stage share 54%).
- **✅ Coverage backfill (2026-06-19, human-approved bounded 10):** a `--backfill 10` round of model-classified `/pr-postmortem` over the most-recent unlabeled heal-signal PRs (#37 #45 #54 #55 #59 #63 #64 #65 #66 #71) lifted self-repo coverage **24% → 55%** (joined N 8 → 18). The wider sample **SHARPENED, not softened, the baseline**: recall still **0%**, **FN 15/18**, self_heal-stage churn share **53%** (was 54% at N=8) — 9 of the 10 new PRs were FN (heal PASS yet 1–3 self-heal-class misses each; only #66 was clean). So the rubber-stamp is not a small-N artifact. (Artifacts are gitignored runtime state under `.supervisor/heal-signal/`; this line is the durable record.)
- **Still open (Step-2 tail, a human decision):** the remaining ~15 unlabeled self-repo PRs, and running the instrument across the OTHER repos (pass their paths via `--repo` / the env / config) to get per-repo + pooled cross-repo recall.

### Step 3 — GRAPH (produce a local graph where the findings live)
- **Do:** run graphify in the work repos → `graphify-out/graph.json` (graph-only / local tier — real file or symlink; **no external brain required**).
- **Out:** the first time graph (structure) + findings (rationale) coexist in one repo. Cheap, reversible.
- **Note:** this is the missing *graph-production* step — the read path already consumes a graph if present (`brain-context` skill), but nothing in the plugin produces one today.
- **✅ Result (2026-06-22, `ai-agent-manager`):** graph **PRODUCED** via `/graphify .` (graphify CLI v0.8.37) over 224 corpus files (83 code → AST, 141 docs → 7 parallel semantic subagents; no `GEMINI_API_KEY`, so the host session was the extractor). **`graphify-out/graph.json` (856 KB): 994 nodes · 1228 edges · 118 communities · 21 hyperedges.** Structure (the plugin's agents/commands/skills/scripts) now coexists in-repo with the findings the bridge will link. **VERIFIED:** `test -e graphify-out/graph.json` → `GRAPH_PRESENT`, so brain-context Signal-1 now fires; the graph's trailing `built_at_commit` = `f5e10d6` = HEAD (fresh, not stale). **Gitignored:** `graphify-out/` added to `.gitignore` — only that line + this note are committed; `graphify-out/` is invisible to `git status`.
  - **Actual schema the Step-4 bridge will rely on** (inspected, not assumed) — graph.json is **NetworkX node-link** JSON, top-level key order `directed, multigraph, graph, nodes, links, hyperedges, built_at_commit`:
    - ⚠️ **edges live under `links`, NOT `edges`** (node-link convention) — the bridge must read `graph["links"]`.
    - **Nodes** carry: `id`, `label`, `norm_label`, `file_type` (`code|document|paper|image|rationale|concept`), **`source_file` (994/994)**, **`source_location`** (e.g. `"L66"`; 494/994 — AST code/rationale nodes always have it, many pure-semantic nodes are `null`), **`community`** (a plain **integer** cluster id, present on **994/994**, range **0–117**), `metadata`, and `_origin` (`"ast"` for the 395 AST nodes; absent on the 599 semantic nodes). Community ids are **numeric**, left un-named in graph.json (LLM/manual community *labels* live only in `GRAPH_REPORT.md`/HTML — cosmetic; the bridge keys on the integer id).
    - **Links (edges)** carry: `source`, `target`, `relation`, **`confidence`** (`EXTRACTED` 1149 / `INFERRED` 78 / `AMBIGUOUS` 1) **and `confidence_score`** (numeric; present on **1228/1228**), plus `source_file`, `source_location`, `weight`, `context`. Per brain-context's staleness rule, relationship/path confidence is read here on the **link**, not the node.
    - **Freshness:** the file ends with `"built_at_commit": "<sha>"` (here `f5e10d6…`) — the durable staleness anchor (compare to HEAD; never `git log` the gitignored file).
  - **Scope:** `ai-agent-manager` only (BetterBlocks deferred). This is PRODUCE + VERIFY + RECORD — **not** the Step-4 bridge.

### Step 4 — BRIDGE (findings → graph communities) + re-measure
- **Do:** adapt `personal-brain`'s community-stub mechanism — link the plugin's findings (LESSONS, postmortem ledger, Twin contracts, done-brief Outcomes) to **graph communities** (stable, human-named clusters — survive symbol churn). Add freshness (`built_at_commit` / `last_verified`) + a concept-graph over the findings. Re-run the Step-2 instrument.
- **GATE:** *the real "graph-first beats baseline" eval gate* — answered on **own runs**, not a hand-authored external corpus. Does graph-linked context **measurably cut the FN miss-classes** vs the Step-1 baseline?
  - **No lift → stop the graph investment**, keep findings flat. (Bridge is the keystone but it must pay for itself.)
- **✅ Result (2026-06-23, `ai-agent-manager`):** GATE = **PROCEED**. The bridge was **BUILT** as a re-runnable scratch spike (`.supervisor/scratch/local-twin-step4/build_bridge.py` → `bridge.{json,md}` + `gate.{json,md}`; gitignored) and the retrospective gate was answered on own-run history — no Step-5 wiring, no new PRs.
  - **The bridge (join confirmed):** `finding.changed_paths → graph node.source_file → node.community` (integer). Adapted `personal-brain`'s community-stub mechanism (`bin/build-community-notes.mjs`): integer communities → readable labels from top member `source_files`; findings attach many-to-many (a finding spans 10–26 communities). **31 findings** (postmortem ledger; `changed_paths` from the record, else git-backfilled from the squash-merge `(#N)` commit), **22 of them real misses** (`self_heal_misses>0`). Of **118 communities, 70 carry a finding and 64 carry a prior MISS**; 2 of 8 LESSONS file-anchor (the rest are category-scoped, not file-linkable); Twin contracts = 0. Per-community index answers "what do we already know about this area?" (top files, attached findings, miss-class histogram).
  - **Retrospective hit-rate** = fraction of the **17 confirmed FN PRs** whose community(ies) already held an EARLIER finding (a prior PR `#<N` with a recorded `self_heal_miss`) the bridge would have surfaced. Chronology anchor = **PR number** (single repo, monotonic; postmortem `ts` is a backfill-burst gather-time and unreliable, but the churn events themselves happened in PR-number order). **Stratified to defeat god-node ubiquity** (`agents/supervisor.md` + command-prose clusters are touched by nearly every plugin PR, so a naive match is trivially always-true): **naive 16/17 = 94%** → **exclude doc-surface version-bump files 94%** (so the hit is **NOT** a CLAUDE.md/plugin.json metadata artifact) → **exclude the 11 ubiquitous god-node communities 15/17 = 88%** → **strict (also drop mega super-clusters >40 nodes) 12/17 = 71%**. Every surviving strict hit rides on a **specific, actionable area**, verified by sample shared files: review-heal (`skills/review-heal/SKILL.md`, c6) for #45/#54/#62/#63/#65/#68/#75; autonomous-loop (`skills/autonomous-loop/SKILL.md`, c7) for #70/#71; automate-loop (`skills/automate-loop/SKILL.md`, c9) for #74; brain-context (c7) for #60; the postmortem **dispatch scripts** (`dispatch-pr-postmortem.sh` c85 + its test c45) for #67.
  - **Verdict:** **PROCEED to Step 5** — the conservative floor (71% specific-area) is well above the ≥50% bar AND the matches are genuine area-knowledge, not ubiquity noise → "the knowledge was present + linkable", so the bridge has **real retroactive value**. The 5 strict-misses are honest: #37/#43 are at/near the chronology floor (no prior to share), #55/#59/#64 had only god-node/mega-cluster overlaps (knowledge too broad to be specifically actionable). **Caveats:** single repo; model-generated (`agent_generated_guess`) labels; graph is 1 doc-only commit stale vs HEAD (`built_at` f5e10d6) and **20 findings reference ≥1 file newer/renamed than the graph** (real but minor coverage gap — the specific anchor files that drive the hits are all present). The optional finding-concept-graph is **deferred** (not needed to clear the gate).
  - **Scope:** PRODUCE-bridge + RETROSPECTIVE-gate only. The builder stays a **scratch spike** — it graduates to `scripts/` (and the brain-context read-path / Phase 4.5 wiring) only in **Step 5 APPLY**, mirroring how Step 2b graduated only after Step 1's gate.

### Step 5 — APPLY (feed graph-linked context into the loop) + re-measure
- **Do:** wire graph-linked findings into **Launch Pad risk** + **Phase 4.5 self-heal review** (the `brain-context` hook already exists). Re-measure.
- **GATE:** is the FN rate trending **down run-over-run**? The loop compounds only if catch-rate rises.

### Step 5.5 — LABEL UPGRADE (Twin M2b slice 1b / part-2b) — *only if heading to gating*
- **Do:** upgrade the outcome label from churn → **real behavior**: auto-dispatch QA Executor Playwright for web-app repos (**M2b slice 1b**) and/or headless-`claude` generative eval in CI (**M2b part-2b**, OAuth-token default + per-run budget + circuit-breaker).
- **Why here:** moves the threshold from **directional → gating-grade**. Pull in **only** when Step-5 numbers justify the spend — never before Step 1.

### Step 6 — FLIP advisory → gating  ( = Twin **M3** )
- **Do:** write the **threshold sentence** (e.g. *recall ≥ X% AND false-positive ≤ Y%, sustained over ≥ N PRs across ≥ 2 repos, FN set human-verified*) from the gating-grade matrix; flip heal / conformance from advisory to **gating** (block a bad PR). **Human decision** — earned on the benchmark, not granted by calendar.

### Step 7 — FEDERATE  ( = `/setup brain`; the original Learning-Loop Phase 5/6, now **last** )
- **Do:** build `/setup brain` — **named global brains** (personal / work), **3-tier source resolution** (project-local graph → project `.supervisor/config.json` `.brain_root` → global `~/.claude` `AI_AGENT_MANAGER_BRAIN_ROOT`), cross-repo knowledge sharing + **draft write-back** to `personal-brain` (`wiki/_drafts/`, never trusted-promote). The **federation tier**, built on proof — an extension, never the substrate.

### Beyond — Twin **M4** → **M5**
- **M4 proactive driver:** unprompted PRs behind the **4 guardrails** (durable cadence < 7-day expiry, per-run budget, circuit-breaker, heartbeat). Requires M3 trustworthy.
- **M5 director model:** human sets intent + approves **outcomes**, stops reviewing diffs. Emerges from M1–M4.

---

## 2. The label-quality ladder (how you climb from directional → gating-grade)

The confusion matrix is only as trustworthy as its **outcome label**. Climb this ladder as you climb from Step 1 (directional) to Step 6 (gating):

```
churn (review rounds)             ← Step 1 uses this. Cheap. DIRECTIONAL only.            [have it now]
   ↓
executable-acceptance run         ← run-ground-truth.sh (Twin M2b slice 1a, SHIPPED) runs a brief's cmd:/corpus-task: checks
   ↓
full app execution (Playwright)   ← Twin M2b slice 1b — strongest "does it actually work"
   ↓
continuous generative eval in CI  ← Twin M2b part-2b — automates the whole thing
```

Step 1 with churn labels is enough to **decide whether to invest further**. Gating-grade evidence (Step 6) wants the upper rungs — that is exactly what M2b slice 1b / part-2b deliver, pulled in at Step 5.5.

---

## 3. Step ↔ Twin-milestone mapping

| This path | Twin milestone | Notes |
|---|---|---|
| Steps ①–② | (the MEASURE instrument M3 always needed) | Closes the "benchmark is real" open decision |
| Steps ③–⑤ | the Twin's "structured model" substrate (structure + bridge + APPLY) | The local Twin made concrete |
| Step 5.5 | **M2b slice 1b / part-2b** | Label-quality + automation upgrades; pulled in just before gating |
| Step ⑥ | **M3** (advisory → enforcing) | Same milestone; this path is the route to it |
| Step ⑦ | (Learning-Loop Phase 5/6) `/setup brain` | Federation tier, resequenced to last |
| beyond | **M4 → M5** | Unchanged; gated on a trustworthy M3 |

Nothing in the Twin ladder is discarded — this path **reorders the cheap-evidence-first half** (use own run history before standing up CI app-execution) and slots M2b's expensive machinery in **where it pays for itself**: the M3 gating decision.

---

## 4. Step-1 spec (the immediate build)

**Read-only. No source changes, no PR. Writes only a report under a gitignored scratch path.**

```
HARVEST  parse `## Outcome` blocks across all repos
         → rows: {repo, pr_url, heal_decision, heal_iterations, heal_remaining}
         (signal side — ~120 rows exist today in done briefs; the durable channel,
          since session_end JSONL is lossy)

BACKFILL run /pr-postmortem (gather) over those pr_urls
         → rows: {pr_url, review_rounds, self_heal_misses, per-round class/flow_stage}
         (outcome/label side — reconstructable from the live PRs; ~19 already stored)

JOIN     on pr_url → confusion matrix for the heal signal:
            FN = heal_decision PASS but self_heal_misses > 0   (the dangerous miss; ~10 candidates today)
            TN = PASS, 0 misses, low review_rounds             (correctly clean)
            (FP cheap to observe today — heal is non-gating)
         → catch-rate (recall) + false-positive, per-repo AND pooled

OUT      one report (markdown + JSONL) + honest caveats:
         labels are model-self-generated (agent_generated_guess) + the churn counter
         has known blind spots → v1 numbers are DIRECTIONAL, not gating-grade.
         Bolt on a quick human-verify pass over the FN set.
```

> **Label source is `/pr-postmortem` only.** `/dreaming` (LESSONS) is *not* part of this heal-signal measurement — it produces *findings*, not *labels*. The **knowledge-efficacy** measurement that joins `/dreaming`'s applied LESSONS (the `knowledge_sources_used` marker) against the `/pr-postmortem` outcome is the **Step-2 generalization**, not Step 1.

**Build it directly as a thin script** (a measurement spike), not through the Launch Pad → Supervisor machinery — graduate it into a shipped tool only after the numbers justify it. **No Launch Pad brief / Supervisor job is needed for Step 1.**

---

## 5. Invariants (carry through every step)

1. **Advisory-first → measure → earn trust → promote.** Never flip straight to gating/autonomous. (Twin §5.)
2. **Brain/graph reads fail SAFE.** A missing/stale/low-confidence graph silently falls back to grep/read; never blocks a run or changes a `heal_decision`. The graph is authoritative for **committed** structure only — never for a file the session is editing (staleness rule).
3. **No external dependency for a single repo.** The local Twin works with no `personal-brain`. Federation is opt-in.
4. **Sole-writer + provenance** for accumulated state; **human-promoted** for any trusted/cross-repo note. The plugin only ever writes drafts to `personal-brain`.
5. **Each step is independently useful and revertible.** The off-ramps (Step-1 noise, Step-4 no-lift) are first-class outcomes, not failures.
