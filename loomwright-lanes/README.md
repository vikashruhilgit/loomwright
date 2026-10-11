# loomwright-lanes

An **optional** live pane for Loomwright's `/automate --parallel` lanes. `/lanes` opens a pane that shows every lane and lets you answer a lane that is waiting on you, with one button per option. It is a Claude Code mod: a hooks module, no agents, commands files, skills or MCP server.

It holds no state that matters. It reads `lane-status --json` and `lane-feed`, and writes only through `lane-answer`, the same commands you can run by hand. Uninstall it and every lane runs exactly as before.

## Install

```
/plugin install loomwright-lanes@atelier
```

It needs `loomwright@atelier` installed (it calls Loomwright's `scripts/automate-lanes.sh`). It finds Loomwright through `claude plugin list --json`; to point it at a dev checkout instead, set **Loomwright plugin folder** (`loomwrightRoot`) in `/config` to the folder holding `scripts/`, for example `~/work/ai-agent-manager/loomwright`.

## What it shows

- **Machine health** at the top: load state (`ok` / `busy` / `overloaded`), load1 and CPUs, memory pressure, keep-awake. An overloaded machine gets a red **HIGH-LOAD** line and one toast per episode.
- **Per lane**: state (running, waiting for you, stalled, parked and why), item, PR, branch, last progress line, the lane's latest message, its last three actions, CI-slot queue position, held-for-load, and merge-readiness (`ready 5/5`, or the failing checks).
- **Details**: the last 20 steps of the lane's feed (`lane-feed`).
- **Inbox**, near the top: every lane's pending question in one list, oldest first, each with its lane, item and how long it has waited. Each shows its options as buttons (● ○ pick one, ☑ ☐ pick any), an optional **note** to the lane (delivered with the answer as an annotation; it never decides), and **Send**, which stays light until every question has a pick, then calls `lane-answer`; that validates the labels and resumes the lane. The answer file records `via: lanes-addon`, and a refusal from `lane-answer` is shown word for word. A lane whose answer is already held (the machine was busy) says so, and sending again replaces the held answer. Each lane card points to the inbox and shows how many questions its stamped policy answered automatically.
- A status-line summary (`lanes: 2 running · 1 waiting for you`), and a toast when a lane starts waiting.

It refreshes every 15 seconds; `/lanes` and every answer refresh it at once. If `lane-status` fails, the pane says "status unavailable" and keeps the last good reading.

## Without it

The plain view needs nothing extra:

```bash
bash <loomwright>/scripts/automate-lanes.sh lane-status --watch
```

and answer from the main session: `lane-status --inbox` lists pending questions, and `lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>'` (answers JSON on stdin) answers one.

## Honest limits

- **A button press counts as you answering.** The pane passes `--owner-command '/lanes answer <lane> <id>'` to `lane-answer`. Anyone who can press buttons in your session can answer a lane, the same as anyone who can type in it.
- **Claude Code only.** Other harnesses use the plain view above.
- **One run at a time.** It shows the run `lane-status` picks by default: the newest lane table in the project you opened the session in.

## Development

```bash
claude plugin validate loomwright-lanes
claude plugin test loomwright-lanes
bash scripts/test-lanes-addon.sh
```

`scripts/test-lanes-addon.sh` also holds the module to the three lane commands (no lane files, no other process calls). To try a change live, start a session with `claude --plugin-dir loomwright-lanes`.
