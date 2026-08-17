# Code-graph validation harness (frozen spike snapshot)

**What this is:** the reusable validation harness kept from the code-graph ownership spike
(`../CODE_GRAPH_OWNERSHIP.md`) — the one deliverable that survived the spike's own FAILED
ranking validation, committed here so the graphify-tier **reversal condition** (below) cites
only files that survive a `git clone`.

## What the harness validates

Edge precision + ranking validity of a repo-map/code-graph against an **INDEPENDENT ground
truth**: the real TypeScript import graph (`import ... from '...'`). Imports are deterministic
and verifiable, and are extracted by a *different* method than the graph's own
type-identifier matching — so agreement is real validation, not circular (read `validate.py`'s
module docstring for the exact scoring definitions):

- **edge precision** — of the graph's edges (A uses a type defined in B), what fraction are
  backed by a real import A→B (catches coincidental/false edges);
- **ranking validity** — do the graph's top files by PageRank match the most-imported files
  (independent importance signal)? top-N overlap + Spearman.

`validate_gen.py` generalizes the same check across languages (TS monorepo, Dart/Flutter);
`reposcan_multi.py` is the bundled scanner engine module both scripts `import` — the harness
is a 3-file closure, and committing fewer than all three ships an unrunnable harness.

## External deps + invocation

Requires `tree-sitter` and `tree-sitter-typescript` (Python packages), not vendored here:

```
uv run --with tree-sitter --with tree-sitter-typescript python3 validate.py <root>
uv run --with tree-sitter --with tree-sitter-typescript python3 validate_gen.py <root> <ts|dart>
```

Run from this directory (both scripts `import reposcan_multi` from the CWD/sys.path).

## Provenance

Copied **verbatim** on 2026-08-17 from the gitignored code-graph spike scratch directory
(`.supervisor/scratch/code-graph-spike/`, verified byte-identical with `cmp` at copy time).
This is a **frozen snapshot, not maintained plugin runtime** — deliberately placed under
`docs/SPIKES/` so no CI `test-*.sh` glob and no prompt-token budget picks it up, and so it
implies no operational support. Do not edit the `.py` files in place; a future revival forks
them.

## THE REVERSAL CONDITION

The graphify/bridge tier was retired (2026-08-17) because of its **maintenance model** —
expensive deliberate rebuild, gitignored artifact, silent degradation: the staleness trap
`NORTH_STAR_DIRECTION.md` named, fallen into by the tier itself. Any revival of
concept-retrieval must therefore:

1. **Be a cheap incremental refresh** — never a manual/deliberate rebuild step a human must
   remember to run; and
2. **Pass this harness** — ranking validated against an independent ground truth (the real
   import graph), per the scoring above.

Per settled owner decision (h) of the retirement job, this condition governs
**external-brain revivals too** (`LOOMWRIGHT_BRAIN_ROOT` / wiki-path variants), not only a
local graph rebuild: the measured fact that settled the tier — `brain_context` consumed 0
times across all session logs — covers the whole rung, external path included.
