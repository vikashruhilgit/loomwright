# Spike: cross-plugin resolution — can a companion plugin depend on Loomwright-owned assets?

**Status:** MEASURED. All three unknowns answered by executed probes.
**Date measured:** 2026-08-20
**Measured against:** Claude Code **2.1.228** (`claude --version`, captured in
`cross-plugin-probe/transcripts/2026-08-20-unknown-a.log`)
**Probe harness (committed):** [`cross-plugin-probe/`](cross-plugin-probe/)

**Exact re-run command**, from the repo root:

```
bash loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh
```

> **This answer has an expiry date.** Every verdict below is a statement about Claude Code 2.1.228
> on 2026-08-20, not about Claude Code in general. Re-run the command above before relying on any
> of it against a newer version. `cross-plugin-probe/README.md` explains how to re-run without
> overwriting the recorded transcripts (`PROBE_DATE=$(date +%F)`).

---

## Why this spike existed

The `selvedge` extraction plans a **companion** plugin that depends on Loomwright-owned shared
assets rather than vendoring copies. Six downstream slices assume three cross-plugin resolutions
work, and none had ever been exercised here — `stackpack`, the only prior spin-off, ships 18 skills
and zero agents, commands, hooks or scripts, so it is a precedent for none of the three.

The failure mode is **silent**, which is what made this a gate rather than a risk note. CLAUDE.md
§"Hook gotcha" already records that Claude Code silently ignores `hooks`, `mcpServers` and
`permissionMode` in plugin agent frontmatter — silent-ignore is an *established* behaviour for this
exact frontmatter block. A dropped `skills:` preload fails no gate and logs nothing; an unset
`${CLAUDE_PLUGIN_ROOT}` under the plugin's `|| true` hook convention exits 0 and validates nothing.

## Results at a glance

| Unknown | Verdict | One-line answer |
|---|---|---|
| **A** — cross-plugin `skills:` preload | **RESOLVES** | A second plugin's agent preloads another plugin's skill body by bare name. |
| **B** — `${CLAUDE_PLUGIN_ROOT}` in a second plugin's `hooks.json` | **RESOLVES, PER-PLUGIN** | It expands to the *declaring* plugin's own directory. Empty/unset is ruled OUT. Downstream this is a **NO**: a selvedge hook cannot invoke loomwright's scripts by that path. |
| **C** — cross-plugin `Task(subagent_type:)` | **RESOLVES WITH CAVEAT** | Only the **doubled-prefix** form works. The single-prefix form errors with `not found`. |
| *(incidental)* — tool-subtraction hardening | **CONSTRAINT FOUND** | An agent whose resolved tool list is empty is **refused at spawn**. |

---

## Unknown A — cross-plugin skills preload resolution

**Question.** Does an agent's `skills:` frontmatter preload resolve across plugin boundaries? Under
the companion model, `selvedge:qa-executor` and `selvedge:qa-strategist` would preload
`quality-checklist`, which lives in loomwright and must not be duplicated.

**Verdict: RESOLVES.** Both arms agree.

### Probe design, and why it is not the obvious one

The obvious design — inject a nonce into a real loomwright skill and see whether it comes back — is
**unreachable**, and its only possible outcome is a *false* DOES NOT RESOLVE. Installed plugin
bodies are separate snapshots, not live views of this checkout: `claude plugin details loomwright`
reports source `loomwright@atelier`, and the plugin manager's own `installed_plugins.json` resolves
that install to

```
LOOMWRIGHT_INSTALL_PATH=[/Users/vikashruhil/.claude/plugins/cache/atelier/loomwright/15.36.0]
INSTALLED_SKILL=[/Users/vikashruhil/.claude/plugins/cache/atelier/loomwright/15.36.0/skills/quality-checklist/SKILL.md]
```

A nonce written to the repo working copy would land in a different file on disk from the one the
session loads. So `run-probe.sh` instead generates **two throwaway plugins** — `probe-host`, which
owns a skill carrying a run-scoped nonce, and `probe-consumer`, whose agent's `skills:` frontmatter
names *probe-host's* skill. Mutation-target and preload-source are then the same file by
construction, and **no tracked file is written at all**.

