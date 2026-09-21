# 01 — Cross-plugin resolution spike (GATE — nothing moves until this lands)

## Problem — the companion model rests on three unverified behaviours

Owner decision 2 says `selvedge` is a **companion**, not a standalone: it may depend on
Loomwright-owned shared assets instead of vendoring copies. Every slice after this one assumes three
cross-plugin resolutions work. **None of them has ever been exercised in this repo.**

`stackpack` is the only prior spin-off and it is a **partial precedent only** — 18 skills, no agents,
no commands, no hooks, no scripts. Consequently:

- **No loomwright agent preloads a stackpack skill.** Zero empirical precedent for cross-plugin
  `skills:` frontmatter resolution.
- **stackpack ships no `hooks.json`.** Zero precedent for a second plugin's `${CLAUDE_PLUGIN_ROOT}`.
- **stackpack ships no agents.** Zero precedent for cross-plugin `Task(subagent_type:)`.

And the failure mode here is **silent**, which is what makes this a gate rather than a risk note.
CLAUDE.md §"Hook gotcha" already records that Claude Code **silently ignores** `hooks`,
`mcpServers`, and `permissionMode` in plugin agent frontmatter — silent-ignore is an *established*
behaviour for this exact frontmatter block. A silently-dropped `skills:` preload fails no gate, logs
nothing, and produces a QA agent that is quietly less capable. CLAUDE.md's own description
("`skills:` pre-injects those skill bodies at spawn time (no runtime file-read)") says nothing about
resolution scope.

**Do not assume any of this works. Measure it.**

## Goal

Empirically resolve three unknowns against real installed plugins, record the answers with their
evidence, and pick the fallback for each NO. Ship a decision record. **Move no QA asset.**

## The three unknowns

### Unknown A — does an agent's `skills:` frontmatter preload resolve ACROSS plugins?

Under the companion model, `selvedge:qa-executor` and `selvedge:qa-strategist` preload
`quality-checklist`, which lives in **loomwright** and — per owner decision 2 — must not be
duplicated.

- `qa-strategist` preloads: `qa-strategy`, `qa-gates`, **`quality-checklist`**
- `qa-executor` preloads: `qa-strategy`, `qa-test-patterns`, `qa-gates`, `playwright-e2e`,
  **`quality-checklist`**

`quality-checklist` is the **only** skill that would cross the plugin boundary; the other four move
with the agents. So the whole question reduces to one skill.

**Fallbacks, in preference order (pick one and record why):**
1. **Drop the preload; reference it as read-on-demand prose.** The QA prompts gain a line pointing at
   `quality-checklist` in loomwright and consult it when relevant. Costs a runtime read; keeps a
   single copy; also *reduces* both agents' `check-token-budget.sh` proxy weight.
2. **Selvedge declares its own narrower checklist skill** covering only the QA-relevant items —
   a deliberate divergence, not a copy. Must be justified as genuinely different content, or it is
   duplication-that-drifts under a different name.
3. **Accept one vendored copy of `quality-checklist` in selvedge.** Last resort. If chosen, it needs
   an explicit anti-drift mechanism (a CI parity check between the two copies), because owner
   decision 2 exists precisely to prevent this.

### Unknown B — what does `${CLAUDE_PLUGIN_ROOT}` resolve to inside a SECOND plugin's `hooks.json`?

CLAUDE.md states `${CLAUDE_PLUGIN_ROOT}` "resolves to the plugin install dir". If that is per-plugin
(the expected answer), a hook declared in `selvedge/hooks/hooks.json` resolves to `selvedge/` and
**cannot** invoke `loomwright/scripts/send-telemetry.sh` or `emit-token-ledger.sh`.

This matters because the `loomwright:qa-executor` `SubagentStop` matcher carries **two** hooks:

1. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true` — moves cleanly, the
   script moves with it.
2. `payload=$(cat); … send-telemetry.sh …; … emit-token-ledger.sh …` — **cannot** move, because
   those two scripts stay in loomwright and are shared with `code-reviewer` and other matchers.

If B resolves per-plugin, the QA telemetry + token-ledger fan-out is **lost** unless it is
re-engineered — and re-engineering it by copying the scripts into selvedge violates owner decision 2.
Slice 03 makes that call; this slice supplies the fact.

**Also test the negative direction:** does `${CLAUDE_PLUGIN_ROOT}` even expand in the second plugin's
hooks at all, or is it empty/unset? An empty expansion turns the command into
`python3 "/scripts/validate-qa-result.py" || true` — which, because of the `|| true` convention,
**exits 0 and validates nothing.** That is a silent gate loss, so it must be checked explicitly, not
inferred from a green run.

### Unknown C — does `Task(subagent_type: "selvedge:qa-executor")` resolve FROM a loomwright surface?

Discovered while verifying the intake handoff, and **not** in the original coupling classification:
**`/dreaming --agent qa-executor` spawns QA Executor.** It is a live spawn, not prose —
`loomwright/commands/dreaming.md` documents it at the `--agent` flag row, in the spawn step ("each
reflection Task spawn sets `model: "sonnet"`"), in the reflection-mode prompt template's per-agent
role hint, and in the tool-permission note ("When `/dreaming` spawns them via
`Task(subagent_type: ...)`, they inherit the tool permissions declared in their registered
frontmatter").

`/dreaming` stays in loomwright. The agent leaves. So a loomwright command must reach a selvedge
agent — or `--agent qa-executor` must be retired. Slice 03 decides; this slice supplies the fact.

**Also check the doubled-prefix form.** Prior measurement in this project recorded that plugin agent
`subagent_type` values appear in a **doubled** form at spawn time
(`<plugin>:<plugin>:<agent>`), and the single-prefix form errored. Determine the exact working
string for a selvedge agent and record it verbatim — do not infer it from the loomwright pattern.

## Method — this is an OPERATOR-RUN spike, not a code trace

A static read of the codebase cannot answer any of these. The spike is only satisfied by running it.

1. Build a **throwaway probe plugin** (or a scratch `selvedge` skeleton — do **not** move real QA
   assets) registered in a local marketplace alongside loomwright.
2. Give the probe agent a `skills:` entry naming a **loomwright-owned** skill, and a **sentinel
   string** that exists only inside that skill body. Spawn the probe agent and ask it to echo the
   sentinel. Sentinel present ⇒ cross-plugin preload resolves. Sentinel absent ⇒ it does not.
   **Do not accept "the agent said it read the skill"** — assert on the sentinel.
3. Give the probe plugin a `hooks.json` whose command prints the expanded `${CLAUDE_PLUGIN_ROOT}` to
   a file. Trigger it. Read the file. Record the literal value (and whether it expanded at all).
4. From a loomwright surface, attempt `Task(subagent_type: "<probe-plugin>:<probe-agent>")` and the
   doubled-prefix variant. Record which resolves and which errors, verbatim.
5. `/plugin uninstall` + `/plugin install` both plugins first, per CLAUDE.md §"Adding or Modifying
   Agents" step 4, and verify with `/agent-help`. Note the desktop-vs-CLI install-location trap: do
   not diagnose the active plugin version from `~/.claude/plugins/cache/` — that is the CLI store and
   holds stale leftovers.

## Scope

1. Run the three probes above.
2. Commit a findings doc — `loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md` — recording, per
   unknown: the probe used, the **raw observed output**, the verdict (RESOLVES / DOES NOT RESOLVE /
   RESOLVES WITH CAVEAT), and the date + Claude Code version it was measured against.
3. Record the **chosen fallback** for each NO, with the reason it was chosen over the alternatives.
4. Delete the throwaway probe plugin; the findings doc is the deliverable.

## Non-goals

No `selvedge/` scaffold (that is 02). No QA asset moves. No count changes. No gate edits. No decision
about `/dreaming` or telemetry beyond recording the *capability* — the behavioural calls are 03's.

## Acceptance criteria

- [ ] All three unknowns answered by an **executed probe**, not by reading code or docs. The findings
      doc records raw observed output for each, not a summary of it.
- [ ] Unknown A: the sentinel-string test is used. A verdict of "resolves" is backed by the sentinel
      appearing in the spawned agent's output.
- [ ] Unknown B: the literal expanded `${CLAUDE_PLUGIN_ROOT}` value from the second plugin is
      recorded, **and** the empty/unset case is explicitly ruled in or out (the `|| true` convention
      means an unset expansion is a silent no-op, so a green run is not evidence).
- [ ] Unknown C: the exact working `subagent_type` string for a second-plugin agent is recorded
      verbatim, including whether the prefix is doubled; the failing form and its error text are
      recorded too.
- [ ] For every unknown answered NO, a fallback is chosen **and justified against the alternatives**
      — not merely listed.
- [ ] `loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md` is committed and reachable from a fresh
      clone (it is the evidence every later slice cites; a finding living in a gitignored scratch dir
      is void — this repo has already been burned by exactly that, see twin-loop item 06).
- [ ] The findings doc is dated and names the Claude Code version measured against, so a future
      reader can tell whether the answer has expired.
- [ ] Throwaway probe plugin removed; `.claude-plugin/marketplace.json` unchanged at merge.
- [ ] All CI gates green (trivially — nothing functional changed).

## Outcomes Rubric

- Three unknowns empirically resolved, each with raw observed evidence, not inference
- Sentinel-based proof for the preload question — no self-reported "I read the skill"
- The silent-failure paths (dropped preload, unset `${CLAUDE_PLUGIN_ROOT}` under `|| true`) are
  explicitly ruled in or out rather than assumed absent
- A chosen, justified fallback exists for every NO — the queue can proceed either way
- Evidence is committed and citable from a fresh clone, dated, and version-stamped
- No QA asset moved, no count changed, repo green


## Method note (added 2026-08-20 by the /automate engine at RUN — measured, not assumed)

Method step 5 says `/plugin uninstall` + `/plugin install`. **Those are interactive terminal-dialog
slash commands and are NOT available in every session type** (they are unavailable in the desktop /
SDK-hosted session this spike was dispatched from). A worker that waits on them stalls, and a worker
that "infers the answer instead" violates this slice's whole premise.

**Measured on 2026-08-20: a non-interactive CLI exists and covers every step.** `claude plugin --help`
resolves; the relevant verified subcommands are:

- `claude plugin marketplace add <source> [--scope user|project|local]` — `<source>` is documented as
  "a URL, path, or GitHub repo", so a **local path** to a throwaway probe marketplace works. Use
  `--scope local` so the probe never touches user- or project-scoped config.
- `claude plugin install <name>@<marketplace> [--scope user|project|local]`
- `claude plugin uninstall <plugin>`, `claude plugin marketplace remove <name>` — the teardown.
- `claude plugin list`, `claude plugin details <name>`, `claude plugin validate <path>`.

**The registration constraint that shapes the whole probe:** a newly installed plugin's agents,
skills, and hooks do NOT become available inside the session that installed it (`claude plugin update`
states "restart required to apply"; the same holds for install). A Supervisor worker is a Task
subagent of the *dispatching* session, so **the worker cannot spawn the probe agent itself.**

**Therefore each probe must be observed from a FRESH `claude -p` process**, which starts a new session
that loads the newly installed probe plugin:

- **Unknown A / C** — `claude -p "<prompt that Task-spawns the probe agent and asks it to echo the sentinel>"`
  and capture stdout. Assert on the **sentinel string**, per the acceptance criteria — not on the
  agent's self-report. Record the exact `subagent_type` string that worked and the verbatim error text
  of the one that did not.
- **Unknown B** — the probe's `hooks.json` command writes the expanded `${CLAUDE_PLUGIN_ROOT}` to an
  absolute path under a scratch dir; run any `claude -p` prompt that triggers the matcher, then read
  the file. **Write the value in a form that distinguishes empty from unset** (e.g.
  `printf '[%s]\n' "${CLAUDE_PLUGIN_ROOT}"`), because the `|| true` convention makes an empty
  expansion exit 0 and look green.

**Two traps already recorded in this project's memory that apply directly here:**

1. **Detached/headless `claude` needs `-p`.** Plain `claude` (and `claude --agent X`) is
   interactive-by-default and can hang on a permission prompt with no TTY. Use `-p`. Do **not** add
   permission-bypass flags — that is a deliberate project constraint.
2. **Do not read the active plugin version out of `~/.claude/plugins/cache/`** — that is the CLI store
   and holds stale leftovers. `claude plugin list` / `claude plugin details` is the authority. (This
   trap is already named in Method step 5; it is restated here because the CLI path makes it easy to
   `ls` the cache instead.)

Nothing else in this slice changes: still no `selvedge/` scaffold, no QA asset moves, no count
changes, and `.claude-plugin/marketplace.json` must be **unchanged at merge** — the probe marketplace
is a throwaway registered by path outside this repo's manifest, not an entry added to it.

## Status: done (PR #153, merge 97ff83d)
- **Completed:** 2026-08-20T06:11:44Z
- **Brief:** (engine-driven; see automate-2026-08-18-124023.md)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/153
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
