---
name: brainstorming
description: Multi-mind brainstorming framework with 5 expert lenses, structured debate, and idea scoring. Use when generating options, exploring solutions, or evaluating strategic directions.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-04"
---

# Multi-Mind Brainstorming Skill

Framework for structured ideation using 5 expert perspectives that independently analyze, challenge each other, and converge on scored recommendations.

## Quick Rules

- 5 lenses think independently BEFORE any cross-talk
- Debate is mandatory — consensus without conflict is shallow
- Score every surviving idea on 4 axes (1-10)
- Critic MUST find real flaws — if every lens agrees, Critic hasn't done its job
- No generic ideas — "add AI" without specifics is banned
- Recommendation needs rationale, not just highest score

## When to Use This Skill

- Exploring new product ideas or feature directions
- Evaluating multiple strategic options
- When the right solution isn't obvious and you need structured comparison
- Before writing user stories, to identify WHAT to build
- When stakeholders disagree on direction

## When NOT to Use

- Requirements are already clear — go straight to user stories
- Single obvious solution — just scope and build it
- Pure technical decisions — use engineering judgment, not 5-lens debate
- Trivial changes — don't brainstorm a button color

## The 5 Expert Lenses

### 1. Creative Thinker
- **Domain:** Innovation, lateral thinking, unconventional approaches
- **Mandate:** Generate bold ideas nobody else would suggest
- **Techniques:** "What if..." inversion, analogy from other industries, constraint removal
- **Constraint:** At least 1 idea must be genuinely surprising — not an incremental improvement

### 2. Product Manager
- **Domain:** User needs, market fit, adoption, prioritization
- **Mandate:** Filter ideas through real user problems and willingness to pay/adopt
- **Techniques:** Jobs-to-be-done, user journey friction, competitive positioning
- **Constraint:** Must identify WHO specifically wants this and WHY they'd switch from alternatives

### 3. Engineer
- **Domain:** Technical feasibility, architecture, implementation complexity
- **Mandate:** Evaluate how to build top ideas and what makes them hard or easy
- **Techniques:** System design thinking, build-vs-buy, dependency analysis
- **Constraint:** Must give honest complexity ratings (S/M/L/XL with time estimates) — no "it depends"

### 4. Business Strategist
- **Domain:** Monetization, growth, competitive advantage, unit economics
- **Mandate:** Find the money — how does this become a business, not just a feature?
- **Techniques:** Revenue models, moats, CAC/LTV thinking, go-to-market
- **Constraint:** Must identify at least one non-obvious revenue or growth path

### 5. Critic
- **Domain:** Risks, failure modes, blind spots, devil's advocacy
- **Mandate:** Find why each idea fails in the real world. Be the hostile investor
- **Techniques:** Pre-mortem, edge case analysis, competitive response, "what kills this?"
- **Constraint:** Must specifically challenge the top-rated idea. No softball criticism

## 5-Phase Framework (Phase 3.5 Reality Check added)

### Phase 1: Independent Lens Analysis

Each lens independently generates 3-5 options from their perspective. No cross-talk.

```markdown
### Creative Thinker
1. **[INCREMENTAL/DISRUPTIVE/MOONSHOT] Idea Title** — 2-3 sentence description
2. ...

### Product Manager
- Target segments: [who]
- Current alternatives: [what they do today]
- Switching triggers: [what makes them move]
- Top options aligned with user pain: [list]

### Engineer
- For each promising idea:
  | Idea | Complexity | Time Est. | Key Risk | Approach |
  |------|-----------|-----------|----------|----------|
  | ...  | S/M/L/XL  | ...       | ...      | ...      |

### Business Strategist
- Revenue model options: [list with rationale]
- Competitive gaps: [where market is underserved]
- Growth levers: [viral, SEO, partnerships, etc.]
- Unit economics sketch for top option

### Critic
- For each idea: top 2-3 failure modes
- Market timing risks
- Execution risks
- Graveyard: similar ideas that failed and why
```

### Phase 2: Cross-Challenge

Lenses directly challenge each other. Each challenge must:
- Name the specific idea being challenged
- State the specific objection
- End with one of:
  - **CONCEDE:** "Fair point. Modified idea: ..."
  - **DEFEND:** "No, because [specific reason]..."
  - **PIVOT:** "Instead, what about [new synthesis]..."

**Required matchups:**
1. Critic challenges Creative's boldest idea
2. Engineer challenges PM's top pick on feasibility
3. PM challenges Business on user experience impact of monetization
4. Business challenges Engineer on build time vs market window
5. Creative defends or pivots based on Critic's attack

```markdown
### Debate Round

**Critic → Creative:** "Your idea X fails because [specific reason]..."
Creative: **PIVOT** — "Modified version: [synthesis]"

**Engineer → PM:** "Users want Y but it requires [complexity]..."
PM: **CONCEDE** — "Revised priority: [adjusted option]"

[etc.]
```

In `--brainstorm deep` mode: run a second debate round after initial scoring, focusing on the top 3 ideas only.

### Phase 3: Scoring

Rate every surviving idea on 4 axes (1-10):

| Idea | Impact | Feasibility | Revenue | Uniqueness | Composite |
|------|--------|-------------|---------|------------|-----------|
| ...  | 1-10   | 1-10        | 1-10    | 1-10       | weighted  |

**Composite formula:**
`Composite = (Impact × 0.30) + (Feasibility × 0.25) + (Revenue × 0.25) + (Uniqueness × 0.20)`

**Scoring rubric:**