> **Provenance note worth stating plainly.** This project's memory carries a standing warning not to
> diagnose the active plugin version by looking in `~/.claude/plugins/cache/` — that is the CLI
> store and it holds stale leftovers. That warning is about *guessing from a directory listing*.
> Here the path was not guessed: it was read out of `installed_plugins.json` for the `loomwright@atelier`
> entry and cross-checked against `claude plugin details`. Resolved that way, the cache path **is**
> the real load path — the corroboration arm below confirms it end-to-end, because the agent
> independently reported that same directory as its skill source.

### Sentinel isolation (why a hit is not confounded)

`probe-consumer`'s agent is declared with the repo's own `tools:` + `disallowedTools:` idiom
(`loomwright/agents/plan-reviewer.md` declares the full list, then subtracts), subtracting every
filesystem-read capability. The generated frontmatter, verbatim from the transcript:

```
name: probe-consumer:probe-agent
description: Throwaway probe agent. Preloads a skill owned by a DIFFERENT plugin (probe-host) and echoes its sentinel.
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
disallowedTools: Read, Write, Edit, NotebookEdit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebFetch
model: inherit
maxTurns: 3
skills:
  - probe-host-skill
```

Isolation is enforced at **both** levels: the observing parent session runs with
`--tools "Task,WebSearch"`, so no process in the chain holds `Read`, `Glob`, `Grep` or `Bash`. Without
the second half, a sentinel hit would prove only that *something* in the process tree could open a
file.

### Arm 1 (primary) — run-scoped nonce, generated fixture

Raw captured output:

```
--- captured stdout+stderr (verbatim) ---
SPAWN: ok
RELAY: SENTINEL: XPLUGIN-NONCE-1787193514-1432331022
--- end capture ---
```

and the assertion:

```
$ grep -cF "$NONCE" <arm 1 captured output>    # <== THE assertion for Unknown A arm 1
1
```

The nonce was generated at run time (`XPLUGIN-NONCE-1787193514-1432331022`), existed only inside the
generated `probe-host` skill body, and reached the output of a `probe-consumer` agent that had no
tool capable of reading it. **Cross-plugin preload resolves.**

### Arm 2 (corroboration, strictly read-only) — the real loomwright skill

The second arm repeats the test against the **real** loomwright-owned `quality-checklist`, writing
nothing. The marker phrase asserted was chosen for **distinctiveness**, not convenience: much of
that skill is generic checklist boilerplate a tool-isolated agent could emit from prior knowledge
with no preload at all, which would be a false RESOLVES through a channel tool isolation never
closes. Uniqueness inside the installed body was verified before the arm ran:

```
marker asserted by arm 2: [Token budget estimated (Context7 needed?)]
$ grep -rlF "$MARKER" $LOOMWRIGHT_INSTALL_PATH   # distinctiveness: which installed files carry it
/Users/vikashruhil/.claude/plugins/cache/atelier/loomwright/15.36.0/skills/quality-checklist/SKILL.md
```

Raw captured output (excerpted; the full block is in the transcript):

```
--- captured stdout+stderr (verbatim) ---
SPAWN: ok
RELAY: The `quality-checklist` skill IS present in my context. Note one discrepancy I should flag rather than paper over: there is no section literally titled **"Before Starting Any Task"**. The closest — and the only pre-start gate in the skill — is **"## Pre-Task Checklist"** ("Before starting implementation:"). I am reproducing that section's items verbatim, unmodified:

ITEM: Task clearly defined (Beads task, Supervisor-Ready Brief, or equivalent source with acceptance criteria)
ITEM: Dependencies checked (blocks, subtasks)
ITEM: Related CLAUDE.md patterns understood
ITEM: Test strategy defined (unit/integration/e2e)
ITEM: Framework-specific skills identified
ITEM: Token budget estimated (Context7 needed?)
```

```
$ grep -cF "$MARKER" <arm 2 captured output>   # <== THE assertion for Unknown A arm 2
1
```

**Arm 2 CORROBORATES arm 1 and never OVERRIDES it.** Unlike a run-scoped nonce, a pre-existing
phrase cannot fully exclude reproduction from the model's prior knowledge, so a hit here is strictly
weaker evidence. Had the arms disagreed, that disagreement would be the finding and arm 1 would
rule. They agree.

Two details make this arm stronger than the marker alone. The agent **corrected the prompt's own
premise** — the prompt asked for a section called "Before Starting Any Task", which does not exist;
the agent reported the real heading `## Pre-Task Checklist` rather than confabulating the requested
one. And it independently named its skill source as
`/Users/vikashruhil/.claude/plugins/cache/atelier/loomwright/15.36.0/skills/quality-checklist/SKILL.md`,
which is the path Phase 0 had resolved from `installed_plugins.json` — a detail no prior-knowledge
reconstruction would supply.

