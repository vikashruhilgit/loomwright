### Harness-memory pointer (on LESSONS Accept)

Whenever a per-item `Accept` (or the replacement half of a `Supersede`) persists a LESSON via `write-lessons.sh`, `/dreaming` additionally ensures **exactly ONE** idempotent pointer line exists in the repo's Claude-harness memory (the harness's own `MEMORY.md`/memory-index surface under `.claude/`), naming `.supervisor/memory/LESSONS.md` as the durable, machine-readable lessons store — for example, a line such as:

```
- [Verified project LESSONS](../../.supervisor/memory/LESSONS.md) — machine-readable, provenance-gated lessons written via /dreaming; read back by read-lessons.sh.
```

**This is a signpost, not a sync.** `/dreaming` is NOT copying lesson content into harness memory, NOT keeping the two in lockstep beyond this one line, and NOT writing one pointer line per lesson — it is a single, idempotent "look here" breadcrumb for the harness's own memory system, written once per repo and left alone on every subsequent Accept once it already exists (a plain string-presence check before writing, so re-running `/dreaming` many times never duplicates the line).

**Where and when this runs is load-bearing, not incidental:**

- It is documented here as executing **at `/dreaming` runtime, from the repo root** — `/dreaming` is an inline main-thread command (never Task-spawned into a worker), so it always runs at the repo root where `.claude/` actually exists and is writable.
- It must **never** be attempted from a worker worktree. Most of `.claude/` is **gitignored** — and the part that is not (`.claude/agent-memory/`, made committable by `/setup memory` since v15.25.0) is *still* the wrong target from a worktree, because the harness reads the store from the **repo root's** path. Either way a worktree's copy of it (if any) is not the real directory the user's harness reads, and a write there would be silently lost the moment `git worktree remove` runs. (Stated this way deliberately: the earlier phrasing rested on the unqualified claim that `.claude/` is gitignored, which stopped being true once the negation block landed — the conclusion survives, the old reason does not.) This is exactly the hazard `write-lessons.sh` itself guards against for `LESSONS.md`: it **hard-refuses to run from a git worktree, exiting 3** (see its own worktree-guard, closing red-team F1) — the harness-pointer write inherits the identical rationale even though it targets a different file, and `/dreaming`'s repo-root-only execution model is what keeps it consistent with that guard rather than fighting it.
- Because `/dreaming` never runs from a worktree in the first place, there is no separate flag or check needed here beyond stating the invariant plainly: this pointer write is a repo-root-only operation, full stop.

### Empty-state suppression

If, after dedup against existing project memory and after bounding LESSONS per category, there are **no new candidates and no new lessons**, `/dreaming` says so in a single line (e.g., "No new memory candidates or lessons after dedup/bounding — nothing to propose.") and **writes nothing**. This keeps reports rare and actionable rather than padding every run with already-known facts.

### APPLY deferral (v14.5.0 scope)

`/dreaming` v14.5.0 closes the **collect → distill → persist** loop only. **Reading LESSONS back into planning/execution** — injecting accepted lessons at Launch Pad / Supervisor decision time so they actually steer future runs — is intentionally **deferred to a follow-up**. v14.5.0 makes lessons durable and human-approved; wiring them into the forward pipeline is out of scope here.

