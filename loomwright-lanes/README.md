# loomwright-lanes

An **optional** live pane for Loomwright's `/automate --parallel` lanes. `/lanes` opens a pane that shows every lane and lets you answer a lane that is waiting on you, with one button per option. It is a Claude Code mod: a hooks module, no agents, commands files, skills or MCP server.

It holds no state that matters. It reads `lane-status --json` and `lane-feed`, writes only through `lane-answer`, and starts nothing but the keep-awake `lane-status --keep-awake` offers — the same commands you can run by hand. Uninstall it and every lane runs exactly as before.

## Install

```
/plugin install loomwright-lanes@atelier
```

It needs `loomwright@atelier` installed (it calls Loomwright's `scripts/automate-lanes.sh`). It finds Loomwright through `claude plugin list --json`; to point it at a dev checkout instead, set **Loomwright plugin folder** (`loomwrightRoot`) in `/config` to the folder holding `scripts/`, for example `~/work/ai-agent-manager/loomwright`.

## What it shows

- **The wave** at the top, as four tiles: when it started (local time) and how long it has run; its lanes (running, waiting for you, to merge, merged, stopped); the machine's load, with a sparkline of the last ten minutes against the CPU count, and memory; and keep-awake. An overloaded machine gets a red **HIGH-LOAD** line and one toast per episode.
- **Keep-awake** says who holds the machine awake. The Claude desktop app's "Keep computer awake while Claude works" counts, but only while a Code session works, and lanes are not Code sessions, so it reads **Claude app only** and offers **Keep awake for this wave**: that runs `lane-status --keep-awake`, which starts `caffeinate -i -w <this session>` (macOS) and ends with the session. A caffeinate already holding hides the button.
- **Per lane**: its current step in the title (`● Build · EXECUTE`, `◆ Merge · ready for release`) and when it started, then a **seven-step rail** — Pick · Plan · Build · Heal · Drain · Decide · Merge — green for done, the current step in its state's color (blue running, amber waiting on you, red stopped), faint for pending. Hover a step for its card: start and end time, time spent (or so far), its last lines, and for Build the Supervisor phases. Below it: state reason, item, PR, branch, last step, the lane's latest message, its last three actions, CI-slot queue position, held-for-load, and merge-readiness (`ready 5/5`, or the failing checks).
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

- **The rail shows what the lane recorded.** A step with no line of its own reads done with no time, and the current step is marked by color and a glyph (a mod's boxes do not animate).
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