### Control arm — the other way to get no sentinel

`probe-zero-tools-agent` is identical to `probe-agent` except that the subtraction is total. It
exists so that "refused spawn" and "preload did not resolve" — which both produce no sentinel —
stay distinguishable in the record instead of being conflated:

```
--- captured stdout+stderr (verbatim) ---
OUTCOME: error
DETAIL: Agent 'probe-consumer:probe-consumer:probe-zero-tools-agent' would be spawned with zero tools — refusing. Its tools list resolved to nothing: recognized but matched no tools in this session [Task]. Fix the agent's tools frontmatter or pass a different subagent_type.
--- end capture ---
```

This is not a hypothetical. **The first two runs of this probe hit exactly this and produced a
nonce-absent result that was NOT a NO** — it was a refused spawn, recorded UNMEASURED per the
UNMEASURED guard rather than written up as DOES NOT RESOLVE. The residual tool was then chosen by
measurement:

| Agent's resolved tool list | Result at spawn |
|---|---|
| everything subtracted | `would be spawned with zero tools — refusing` |
| `TaskOutput` only | `not available to subagents [TaskOutput]` |
| `WebSearch` only | spawns; returns the sentinel |

**Consequence for the extraction:** hardening a companion-plugin agent by subtracting tools has a
floor. The resolved list must be non-empty *and* contain something both subagent-eligible and
present in the spawning session. `TaskOutput` in particular is **not available to subagents**.

---

## Unknown B — CLAUDE_PLUGIN_ROOT inside a second plugin hooks.json

**Question.** What does `${CLAUDE_PLUGIN_ROOT}` resolve to inside a **second** plugin's `hooks.json`
— and does it expand at all, or is it empty/unset? The `|| true` convention means an empty expansion
turns `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true` into
`python3 "/scripts/validate-qa-result.py" || true`, which exits 0 and validates nothing. A green run
is therefore not evidence.

**Verdict: RESOLVES — and it is PER-PLUGIN. The empty/unset case is explicitly ruled OUT.**

### Probe design

The probe plugin's `hooks.json` declares a `SessionStart` hook that appends to an **absolute** scratch
path, writing the value in a form that distinguishes expanded / empty / unset / unsubstituted:

```
            "command": "{ printf 'RAW=[%s]\\n' \"${CLAUDE_PLUGIN_ROOT}\"; printf 'BRACE_DEFAULT=[%s]\\n' \"${CLAUDE_PLUGIN_ROOT:-__UNSET_OR_EMPTY__}\"; printf 'ENV_PRESENT=[%s]\\n' \"$(env | grep -c '^CLAUDE_PLUGIN_ROOT=')\"; printf 'HOOK_CWD=[%s]\\n' \"$PWD\"; printf 'HOOK_FIRED_AT=[%s]\\n' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"; } >> '/var/folders/jh/sbkxjbkj7y959rkxq2m61rbw0000gn/T//loomwright-xplugin-probe-97054/out/unknown-b-plugin-root.txt' 2>&1 || true"
```

That block is quoted from the transcript, so the output path is the run's real absolute scratch
path; in committed source (`run-probe.sh`) it is a `@@OUT@@` placeholder substituted at generation
time, which is what keeps `${CLAUDE_PLUGIN_ROOT}` from being expanded by the generating shell.

`|| true` is present **on purpose** — it is this plugin family's convention, and it is precisely why
the file content, not the exit status, is the evidence.

### Raw observed output

```
RAW=[/var/folders/jh/sbkxjbkj7y959rkxq2m61rbw0000gn/T/loomwright-xplugin-probe-97054/marketplace/probe-consumer]
BRACE_DEFAULT=[/var/folders/jh/sbkxjbkj7y959rkxq2m61rbw0000gn/T/loomwright-xplugin-probe-97054/marketplace/probe-consumer]
ENV_PRESENT=[1]
HOOK_CWD=[/Users/vikashruhil/Documents/work/AI/ai-agent-manager]
HOOK_FIRED_AT=[2026-08-20T02:38:39Z]
```

### Reading it

- **It expanded**, to `.../marketplace/probe-consumer` — the **declaring plugin's own directory**,
  not loomwright's and not the session cwd. `${CLAUDE_PLUGIN_ROOT}` is per-plugin, as CLAUDE.md's
  wording implied but had never been tested across a plugin boundary.
