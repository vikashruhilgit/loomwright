# Cross-plugin resolution probe (committed, re-runnable)

**What this is:** the executable half of [`../CROSS_PLUGIN_RESOLUTION.md`](../CROSS_PLUGIN_RESOLUTION.md).
That document records what was measured; this directory records **how**, so the measurement can be
re-run when Claude Code changes and the findings can be checked rather than believed.

It follows the precedent set by [`../code-graph-harness/`](../code-graph-harness/): a spike whose
conclusion has downstream consequences ships its validation harness alongside the prose, so the
reversal condition cites only files that survive a `git clone`.

## The unknowns

| | Question | Why it matters |
|---|---|---|
| **A** | Does an agent's `skills:` frontmatter preload resolve **across plugins**? | A companion plugin's QA agents would preload loomwright-owned `quality-checklist` rather than vendoring a copy. A silently-dropped preload fails no gate and logs nothing. |
| **B** | What does `${CLAUDE_PLUGIN_ROOT}` resolve to inside a **second** plugin's `hooks.json`? | The QA `SubagentStop` matcher fans out to `send-telemetry.sh` and `emit-token-ledger.sh`, which stay in loomwright. An empty expansion turns the command into `python3 "/scripts/…" \|\| true`, which exits 0 and validates nothing. |
| **C** | Does `Task(subagent_type: "<other-plugin>:<agent>")` resolve **from a loomwright surface**? | `/dreaming --agent qa-executor` is a live spawn and stays in loomwright while the agent would leave. |
| **D** | Does a `SubagentStop` **matcher declared in plugin X** fire for an agent **owned by plugin Y** — and in which namespace is the matcher written? | The chosen Unknown B fallback rests entirely on this. A matcher lives in a *different* namespace from the `Task(subagent_type:)` string C measured: loomwright's own `hooks.json` matchers are single-prefix frontmatter names. Added after review found the fallback resting on an unmeasured premise. |

## Re-run

From the repo root:

```
bash loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh
```

Optional environment overrides:

| Variable | Default | Meaning |
|---|---|---|
| `PROBE_DEADLINE` | `240` | Seconds allowed for each nested `claude -p` before the step is recorded **UNMEASURED**. The default is the value the recorded run used, so the documented command is the command that produced the committed transcripts |
| `PROBE_CLI_DEADLINE` | `120` | Seconds allowed for each `claude plugin …` subcommand |
| `PROBE_DATE` | a to-the-second timestamp | The run label, used as the transcript filename prefix. A run that is meant to *be* the record names itself explicitly (`2026-08-20`, `2026-08-20-armd`) |
| `PROBE_OVERWRITE` | unset | Set to `1` to allow a run to replace transcripts that already exist. Without it, the run **refuses to start** (exit 2) and names the files it would have clobbered |
| `PROBE_ONLY` | `all` | Space-separated phase list — `a b c d control`. Preflight and install always run. Use it to add one arm without regenerating an existing record |

**The committed evidence cannot be destroyed by a bare re-run.** Two independent guards: the default
run label carries seconds, so a fresh run never lands on an existing prefix; and any collision that
does occur aborts before the first install unless `PROBE_OVERWRITE=1` is set explicitly. The label
actually used is printed as `transcript prefix:` at the top of the run — use it to diff:

```
bash loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh          # prints e.g. 2026-09-14T101755
diff loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-08-20-unknown-b.log \
     loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-09-14T101755-unknown-b.log
```

The two prefixes must differ for that `diff` to mean anything — comparing today's run against a file
named with today's date is a file diffed against itself, which is how the earlier version of this
instruction was vacuous.

Expect timestamps, the run-scoped nonce, and `$TMPDIR` paths to differ on every run — those are not
findings. What matters is whether the **verdicts** still hold.

