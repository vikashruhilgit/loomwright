# North-Star Direction — owning the evolution

**Status:** Owner's-view direction doc. Opinionated, sequenced. Not a contract — a thesis to steer by.
**Date:** 2026-06-25
**Provenance:** Synthesized from a long working session (build-vs-buy code intelligence, doc/continuity,
`.supervisor/` as a continuity asset, staleness-as-correctness). Sibling record: `CODE_GRAPH_OWNERSHIP.md`.
This doc is itself an instance of Bet 2 (a handoff digest: decision + why + rejected + provenance).

---

## Thesis

**This is not an "agent framework." It is a Twin that accumulates and applies judgment.**

The 14 agents are the engine, not the moat — every framework has agents. The moat is the **closed loop**:
work generates knowledge (decisions, findings, lessons, churn signals) → that knowledge is kept fresh and
provenance-stamped → it is fed back as *advisory* context → the next piece of work is better and does not
diverge. Measure the project by **"does the loop demonstrably make work better,"** not by capabilities added.

The repo is already becoming this (System/Local Twin, learning-loop phases, the findings→community bridge).
The job is to *sharpen the thesis*, add the two things this session surfaced (owned code+decision intelligence;
a real handoff digest), make freshness a law, and earn every bit of surface area with evidence.

## The six bets

**1. Own code+decision intelligence — but it needs almost no build (validated 2026-06-27).**
The capability = answer *what/where* (code structure) and *why* (decisions) cheaply and accurately. We tested
whether this needs a graph — it does **not**:
- **Code structure → LSP** (callers / blast-radius / go-to-def — exhaustive, deterministic, ALWAYS fresh, zero
  cache) + grep + on-demand import scan. LSP is already in code-reviewer; the only pending work is *wiring* it
  into worker / QA / launch-pad. **graphify** stays as the advisory bonus for feature/concept navigation +
  surprising connections (validated good for THAT; weak for precise code-dependency — complementary, not rivals).
- **Decisions ("why / what we tried") → prose curation**, delivered by the **handoff digest (Bet 2)**. No graph.
- **Reposcan is PARKED.** The deterministic repo-map spike was built and then FAILED validation vs an
  independent ground truth (0/10 ranking — type-only edges miss value/function hubs; an import-edge fix scored
  7/10 but needs per-language resolution). The spike + a reusable validation HARNESS are shelved — graduate
  ONLY if LSP+graphify prove insufficient, and only back through the harness. (Record + validation:
  `CODE_GRAPH_OWNERSHIP.md`.)

Net: the code half is covered by existing tools (LSP + graphify); the decision half folds into Bet 2. **This
bet is effectively de-scoped to LSP wiring — no standalone build.**

**2. Make the handoff digest a first-class output.**
`.supervisor/` is a rich but *fragmented* continuity store (briefs, worker-summaries, memory, state.md).
Ship a "catch up / hand off in 2 minutes" digest: **decision + why + tried/rejected + current state +
provenance**, assembled from artifacts already generated. This is the differentiator — every other framework
is amnesiac between sessions; this one lets a second person inherit the first's full reasoning and not
re-litigate or diverge. `/obsidian` and `/dreaming` are the seeds; aim them here.
**Mode-agnostic (verified):** work flows through Supervisor (`jobs/`), `/autonomous` (`.supervisor/autonomous/`)
AND `/automate` (`.supervisor/automate/<run>.md`) — assemble ONE catch-up view from *all* surfaces
(jobs/ + autonomous/ + automate/ + worker-summaries/ + state.md + memory/ + postmortem/), not three per-mode
digests. This is the *human curation* layer; the per-mode *machine* readers already exist — don't rebuild them.