| Score | Impact | Feasibility | Revenue | Uniqueness |
|-------|--------|-------------|---------|------------|
| 10 | Life-changing for users | Ship this week | Obvious willingness to pay | Category creator |
| 7-9 | Significant improvement | 1-4 weeks to MVP | Clear revenue path | Strong differentiator |
| 4-6 | Nice to have | 1-3 months | Revenue possible but unclear | Some differentiation |
| 1-3 | Marginal value | 6+ months or major unknowns | No clear revenue path | Commodity / me-too |

### Phase 3.5: Reality Check (Grounded Feasibility)

**Why:** The Engineer lens scores Feasibility abstractly. Without codebase grounding, infeasible ideas can score 8/10 and get locked into stories. A prior real-world example: a Dispatcher Agent idea scored highly but had 6 architectural blockers already in the codebase (interactive agent flows, non-uniform result contracts, state ownership conflicts) that the abstract score missed.

**Tool contract:** This skill stays `allowed-tools: [Read]`. The **invoking agent** (e.g., Product Owner, which has `Read, Glob, Grep, Bash`) performs the codebase grounding described here.

**Actions (for top 2-3 scored ideas only):**

1. **System Architecture Check** — Read CLAUDE.md + key agent/module files. Does the idea fit the current design?
2. **Prerequisite Detection** — Identify foundation work required BEFORE the idea works
3. **Contract Compatibility** — If the idea touches existing contracts (result schemas, state ownership, agent interfaces), check them
4. **Interaction Model** — Does the idea require behaviors the current system doesn't support (e.g., non-interactive mode, background execution, unattended chaining)?

**Verdict per idea:**
- **VIABLE** — buildable with current system as-is
- **NEEDS_FOUNDATION** — requires prerequisite work first (specify prerequisites)
- **BLOCKED** — architectural mismatch; would require fundamental redesign before this idea is feasible

**Score caps (applied to Feasibility axis; composites recomputed):**
- VIABLE → no change
- NEEDS_FOUNDATION → cap Feasibility at 5; append prerequisites to trade-offs
- BLOCKED → cap Feasibility at 2; flag as "requires rearchitecture"

**Output table:**

| Idea | Verdict | Blockers/Prerequisites | Feasibility Cap Applied |
|------|---------|------------------------|-------------------------|
| [A]  | VIABLE | — | — |
| [B]  | NEEDS_FOUNDATION | [list] | capped at 5 |
| [C]  | BLOCKED | [list] | capped at 2 |

After caps, **re-rank** top 3 by composite.

**Rule:** The Recommendation (Phase 4) uses the post-Reality-Check ranking, not the raw Phase 3 scores.

### Phase 4: Recommendation

For the top 3 ideas by composite score:

```markdown
### Top Options (Ranked)

**#1: [Idea Title]** (Composite: X.X)
- Champion: [which lens]
- Why it wins: [1-2 sentences]
- Key trade-off: [what you sacrifice]
- Biggest remaining risk: [from Critic]

**#2: [Idea Title]** (Composite: X.X)
[same format]

**#3: [Idea Title]** (Composite: X.X)
[same format]

### Recommendation
[Which option to pursue and why — not just "highest score" but reasoned judgment]

### MVP Scope (for recommended option)
- Core features (3-5 max): [list]
- Explicitly excluded: [what to leave out]
- Timeline estimate: [rough]
- Key validation step: [how to test demand before building]

### Next Steps
- Quick wins (this week): [2-3 items]
- Long-term bets (compounds over time): [2-3 items]
- Who to talk to: [validation targets]
```

## Depth Modes

| Mode | Flag | Debate Rounds | Ideas per Lens | Market Research | Output Size |
|------|------|---------------|----------------|-----------------|-------------|
| Standard | `--brainstorm` | 1 round | 3-5 | No | ~1,500 words |
| Deep | `--brainstorm deep` | 2 rounds | 5-7 | Yes (WebSearch) | ~3,000 words |

## Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| "Add AI/blockchain/gamification" | Generic, not specific | Describe the specific mechanism and why it works here |
| Echo chamber | All lenses agree immediately | Critic must find real flaws; force at least 2 CONCEDE/PIVOT outcomes |
| Skipping debate | Premature consensus | Debate is mandatory — it refines ideas |
| All 10/10 scores | Dishonest scoring | A 10 on Feasibility means "ship today" — be honest |
| Recommending everything | No prioritization | Pick one winner with rationale |
| Ignoring Critic | Optimism bias | Critic's top concern must be addressed in recommendation |
| Solutions without users | Building for no one | PM must name specific users and their current alternative |

## Quality Checklist

Before emitting recommendation:
- [ ] All 5 lenses contributed independently (not just echoing each other)
- [ ] At least 1 debate exchange resulted in CONCEDE or PIVOT (real conflict happened)
- [ ] Critic specifically challenged the top-rated idea
- [ ] No generic ideas survived scoring (each is specific and actionable)
- [ ] Scores are honest (no idea scores 10/10 on everything)
- [ ] Recommendation has rationale beyond "highest score"
- [ ] MVP scope is actually minimal (3-5 features, not 15)
- [ ] Next steps are concrete (not "do more research")
- [ ] Reality Check (Phase 3.5) performed on top 2-3 ideas with codebase-grounded verdicts (VIABLE/NEEDS_FOUNDATION/BLOCKED)
- [ ] Feasibility score caps correctly applied (NEEDS_FOUNDATION ≤ 5, BLOCKED ≤ 2)
- [ ] Recommendation uses post-Reality-Check ranking, not raw Phase 3 scores

## Related Skills

- `skills/product-discovery/SKILL.md` — Problem understanding before ideation
- `skills/mvp-scoping/SKILL.md` — Prioritizing features after ideation
- `skills/user-story-writing/SKILL.md` — Formalizing the winning idea into stories