**Cost note:** a full run starts **eight** fresh `claude -p` sessions — one per probe arm: Unknown A
arms 1, 2 and the zero-tools control; Unknown B's trigger; Unknown C's two `subagent_type` forms;
Unknown D's two spawn triggers; plus the TaskOutput control arm. It is not free and it is not
instant (the recorded A/B/C run took roughly 2–4 minutes end to end).

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
      agents/probe-host-agent.md               # the agent a FOREIGN matcher targets (Unknown D)
    probe-consumer/
      .claude-plugin/plugin.json
      agents/probe-agent.md                    # skills: probe-host-skill      (Unknown A arm 1, Unknown C)
      agents/probe-checklist-agent.md          # skills: quality-checklist     (Unknown A arm 2)
      agents/probe-zero-tools-agent.md         # control arm — total tool subtraction
      agents/probe-taskoutput-agent.md         # control arm — TaskOutput as the only residual tool
      hooks/hooks.json                         # SessionStart (Unknown B) + 5 SubagentStop matchers (Unknown D)
  out/unknown-b-plugin-root.txt                # what the Unknown B hook wrote
  out/unknown-d-matcher.txt                    # which SubagentStop matchers fired, and for which agent
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

   | Agent's resolved tool list | Result at spawn | Committed transcript |
   |---|---|---|
   | everything subtracted | `would be spawned with zero tools — refusing` | `2026-08-20-unknown-a.log` |
   | `TaskOutput` only | refused, naming `not available to subagents [TaskOutput]` | `2026-08-20-armd-control-taskoutput.log` |
   | `WebSearch` only | spawns; returns the sentinel | `2026-08-20-unknown-a.log` |

   Those two earlier runs left **no transcript** — they predate this harness being committed, so as
   evidence they are recollection. Both rungs are therefore reproduced as control arms that run on
   every invocation (`probe-zero-tools-agent`, `probe-taskoutput-agent`), and the table above cites
   the committed transcript for each row rather than the lost runs.

   So a second plugin's agent must resolve to a **non-empty** tool list containing something that is
   both subagent-eligible and present in the observing session. `WebSearch` is the weakest tool
   meeting all three conditions and cannot read the local filesystem. Keeping the refusals as
   controls is what stops "refused spawn" and "preload did not resolve" — which both produce no
   sentinel — from being conflated in the record.
7. **Teardown is a `trap`, not a closing step.** `EXIT` alone is not enough: `INT`/`TERM` handlers
   that return let bash **resume** the script, so the handlers exit 130/143 explicitly rather than
   letting a torn-down environment go on to overwrite the remaining transcripts.
8. **Teardown assertions fail INCONCLUSIVE, never PASS.** Every post-condition is an absence test,
   and an absence test over a file that a timed-out or failed `claude plugin list` never wrote is
   vacuously true — four PASS lines for a teardown that ran before anything was installed. Each
   assertion is gated on the listing having actually succeeded (rc 0, non-empty capture, the
   command's own header line); anything less prints INCONCLUSIVE and preserves the scratch directory.
   The gate was verified by fault injection — a stub `claude` that fails, and one that exits 0 with
   no output — both of which produce INCONCLUSIVE, while a well-formed stub still produces PASS.

## Transcripts

| File | Contents |
|---|---|
| `transcripts/2026-08-20-unknown-a.log` | Preflight, fixture generation, install, and all three Unknown A arms |
| `transcripts/2026-08-20-unknown-b.log` | The `${CLAUDE_PLUGIN_ROOT}` hook probe and the raw file it wrote |
| `transcripts/2026-08-20-unknown-c.log` | Both `subagent_type` forms with verbatim outcomes |
| `transcripts/2026-08-20-teardown.log` | Uninstall, removal, and the asserted post-conditions |
| `transcripts/2026-08-20-armd-phase0.log` | Second run — preflight, fixtures, install (`PROBE_ONLY="d control"`) |
| `transcripts/2026-08-20-armd-unknown-d.log` | Both spawn triggers and the raw record of which `SubagentStop` matchers fired |
| `transcripts/2026-08-20-armd-control-taskoutput.log` | Rung 2 of the tool ladder, measured instead of recalled |
| `transcripts/2026-08-20-armd-teardown.log` | Second run's teardown, with the evidence-gated assertions |

Every block quoted in `../CROSS_PLUGIN_RESOLUTION.md` appears verbatim in one of these — with two
explicitly-marked exceptions, where a long block is elided with a `[...]` marker inside the quote
(Unknown A arm 2's limit bullets, and the Unknown D wildcard rows' raw payload). Nothing is quoted
that is not in a committed transcript. The first version of that claim was **false**: the ladder's
`TaskOutput` row was quoted from an uncommitted run, which is why that arm now exists.

**Two runs, two labels.** `2026-08-20-*` measured Unknowns A/B/C. `2026-08-20-armd-*` was added
after review to measure Unknown D and the TaskOutput rung; it ran `PROBE_ONLY="d control"`, so it
carries its own preflight and teardown and its own run-scoped nonce, and it left the first run's
transcripts byte-untouched.

> **Why `transcripts/.gitignore` exists.** The repo root `.gitignore` excludes `*.log`, which would
> have made these four files invisible to `git add` and absent from a fresh clone — the evidence
> would have been void, which is precisely the failure the source requirement calls out. The
> negation is scoped to this directory rather than fixing it by editing the root `.gitignore` (out
> of this spike's lane) or by `git add -f` (which works once and then silently skips a regenerated
> transcript on the next `git add .`).

**Honest limit:** that cross-check raises the cost of fabrication; it does not eliminate it. One
agent can author both the prose and the transcripts. The only true anti-fabrication anchor is a
human re-running the command above — which is the entire reason this directory is committed.
