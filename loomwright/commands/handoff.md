---
description: Catch up / hand off in 2 minutes — a unified, read-only digest (decision · why · tried/rejected · current state · provenance, with freshness) over the plugin's continuity surfaces
---

> **Read-only on your work; writes only a derived digest.** `/handoff` reads the continuity surfaces the plugin already wrote (`.supervisor/jobs/`, `.supervisor/autonomous/`, `.supervisor/automate/`, `.supervisor/state.md`, plus verified project memory / lessons via the sanctioned `read-project-memory.sh` / `read-lessons.sh` readers) and writes a derived digest to `.supervisor/handoff/digest.md` (gitignored). It touches no code, no agent, no state-of-truth surface, sends nothing anywhere, and always exits 0.

# Command: /handoff

> **This is the plugin's recency-focused _per-work-item catch-up view_** — it assembles ONE unified digest a second person can inherit to pick up where you left off in ~2 minutes. It is distinct from `/insights` (which computes run *trends / aggregates*) and `/obsidian` (which projects to an external *vault*): `/handoff` is the per-work-item, newest-first handoff view.

## Purpose

When you (or a teammate) come back to a project, the knowledge needed to continue is **fragmented** across many surfaces the plugin writes: Supervisor jobs (`.supervisor/jobs/`), autonomous runs (`.supervisor/autonomous/`), automate runs (`.supervisor/automate/`), the active session (`.supervisor/state.md`), and verified project memory / lessons (`.supervisor/memory/`, surfaced via the sanctioned readers). There's no single place to see *what was decided, why, what was tried and rejected, where it stands now, and how stale that is.* `/handoff` unifies them into ONE recency-focused, **per-work-item** view — mode-agnostic across Supervisor / autonomous / automate work — so a second person can inherit the context without spelunking through directories.

## Usage

```bash
/handoff                # Rebuild the digest (default — unchanged, byte-for-byte, since the flag below shipped)
/handoff --publish      # ALSO write a shareable, point-in-time snapshot alongside the digest
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--publish` | No | off | **Opt-in.** Emits the existing digest a second time as a shareable **snapshot** at `.supervisor/handoff/snapshot.md` — the same what-shipped / what-was-decided / what-was-tried-and-rejected / current-state / provenance content, wrapped in a banner that states its own generation time and explicitly disclaims polling: it is a static, point-in-time export, not a live view, and will not update itself. **Absent this flag, no new code path executes** — the default `digest.md` write is byte-for-byte identical to every pre-`--publish` release. The publish path writes only under `.supervisor/handoff/`; it never touches any source-of-truth surface (`.supervisor/jobs/`, `.agent/`, `.supervisor/postmortem/`, etc.). |

## What it does

Runs the deterministic assembler and reports where it wrote:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-handoff.sh"            # default
bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-handoff.sh" --publish  # with the opt-in flag
```

1. Assembles **ONE mode-agnostic digest** by interleaving work items across **Supervisor jobs** (`.supervisor/jobs/{pending,in-progress,done,failed}/*.md`), **autonomous runs** (`.supervisor/autonomous/<session_id>/`), and **automate runs** (`.supervisor/automate/*.md`) into a single newest-first list — not three per-mode digests.
2. For each item it shows the **five facets where derivable** — **decision · why · tried/rejected · current state · provenance** (the source artifact path it was drawn from) — plus a **freshness / basis line**. A facet that isn't derivable is omitted, never fabricated.
3. **Freshness is honest about its basis** — mtime and commit-SHA are **never conflated**. A commit-SHA comparison against current `HEAD` appears **only** when an artifact recorded an actual SHA in a structured trailer (match ⇒ fresh; mismatch ⇒ a hint showing both SHAs, never silently dropped). Otherwise (the common case — jobs / autonomous / automate / `state.md` carry no SHA) the basis is the artifact's mtime and freshness is reported as **unknown**, with no SHA comparison.
4. **Reuses the existing readers** — where it surfaces verified project memory / lessons it **calls** the sanctioned `read-project-memory.sh` / `read-lessons.sh` helpers rather than re-parsing those stores.
5. **Absent surfaces are silently skipped** (e.g. `.supervisor/automate/` does not exist on every repo); with no continuity surfaces at all it emits a benign "nothing to summarize yet" line. It then writes **`.supervisor/handoff/digest.md`** (gitignored) and **echoes the path**.
6. **With `--publish`** it additionally writes **`.supervisor/handoff/snapshot.md`** (also gitignored) — the digest content re-emitted as a shareable snapshot, framed as a static export rather than a live view, for handing to a teammate, pasting into a PR description, or archiving outside this checkout.

It always exits 0 — a digest tool must never break its caller. Re-run any time to refresh.

## Distinct from `/insights` and `/obsidian`

- **`/insights`** computes run **trends / aggregates** (work · quality · session performance, scoreboard-style) over the session logs.
- **`/obsidian`** projects continuity surfaces into an external Obsidian **vault** for browsing.
- **`/handoff`** is the recency-focused, **per-work-item catch-up view** — the one digest a second person reads to inherit the work. Use it when you need *state to continue*, not *trends to analyze* or a *vault to browse*.

## See Also
- `scripts/build-handoff.sh` — the deterministic, read-only digest assembler (the engine); `scripts/test-build-handoff.sh` — its self-test.
- `commands/insights.md` — the run *trends / aggregates* scoreboard; `commands/obsidian.md` — the external *vault* projection. `/handoff` is the per-work-item catch-up view distinct from both.