- **`ENV_PRESENT=[1]`** — it is a real exported environment variable in the hook process, not a
  textual pre-substitution. `BRACE_DEFAULT` agreeing with `RAW` confirms it: the `:-` default form
  was resolved by the shell against a set, non-empty variable.
- **The empty/unset case is ruled OUT.** `RAW` is non-empty and `ENV_PRESENT` is 1, so neither
  silent-no-op branch is in play.
- **A second plugin's `hooks.json` registers and fires at all.** The hook fired on every fresh
  `claude -p` session in the run — the transcript shows repeated records with distinct
  `HOOK_FIRED_AT` timestamps. That is itself a positive finding: hooks are not silently dropped for
  a second plugin the way frontmatter `hooks:` are.
- `HOOK_CWD` is the *session's* directory, so it is not a usable anchor for locating another
  plugin.

### What this means downstream — this is the NO

The QA `SubagentStop` matcher carries two hooks. The first,
`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true`, **moves cleanly**: the
script travels with the agent, and `${CLAUDE_PLUGIN_ROOT}` will correctly resolve to selvedge.

The second — the `send-telemetry.sh` / `emit-token-ledger.sh` fan-out — **cannot move**. Those
scripts stay in loomwright because `code-reviewer` and other matchers share them, and a hook
declared in `selvedge/hooks/hooks.json` resolves `${CLAUDE_PLUGIN_ROOT}` to *selvedge*. There is no
variable in that hook's environment pointing at the other plugin. So a selvedge hook **cannot**
invoke loomwright's shared scripts by that path, and the QA telemetry + token-ledger fan-out is lost
unless it is re-engineered. Fallback chosen below.

---

## Unknown C — cross-plugin Task subagent_type resolution

**Question.** Does `Task(subagent_type: "<other-plugin>:<agent>")` resolve *from a loomwright
surface*? `/dreaming --agent qa-executor` is a live spawn and stays in loomwright while the agent
would leave.

**Verdict: RESOLVES WITH CAVEAT — only the doubled-prefix form.**

Both forms were attempted against the probe plugin from a session with cwd at the repo root and the
loomwright plugin enabled. The loomwright precedent recorded in project memory was treated as
advisory context only and never substituted for the measurement.

### Single-prefix form — FAILS

```
SUBAGENT_TYPE: probe-consumer:probe-agent
OUTCOME: error
DETAIL: Agent type 'probe-consumer:probe-agent' not found. Available agents: claude, claude-code-guide, Explore, general-purpose, loomwright:loomwright:code-reviewer, loomwright:loomwright:context-keeper, loomwright:loomwright:execute-manager, loomwright:loomwright:launch-pad-runner, loomwright:loomwright:orchestrator, loomwright:loomwright:plan-reviewer, loomwright:loomwright:product-owner, loomwright:loomwright:qa-executor, loomwright:loomwright:qa-strategist, loomwright:loomwright:red-team-reviewer, loomwright:loomwright:review-pr-runner, loomwright:loomwright:rubric-grader, loomwright:loomwright:supervisor-runner, loomwright:loomwright:worker, Plan, probe-consumer:probe-consumer:probe-agent, probe-consumer:probe-consumer:probe-checklist-agent, probe-consumer:probe-consumer:probe-zero-tools-agent, statusline-setup
```

### Doubled-prefix form — WORKS

```
SUBAGENT_TYPE: probe-consumer:probe-consumer:probe-agent
OUTCOME: resolved
DETAIL: SENTINEL: XPLUGIN-NONCE-1787193514-1432331022
```

### The exact working string, and how to construct it

The agent's frontmatter declares `name: probe-consumer:probe-agent`, and the plugin name is
`probe-consumer`. The working `subagent_type` is:

```
probe-consumer:probe-consumer:probe-agent
```

i.e. **`<plugin>:<frontmatter-name>`**, where the frontmatter name already carries a plugin prefix by
this repo's convention — hence the doubling. This is a measurement of the *probe* plugin, but the
error listing above independently confirms the same shape for every loomwright agent
(`loomwright:loomwright:worker` and siblings), so the rule is not probe-specific.

Two further facts the error text hands over for free:

- **Cross-plugin resolution genuinely works from a loomwright surface.** All three
  `probe-consumer:probe-consumer:*` agents appear in the same available-agents namespace as the
  loomwright ones. There is no per-plugin partition.
