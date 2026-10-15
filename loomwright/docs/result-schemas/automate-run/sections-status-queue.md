### Section reference

| Section | Required | Notes |
|---|---|---|
| `# Automate Run: <title>` | yes | The run title (H1). **Load-bearing:** RESUME keys on this line (`is_run_file`, matched line-anchored anywhere in the file) to tell a run file from the §6 result sidecars in the same directory — a run file without it is never offered for resume. Writers emit the exact form above; readers also accept the tolerated title forms (a leading BOM, CommonMark-legal indentation, whitespace and letter case — never an H2 or an indented code block), owned by `skills/automate-loop/SKILL.md` §4 step 1 and implemented once as `RUN_TITLE_ERE` in `automate-helpers.sh`. |
| `## Status` | yes | The run-level status — the `/loop` stop signal. Enum below. |
| `## Source` | yes | The single resolved source for this run — the user's prompt text, `folder <dir>`, or `backlog <_BACKLOG.md>`. Exactly one source is resolved per run (`skills/automate-loop/SKILL.md` §2). |
| `## Run Config` | yes | `mode` (`safe` \| `auto-merge`), `parallel` (OPTIONAL — `N`, present on any `--parallel` parent run, `1` included — `- parallel: 1` marks single-lane mode, `skills/automate-loop/lanes.md` "Single-lane mode" — absent on every sequential run and inside every lane; `skills/automate-loop/SKILL.md` §14), `limit` (PROCESSED-item cap, **default 5** — caps completed items this run, never Queue size), `trust_unprotected` (allows auto-merge onto a branch without enforceable protection — **condition 4 only**; nothing overrides condition 6, the `classify-risk.sh` high-risk park), `auto_review_original` (the original `.auto_review` value captured before the suppress window — `true`/`false`/`absent`), `config_backup` (path of the transient byte-for-byte config-backup sidecar), `max_tokens` (optional, red-team-hardening/06 — the `--max-tokens N` ceiling, present ONLY when passed; unlike `--cheap`/`--notify` this one IS persisted so a bare `--resume` still enforces it). The single-drain config-toggle contract is the skill's domain (`skills/automate-loop/SKILL.md` §7); the ceiling contract is §6 step 1 / §11. |
| `## Queue` | yes | The **FULL** resolved item list, in **processing order** (top-down). Checklist convention below. |
| `## Current` | yes | The in-flight item, its item-level status, `pause_reason`, and the owned-drain observability fields. Enums below. |
| `## Progress` | yes | **APPEND-ONLY** event log — one timestamped line per event; never rewritten. |

### `## Status` enum (run-level)

| Value | Meaning |
|---|---|
| `running` | The loop is actively processing (or this is the freshly-created run). |
| `paused` | Stopped with **work remaining** — always paired with a `pause_reason` in `## Current` (`awaiting_merge` \| `ready_for_release` (an N>1 lane only) \| `awaiting_go` \| `escalated` \| `limit_reached` \| `resume_ambiguous` \| `rate_limit` \| `drain_died` \| `token_ceiling` \| `run_lock_held` \| `meta_unreachable` \| `trail_pr_open` \| `closeout_leftover` \| `live_lane`). |
| `done` | Set **only** when the Queue is **fully resolved** (no `- [ ]` items remain), i.e. `remaining: 0`. (`remaining` is **COMPUTED/REPORTED** — the count of `- [ ]` Queue items, derived by `automate-helpers.sh remaining` — **not a persisted run-file field**; there is no `remaining:` line stored in the template.) |

### `## Queue` checklist convention

- `- [ ] <path>` — **queued** (unprocessed). `remaining` counts only `- [ ]` items.
- `- [x] <path>` — **done** (merged).
- `- [x] <path>  # skipped: <reason>` / `- [x] <path>  # abandoned: <reason>` — **excluded**: checked-off so "next unchecked" never re-picks it; the reason is also logged in `## Progress`. Because `remaining` counts only `- [ ]` items, a skipped/abandoned item does **not** block `## Status: done`. (This is the documented way to unblock an `escalated`-parked run without merging — see `skills/automate-loop/SKILL.md` §5/§9.)
- **Order = processing order** (top-down).
