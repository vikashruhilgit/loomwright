---
name: attack-sole-writer-worktree-ban
description: .supervisor/{state.md,twin,memory,lessons} each have one repo-root writer that refuses a worktree CWD; flag any direct/worktree write
metadata:
  type: project
---

`.supervisor/{state.md, twin/, memory/, lessons}` each have exactly ONE repo-root writer script that refuses a worktree CWD; workers/agents only PROPOSE.

**Why:** Worktree-relative writes don't reach the canonical store and corrupt shared state; the writer-refuses-worktree backstop is named "red-team F1" in system-twin-foundation.

**How to apply:** Flag any agent or script that writes `.supervisor/{twin,memory,state.md,lessons}` directly (not via `write-system-contract.sh` / `write-project-memory.sh` / `write-lessons.sh` / Context-Keeper for state.md), OR any writer script missing a worktree-CWD refusal. Context-Keeper is sole writer of `state.md` ONLY — it is explicitly out of the twin/memory write path.