- **The failure is loud, not silent.** Unlike the `skills:`/`hooks:` frontmatter silent-ignore that
  motivated this spike, a wrong `subagent_type` produces an explicit `not found` naming every valid
  alternative. A typo in a companion-plugin spawn will surface immediately.

**The caveat that matters:** an agent's registered `subagent_type` is derived from its *plugin name*.
If selvedge's agents keep frontmatter names like `selvedge:qa-executor`, the spawn string becomes
`selvedge:selvedge:qa-executor` — and any loomwright surface that spawns them must use that exact
string. It is not derivable from the agent file alone; it depends on the installed plugin name.

---

## Chosen fallbacks and why

Unknowns A and C resolved, so no fallback is needed for them; the reasoning for *not* taking the
stated alternatives is recorded anyway, because "we didn't need it" is not the same as "we
considered it".

### Unknown A — no fallback taken

The source requirement listed three fallbacks in preference order. All three are **declined**, and
each is declined for a reason specific to it rather than by blanket appeal to the measurement:

1. **Drop the preload, reference it as read-on-demand prose.** Declined. This was the *preferred*
   fallback and it is now strictly worse than doing nothing: it would trade a working zero-runtime-cost
   preload for a runtime read on every invocation. Its one genuine upside — a lower
   `check-token-budget.sh` proxy weight — is a cost optimisation available independently, not a
   reason to abandon a mechanism that works.
2. **Selvedge declares its own narrower checklist skill.** Declined. Justifiable only if the content
   were genuinely different; a narrower copy of the same items is duplication-that-drifts under a
   different name. With cross-plugin preload working there is no forcing function for it at all.
3. **Vendor a copy of `quality-checklist` into selvedge.** Declined, and it was already the stated
   last resort. It contradicts owner decision 2 outright and would need a CI parity check to stop the
   two copies diverging — permanent machinery to solve a problem that does not exist.

**Chosen:** `selvedge:qa-executor` and `selvedge:qa-strategist` keep `quality-checklist` in their
`skills:` frontmatter and preload it from loomwright. One copy, no anti-drift machinery.

One constraint travels with this choice: per the control arm, a companion-plugin agent's resolved
tool list must not be empty. Any hardening of the selvedge QA agents by subtraction must leave at
least one subagent-eligible tool standing, and `TaskOutput` does not qualify.

### Unknown B — fallback REQUIRED and chosen

`${CLAUDE_PLUGIN_ROOT}` is per-plugin, so a selvedge hook cannot reach
`loomwright/scripts/send-telemetry.sh` or `emit-token-ledger.sh`. The alternatives, and why the
chosen one wins:

| Option | Assessment |
|---|---|
| **(a) Copy the two scripts into selvedge** | **Rejected.** Directly violates owner decision 2, and these are exactly the scripts that must not fork — `code-reviewer` and other matchers share them, so a divergence would silently change telemetry semantics for one agent only. |
| **(b) Hard-code an absolute path to the loomwright install** | **Rejected.** The install path is machine-specific and version-stamped (`.../atelier/loomwright/15.36.0`, as this very spike had to resolve dynamically). It would break on every loomwright version bump, and — under `\|\| true` — break **silently**. |
| **(c) Derive loomwright's root at hook time** (e.g. read `installed_plugins.json`, as `run-probe.sh` does) | **Rejected as a default.** It works, and this spike proves it works, but it makes selvedge depend on the plugin manager's private state file. That is an unstable contract to build a shipped hook on. |
| **(d) Keep the shared-script fan-out hooks in LOOMWRIGHT, matched on the selvedge agent** | **CHOSEN.** |

**Chosen: (d).** Hooks are matched by agent identity, not by owning plugin, and Unknown C proved the
identities are visible across the plugin boundary in one shared namespace. So loomwright keeps a
`SubagentStop` matcher for `selvedge:selvedge:qa-executor` carrying the telemetry + token-ledger
fan-out, where `${CLAUDE_PLUGIN_ROOT}` correctly resolves to loomwright and the scripts stay
single-copy. Selvedge's own `hooks.json` keeps only `validate-qa-result.py`, whose script moves with
it and whose `${CLAUDE_PLUGIN_ROOT}` correctly resolves to selvedge.

This splits the two hooks by *which plugin owns the script*, which is the real coupling, rather than
by which plugin owns the agent. It costs loomwright a small permanent awareness of selvedge's agent
names — recorded honestly as the price, and the reason slice 03 should confirm it against the
`/dreaming` surface before implementing.

