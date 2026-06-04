---
description: On-demand scan for Claude Code adoptions (default) or differentiated product directions (--strategy) — propose-only, bounded, human-gated, never self-applies
---

> **Read-only / propose-only contract.** `/capability-check` is strictly read-only on the plugin and the codebase. It fetches the live Claude Code changelog/docs and dependency info, diffs them against the tracked capability baseline, and **reports candidate adoptions**. With `--strategy` it instead runs a grounded product-evolution pass and reports candidate **product directions**. In either mode it **never** edits an agent, command, skill, hook, or any plugin file. Adoption is always a separate, human-driven change (typically a `/launch-pad` → `/supervisor` run). The only file it may write is the baseline itself, and only when you pass `--update-baseline`.

> **Two report types, kept distinct.** This command emits one of two distinct reports depending on mode. The **default** mode (no `--strategy`) emits a `CAPABILITY_REPORT` of **adoption candidates** — Claude Code *platform features* the plugin should adopt to keep current. The **`--strategy`** mode emits a `DIRECTION_REPORT` of **product directions** — net-new, differentiated *product strategy* (how to make this plugin uniquely better than a stateless task-runner), the kind of reframe that produced "System Twin." Adoption = catch up to the platform; direction = pull ahead of the field. They are never mixed in one run.

# Command: /capability-check

## Purpose

The plugin can quietly fall behind Claude Code: a new hook event, tool, agent-frontmatter field, or SDK feature ships, and nothing prompts the maintainer to adopt it. `/capability-check` is the **on-demand** answer (the "continuously checks what's available" half of self-evolution, built abandonment-resilient — you run it when a session surfaces a gap, instead of being trained to ignore a weekly cron).

It does what a maintainer would do by hand: read what's new in Claude Code, compare it to what this plugin already uses (the **baseline**), and surface a short, actionable list of things worth adopting — each as a *candidate*, never an applied change.

## Usage

```bash
/capability-check                      # default: adoption diff → report of candidate platform-feature adoptions
/capability-check --strategy           # product-evolution pass → report of candidate differentiated product DIRECTIONS
/capability-check --max-fetches 3      # tighten the network budget (default 5) — applies to BOTH modes
/capability-check --strategy --max-fetches 3   # strategy pass under a tighter fetch budget
/capability-check --update-baseline    # after reviewing, record this scan as the new baseline (maintainer / repo-root only)
/capability-check --strategy --update-baseline # record reviewed direction STATUSes into product_directions (maintainer / repo-root only)
/capability-check --save               # also write the report to .supervisor/capability/{YYYY-MM-DD}.md (gitignored)
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--strategy` | off | Switch from the default adoption diff to the **product-evolution pass** (see "Workflow B"). Emits a `DIRECTION_REPORT` of differentiated product directions instead of a `CAPABILITY_REPORT` of platform adoptions. All other guardrails (`--max-fetches`, propose-only, `--update-baseline`-only-write) are preserved. |
| `--max-fetches N` | `5` | Hard cap on external fetches (WebFetch + WebSearch + Context7 calls) for the run — **shared by both modes**. In `--strategy` mode the optional frontier-AI-trend signal draws from this same budget; there is no separate or uncapped fetch path. Bounds cost; a run that hits the cap reports partial coverage and says so. |
| `--update-baseline` | off | After you've reviewed the report, rewrite `docs/CAPABILITY_BASELINE.json`. In default mode: bump the scan date + record accounted-for platform features. In `--strategy` mode: record reviewed direction STATUSes into the `product_directions` section (never edits plugin code). Meaningful only in the plugin's own repo (the install dir is read-only); a no-op notice elsewhere. |
| `--save` | off | Also persist the report (gitignored): default mode → `.supervisor/capability/{YYYY-MM-DD}.md`; `--strategy` mode → `.supervisor/capability/{YYYY-MM-DD}-strategy.md`. The mode suffix keeps a same-day adoption scan and strategy pass from overwriting each other. Default is print-only. |

## Workflow A — default adoption diff (bounded, on-demand)

> Runs when `--strategy` is **absent**. Behavior is unchanged from prior versions.

```
LOAD baseline → FETCH live state (≤ max-fetches) → DIFF → REPORT candidates (or suppress) → [optional] UPDATE baseline
```

