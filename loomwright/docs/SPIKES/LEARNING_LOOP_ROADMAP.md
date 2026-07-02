# Learning Loop Roadmap — Apply Before More Memory

> **Status:** planning spike / Launch Pad input (authored 2026-06-17).
> This doc sequences the missing pieces around Agent Manager's memory, review quality,
> churn learning, and brain integration. It complements:
>
> - `ENHANCEMENT_PLAN_v15_DRAFT.md` — original OBSERVE -> DISTILL -> PROMOTE -> APPLY -> MEASURE thesis.
> - `SYSTEM_TWIN_ROADMAP.md` — execution/proof axis: contracts, conformance, benchmark, ground truth.
> - `BRAIN_INTEGRATION_EVOLUTION.md` — optional external brain integration: Graphify + wiki read/write path.

---

## ⚑ DIRECTION UPDATE — 2026-06-19

- **Phase 4 (churn ledger) SHIPPED in v14.36.0 (PR #69)** — the "Phase 4+ Not started" rows below are stale and are corrected in §3 and §"Phase 4".
- **Phases 5/6 direction revised to LOCAL-FIRST.** The next move is *not* `/setup brain`; it is to **measure the local loop on the plugin's own run history** (a confusion matrix harvested from done-brief `## Outcome` blocks + `/pr-postmortem` backfill), then build the per-repo Twin (graphify + own findings, bridged) and prove it before federating. `/setup brain` is resequenced to **last**. Full statement: `BRAIN_INTEGRATION_EVOLUTION.md` §"⚑ DIRECTION UPDATE — 2026-06-19 (local-first Twin)"; the **ordered, gated execution path** is `LOCAL_TWIN_PATH.md`. Where this and the original phase prose conflict, the DIRECTION UPDATE wins.

---

## 0. Thesis

Agent Manager already writes many useful artifacts:

- `.claude/agent-memory/` per-agent memory
- `.supervisor/memory/PROJECT_MEMORY.md`
- `.supervisor/memory/LESSONS.md`
- `.supervisor/logs/*.jsonl`
- `.supervisor/worker-summaries/*.md`
- `.supervisor/twin/` System Twin contracts
- `.supervisor/postmortem/results.jsonl`
- `.supervisor/eval/*.jsonl`
- optional Graphify / brain context

The current gap is **not lack of memory**. The gap is inconsistent **APPLY** and
**MEASURE**: some artifacts are written and reported, but not consistently routed back
to the next planning/review decision.

The next product move is:

```text
Stop adding storage surfaces.
Make existing knowledge actionable.
Measure whether it helps.
Then promote durable knowledge to the brain.
```

---

## 1. Non-Negotiable Requirements

1. **Agent Manager remains standalone.** `personal-brain` is optional, advisory, and fail-safe.
2. **`CLAUDE.md` remains the human authority.** Memory, lessons, Twin contracts, and brain notes are subordinate.
3. **No self-trusting memory.** Anything machine-written must be provenance-gated, human-promoted, or advisory-only.
4. **No new memory surface without a named consumer.** Every stored artifact needs a read path and a measurement path.
5. **Workers stay focused.** Memory/postmortem context flows through Launch Pad, Supervisor, and reviewers; workers execute richer briefs.
6. **Advisory first.** Do not change `heal_decision`, review verdicts, or gating behavior until a signal proves itself.
7. **Use structured facts, not blanket context.** Read scoped memory/lessons/postmortems only when relevant.

---

## 2. Knowledge Layers

| Layer | Store | Current status | Needed next |
|---|---|---|---|
| Per-agent memory | `.claude/agent-memory/<agent>/` | Read explicitly in `/dreaming`; normal forward-read is inconsistent | Add scoped read to Code Reviewer and other memory-bearing agents where valuable |
| Project memory | `.supervisor/memory/PROJECT_MEMORY.md` | Read by Launch Pad and Supervisor through `read-project-memory.sh` | Keep; record when used |
| Lessons | `.supervisor/memory/LESSONS.md` | Written by `/dreaming`; reader exists; forward APPLY deferred | Wire `read-lessons.sh` into planning |
| System Twin | `.supervisor/twin/` | Used by Launch Pad and Supervisor Phase 4.5; reported by `/insights` | Continue advisory; measure usefulness |
| Postmortem corpus | `.supervisor/postmortem/results.jsonl` | Manual / trend seed; not read back | Upgrade into churn ledger and feed planning/self-heal |
| Brain | Graphify + `personal-brain/wiki/` | Optional read path exists in `brain-context`; write-back deferred | Keep optional; productize after local loop works |
| Langfuse | OTel traces | Observability only | Use for measurement later, not memory |

---

## 3. Phase Sequence

### Current State After v14.28.0

The roadmap is no longer greenfield. Treat the remaining work as incremental slices:

| Area | Status | Remaining work |
|---|---|---|
| Phase 0 — Brain read-path cleanup | Shipped in v14.27.0 | Only fix regressions if the baseline harness or `brain-context` docs drift |
| Phase 1 — Internal memory APPLY | Shipped in v14.28.0 | Monitor prompt behavior; no new storage surfaces |
| Phase 2 — Knowledge usage telemetry | Foundation shipped in v14.28.0; measurement close-out (Phase 2B) shipped in v14.33.0 | Complete for the measurement loop — `build-insights.sh` aggregation + `/insights` surfacing landed in v14.33.0. The optional `LAUNCH_PAD_RESULT.knowledge_sources_used` marker remains **explicitly deferred** (validator four-field discipline; Launch Pad emits no `session_end` line, so it would not feed `/insights`) |
| Phase 3 — Review quality | Core shipped in v14.21.0; residual shipped in v14.29.0 | Complete — CI miss-class vocabulary (R4), drift-taxonomy split (R3), and opt-in advisory red-team lens (R1) all landed |
| Phase 4 — Churn ledger | **Shipped in v14.36.0 (PR #69)** | Complete — postmortem provenance + read-back into Launch Pad Phase 3 / Supervisor Phase 4.5; `read-postmortem.sh` advisory-only |
| Phase 5 / 6 — Brain consolidation / write-back | **Not started — direction revised (local-first; see top banner)** | Now build the per-repo Twin (graphify + own findings, bridged) and **measure it on own-run history first**; `/setup brain` resequenced to last |

Recommended next order (remaining — Phase 3 residual shipped v14.29.0, Phase 2B shipped v14.33.0, **Phase 4 churn ledger shipped v14.36.0**):

1. ✅ **Phase 4 churn ledger (SHIPPED v14.36.0):** postmortem provenance + read-back into Launch Pad / Supervisor Phase 4.5.
2. **Measure the local loop on own-run history** (confusion matrix over done-brief `## Outcome` blocks + `/pr-postmortem` backfill, joined on PR URL) — the unblocking step for everything below. See the top DIRECTION UPDATE.
3. **Phase 5/6 — local-first:** build the per-repo Twin (graphify + own findings, bridged), prove it on the measurement, then federate via `/setup brain` (resequenced to last).

---

### Phase 0 — Finish Brain Read-Path Cleanup

Scope: complete the already-started Phase 0/1 brain-context slice so it does not leave a broken eval baseline.

Requirements:

- Keep `brain-context` optional and fail-safe.
- Keep baseline outputs under `.supervisor/eval/`.
- Keep baseline corpus fixtures in a tracked path, e.g. `loomwright/scripts/brain-baseline-corpus/`.
- Reconcile naming (`brain-corpus` vs `brain-baseline-corpus`) across docs and scripts.
- Correct Graphify confidence wording: nodes provide `source_file` / `source_location`; relation confidence lives on links.
- Normalize manual `tool_calls` input before passing to `jq --argjson`.

Acceptance criteria:

- `brain-baseline-eval.sh` exits 0 for missing corpus / missing jq / malformed env inputs.
- Tracked corpus fixtures are present in git.
- `check-doc-currency.sh` and `validate-version.sh` pass.

---

### Phase 1 — Internal Memory APPLY Path

Scope: make existing Agent Manager memory influence planning and review before adding more storage.

Requirements:

- Add explicit Code Reviewer memory consult:
  - read its own `.claude/agent-memory/...` directory in read-only mode;
  - read shared project memory via `read-project-memory.sh`;
  - treat all memory as advisory and subordinate to `CLAUDE.md`;
  - ignore stale or unrelated entries.
- Add scoped LESSONS apply path:
  - Launch Pad reads verified/fresh lessons through `read-lessons.sh`;
  - Supervisor reads verified/fresh lessons at task acquisition/planning;
  - include only relevant categories;
  - skip stale/unverified lessons;
  - fail safe when reader is absent or emits nothing.
- Document memory hierarchy:
  - `CLAUDE.md`
  - `PROJECT_MEMORY`
  - `LESSONS`
  - per-agent memory
  - brain/wiki hints

Acceptance criteria:

- Launch Pad and Supervisor can cite which verified lessons were considered.
- Code Reviewer has an explicit, bounded memory read step.
- No memory read can block a run or change a verdict by itself.

---

### Phase 2 — Knowledge Usage Telemetry

Scope: measure whether applied knowledge is actually used.

Requirements:

- Add an additive usage marker to session/result output:

```json
"knowledge_sources_used": [
  "project_memory",
  "lessons:testing",
  "agent_memory:code-reviewer",
  "twin:scripts/build-insights.sh",
  "brain_context"
]
```

- Keep the field optional and additive.
- Do not gate on it.
- Let `/insights` surface it later as a trend; no need to block Phase 2 on dashboard work.

Acceptance criteria:

- Runs can distinguish "memory existed" from "memory was actually used."
- Missing field remains valid for old logs.

**Known gaps after the v14.28.0 slice (deliberate follow-ups, not regressions):**

- **Emit-only consumption gap — CLOSED in v14.33.0.** `knowledge_sources_used` was emit-only after v14.28.0; as of v14.33.0 `build-insights.sh` aggregates it and `/insights` surfaces it in the `## Knowledge sources (memory APPLY)` dashboard section (runs-reporting-a-source count, top source tags, per-version usage) plus a per-run note bullet — so the Phase 2 success signal ("distinguish memory existed from memory used") is now observable. Section is suppressed when no run reports a source; old logs parse cleanly.
- **Launch Pad is unmeasured — explicitly DEFERRED.** Supervisor and Code Reviewer emit `knowledge_sources_used`; Launch Pad consults lessons/project memory but emits no marker (no field on `LAUNCH_PAD_RESULT` — its usage is only free-text "citation" in the brief). The optional `LAUNCH_PAD_RESULT.knowledge_sources_used` field remains deferred as a clean fast-follow: (a) `scripts/validate-launch-pad-result.py` enforces a strict four-field discipline (`ALLOWED_KEYS = {schema_version, status, saved_brief_path, summary}`) with a scalar-only parser, so adding an array field is disproportionate and parser-risky for this slice; (b) Launch Pad emits no `session_end` line, so the field would not feed `/insights` anyway — it is decoupled from this measurement close-out.
- **Claimed vs verified.** The field is model-self-reported and non-gating: it measures *claimed* usage, not machine-verified reads. Fine for advisory telemetry; calibrate trend interpretation accordingly.

**Phase 2B — Measurement close-out (SHIPPED in v14.33.0):**

- ✅ Wired `build-insights.sh` to read the flat `session_end.knowledge_sources_used` array (projection defaults absent → `[]`).
- ✅ Surfaces per-run knowledge sources in generated run notes (frontmatter `knowledge_sources_used:` + a `- **Knowledge sources:**` body bullet) and a dashboard `## Knowledge sources (memory APPLY)` section.
- ✅ Added a trend view: runs reporting any knowledge source, top source tags by frequency, and per-version usage; suppressed entirely when no run reports a source (System-Twin-hard-signal precedent).
- ⏸️ Optional `LAUNCH_PAD_RESULT.knowledge_sources_used` — **explicitly deferred** (validator four-field discipline; Launch Pad emits no `session_end` line, so it would not feed `/insights`). Recorded as a clean fast-follow, not silently dropped.
- All fields stay optional, additive, self-reported, and non-gating; no `schema_version` bump.

Acceptance criteria for Phase 2B (status):

- ✅ `/insights` can answer which knowledge sources were claimed by recent runs (v14.33.0 dashboard section + per-run notes).
- ✅ Supervisor and Code Reviewer have a machine-readable usage marker; the Launch Pad gap **remains explicitly documented as deferred** (the AC's sanctioned alternative path).
- ✅ Old logs and old result blocks still parse without the field (absent ⇒ `[]`; section suppressed when none).

---

### Phase 3 — Review Quality: Different Lens + Class-Based Fixer

Scope: reduce real defects earlier. This is separate from brain-context; the brain gives context, not better verdicts.

**Status note:** v14.21.0 already shipped the core local self-heal improvements for this phase: a different-lens directive, class-based fixer behavior, and most miss-class vocabulary. Do not re-implement those pieces blindly. The remaining work is the residual slice below.

Requirements:

- Make Phase 4.5 self-heal use a genuinely different second lens where practical:
  - different reviewer prompt/lens;
  - avoid "same reviewer twice" as the only strategy.
- Change fixer behavior from instance-only to class-based:
  - when one miss-class is flagged, sweep the whole diff for that class;
  - prioritize behavioral defects first, drift second.
- Explicit miss-classes:
  - validation parity
  - numeric falsy coercion
  - positional args vs options object misuse
  - missing branch coverage
  - count/version/restated-list drift
  - cross-reference precision drift
- Keep CI review independent, but enrich its prompt with the same defect classes.
- Add optional red-team/adversarial review for high-risk integrated diffs only.

Acceptance criteria:

- Self-heal instructions require a class sweep, not just the flagged instance.
- CI and local review remain independent; convergence is not the goal.
- Review quality improves because code is better, not because bots are quieter.

**Phase 3 residual scope — full option:** _(Shipped in v14.29.0 — R4 CI miss-class vocabulary, R3 drift-taxonomy split, and R1 opt-in advisory red-team lens all landed; advisory/non-gating, no `schema_version` bump, counts unchanged.)_

1. **R4: independent CI review prompt miss-class vocabulary**
   - Enrich `.github/workflows/claude-code-review.yml` with the same defect-class vocabulary used by local review/self-heal.
   - Keep the CI review independent; do not try to force identical findings or converge bot behavior.
   - Mention classes as review lenses, not as hard schema.

2. **R3: Taxonomy cleanup**
   - Split the current drift wording into clear classes:
     - `count/version/restated-list drift`
     - `cross-reference precision drift`
   - Keep behavioral miss-classes separate from doc/count drift.
   - Preserve severity philosophy: behavioral defects first, drift second.

3. **Docs and roadmap alignment**
   - Mark already-shipped v14.21.0 Phase 3 pieces as done.
   - Capture residual scope so future agents do not rebuild shipped behavior.
   - Keep red-team/adversarial review documented as advisory at first.

4. **R1: Optional red-team lens for high-risk integrated diffs**
   - Trigger only for high-risk integrated diffs, for example auth/security, data loss, permissions, secrets, migrations, workflow automation, or broad cross-agent prompt changes.
   - Run as an advisory second lens; it must not directly change `heal_decision`, block a PR, or create a new gate in the first slice.
   - Bound it to one pass per run and record findings as review input / risks, not as an unbounded loop.
   - If it produces actionable HIGH/BLOCKING issues, the existing self-heal/fix loop may address them through the normal class-based path.

Acceptance criteria for the full residual:

- CI review prompt includes the miss-class taxonomy.
- The roadmap and docs distinguish shipped Phase 3 work from residual work.
- Red-team/adversarial review, if implemented, is opt-in or high-risk-only, advisory, bounded, and non-gating.
- No new required review gate is introduced without separate evidence from Phase 2B / Phase 4 measurement.

---

### Phase 4 — Churn Loop: Postmortem as Ledger

> **✅ Status: SHIPPED in v14.36.0 (PR #69).** Postmortem provenance enrichment + read-back wired advisory-only into Launch Pad Phase 3 / Risk and Supervisor Phase 4.5 (`read-postmortem.sh`). The churn ledger is now *also* the labeling substrate for the local-loop measurement (see top DIRECTION UPDATE).

Scope: close the PR-churn learning loop.

Requirements:

- Treat `/pr-postmortem` output as the PR churn ledger.
- Enrich `POSTMORTEM_RESULT` with provenance:
  - `pr_url` / number
  - `brief_path`
  - `job_path`
  - `branch`
  - `changed_paths`
  - `review_rounds`
  - root-cause classes
  - flow stage
- Run postmortem on every PR where practical:
  - clean PRs are useful positive examples;
  - churned PRs carry lessons.
- Feed patterns back into:
  - Launch Pad risks / acceptance criteria;
  - Supervisor Phase 4.5 review/fix prompt.
- Do not feed postmortem corpus directly to workers.

Acceptance criteria:

- Future planning can answer: "Have similar PRs churned before, and why?"
- Launch Pad can surface prior churn risk for touched areas.
- Self-heal can apply known miss-classes from prior churn.

---

### Phase 5 — Brain Read-Path Consolidation

> **⚑ Direction revised 2026-06-19 (local-first).** This phase is now framed as *building the **local** Twin* — graphify (structure) + the plugin's own `.supervisor/` findings as the rationale layer, bridged findings→graph-communities — and **measuring it on own-run history before any `/setup brain`**. The "add `/setup brain`" requirement below is **resequenced to last** (federation tier, post-proof). See `BRAIN_INTEGRATION_EVOLUTION.md` §"⚑ DIRECTION UPDATE". The "keep brain-context optional / fail-safe / strengths-only" requirements below remain valid.

Scope: keep the brain read path focused on its actual strength.

Requirements:

- Keep `brain-context` optional.
- Use Graphify/wiki for:
  - `missing_context`
  - architecture lookup
  - blast radius
  - rationale / decisions / gotchas
- Do not expect brain-context to solve:
  - review quality
  - behavioral bugs
  - churn loop
  - two-reviewer divergence
- Add `/setup brain` only after internal APPLY/MEASURE is working.
- `/setup brain` remains direct-only unless the dashboard UX is redesigned.

Acceptance criteria:

- Agent Manager behaves unchanged when no brain is configured.
- Brain reads are advisory and fail safe.
- Setup productizes a proven integration rather than creating a new dependency.

---

### Phase 6 — Brain Write-Back

Scope: promote only durable, reusable knowledge to `personal-brain`.

Requirements:

- Add `/dreaming --target brain` or equivalent.
- Write only draft notes to `<BRAIN_ROOT>/wiki/_drafts/`.
- Use the brain draft schema:

```yaml
---
id: <kebab-slug>
tags: [<reuse-existing-vocabulary>]
source: <PR URL, commit sha, or run artifact>
owner: <git user>
last_verified: <YYYY-MM-DD>
confidence: low
draft: true
---
```

- Never auto-promote trusted wiki notes.
- Apply a promotion filter:
  - durable beyond one run;
  - reusable;
  - rationale/gotcha/decision-shaped;
  - has source provenance;
  - not already captured in `CLAUDE.md`, `PROJECT_MEMORY`, `LESSONS`, or the brain wiki.
- Keep local lessons local unless they deserve brain promotion.
- Optionally add `personal-brain/bin/harvest-plugin-runs.mjs` later.

Acceptance criteria:

- Plugin writes only to `wiki/_drafts/`.
- Drafts are not added to the trusted index.
- Brain review remains the promotion gate.

---

## 4. Recommended First Launch Pad Brief

Start with Phase 1 + Phase 2 only.

```text
Goal: Make existing Agent Manager memory actionable before adding more storage.

Implement a scoped memory APPLY path and usage telemetry:
- Code Reviewer explicitly consults its per-agent memory and project memory before review.
- Launch Pad and Supervisor consult verified/fresh LESSONS through read-lessons.sh.
- All memory is advisory and subordinate to CLAUDE.md.
- Add additive knowledge_sources_used markers so future insights can measure whether memory was applied.
- Do not add new storage surfaces.
- Do not change review verdicts, heal_decision, or gating behavior.
```

Why first:

- It closes the most obvious local gap.
- It does not depend on `personal-brain`.
- It turns existing stored knowledge into decision-time context.
- It creates the measurement hook needed before expanding the brain loop.

---

## 5. Explicit Non-Goals For The First Slice

- No `/setup brain`.
- No brain write-back.
- No trusted wiki writes.
- No worker memory reads.
- No gating changes.
- No new memory directories.
- No vector/RAG store.
- No CI reviewer convergence project.

---

## 6. Success Signal

The roadmap is working when future runs can answer all three:

1. **What did we know before planning?**
   - project memory, lessons, Twin contracts, brain context, postmortem patterns
2. **Which of those did we actually use?**
   - `knowledge_sources_used`
3. **Did using it improve outcomes?**
   - fewer repeated review classes
   - fewer self-heal iterations
   - fewer Plan Review retries
   - fewer post-PR churn rounds

Until then, more memory is only more files.
