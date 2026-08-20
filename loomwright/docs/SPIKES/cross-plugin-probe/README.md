# Cross-plugin resolution probe (committed, re-runnable)

**What this is:** the executable half of [`../CROSS_PLUGIN_RESOLUTION.md`](../CROSS_PLUGIN_RESOLUTION.md).
That document records what was measured; this directory records **how**, so the measurement can be
re-run when Claude Code changes and the findings can be checked rather than believed.

It follows the precedent set by [`../code-graph-harness/`](../code-graph-harness/): a spike whose
conclusion has downstream consequences ships its validation harness alongside the prose, so the
reversal condition cites only files that survive a `git clone`.

## The three unknowns

| | Question | Why it matters |
|---|---|---|
| **A** | Does an agent's `skills:` frontmatter preload resolve **across plugins**? | A companion plugin's QA agents would preload loomwright-owned `quality-checklist` rather than vendoring a copy. A silently-dropped preload fails no gate and logs nothing. |
| **B** | What does `${CLAUDE_PLUGIN_ROOT}` resolve to inside a **second** plugin's `hooks.json`? | The QA `SubagentStop` matcher fans out to `send-telemetry.sh` and `emit-token-ledger.sh`, which stay in loomwright. An empty expansion turns the command into `python3 "/scripts/…" \|\| true`, which exits 0 and validates nothing. |
| **C** | Does `Task(subagent_type: "<other-plugin>:<agent>")` resolve **from a loomwright surface**? | `/dreaming --agent qa-executor` is a live spawn and stays in loomwright while the agent would leave. |

## Re-run

From the repo root:

```
bash loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh
```

Optional environment overrides:

| Variable | Default | Meaning |
|---|---|---|
| `PROBE_DEADLINE` | `300` | Seconds allowed for each nested `claude -p` before the step is recorded **UNMEASURED** |
| `PROBE_CLI_DEADLINE` | `120` | Seconds allowed for each `claude plugin …` subcommand |
| `PROBE_DATE` | today | Transcript filename prefix. Set it to avoid overwriting the committed `2026-08-20-*` logs |

A run **regenerates** the four files in `transcripts/`. To compare against the recorded measurement
without destroying it:

```
PROBE_DATE=$(date +%F) bash loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh
diff loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-08-20-unknown-b.log \
     loomwright/docs/SPIKES/cross-plugin-probe/transcripts/$(date +%F)-unknown-b.log
```

Expect timestamps, the run-scoped nonce, and `$TMPDIR` paths to differ on every run — those are not
findings. What matters is whether the **verdicts** still hold.

**Cost note:** a run starts five fresh `claude -p` sessions. It is not free and it is not instant
(roughly 2–4 minutes end to end on the recorded run).

## What the probe generates — and what it never touches

`run-probe.sh` writes **every** probe artifact inline from heredocs into a `$TMPDIR` scratch
directory and deletes them at teardown. Nothing under `probe-host/` or `probe-consumer/` is
committed; the create-count for this spike stays at the fixture plus the transcripts, while every
asserted frontmatter and hook command is still readable in committed source (in `run-probe.sh`).

Generated at run time:

```
$TMPDIR/loomwright-xplugin-probe-<pid>/
  marketplace/
    .claude-plugin/marketplace.json            # the throwaway marketplace "xplugin-probe"
    probe-host/
      .claude-plugin/plugin.json
      skills/probe-host-skill/SKILL.md         # carries the run-scoped nonce
    probe-consumer/
      .claude-plugin/plugin.json
      agents/probe-agent.md                    # skills: probe-host-skill      (Unknown A arm 1, Unknown C)
      agents/probe-checklist-agent.md          # skills: quality-checklist     (Unknown A arm 2)
      agents/probe-zero-tools-agent.md         # control arm — total tool subtraction
      hooks/hooks.json                         # SessionStart hook             (Unknown B)
  out/unknown-b-plugin-root.txt                # what the Unknown B hook wrote
```

Never touched:

- **No tracked file is mutated.** The nonce lives in a plugin the script authors, so
  mutation-target == preload-source holds by construction.
- **`.claude-plugin/marketplace.json` is not edited.** The probe marketplace is registered by
  *path*, outside this repo's manifest.
- **`plugin.json` counts are unchanged.** This directory lives under `docs/`, so it adds no
  agent/command/skill/hook.
