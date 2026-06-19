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

### Step 3 — GRAPH (produce a local graph where the findings live)
- **Do:** run graphify in the work repos → `graphify-out/graph.json` (graph-only / local tier — real file or symlink; **no external brain required**).
- **Out:** the first time graph (structure) + findings (rationale) coexist in one repo. Cheap, reversible.
- **Note:** this is the missing *graph-production* step — the read path already consumes a graph if present (`brain-context` skill), but nothing in the plugin produces one today.

### Step 4 — BRIDGE (findings → graph communities) + re-measure
- **Do:** adapt `personal-brain`'s community-stub mechanism — link the plugin's findings (LESSONS, postmortem ledger, Twin contracts, done-brief Outcomes) to **graph communities** (stable, human-named clusters — survive symbol churn). Add freshness (`built_at_commit` / `last_verified`) + a concept-graph over the findings. Re-run the Step-2 instrument.
- **GATE:** *the real "graph-first beats baseline" eval gate* — answered on **own runs**, not a hand-authored external corpus. Does graph-linked context **measurably cut the FN miss-classes** vs the Step-1 baseline?
  - **No lift → stop the graph investment**, keep findings flat. (Bridge is the keystone but it must pay for itself.)

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