### 1. LOAD baseline
Read `${CLAUDE_PLUGIN_ROOT}/docs/CAPABILITY_BASELINE.json` — the snapshot of Claude Code features the plugin already uses (`claude_code.*` lists), features deliberately **not** adopted yet (`known_not_adopted`, so they aren't re-flagged), pinned `deps`, and the `sources_to_check` URLs. If the file is missing or unparseable, report that and stop (do not invent a baseline).

### 2. FETCH live state (hard-bounded)
Spend **at most `--max-fetches`** external calls, in priority order, stopping when the budget is hit:
1. WebFetch `sources_to_check.claude_code_changelog` — the release notes.
2. WebFetch `sources_to_check.claude_code_docs_hooks` and `…_docs_subagents` — to spot new hook events / agent-frontmatter fields / tools.
3. For each entry in `deps` with a real package: Context7 `resolve-library-id` + a short `query-docs` for "latest version / breaking changes" (skip unpinned/bundled ones where it adds no signal).
4. If a primary fetch fails, fall back to **one** WebSearch using `sources_to_check.search_fallback`.

If the budget is exhausted before all sources are covered, continue to REPORT but mark coverage as **partial** and list which sources were not checked. Never exceed the cap.

### 3. DIFF
From the fetched material, identify items **present upstream but absent from the baseline** and not already in `known_not_adopted`:
- new **hook events** or hook capabilities,
- new **tools** or tool options,
- new **agent-frontmatter fields** / subagent features,
- new **SDK / slash-command / skill / MCP** capabilities,
- **dependency** updates with relevant changes.

For each, write one line of *why it matters for THIS plugin* — which agent/hook/command it would plausibly improve. Discard anything the plugin already uses or has explicitly deferred.

### 4. REPORT (rare + actionable)
- **If there are no new candidates:** print exactly one line — `No new Claude Code capabilities since baseline {baseline_date} (checked {N} sources). Nothing to adopt.` — and stop. **Do not pad** the output. (Red-team W3: a report that fires every run with already-known facts trains the maintainer to ignore it.)
- **If there are candidates:** print a `CAPABILITY_REPORT` with, per candidate:
  - **Capability** — name + one-line description of what shipped.
  - **Source** — the URL/version it came from.
  - **Plugin fit** — the specific agent/hook/command/skill it would improve, and a rough effort (S/M/L).
  - **Status: CANDIDATE — not applied.** Adoption is a separate human-driven change.
  - A coverage footer (sources checked / skipped, partial?).
- With `--save`, also write the same report to `.supervisor/capability/{YYYY-MM-DD}.md`.

**Never** edit an agent/command/skill/hook/manifest here. The report is the deliverable; adopting a candidate is a deliberate follow-up (usually `/launch-pad goal: "adopt <capability>"` → `/supervisor`).

### 5. UPDATE baseline (only with `--update-baseline`)
After you've read the report and decided what's accounted for, rewrite `docs/CAPABILITY_BASELINE.json`: bump **`baseline_date` to today AND `plugin_version_at_last_scan` to the current plugin version** (the two are the date/version pair of this scan — bump them together so the field never silently drifts stale), add adopted capabilities to the relevant `claude_code.*` lists, and move "seen but not adopting yet" items into `known_not_adopted` (so the next run doesn't re-flag them). This is a maintainer action in the plugin's own repo; in an installed copy the plugin dir is read-only, so print a notice and skip the write.

## Workflow B — `--strategy` product-evolution pass (bounded, on-demand)

> Runs only when `--strategy` is present. This is a **grounded product-evolution pass** that thinks like a senior product strategist: it proposes net-new, **differentiated product directions** — how to make this plugin uniquely better than a stateless task-runner — exactly the kind of reframe that produced "System Twin." It preserves *every* guardrail of the default mode (read-only/propose-only, bounded by `--max-fetches`, rare + actionable with a single suppression line, `--update-baseline` as the only write path).
>
> This is the outer loop of the OBSERVE→DISTILL→PROMOTE→APPLY→MEASURE flywheel (`docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` §0d): the adoption diff keeps the plugin *current* with the platform; the strategy pass keeps it *ahead* of the field. Both are on-demand-first and human-gated (§4.1/§4.4); both honor the W3 rarity discipline (§4.4, §7) — a report that fires every run trains the maintainer to ignore it.

```
LOAD baseline (+ product_directions) → READ product surface → [optional] platform diff + bounded frontier-AI signal (≤ max-fetches)
  → IDEATE via brainstorming 5-lens → SCORE (moat × feasibility × effort) → DEDUP → REPORT directions (or suppress) → [optional] UPDATE baseline
```

### B1. LOAD baseline + product_directions
Read `${CLAUDE_PLUGIN_ROOT}/docs/CAPABILITY_BASELINE.json` as in Workflow A, **and** read its `product_directions` section (see schema below). Directions already recorded there with status `adopted`, `proposed`, or `deferred` are the DEDUP set — they are NOT re-proposed (B6). If the section is absent, treat the DEDUP set as empty (the first `--strategy` run seeds it).

### B2. READ the product surface (grounding inputs — name them concretely)
The strategy pass grounds every idea in the plugin's *real* surface, not generic advice. Read:
- **`agents/`** — the 13 agent roles (their missions, frontmatter, contracts) — the plugin's core capabilities and gaps.
- **`commands/`** — the command set (the user-facing entry points) — where new directions plug in.
- **The flywheel / insights state** — `.supervisor/insights/` (the `/insights` dashboard) and `.supervisor/logs/*.jsonl` session logs — what the system already observes about its own use. These are gitignored session artifacts: **if absent** (fresh install / CI / no prior runs), skip them and note the gap in the coverage footer (the same graceful-degradation Workflow A applies to a missing source).
- **`docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`** — the north-star direction doc (flywheel §0d, on-demand-first §4.1, the single most dangerous idea §7).
- **The platform diff (optional)** — the *output of Workflow A's DIFF step*: what is newly feasible on the Claude Code platform. A direction can be enabled by a freshly-shipped platform capability.
- **A bounded, optional frontier-AI signal** — ONE WebSearch (or Context7) step for recent AI-capability trends, **strictly within `--max-fetches`** (reuse the existing cap; never add a separate or uncapped fetch path). If the budget is exhausted, skip it and mark coverage partial. This is a signal, not a requirement — directions may ground entirely on the platform diff instead.

> **Fetch-budget note:** the local product-surface reads above (`agents/`, `commands/`, the insights state, the draft, and the platform diff already produced by Workflow A) are ordinary file reads and do **not** count against `--max-fetches`. Only external calls — the optional frontier-AI signal's WebSearch / WebFetch / Context7 — draw from that budget.

### B3. IDEATE (bounded engine — reuse the brainstorming skill)
Generate and stress-test direction candidates using the **5-lens scored-debate framework** in `${CLAUDE_PLUGIN_ROOT}/skills/brainstorming/SKILL.md` (Creative Thinker, Product Manager, Engineer, Business Strategist, Critic — independent analysis → mandatory cross-challenge → scoring, with the Phase 3.5 Reality Check grounding ideas against the actual codebase). **Do not invent a new framework**; this is the bounded ideation engine. Honor its anti-patterns — especially "no generic ideas" ("add AI" without a specific mechanism is banned).

### B4. SCORE (rubric)
Score each surviving direction on three axes, then rank by composite:

| Axis | Meaning | Anchor |
|------|---------|--------|
| **Differentiation / moat** | How much this makes the plugin *uniquely* better than a stateless task-runner — a defensible edge competitors can't trivially copy. | High = category-defining (e.g. cross-run compounding "gets smarter with use"); Low = me-too convenience. |
| **Feasibility** | Buildable against the current architecture — graded with the brainstorming skill's Phase 3.5 Reality Check verdict (VIABLE / NEEDS_FOUNDATION / BLOCKED). Cite `skills/mvp-scoping/SKILL.md` for the prioritization lens. | High = VIABLE as-is; cap NEEDS_FOUNDATION feasibility ≤ 5, BLOCKED ≤ 2 (per the brainstorming Reality-Check caps). |
| **Effort** | Rough build size (S / M / L) — *inverted* in the composite (smaller effort ranks higher). Use `skills/mvp-scoping/SKILL.md` as the prioritization lens (MVP / Phase 2 / Nice-to-have) for sequencing which directions to build first, not as the source of the S/M/L buckets. | S = a wedge shippable in days; L = a multi-week program. |

**Composite ranking:** prefer **high differentiation × high feasibility × low effort** — a strong moat that is buildable now via a small wedge. A high-moat direction that is BLOCKED or L-effort ranks below a moderate-moat direction that is VIABLE and S-effort, because the flywheel rewards directions that can actually ship and start compounding (§0d "smallest loop that visibly compounds"). Rank candidates and carry only those that clear the bar (B7) into the report.

**Clears-the-bar threshold (concrete, so suppression is deterministic):** score the moat and feasibility axes on the **brainstorming skill's 1–10 scale** (`skills/brainstorming/SKILL.md` → **Phase 3: Scoring**, "Rate every surviving idea on 4 axes (1-10)", with the Phase 3.5 Reality-Check caps applied to feasibility). A direction **clears the bar** only if it meets ALL of: **moat ≥ 7** (strongly differentiating, not me-too convenience), **feasibility ≥ 5** (VIABLE, or NEEDS_FOUNDATION not capped below 5 — a BLOCKED direction at ≤ 2 never clears), **AND** it passed the B5 grounding mandate. Anything below those is suppressed (B7), not reported. Rank the survivors by composite (moat × feasibility, effort-adjusted).

### B5. GROUNDING MANDATE (hard rule — mirrors the default mode's discipline)
Every emitted DIRECTION **MUST cite ≥1 concrete product asset** (a specific named `agents/` role, `commands/` entry, or identified gap) **AND ≥1 newly-feasible enabler** (a specific Claude Code platform capability from the diff, OR a specific frontier-AI trend from the bounded signal). **A direction that cannot ground BOTH is DROPPED** — no generic advice, no hype, no "leverage AI" filler. This is the strategy-mode parallel to the default mode's "one line of *why it matters for THIS plugin*" rule.

> **Fetch-exhausted edge case:** the newly-feasible enabler comes from the platform diff or the frontier-AI signal — both optional fetches (B2). If **neither** was reachable (e.g. `--max-fetches 0`, or the budget was consumed before either source was read), no candidate can satisfy the mandate. In that case emit the B7 suppression line with coverage marked **partial** and a note that grounding could not be evaluated (a *fetch-exhausted* run — distinct from "nothing scored high enough"). Do **not** emit ungrounded directions to work around an exhausted budget.

### B6. DEDUP against `product_directions`
Drop any direction already present in the baseline's `product_directions` section with status `adopted`, `proposed`, or `deferred` (matched on `id`/`title` and intent). The report surfaces only *net-new* directions, so re-running `--strategy` doesn't re-pitch the same ideas (the W3 rarity contract again).

### B7. REPORT (rare + actionable) or SUPPRESS
- **If no direction clears the scoring bar (B4) and grounding mandate (B5):** print exactly one line —
  `No new product directions clear the bar since baseline {baseline_date} (scored {K} candidates, {N} sources). Nothing to propose.`
  — and stop. **Do not pad.** (Red-team W3, mirrored from the default mode's `No new Claude Code capabilities since baseline …` suppression: a report that fires every run with marginal ideas trains the maintainer to ignore it.)
- **If one or more directions clear the bar:** print a `DIRECTION_REPORT` with, per ranked direction:
  - **Gap / Asset** — the specific named product asset (an `agents/` role, a `commands/` entry, or a named gap) it addresses.
  - **Moat / why differentiating** — why it makes the plugin uniquely better than stateless task-runners.
  - **Newly-feasible enabler** — the specific Claude Code platform capability OR frontier-AI trend that makes it newly feasible.
  - **Effort / Risk** — rough sizing (S / M / L) + a one-line risk note (e.g. the Critic lens's top concern).
  - **Wedge** — a concrete first step / smallest entry point that starts compounding.
  - **Status: DIRECTION — propose-only, not applied.** Adoption is a separate human-driven change.
  - A coverage footer (product surface read, sources checked / skipped, partial? candidates scored vs. emitted).
- With `--save`, also write the same report to `.supervisor/capability/{YYYY-MM-DD}-strategy.md` (the `-strategy` suffix keeps it distinct from the default mode's same-day `{YYYY-MM-DD}.md`, so neither overwrites the other).

**Never** edit an agent/command/skill/hook/manifest here. The report is the deliverable; a direction becomes work ONLY via a deliberate human-chosen `/launch-pad goal: "<direction title>"` → `/supervisor`.

### B8. UPDATE baseline (only with `--update-baseline`)
After reviewing the `DIRECTION_REPORT`, rewrite `docs/CAPABILITY_BASELINE.json` to record direction **STATUS** into the `product_directions` section (schema below): add newly-proposed directions with `status: "proposed"`, mark ones you've started building `status: "adopted"`, and park ones you're not pursuing `status: "deferred"` (so the next `--strategy` run dedups them via B6). **When an existing entry's status changes** (e.g. `proposed` → `adopted`/`deferred`), also bump its **`date`** to today — `date` tracks *when surfaced or last status-changed* — while leaving `id` / `title` / `provenance` / `rationale` / `pillars` intact (a status update changes only `status` and `date`; never drop the other fields). This records *status and `date`* only — it **never** edits plugin code (no agent/command/skill/hook change). Maintainer action in the plugin's own repo; in an installed copy the dir is read-only, so print a notice and skip.

### The `product_directions` baseline contract (schema — defined here; ST2 seeds it)
The `--strategy` mode reads and (with `--update-baseline`) writes a `product_directions` section in `docs/CAPABILITY_BASELINE.json`. It sits alongside the existing `claude_code.*`, `known_not_adopted`, `deps`, and `sources_to_check` sections and does not alter them. Shape:

```jsonc
"product_directions": [
  {
    "id": "system-twin",                    // slug, unique within the array — the DEDUP key
    "title": "System Twin",                 // human-readable direction name
    "status": "proposed",                   // enum: "adopted" | "proposed" | "deferred"
    "provenance": "ENHANCEMENT_PLAN_v15_DRAFT.md §0d / MEMORY.md",  // where it was surfaced
    "date": "2026-06-01",                    // YYYY-MM-DD when surfaced / last status change
    "rationale": "Cross-run compounding so the plugin gets smarter with use — the moat vs. stateless task-runners.",  // one line
    "pillars": ["memory", "flywheel", "advisory"]  // OPTIONAL: tags/sub-themes; omit if not needed
  }
]
```

Field contract:
| Field | Required | Type | Meaning |
|-------|:---:|------|---------|
| `id` | yes | string (slug) | Stable unique key; the DEDUP identity used by B6. |
| `title` | yes | string | Human-readable direction name. |
| `status` | yes | enum | `adopted` (being built / shipped) \| `proposed` (surfaced, awaiting decision) \| `deferred` (consciously parked). All three suppress re-proposal in B6. |
| `provenance` | yes | string | Where/how it was surfaced (doc §, session, report date). |
| `date` | yes | string (YYYY-MM-DD) | When surfaced or last status-changed. |
| `rationale` | yes | string (one line) | Why it differentiates — the moat in a sentence. |
| `pillars` | no | string[] | Optional sub-theme tags (e.g. the System-Twin pillars); omit when not useful. |

## Guardrails (non-negotiable)
- **Never self-applies — both modes.** The plugin may *propose* adoptions (default) or product directions (`--strategy`); a human applies them. This command only reads + reports. The strategy mode never edits a plugin file, and when it writes the baseline it records direction STATUS into `product_directions` only — never plugin code. A direction becomes work ONLY via a human-chosen `/launch-pad` → `/supervisor`.
- **Bounded — both modes.** Hard `--max-fetches` cap; no unbounded crawling. The `--strategy` mode's optional frontier-AI-trend signal draws from this same shared budget — there is no separate or uncapped fetch path.
- **`--update-baseline` is the ONLY write path.** Default mode writes the `claude_code.*` / `known_not_adopted` sections; `--strategy` writes only the `product_directions` section. Without the flag, both modes are strictly print-only (plus `--save` to the gitignored report dir).
- **Human-gated + rare.** Suppress no-change / no-direction output to exactly one line; surface only actionable candidates. Both report types honor this W3 rarity contract (a report that fires every run gets ignored).
- **Dedup, so re-runs stay quiet.** Default mode skips items already in `known_not_adopted`; `--strategy` skips directions already in `product_directions` (status `adopted`/`proposed`/`deferred`).
- **Grounded, not generic.** Every default-mode candidate states why it matters for THIS plugin; every `--strategy` direction MUST cite ≥1 concrete product asset AND ≥1 newly-feasible enabler or it is dropped.
- **Advisory.** Candidates and directions are suggestions, not obligations — subordinate to the maintainer's judgment.

## See Also
- `docs/CAPABILITY_BASELINE.json` — the tracked baseline this command diffs against (default mode) and the home of the `product_directions` section (`--strategy` mode; schema defined above under "The `product_directions` baseline contract").
- `skills/brainstorming/SKILL.md` — the 5-lens scored-debate framework `--strategy` reuses as its bounded ideation engine (B3).
- `skills/mvp-scoping/SKILL.md` — the effort/feasibility prioritization lens cited by the `--strategy` scoring rubric (B4).
- `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` — the flywheel (§0d) and on-demand-first / rare+actionable discipline (§4.1, §4.4, §7) that both modes preserve.
- Self-evolution design — on-demand first; the **scheduled-scanner** variant is deferred to **P5** behind four guardrails (durable cadence under a 7-day expiry, explicit per-run budget, circuit breaker on repeated failures, heartbeat). See the v14.6.0 entry in `CHANGELOG.md`.
- `commands/launch-pad.md` / `commands/supervisor.md` — how to actually adopt a reviewed candidate or pursue a reviewed direction.
- `commands/dreaming.md` — the inward-looking counterpart (learns from past runs); `/capability-check` is the outward-looking one (learns what Claude Code newly offers, and — with `--strategy` — where the product should head next).
