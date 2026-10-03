# 10 — Design-system substrate: production-quality UI via system, not per-screen improvisation (P1 product bet)

## Goal
Make Loomwright produce coherent, production-grade UI out of the box by mirroring the
house-rules architecture for design: a committed design-system SUBSTRATE created before any
screen is built, a DO-side seam that injects it into UI workers, a REVIEW-side design-
consistency lens in Code Reviewer, and (optional outer loop) visual verification against it.

## Problem statement / evidence
- Bare Claude Code ≈ Loomwright on UI tasks today: the plugin adds zero design capability.
  `skills/frontend-ui/` exists but NO agent preloads it — workers never see it (verify
  against current agent frontmatter before building).
- No design-system artifact exists anywhere in the flow; each worker in its own worktree
  invents spacing/colors/layout per subtask. Parallel workers produce divergent design
  dialects that merge into one app — the plugin's parallelism makes UI consistency WORSE.
- Phase 4.5 reviews diffs for code correctness; nothing ever checks "does this match the
  rest of the app?" Owner-reported failure list is all consistency properties: spacing,
  alignment, hierarchy, grid, reuse-not-reinvent, responsive discipline, token consistency.
- Architectural precedent to copy: `.agent/rules/` substrate (v14.51.0) + 3 advisory
  enforcement seams (v15.1.0) — substrate → DO-side injection → REVIEW lens, all advisory,
  fail-safe, subordinate to CLAUDE.md.

## Scope — four parts, shippable as separate slices (substrate first)

### Part A — SUBSTRATE: `/design-system` command + committed artifacts
New command (21→22) + protocol skill (`design-system`, 57→58) producing committed files:
- `design/tokens.json` — spacing scale, type scale (family/sizes/weights/line-heights),
  color palette with SEMANTIC roles (primary/surface/border/danger/muted...), radii,
  shadows, breakpoints, z-index scale. JSON so seams can jq it (array/object parse-gate,
  same discipline as `.agent/rules/`).