> **Scope note.** Slice 03 makes the behavioural call. This slice supplies the capability fact and a
> defensible default; it does not implement anything.

### Unknown C — pin the string, do not derive it

No fallback needed, but a decision is: `/dreaming --agent qa-executor` must spawn
`selvedge:selvedge:qa-executor`, and that literal string has to be written down wherever the spawn
happens, because it depends on the installed plugin name and cannot be derived from the agent file.
Retiring `--agent qa-executor` — the alternative the source requirement floated — is unnecessary.

---

## Measurement provenance and teardown

### Provenance

| Item | Value |
|---|---|
| Date | 2026-08-20 |
| Claude Code version | 2.1.228 (captured by the probe, not quoted from memory) |
| Loomwright version present | 15.36.0, source `loomwright@atelier` |
| Installed loomwright body | `/Users/vikashruhil/.claude/plugins/cache/atelier/loomwright/15.36.0` |
| Install scope used by the probe | `local` only — never `user`, never `project` |
| Run-scoped nonce | `XPLUGIN-NONCE-1787193514-1432331022` |
| Transcripts | `cross-plugin-probe/transcripts/2026-08-20-{unknown-a,unknown-b,unknown-c,teardown}.log` |

All four transcripts come from the **same** run (scratch `loomwright-xplugin-probe-97054`) and carry
the same nonce, so they cross-check each other rather than describing four different states.

### Teardown, asserted

Teardown is a `trap`, so it runs on success, failure and interrupt alike, and every command in it is
bounded. Raw assertion output:

```
ASSERT probe-host absent from plugin list ......... PASS
ASSERT probe-consumer absent from plugin list ..... PASS
ASSERT xplugin-probe absent from marketplace list .. PASS
ASSERT loomwright registrations unchanged ......... baseline=1 final=1 PASS
  baseline loomwright lines:
      ❯ loomwright@atelier
  final    loomwright lines:
      ❯ loomwright@atelier
```

```
ASSERT settings.local.json identical to pre-run backup ... PASS
```

The last one covers the only file `--scope local` writes. It is backed up byte-for-byte before the
run and restored (or deleted, if it did not exist) afterwards. It is gitignored via `.gitignore`'s
`.claude/*`, which is exactly why `--scope local` was chosen and `--scope project` forbidden.

### No probe write reached a shipped plugin surface

The **range** form is required here. The working-tree-vs-index form exits 0 when a stray edit was
*committed*, which is precisely the shipping case this check exists to catch:

```
$ git diff --exit-code origin/main...HEAD -- loomwright/skills/ loomwright/agents/ loomwright/commands/ loomwright/hooks/
$ echo $?
0
```

`.claude-plugin/marketplace.json` is unchanged — the probe marketplace was registered **by path**,
outside this repo's manifest. No QA agent, command, skill or hook moved. No `selvedge/` scaffold
exists. The agent/command/skill/hook counts in `plugin.json` are unchanged: this spike adds only
files under `docs/`, which carry no counts.

### Honest limits

1. **Two consistent artifacts are not proof.** Every block quoted above appears verbatim in a
   committed transcript, which turns one self-authored artifact into two that must agree — it raises
   the cost of fabrication, it does not eliminate it. One agent can author both. **The only true
   anchor is a human re-running the command at the top of this document.** That is the entire reason
   the harness is committed rather than described.
2. **One machine, one version, one day.** Every verdict is scoped to Claude Code 2.1.228 on macOS on
   2026-08-20. Nothing here is a statement about Claude Code in general.
3. **Arm 2 corroborates; it cannot prove.** A pre-existing marker phrase, however distinctive, cannot
   fully exclude reproduction from prior knowledge the way a run-scoped nonce can. Arm 1 is the
   load-bearing evidence.
4. **The probe measures the probe plugin.** Unknown C's working string was measured against
   `probe-consumer`. The available-agents listing corroborates the same shape for loomwright's own
   agents, but selvedge's exact string should be re-confirmed once selvedge is actually installed —
   it is one `claude -p` call, and the failure mode is loud rather than silent.
5. **Unknown B was measured on a `SessionStart` hook**, not on the `SubagentStop` matcher the QA
   fan-out actually uses. `${CLAUDE_PLUGIN_ROOT}` is an environment variable of the hook process, so
   the event type should not matter — but that reasoning is inference, and it is flagged here rather
   than buried.