**3. Promote freshness + provenance to a cross-cutting law.**
Staleness appeared in *every* topic this session — code graph, docs, decisions, branches (the v13→v14
stale-branch incident that motivated PRE-FLIGHT SYNC). That is the central risk of any learning system.
The law has two halves:
- **Read side:** every advisory signal carries its basis and its as-of commit; **stale = hint, never truth;
  nothing gating.** (`read-bridge`'s staleness caveat is the seed.)
- **Write side — Read-before-write freshness gate:** *before writing X, verify the freshness of what X
  depends on; if the basis is stale, refresh or flag before committing the write.* Generalizes PRE-FLIGHT SYNC
  (today only pre-planning) into a universal habit. **Scope caveat:** check the *specific dependency*, not the
  whole world — "updating the doc that describes `read-bridge` → first confirm `read-bridge` still works that
  way." Targeted, not a global re-scan. This is the single best guard against stale-decision divergence.

**4. Design the WRITE/CURATION half (the missing piece).**
Bets 1–3 are the *read* side (advisory context in) + the freshness check; this (Bet 4) is the *write* side. But a Twin that *accumulates*
judgment only improves if the store stays high-quality — and that is undesigned. Required:
- **Anti-rot:** dedup, **supersession** ("X supersedes Y because Z", not two coexisting truths), and **decay**
  of stale lessons. Without these the advisory signal degrades and the Twin gets *worse* than none.
- **Unlearning:** a delete/correct path when a captured finding is disproven (append-only memory has none).
- **Net-positive budget for the WHOLE advisory stack** (bridge + postmortem + repo-map + digest): each reader
  adds tokens; together they must save more than they cost, or the learning loop becomes the context-bloat it
  was meant to prevent. Budget it, don't just win per-feature.
- **Counterfactual eval:** "advisory context *prevented* a divergence" is unobservable directly (you can't see
  the bug that didn't happen). Token savings are easy; *quality prevented* needs the deferred eval harness.
- **Cross-repo transfer = frontier + trap.** Twin is repo-local; over-generalizing a repo-specific lesson is a
  real risk. Deliberate stance for now: don't transfer across repos yet.

**5. Prove the loop works — or cut it.**
Telemetry / insights / postmortem already exist. Hold the loop to account: does advisory context reduce
review churn? Does the repo-map actually save tokens? Start with the Langfuse A/B (cold-LLM vs repo-map vs
LSP — tokens from traces, completeness by hand). A learning loop that can't show it's learning is ceremony.

**6. House rules — mandate conventions on the DO side; prefer executable over prose.**
Grounded gap (audit): conventions are enforced almost entirely on the REVIEW side (`code-reviewer` ~24
mentions, `frontend-ui` ~41) and are OPTIONAL/vague on the DO side (`worker`: *"(optional) key patterns from
CLAUDE.md"*, *"follow existing patterns"*). No single source of truth. Result: an implementer can drift from
the style guide / theming / validation rules and only (maybe) get caught at review = churn. Fix, strongest tier
first:
- **Tier 1 — Executable (preferred):** push every mechanizable convention down to a check that *runs* —
  linter/formatter, type-check, design-token linter, form-field validation-schema tests, custom lint rules.
  Worker runs them before "done"; reviewer re-runs. *"Please follow the style guide" in a prompt is the weakest
  enforcement; a failing lint rule is the strongest.* Don't rely on the model remembering rules — mechanize them.
- **Tier 2 — Structured house-rules contract:** ONE source of truth (style, theming tokens, form-field +
  validation patterns, naming) the worker MUST load at DO time (mandatory, not optional), reviewer checks
  against. **Layer it: company-wide base + per-project overrides** (mirrors CLAUDE.md layering) — handles
  "project-specific AND company-wide" in one model.
- **Tier 3 — Learned conventions:** review violations ("raw hex instead of a theme token") become rules-store
  entries surfaced on the DO side next time. Conventions ARE accumulated judgment — folds house rules into the
  loop instead of bolting them on. (Freshness/Bet 3 applies: provenance-stamp rules; tokens/standards rename.)

**Mechanics (design):**
- **Committed, tool-agnostic rules dir — OUTSIDE `.claude/`.** Default `.agent/rules/` (configurable; may align
  with the `AGENTS.md` convention). Version-controlled — NOT gitignored `.supervisor/`. Because rules are
  *committed*, they travel with the repo: **bootstrap once per repo; a cloning teammate inherits them** (this is
  why they must not live in machine-local/gitignored space). Each rule = `{category, statement, enforcement:
  advisory|must, check: <runnable cmd if mechanizable>, provenance}`. Pattern: advisory-when-present /
  must-when-present / **no-op-when-absent** (mirrors `brain-context`).
- **Enforce at SEAMS — three ROLES, not three copies:** (a) **Brief creation** (Launch Pad — standalone or
  inline in autonomous/automate) injects applicable MUST rules *into the brief* → worker *knows* them. (b)
  **Worker DO** runs the **fast/LOCAL** rule checks as part of its **existing** Step-5 verify gate (workers
  already run a build/test gate before "done") → cheap shift-left self-check on its own subtask. (c) **Phase 4.5
  self-heal/review** runs the **full/INTEGRATED** check set on the merged diff → the authoritative gate + the
  only place cross-subtask violations are visible (worktree isolation means the worker can't see them).
  *Why not collapse (b) into (a)+(c):* "plan carries the rule" ≠ "worker applied it" (LLMs drift — a check that
  *runs* verifies behavior, not intent); and catching a violation at the worker costs ~one turn vs a full
  review→heal→re-review cycle at (c) — dropping (b) doesn't save work, it pushes every catch to the most
  expensive seam (the exact review-churn the project already bleeds on). Not duplication — (b) is local+cheap,
  (c) is integrated+authoritative. Worker runs the cheap subset; the full suite runs at (c) [+CI].
- **Close the loop — split enforce vs. change:** code violates an *existing* rule → **auto-fix** (no approval;
  self-heal treats it like any BLOCKING finding). **Human approval ONLY for the rule-vs-reality conflict** — code
  consistently diverges from the rule (or no rule exists), signalling the *rule* may be stale/missing; updating
  the rule is the human decision (ties to Bet 3 freshness).
- **`/rules` command** to author/list/check — **scan-to-suggest, not blank-slate ask**: analyzes the app and
  *proposes* ("Radix for UI, Zod validation, tokens in `theme.ts`, RHF forms — make these rules?"), user
  confirms/edits. Categories pluggable: style / theme / implementation (form, validation, layout) / external
  libs (which UI lib) / naming / testing / a11y / security. Division: `/setup twin` *bootstraps* on first run;
  `/rules` *maintains*. graphify (or an on-demand grep/AST scan) is the scanner powering suggestions.

## Explicit NOs (owning means refusing)

- **No monolithic "index everything" graph.** Index by *intent*; keep layers separate; never re-index what has
  a typed reader. (The clearest lesson of the session — vendors sell the all-in-one graph; it's the staleness trap.)
- **No vendor-parity chasing.** Own the primitives (tree-sitter / LSP / SCIP-stack-graphs).
- **No speculative new agents.** And be ruthless about *existing* surface (see audit below).
- **Nothing gating.** Advisory/fail-safe is simultaneously the moat and the safety rail. A learning signal that
  can block a PR is a liability, not a feature.

## How docs are handled (index code, NOT docs)

We index **code** (the repo-map) — it compresses ~1000× and you don't already hold it. We do **not** index docs;
the doc-map was a spike (`CODE_GRAPH_OWNERSHIP.md`) that argued against it (docs compress ~14×; the doc→code
join is noisy). Docs are handled three ways, none needing an index:
- **Generated artifacts** (`.supervisor/` briefs, summaries, logs) → *typed readers* + *curated* into the digest
  (Bet 2). Never re-index what already has a typed reader (lossy regression).
- **Conventions / CLAUDE.md / `.agent/rules/`** → *read directly* (in context, or loaded at the enforcement
  seams), not indexed — you don't index what you always load.
- **Human architecture / ADR docs** → the only doc-index *candidate*, and even then advisory findability-only,
  deliberately NOT prioritized. (Bet 1's "decision intelligence" = the *curated* `.supervisor/` decision trail
  via the digest, NOT a doc index.)

## Grounded bloat finding (evidence for Bet/NO above)

Surface today: **14 agents / 19 commands / 56 skills**. A wiring audit (refs outside each skill's own dir +
preload status) shows a **dormant, stack-specific knowledge library** — ~15 skills at 1–4 refs and **0 agent
preloads**: `nextjs-*` (routing, auth, api-routes, components, data-fetching), `nestjs-*` (controllers,
typeorm, drizzle), `gateway-*` (rate-limiting, correlation, proxy-patterns, auth-middleware), `postgresql`,
`redis-caching`, `ci-cd`. They are catalogued in `SKILLS_INDEX` and cross-reference each other, but no agent
drives them. Odd for a *language-agnostic* framework. **Action:** evidence-based prune/merge pass — collapse to
on-demand reference or extract; keep the depth that earns its keep, cut the dormant. (Not "collapse to 3
agents" — that critique misread the subagent-isolation runtime; per-run token cost is not 14× and the agents
provide real distinct value.)

## Sequencing — where to start

1. **Read-before-write rule** (Bet 3 write-side) — promote the 3 existing feedback lessons to ONE named rule in
   `AGENT_GUIDELINES.md` + a `quality-checklist` pre-write gate. Cheapest, highest-leverage, fully unblocked.
2. **Handoff digest** (Bet 2) — the genuine differentiator (also delivers Bet 1's *decision* half).
3. **House rules** (Bet 6) + `/setup twin` cold-start bootstrap.
4. **Write/curation health** (Bet 4) — anti-rot so the store doesn't lie over time.
5. One-time evidence-based skill/agent prune pass (grounded above); wire LSP into worker/QA/launch-pad.
6. **(Deferred)** reposcan + Langfuse A/B — only if LSP+graphify prove insufficient for precise code-dependency,
   and only back through the validation harness. (Prove-the-loop / Bet 5 measurement runs against whatever ships.)

## Open frontier (still missing — beyond the bets)

- **Cold-start / bootstrapping.** A Twin is *empty* on a fresh repo — no patterns, conventions, or lessons, so
  it adds nothing until populated. **Home = a new `/setup twin` module** (umbrella already has 6; this is
  net-new): on first run it scans the app → suggests conventions/rules + seeds/validates CLAUDE.md patterns →
  refreshes the graphify graph → asks the user to confirm. graphify (or an on-demand scan) is the scanner. The one correct half of the
  "3-step wizard" critique — guided init for *knowledge* bootstrapping, not config.
  **`/setup` shape:** no-arg = guided setup of *everything* (multi-select offering all modules incl. `twin`) —
  but **offer/guide, never silently auto-enable** observability (Docker) or telemetry (consent); `/setup <module>`
  = individual. **Per-repo vs per-user split:** `twin`/rules are **committed → bootstrap once per repo; a cloning
  teammate inherits them** (no re-run needed). observability / telemetry / notifications are **per-user/machine**
  (Docker, consent, env) → each user still runs `/setup` for those even on an already-bootstrapped repo.
  **Nudge:** a one-time advisory SessionStart hint when no twin/rules detected ("for best results, run
  `/setup twin`") — non-blocking, per the invariants.
  **Grounded finding:** brain integration today is half-built — `brain-context` is **read-path-only and
  opportunistic** (detects an existing `graphify-out/graph.json` + wiki, else silently falls back to grep,
  forever). There is **no brain setup/bootstrap path**, so a fresh repo's Twin never populates unless the user
  manually runs `/graphify`. `/setup twin` closes exactly this gap.
- **Auditability / trust surface.** For an advisory Twin the human must be able to SEE what context was injected
  into a decision and CORRECT it ("why did it look there / follow that rule?" → show provenance). Without it,
  advisory context is a black box and trust erodes; with it, corrections feed Bet 4's unlearning path.
- **Read-before-write rule already exists, fragmented.** Bet 3's write-side gate is proven as three feedback
  lessons (`verify-invocation-shapes-from-the-file`, `verify-consumer-contract-before-for-free`,
  `verify-before-claiming-missing`). Promote to ONE named rule in `AGENT_GUIDELINES.md` + a `quality-checklist`
  pre-write gate. Near-zero cost; highest leverage.

## Invariants this direction must not break

Advisory / non-gating / fail-safe throughout (mirrors the existing bridge + the bimodal failure philosophy in
CLAUDE.md). Correctness gates fail CLOSED; side-effect emitters fail SAFE. A learning/continuity signal NEVER
changes a `heal_decision`, a review `decision`, a GO/NO-GO verdict, or blocks a PR/brief save.
