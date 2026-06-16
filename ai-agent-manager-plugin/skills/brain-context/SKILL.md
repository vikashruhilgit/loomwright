---
name: brain-context
description: Read-on-demand brain-aware context enrichment (Graphify graph + brain wiki). Advisory only — a missing/broken/stale graph silently falls back to grep/read; NEVER blocks a run and NEVER changes a decision. Deliberately NOT preloaded into any agent frontmatter; agents read it at context-setup / analysis points when a brain is detected.
version: 1.0.0
lastUpdated: 2026-06-16
allowed-tools: Read, Bash, Grep
---

# Brain-Context Skill (read path)

This skill is the single source of truth for the **read path** of brain integration: how an
agent enriches its codebase understanding from a knowledge brain (Graphify `graph.json` +
the brain's `wiki/`) when one is detected, and how it degrades to plain grep/read when one
is not. It encodes the staleness rule from `docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md` §3 —
the correctness keystone of the whole initiative.

**HARD ADVISORY CONTRACT (applies to everything in this file):** brain integration is
**advisory and fails SAFE.** Nothing here ever blocks a run, fails a task, or changes a
`heal_decision` / review verdict / plan. A missing, broken, empty, low-confidence, or stale
graph ⇒ silently fall back to the existing grep/read flow and continue. This matches the
plugin's bimodal rule — correctness gates fail CLOSED, but side-effect/advisory emitters
(telemetry, webhook, the brain read path) fail SAFE and never disrupt the run.

**When to read this file:** an agent reads it on demand at its context-setup / analysis
point when a brain is detected (see Detection below). It is **deliberately NOT in any
agent's preloaded `skills:` list** — preloading would re-inject this content into 6+ agents
at spawn time (token bloat), and most runs touch no brain at all. On-demand reading keeps
agent prompts focused; mirror `self-heal-advisory` (Supervisor Phase 4.5 reads that on
demand for the same reason).

---

## Detection

Before any brain query, detect whether a brain is reachable. There are two independent
signals; **either, both, or neither** may be present — degrade gracefully in all four cases.

```bash
# Signal 1 — local graph in the current repo (symlink or real file both count).
test -e graphify-out/graph.json && echo "GRAPH_PRESENT"

# Signal 2 — configured brain root with a wiki.
[ -n "$AI_AGENT_MANAGER_BRAIN_ROOT" ] && test -d "$AI_AGENT_MANAGER_BRAIN_ROOT/wiki" && echo "BRAIN_ROOT_PRESENT"
```

Detection matrix:

| `graphify-out/graph.json` | `AI_AGENT_MANAGER_BRAIN_ROOT` (+ `wiki/`) | Behavior |
|---|---|---|
| present | set & valid | full read path: graph → wiki → raw |
| present | unset/invalid | graph queries available; skip the wiki step |
| absent | set & valid | wiki rationale available; graph step falls back to raw |
| absent | unset/invalid | **no brain** — behave exactly as today (grep/read only) |

Detection failure of any kind (path missing, env unset, `test` non-zero) is **never an
error** — it just narrows or disables the brain steps. The "neither" row is the default for
the vast majority of repos and must be a silent no-op.

> **Scope note — root-level agents only.** Signal 1 (`test -e graphify-out/graph.json`) is
> **cwd-relative**, so this skill is intended for agents that run at the repo root (Launch Pad
> Phase 2, Code Reviewer, Supervisor Phase 1.5/2/4.5). Workers operate inside isolated git
> worktrees where a `graphify-out/` symlink generally will not resolve — detection there simply
> returns "no brain" and the worker proceeds on grep/read (which is correct: a worker is editing
> uncommitted code the graph can't describe anyway). The `AI_AGENT_MANAGER_BRAIN_ROOT` signal is
> absolute and works from any cwd.

---

## Query order (graph → wiki → raw)

When a brain is detected, answer structural questions in this order, **stopping early** and
**falling back to raw read** the moment the staleness rule (below) or a low-confidence
result says so:

1. **Graph (`graphify-out/graph.json`)** — for *committed* structure only: "what connects to
   what", "where does concept X live", "blast radius of changing Y", "what calls Z". Scope a
   broad/generic term with the **graphify CLI's** `--graph <repo>` flag first to avoid
   cross-repo collisions. If the
   query returns empty or low-confidence (see definition below), **fall through to step 3**.
2. **Wiki (`$AI_AGENT_MANAGER_BRAIN_ROOT/wiki/`)** — for *rationale*: why a decision was made,
   what a community/concept means. See "Wiki access" below. A stale or unanchored note is a
   **caution, not a fact**.
3. **Raw (Read/Grep on the working tree)** — the ground truth and the universal fallback.
   **Mandatory** for any file this session is editing or will edit (staleness rule), and the
   fallback whenever step 1/2 is absent, empty, low-confidence, or stale.

The graph and wiki are accelerators on top of raw read — never a replacement for it. If in
doubt, read raw.

---

## The staleness rule (correctness keystone)

A graph-first agent that trusts a stale graph is *worse* than a grep-first one. Encode this
verbatim (intent from `docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md` §3):

- **Use the graph for:** "what connects to what", "where does concept X live", "blast radius
  of changing Y", "what calls Z" — over the **committed** codebase.
- **The graph is authoritative ONLY for committed structure, NEVER for any file the current
  session is editing or will edit.** Graphify reflects the last commit; the plugin edits in
  uncommitted worktrees, which are invisible to the graph. Any file the session will touch is
  **read raw, every time.**
- **Fallback triggers (read raw / grep):**
  (a) no `graphify-out/graph.json` present;
  (b) the graph query returns empty or low-confidence;
  (c) you are about to edit the file.
- **"Low-confidence" defined for Graphify output** (so trigger (b) is testable, not vibes):
  treat a graph answer as low-confidence — and fall back to raw read — when **ANY** of:
  - the query returns **no nodes**;
  - the traversal is **too broad** (a generic term like `match`/`court`/`score` that collides
    across repos — scope by `--graph <repo>` first, per the brain's `hot.md` warning);
  - the matched **nodes** carry **no cited `source_location` / `source_file`** — node hits are
    anchored to real code by these fields (Graphify stamps `source_*` on nodes); their absence
    means the answer isn't anchored;
  - the governing **`confidence` / `confidence_score`** is weak (Graphify stamps `confidence:
    EXTRACTED` plus a numeric score). **Read confidence from whichever graph element the answer
    rests on, per the graph's actual schema** — for a relationship/path answer ("what calls Z",
    blast-radius traversals) it typically lives on the **relationship/path edges**, not on the
    nodes; node hits are judged by their `source_*` anchoring above. Do **not** assume a single
    fixed location — inspect `graph.json` to confirm where `confidence` / `confidence_score`
    actually sit before trusting a numeric threshold. The brief pins the exact threshold against
    real query output.
- **Staleness signal — use the graph's own metadata, NOT `git log` on the file.** The graph
  file is gitignored + symlinked in a configured-brain layout, so `git log
  graphify-out/graph.json` tracks nothing in the app repo. Instead read the graph's embedded
  `built_at_commit` field (the `graph.json` ends with `"built_at_commit": "<sha>"`) and
  compare it to the repo's current HEAD / the commits touching the queried path:

  ```bash
  # Resolve the graph location by wiring mode (local file, symlink target, configured
  # BRAIN_ROOT, or MCP) — never assume graphify-out/graph.json is a tracked path in the app repo.
  built_at=$(grep -o '"built_at_commit"[[:space:]]*:[[:space:]]*"[^"]*"' graphify-out/graph.json | grep -o '[0-9a-f]\{7,\}')
  head=$(git rev-parse HEAD 2>/dev/null)
  # If HEAD has advanced past built_at for the queried path, downgrade graph answers to
  # "hint" and verify against source. Advisory — never an error.
  ```

  If HEAD has advanced past `built_at_commit` for that path, **downgrade graph answers to a
  "hint"** and verify against source. The comparison branches by wiring mode (local graph
  file, symlink target, configured `BRAIN_ROOT`, or MCP) — resolve the graph location
  accordingly. This is advisory — never an error.

---

## Wiki access

When `AI_AGENT_MANAGER_BRAIN_ROOT` is set and contains `wiki/`, search it for **rationale**
(why, not just where):

```bash
# Search the trusted wiki for a concept's rationale note (skip _drafts/ — those are untrusted).
grep -rl --include='*.md' "<concept or symbol>" "$AI_AGENT_MANAGER_BRAIN_ROOT/wiki/" \
  | grep -v '/_drafts/'
```

Each trusted note carries provenance frontmatter — `source`, `confidence`, and
`last_verified`. Use them as a trust filter, not a rubber stamp:

- A note with a **stale `last_verified`** (well behind the repo's current state) or a
  **broken `source:` anchor** (the cited file/line no longer exists) is treated as
  **low-confidence context — surfaced as a caution, not a fact.** Verify against live code
  before relying on it.
- When the brain's own wiki concept-graph exists (a `graphify-out/graph.json` *at the brain
  root*), it may be queried for symbol→rationale hops — but the same low-confidence and
  staleness rules apply to it.
- Anything under `wiki/_drafts/` is **untrusted** (plugin-authored drafts awaiting a brain-side
  PR) — never cite it as authority.

A wiki miss, an unreadable note, or absent provenance is a silent no-op — fall back to raw.

---

## Usage in agents

- Invoked **on demand** at an agent's context-setup or analysis point — e.g. the shared
  `context-setup` entry point, Launch Pad Phase 2 codebase analysis, Code Reviewer
  blast-radius / consistency-audit context, and Supervisor Phase 1.5/2 + Phase 4.5 self-heal
  review context. The agent reads this file only after Detection finds a brain.
- **This skill is NOT preloaded into any agent's frontmatter `skills:` list** (mirror
  `self-heal-advisory`). Adding it to a `skills:` preload is a regression against the
  on-demand-only rule: it would re-inject this content into every spawn of those agents
  (token bloat) even on the common no-brain run. Wiring is by prompt reference ("read
  `skills/brain-context/SKILL.md` when a brain is detected"), never a preload entry.
- The behavior lives in this skill prompt — **do not depend on any grep-before-graph hook.**
  That hook lives only in a brain owner's *global* `~/.claude/settings.json`, is not shipped
  in either repo, and `/setup brain` may *optionally* install it as a nudge.

---

## Token budget

Like other read-on-demand skills (`self-heal-advisory`, `review-heal`, `memory-tool`), this
file is read only when relevant and is **never preloaded** — so it costs zero spawn-time
tokens on the common path and is read once, on demand, only when a brain is actually
detected. Keep queries scoped (use `--graph <repo>` and targeted grep) so the enrichment
stays a net token *saving* over blind grep sweeps, not an addition.

---

## See Also

- `docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md` — §2 (invariants), §3 (staleness rule), Phase 1
- `skills/context-setup/SKILL.md` — the shared entry point that references this skill on demand
- `skills/self-heal-advisory/SKILL.md` — the read-on-demand / not-preloaded pattern this mirrors