- `design/DESIGN_SYSTEM.md` — layout grid rules, component inventory (name, purpose,
  when-to-use, path), composition patterns, visual-hierarchy rules, responsive strategy,
  accessibility floor (WCAG 2.1 AA — reuse frontend-ui content, don't duplicate).
Two modes:
- `extract` (brownfield): scan tailwind.config/CSS vars/theme files/component dirs →
  propose tokens + inventory; human confirms before write (per-item accept, /dreaming UX
  precedent).
- `init` (greenfield): opinionated bootstrap. NOT generated-fresh-per-run: offer 3–4
  CURATED preset design personalities (e.g. editorial — serif display type, generous
  whitespace; dense-product — compact spacing, utilitarian; soft-consumer — large radii,
  warm neutrals), each a complete internally-tuned token set + matching craft defaults,
  authored ONCE with real care and shipped as fixtures in the skill. AskUserQuestion picks
  personality + brand color + font override; init instantiates the preset. Curation gives
  best-authorable taste reused forever; per-run generation gives average taste — this is
  what makes "out of the box" true when the user has nothing, and preset quality is the
  single highest-leverage investment in the whole item.
Sole-writer script `scripts/design-system-write.sh` (atomic temp-mv, parse-gate, path
containment under `design/` — clone add-rule.sh discipline) + `scripts/read-design-system.sh`
fail-safe reader (absent/malformed ⇒ silent empty output, NEVER blocks; never executes
anything; clone read-rules.sh contract) + `test-*.sh` for both.

### Part B — DO-side seam: workers consume the system
- In supervisor fast-path spawn + execute-manager parallel spawn (the exact two spots where
  read-rules.sh is injected today): when the subtask's impact map touches UI paths
  (heuristic: components/, pages/, app/, *.tsx/jsx/vue/svelte/css — define the glob set in
  the skill), inject the reader's digest (tokens summary + component inventory) into the
  worker prompt with the core discipline: reuse inventory components; only token values for
  spacing/color/type; a new component or non-token literal requires a one-line
  justification in WORKER_RESULT (additive optional field `design_deviations[]` — no
  schema_version bump; nullable-required presence-check discipline in the validator prompt).
- The digest carries THREE blocks, not just tokens: (1) tokens summary + component
  inventory; (2) a ~30-line CRAFT block — the un-mechanizable taste rules injected only on
  UI subtasks: one display + one body font, hierarchy via size AND weight AND color
  together, never center-align body text blocks, real content over filler-shaped lorem,
  restraint on gradients/shadows, whitespace as a first-class tool (source the block from
  the preset personality so craft rules match the chosen system); (3) exemplar pointer —
  see the exemplar-first step below. Taste can't be review-checked mechanically, so the
  DO-side prompt is the only place it can live.
- Preload `frontend-ui` into the worker agent for UI work OR (cheaper) fold the essential
  rules into the injected digest — decide at plan time by token cost; do NOT preload the
  full skill into every worker unconditionally.
- **Exemplar-first sequencing (highest-impact single mechanism):** for multi-screen UI
  goals, Orchestrator emits subtask 1 = "build the REFERENCE screen" (the most
  representative page), SEQUENTIAL — it blocks the parallel fan-out via the existing
  dependency graph. Optional human look-gate on it (AskUserQuestion: "this is the
  direction — OK?", skipped under --non-interactive as an advisory, never a blocker).
  Every subsequent UI worker's digest then includes the reference screen's file path(s) as
  the canonical example to MATCH. Models imitate a concrete exemplar far better than they
  follow abstract rules — this converts worktree parallelism from a divergence liability
  into N workers copying one approved reference. Wire it as an Orchestrator planning rule
  in the design-system skill, not a Supervisor phase change.
- **Worker visual self-check (Part D-lite, ships with Part B):** when the app is runnable
  in the worktree, the UI worker screenshots its own screen (1280 + 375) and self-critiques
  against the digest (overflow, cramped spacing, misalignment, hierarchy) BEFORE emitting
  WORKER_RESULT — catches "token-compliant but visually broken" at the cheapest point,
  inside the worker's own loop. Degrades to skipped (=UNVERIFIED, not clean) when the app
  isn't runnable; never blocks.
- Launch Pad: when the goal is UI-shaped and no `design/` exists, Phase 2.5 emits a CAUTION
  advising `/design-system init` first (advisory, never NO-GO on this alone).

### Part C — REVIEW-side lens: design-consistency category
- Code Reviewer: for diffs touching UI paths, add a design-consistency check (mechanical,
  no vision needed): raw hex/px/rem literals not in tokens.json → finding; new component
  duplicating an inventory entry → finding; missing responsive handling where the diff adds
  layout → finding. Reuse the existing `drift` category or add `design_drift` kind —
  decide at plan time; if a new issue category is added, CODE_REVIEW_RESULT goes v3→v4
  (legacy accepted), hooks.json validator prompt updated in the same change.
- Advisory severity cap: design findings cap at MEDIUM in v1 (never BLOCKING) — the seam
  must not gate until proven (bimodal invariant: this is advisory, not a gate).

### Part D — outer visual loop (optional, separate slice; supersedes the earlier
"ui-fidelity" sketch)
`## Visual Acceptance` optional brief section (reference image path + route + viewports);
when present, Phase 4.5 runs: Playwright screenshot at 1280/768/375 → vision-compare agent
Reads mock + screenshot + tokens.json → structured findings (region/expected/actual/
severity) → bounded fix loop (heal-iterations semantics) → MATCH / ACCEPTABLE_DRIFT /
ESCALATED, advisory, recorded in SUPERVISOR_RESULT.summary + job Outcome (red-team-lens
precedent). Requires the app to be runnable — degrade to skipped (=UNVERIFIED, not clean)
when it isn't.

## Constraints / invariants
- All seams advisory + fail-safe: missing/malformed design/ files change NOTHING; no seam
  alters heal_decision or blocks a PR; subordinate to CLAUDE.md and to `.agent/rules/`.
- Sole-writer, atomic writes, parse-gates, no reader ever executes content.
- Counts: +1 command, +1–2 skills → full doc-currency sweep + blind-spot greps.
- Run through /product-owner + /launch-pad first (design decisions: token schema shape,
  UI-path glob set, extract-mode heuristics, Part C category choice). Slice order A → B →
  C → D, one PR each.
- Honest limit stated in docs: the substrate enforces CONSISTENCY and reuse; per-screen
  taste comes from the three taste mechanisms above (curated presets, craft block,
  exemplar-first) — invest there (steal patterns from the frontend-design skill's
  guidance: distinctive type pairing, restrained palette, real spacing rhythm).
- **Learning loop (ties to item 08):** `design_deviations[]` entries and design-drift
  review findings feed curation — recurring justified deviations graduate into
  tokens/components via `/design-system` (human-gated, /dreaming per-item-accept UX);
  recurring UNjustified ones become new craft-block rules. Without this the system is
  frozen at init quality; with it, design judgment accumulates like rules/lessons do.
  V1 scope: just ensure deviations land somewhere /insights can surface (one advisory
  section); the graduation verb can ship with item 08's curation machinery.

## Acceptance criteria
- [ ] `/design-system init` on an empty repo yields committed tokens.json +
      DESIGN_SYSTEM.md that pass their own parse-gates; `extract` proposes-then-confirms.
- [ ] A UI subtask worker prompt demonstrably contains the digest (seam test mirroring
      test-rules-seams.sh: seams reference read-design-system.sh, never the writer, never
      pipe reader output to a shell).
- [ ] `init` offers ≥3 curated preset personalities; each preset's tokens.json passes the
      parse-gate and its craft block is preset-specific.
- [ ] On a multi-screen UI goal, the Orchestrator plan shows the reference-screen subtask
      blocking the UI fan-out, and a later worker's digest cites the exemplar path.
- [ ] Code Reviewer flags a planted non-token hex + duplicate component in a fixture diff.
- [ ] End-to-end proof: same 2-screen UI goal run twice — with and without design/ present —
      and the with-substrate run shows measurably fewer raw literals + reused components
      (record in the PR as the first fidelity datapoint).
- [ ] All CI gates green; counts swept.

## Out of scope
Pixel-perfect guarantees, generating Figma-quality mocks, theming/dark-mode machinery,
Part D auto-run without `## Visual Acceptance`, gating severities for design findings.
