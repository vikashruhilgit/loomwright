# Evidence: pa/25 backlog board feeds, the SessionStart stamp nudge on a real requirements tree

Captured 2026-10-26 on macOS (bash 3.2) by the pa/25 subtask-4 worker. **Status: partial.** This
file holds what that worker could observe. AC10 asks for one fresh session start on the
**integrated** feature branch in the lane's main checkout. That run is still owed at FINALIZE; see
"What is still owed" at the end.

## Checkout and script

- **Requirements tree read:** the lane's main checkout (the L9 clone root, written `<L9>` below).
  It is the only checkout with a `.supervisor/requirements/` tree, because `.supervisor/` is
  gitignored and a worker worktree has none. At capture time `<L9>` had branch
  `feature/pa25-backlog-board-feeds` checked out at `ec67b67`, which is the job's base commit. No
  subtask was merged into it yet.
- **Scripts run:** the subtask-4 worktree's `loomwright/scripts/session-resume.sh` and
  `automate-helpers.sh`, written `<W>` below. That branch is the base plus subtask 1
  (`backlog --offline`) plus subtask 4 (the nudge). Subtasks 2 (Floor) and 3 (`lane-status`
  pointer) do not touch either script.
- **No writes to `<L9>`:** a worker may not write in the main checkout, so the hook ran with
  `LOOMWRIGHT_HOST_MODE=1` and `LOOMWRIGHT_HOST_STATE_DIR` set to a scratch dir outside every
  worktree. Host mode moves the nudge marker into that dir. It also skips the
  `--repair-merged` brief moves, which are repo writes. The nudge logic itself is the same in
  both modes; only the marker's location changes. After every run, `git -C <L9> status --short`
  printed nothing.

## 1. What the board reads offline

```bash
bash <W>/loomwright/scripts/automate-helpers.sh backlog --json --offline --root <L9> | jq '{item_count, github, totals}'
```

```json
{
  "item_count": 457,
  "github": "unverified",
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

The reader exited 0. It was run twice on its own, and both runs gave identical totals. N =
`merged_unstamped + conflict` = 0 + 0 = **0**, so the nudge must print nothing on this tree. The
16 items that need a decision but are not counted by the nudge are 3 `brief_shipped`, 12
`unknown` and 1 `in_flight`, the `in_flight` one being this job's own requirement. The
`/backlog --unknown` view covers those items; the nudge does not count them by design.

## 2. One simulated fresh session start (scratch state dir, marker absent first)

```bash
SD="$(mktemp -d)"            # scratch state dir, outside every worktree; empty, so no marker
cd <L9> && printf '{"source":"startup"}' \
  | LOOMWRIGHT_HOST_MODE=1 LOOMWRIGHT_HOST_STATE_DIR="$SD" bash <W>/loomwright/scripts/session-resume.sh
```

Output, verbatim. Exit 0, nothing on stderr:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "**Background processes:** 2 item(s) need attention (0 overdue, 0 orphaned, 2 unregistered) — inspect with `proc-registry.sh list`; stop registered ones with `proc-registry.sh reap` (dry run first)"
  }
}
```

**Nudge line: absent.** That matches N = 0 from section 1. The only block in the envelope is
startup-arm block 6, the background-process line, which is unrelated to this job.

## 3. Timing: this host was heavily loaded during capture

Several parallel `/automate` lanes were running on the same machine. The 1-minute load average was
between 9 and 90 during capture, and two `ci-local --affected` runs in that window hit the
watchdog on unrelated gates. Measured under that load:

| Run | `LOOMWRIGHT_SR_BACKLOG_TIMEOUT` | reader alone | hook total | marker in `$SD` afterwards |
|---|---|---|---|---|
| A (tick-only deadline, before the wall-clock check was added) | 10 (default) | 10 s | 26 s | absent: the read hit the deadline, so the fail-safe path ran (no line, no marker) |
| B (tick-only deadline) | 120 | — | 1094 s | `2026-10-26`: the read succeeded, N = 0, no line |
| C (final script) | 10 (default) | 23 s | 24 s | absent: the read hit the deadline, so the fail-safe path ran |

Run B is why the final script adds a wall-clock check (`SECONDS`, no fork) next to the 0.1 s tick
count. Under heavy load each `sleep 0.1` tick is a fork plus exec that takes far longer than
0.1 s, so a deadline counted only in ticks let session start run far past the configured seconds.
Run C took 24 s even though the default deadline is 10 s; the rest of the startup arm accounts for
the difference. The brief's quiet-host figure for this read is about 5 s. **Not measured here: the
reader's cost on a quiet host.**

**Risk to note.** By design, a timed-out read writes no marker, so the next session tries again.
On a 457-item tree whose offline read takes longer than 10 s on a loaded host, every session start
pays the full 10 s and the nudge never prints. On a quiet host the read fits inside the deadline;
after the first success the marker holds the check to once a day.

## What is still owed (AC10 at FINALIZE)

To finish AC10, run the brief's literal command with the integrated feature branch checked out in
`<L9>`. That run is not in host mode, so its marker lands in `<L9>/.supervisor/`:

```bash
cd <L9> && rm -f .supervisor/.backlog-nudge-shown \
  && printf '{"source":"startup"}' | bash loomwright/scripts/session-resume.sh
bash loomwright/scripts/automate-helpers.sh backlog --json --offline --root . | jq '{item_count, totals}'
```

Then replace sections 2 and 3 with its output. Two differences from the runs above are expected.
First, not in host mode, the startup arm's `--repair-merged` may move briefs whose merge the disk
proves, which every real session start there already does. Second, the timing will depend on the
host's load at that moment.
