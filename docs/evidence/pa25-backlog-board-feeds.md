# Evidence: pa/25 backlog board feeds, the SessionStart stamp nudge on a real requirements tree

Captured 2026-10-26 on macOS (bash 3.2) at Supervisor FINALIZE, on the **integrated** feature
branch (AC10).

## Checkout and command

- **Checkout:** the lane's main checkout (the L9 clone root, written `<L9>` below), branch
  `feature/pa25-backlog-board-feeds` at `900a332`: the base `ec67b67` plus all four subtask merges.
  It is the only checkout with a `.supervisor/requirements/` tree; `.supervisor/` is gitignored, so
  a worker worktree has none.
- **Not host mode:** the hook ran as a real session start does there, so the nudge marker lands at
  `<L9>/.supervisor/.backlog-nudge-shown`. `git status --short` printed nothing after every run.
- **Host load:** several parallel `/automate` lanes shared the machine. `uptime` read a 1-minute
  load average of 15–16 throughout.

## 1. What the board reads offline (`item_count` and the totals that explain the nudge)

```bash
cd <L9> && bash loomwright/scripts/automate-helpers.sh backlog --json --offline --root . \
  | jq '{item_count, github, right_size, totals}'
```

Exit 0, 21 s wall clock:

```json
{
  "item_count": 457,
  "github": "unverified",
  "right_size": "unknown",
  "totals": {
    "done": 221,
    "abandoned": 15,
    "parked": 21,
    "proposed": 184,
    "brief_shipped": 3,
    "merged_unstamped": 0,
    "pr_open": 0,
    "in_flight": 1,
    "conflict": 0,
    "open": 0,
    "unknown": 12
  }
}
```

N = `merged_unstamped + conflict` = 0 + 0 = **0**, so the nudge must print nothing on this tree.
The 3 `brief_shipped` and 12 `unknown` items need a decision too, but the nudge does not count
them by design; `/backlog` and the Floor's `needs_decision` list show them. The 1 `in_flight` item
is this job's own requirement.

## 2. The AC10 fresh session start (marker removed first)

```bash
cd <L9> && rm -f .supervisor/.backlog-nudge-shown \
  && printf '{"source":"startup"}' | bash loomwright/scripts/session-resume.sh
```

Exit 0 after 23 s, nothing on stderr:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "**Background processes:** 3 item(s) need attention (0 overdue, 0 orphaned, 3 unregistered) — inspect with `proc-registry.sh list`; stop registered ones with `proc-registry.sh reap` (dry run first)"
  }
}
```

**Nudge line: absent. Marker afterwards: absent.** At this load the offline read (21 s, section 1)
outlives the default `LOOMWRIGHT_SR_BACKLOG_TIMEOUT` of 10 s, so the hook took the fail-safe path:
no line, no marker, exit 0. The only block in the envelope is startup-arm block 6, the
background-process line, which is unrelated to this job.

The same start with a deadline long enough for the read to finish:

```bash
cd <L9> && rm -f .supervisor/.backlog-nudge-shown \
  && printf '{"source":"startup"}' | LOOMWRIGHT_SR_BACKLOG_TIMEOUT=120 bash loomwright/scripts/session-resume.sh
```

Exit 0 after 37 s. The envelope was byte-identical to the one above. **Nudge line: absent**, as
N = 0 predicts. **Marker afterwards: `2026-10-26`**: the read succeeded, so the check is now
held to once for the day.

## 3. Risk this evidence shows

A timed-out read writes no marker by design, so the next session tries again. On this 457-item
tree, while the host is this loaded, the offline read takes about 21 s, longer than the 10 s
default. So every session start pays the full 10 s and the nudge never prints. On a quiet host
the brief's figure for the read is about 5 s, inside the deadline. After the first successful
read, the marker holds the check to once a day. **Not measured here: the read's cost on a quiet
host.** Whether the default deadline should rise is an owner decision; it is recorded as a
follow-up in the PR.