- **`.claude/settings.local.json`** — the one file `--scope local` does write — is backed up
  byte-for-byte before the run and restored (or deleted, if it did not exist) at teardown, with the
  restore **asserted** in `transcripts/*-teardown.log`. It is gitignored via `.gitignore`'s
  `.claude/*`, which is exactly why `--scope local` was chosen and `--scope project` forbidden.

## Design constraints, and the failure each one prevents

1. **Two generated plugins, not a mutated real one.** Installed plugin bodies are separate
   snapshots under `~/.claude/plugins/cache/`, not live views of this checkout. A nonce written to
   the repo working copy could never reach the preloaded body, so the "obvious" design's only
   reachable outcome is a **false DOES NOT RESOLVE**.
2. **`--scope local` only.** Never `user` (machine-global), never `project` (writes
   `.claude/settings.json` into the repo). A local-scope install that failed to register would be a
   *finding*, not a licence to escalate scope.
3. **No permission-bypass flags.** `--dangerously-skip-permissions` and
   `--permission-mode bypassPermissions` are a standing project prohibition and are unused.
4. **Bounded wait on every nested `claude` call** — probes, installs, and teardown alike. Stock
   macOS has no `timeout(1)`, and a nested headless `claude` can hang on a permission prompt with no
   TTY. Each call runs in the background and is collected through a FIFO with
   `IFS= read -r -d '' -t N`. On expiry the step is recorded **UNMEASURED**, naming the timeout as
   the blocker, and the run continues to teardown rather than stalling.
   The FIFO is opened read-write (`exec 9<>`) deliberately: a plain `read … < fifo` blocks in
   `open(2)` until a writer appears — which only happens once the command has already finished — so
   `read -t` would never arm its timeout and the bound would be silently vacuous.
5. **Headless `claude` uses `-p`.** Plain `claude` and `claude --agent X` are interactive by default
   and hang without a TTY.
6. **Tool isolation at both levels.** The probe agents have no filesystem-read capability, *and* the
   observing parent session runs with `--tools "Task,WebSearch"`, so neither the subagent nor the
   process watching it can read the sentinel off disk. Without the second half, a sentinel hit would
   prove only that *something* in the process tree could open a file.

   **"No tools at all" is not an available setting**, and the residual tool was chosen by
   measurement, not taste. Two earlier runs established the ladder:

   | Agent's resolved tool list | Result at spawn |
   |---|---|
   | everything subtracted | `would be spawned with zero tools — refusing` |
   | `TaskOutput` only | `not available to subagents [TaskOutput]` |
   | `WebSearch` only | spawns; returns the sentinel |

   So a second plugin's agent must resolve to a **non-empty** tool list containing something that is
   both subagent-eligible and present in the observing session. `WebSearch` is the weakest tool
   meeting all three conditions and cannot read the local filesystem. The zero-tools refusal is kept
   as a designed control arm (`probe-zero-tools-agent`) so that "refused spawn" and "preload did not
   resolve" — which both produce no sentinel — stay distinguishable in the record instead of being
   conflated.
7. **Teardown is a `trap`, not a closing step.** It runs on success, failure, and interrupt, and its
   post-conditions are asserted in the transcript rather than assumed.

## Transcripts

| File | Contents |
|---|---|
| `transcripts/2026-08-20-unknown-a.log` | Preflight, fixture generation, install, and all three Unknown A arms |
| `transcripts/2026-08-20-unknown-b.log` | The `${CLAUDE_PLUGIN_ROOT}` hook probe and the raw file it wrote |
| `transcripts/2026-08-20-unknown-c.log` | Both `subagent_type` forms with verbatim outcomes |
| `transcripts/2026-08-20-teardown.log` | Uninstall, removal, and the asserted post-conditions |

Every block quoted in `../CROSS_PLUGIN_RESOLUTION.md` appears verbatim in one of these.

> **Why `transcripts/.gitignore` exists.** The repo root `.gitignore` excludes `*.log`, which would
> have made these four files invisible to `git add` and absent from a fresh clone — the evidence
> would have been void, which is precisely the failure the source requirement calls out. The
> negation is scoped to this directory rather than fixing it by editing the root `.gitignore` (out
> of this spike's lane) or by `git add -f` (which works once and then silently skips a regenerated
> transcript on the next `git add .`).

**Honest limit:** that cross-check raises the cost of fabrication; it does not eliminate it. One
agent can author both the prose and the transcripts. The only true anti-fabrication anchor is a
human re-running the command above — which is the entire reason this directory is committed.
