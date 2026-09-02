# Probe: does `PreToolUse[Task]` carry a spawn-side agent id joinable to `SubagentStop.agent_id`?

> **Scope.** This is the evidence gate for
> `.supervisor/requirements/loom-floor-ui/01-agent-spawn-event.md` (the `agent_spawn`
> event). The item's own rule is that the payload shape is **observed or not used** —
> `emit-progress-event.sh`'s header records that the real `SubagentStop` payload carries
> `last_assistant_message` + `agent_transcript_path` and **no** `result_block`, contrary to
> what was assumed at design time. Nothing here is derived from documentation.

## Verdict

**NO-GO** on the requirement as written — and the NO-GO is *informed*, not empty. The probe
ran, the hook fired, and the payload was measured. Per the source requirement's own framing
("A NO-GO with a committed fixture is a **successful** outcome for this item"), this closes
the item as a pass.

Superseded state: this document previously recorded **PROBE-BLOCKED** (the capture session
could not authenticate). That blocker was cleared on 2026-09-02 by minting a long-lived CLI
token, the probe was re-run, and the verdict below rests on six committed payload captures.
The PROBE-BLOCKED reasoning is retained in the sections that follow because the
blocked-vs-negative distinction it drew is what kept the item from closing on absent
evidence.

### The measured answer

`PreToolUse[Task]` **fires per subagent spawn** (2 spawns → 2 captures, 0 empty), but it
**does not carry `agent_id`**, and carries no id in the `SubagentStop.agent_id` namespace at
all. The requirement's gate — *"does not carry an id joinable to `SubagentStop`'s
`agent_id`"* — is therefore met, and the verdict is NO-GO.

| Event | Id field(s) present | Namespace |
|---|---|---|
| `PreToolUse[Task]` | `tool_use_id` | `toolu_…` |
| `PostToolUse[Task]` | `tool_use_id`, `tool_response.agentId` | both |
| `SubagentStop` | `agent_id` | `a…` |

### What the payload DOES offer (this is what items 02–05 re-scope against)

1. **A verified TRANSITIVE join**, demonstrated 2/2 on two real event pairs:
   `PreToolUse.tool_use_id` → `PostToolUse.tool_use_id` → `PostToolUse.tool_response.agentId`
   → `SubagentStop.agent_id`. It requires a **third** hook (`PostToolUse[Task]`), which the
   brief did not budget for, and it resolves the `agent_id` only when the agent **finishes** —
   so it does not give live spawn-time identity against the existing `agent_id`-keyed corpus.
2. **Spawn-time identity that needs no join at all:** `tool_input.subagent_type` and
   `tool_input.description` are both present on the spawn event. Keyed on `tool_use_id`, that
   is sufficient on its own to answer "who is working right now, and on what" — which was the
   actual motivating question. The `agent_id` join is only needed to correlate with the
   *historical* corpus.

### Three findings that contradict reasonable assumptions

Each of these would have produced a silently-wrong emitter if assumed rather than measured.

1. **The matcher is `Task`, but the payload reports `tool_name: "Agent"`.** Both hold at once.
   A consumer that filters on the payload's `tool_name` field expecting `"Task"` never fires.
2. **`effort` is an OBJECT here** (`{"level": "high"}`) but a **STRING** in the previously
   committed `subagentstop-full.json` (`"medium"`). Any emitter copying `effort` additively
   must tolerate both shapes.
3. **`agent_type` is already emitted on the stop side.** See "A correction to the requirement"
   below — GO scope item 3 was already implemented before this item began.

### Committed evidence

`loomwright/scripts/progress-event-fixtures/spawn-probe-2026-09-02/` — six captures
(2 × `PreToolUse[Task]`, 2 × `PostToolUse[Task]`, 2 × `SubagentStop`) from ONE real run of
two different agent types.

**Scrub note (this repo is public):** absolute home paths were replaced with `/nonexistent`,
and `session_id` / `prompt_id` / transcript paths with fixture placeholders. `tool_use_id`,
`agentId` and `agent_id` are retained **verbatim and consistently across all six files**
because they are load-bearing — the join is re-derivable from the committed fixtures alone,
and was re-verified 2/2 after scrubbing.

### What this branch deliberately does NOT ship

No `emit-agent-spawn.sh`, no `hooks.json` `Task` matcher, no `emit-progress-event.sh` change,
no doc-surface count bump — hooks stay at **24**. Brief AC #4, #5, #8, #9, #10, #11 and #12
are `not-applicable (NO-GO)`. Building the emitter on the transitive join would take hooks to
**26** and design around a completion-time id resolution the brief never reviewed; that is a
re-plan, not a continuation.

---

## The exact command run

```
bash loomwright/scripts/capture-task-spawn-payload.sh --out-dir <dir> --timeout 300
```

which builds a capture settings file and invokes, out-of-session:

```
claude -p \
  --settings <dir>/capture-settings.json \
  --agents  <inline JSON defining probe-alpha and probe-beta> \
  --model sonnet \
  --max-turns 12 \
  "Use the Task tool twice, one after the other. First spawn the probe-alpha subagent
   with the prompt \"say your done word\". Then spawn the probe-beta subagent with the
   prompt \"say your done word\". Do not use any other tool. Then reply with the two done words."
```

No permission-bypass flags. `-p` is required: a plain `claude` is interactive-by-default and
can hang detached on a permission prompt (same reason `dispatch-pr-review.sh` uses `-p`).

### Why the probe is out-of-session (brief R1 / R3)

Two constraints make an in-session probe impossible, and one of them makes a careless
in-session probe actively dangerous:

- **R1** — a `loomwright:worker` subagent **cannot spawn `Task` subagents** (spawn-depth), so
  the worker executing this item can never produce a `PreToolUse[Task]` event in its own
  session.
- **R3** — hooks are read at **session start**. Editing `.claude/settings.local.json` inside a
  live session is not a reliable way to arm a capture hook, so "no payload appeared" from a
  mid-session registration is indistinguishable from "the hook silently never armed". That
  would be a **false NO-GO**, which is worse than either real outcome.

A fresh `claude -p --settings <file>` session reads the capture hooks at *its own* start,
which sidesteps both. `--settings <file-or-json>` was verified as a real flag on the
installed CLI (`claude --version` → `2.1.237`).

The capture hooks registered were:

| Hook | Matcher | Purpose |
|---|---|---|
| `PreToolUse` | `Task` | the payload under test |
| `PostToolUse` | `Task` | fallback id source if `PreToolUse` carries none |
| `SubagentStop` | `.*` | the **join target**, captured in the *same run* so pairing could be measured on two real events rather than asserted |

---

## SUPERSEDED (2026-09-02): the blocked first run

> Everything from here to "The joinability measurement" records the FIRST run, which never
> reached the API. It is retained because the blocked-vs-negative distinction it drew is what
> stopped the item closing on absent evidence. The authoritative result is `## Verdict` above.

### The raw evidence that no payload was captured (first run)

Probe summary (`probe-summary.txt`), verbatim:

```
out_dir: <scratch>/probe1
exit_code: 1
timed_out: 0
pretooluse_task_captures: 0
posttooluse_task_captures: 0
subagentstop_captures: 0
PROBE_RESULT: BLOCKED — capture session exited 1 (see <scratch>/probe1/run.log)
```

`run.log`, in full — this is the entire output of the capture session:

```
Failed to authenticate: OAuth session expired and could not be refreshed
```

### The blocker is environment-wide, not probe-specific

Three independent controls, so the failure cannot be blamed on the probe's own wiring:

| # | Control | Result |
|---|---|---|
| 1 | Full probe, cwd = an empty scratch dir | `Failed to authenticate: OAuth session expired and could not be refreshed` |
| 2 | Bare `claude -p --max-turns 1 "reply with OK"`, cwd = repo root | identical message — **no `--settings`, no `--agents`, no subagent involved** |
| 3 | Bare `claude -p --output-format json`, cwd = `$HOME` | `"is_error":true`, `"terminal_reason":"api_error"`, `"duration_api_ms":0`, `"num_turns":1`, `"result":"Failed to authenticate: OAuth session expired and could not be refreshed"` |

Control 2 is the load-bearing one: it removes every element this probe added, and still
fails. `duration_api_ms: 0` in control 3 confirms the request never reached the API — this
is a local credential-refresh failure, not a rejected call.

Supporting facts, gathered without reading any secret:

- No `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or `CLAUDE_CODE_OAUTH_TOKEN` in the
  environment.
- No `~/.claude/.credentials.json` on disk; the macOS Keychain item
  `Claude Code-credentials` **exists** but the session it holds cannot be refreshed. Its
  contents were deliberately not read.

**Resolution is a user action** (`claude login`, or `claude setup-token` for a long-lived
token) — it is interactive and touches credentials, so it was not attempted here.

### No pre-existing real capture exists to fall back on

A repo-wide and `~/.claude`-wide search for `"hook_event_name": "PreToolUse"` returns only
**synthesized** payloads inside test scripts and hook-authoring docs
(`test-notify-desktop.sh`, the `plugin-dev` `hook-development` skill). None is a captured
payload. `loomwright/scripts/progress-event-fixtures/` contains exactly one file,
`subagentstop-full.json`, which is the stop-side fixture and not a spawn payload.

**No fixture is committed by this run, and that is intentional.** The brief's deliverable
list asks for a captured payload under `progress-event-fixtures/`; producing one here would
require fabricating it, which brief R4(b) exists to catch and the requirement forbids in
terms ("not synthesized, not derived from documentation"). An empty or invented fixture
would also be the most damaging possible artifact, because every downstream item would treat
it as observed. This gap is reported rather than papered over.

---

## The joinability measurement

Joinability has **two halves**. Only one of them could be measured.

### Stop side (the join target) — MEASURED, and it is sound

Measured on this repo's own live log
`.supervisor/logs/8d43da72-9b5b-4793-8599-d06e27b3a8b3.jsonl` (10,691 lines at time of
reading):

| Event | Lines | Distinct `agent_id` | Notes |
|---|---|---|---|
| `token_ledger` | 6,914 | — | `agent_id` on 100% |
| `subtask_complete` | 3,783 | — | `agent_id` on 100% |
| **both, combined** | 10,691 | **622** | ids are 17-char lowercase hex, e.g. `a00e8c8c4dbb147df` |

So the thing an `agent_spawn` event would need to join *to* exists, is populated on every
line, and is individually addressable. The spawn half is the unknown.

### Spawn side — MEASURED on the 2026-09-02 re-run

`PreToolUse[Task]` **fires once per spawn** (2 spawns → 2 non-empty captures) and carries
`tool_use_id`, `tool_input.subagent_type` and `tool_input.description` — but **no `agent_id`**
and nothing in the 17-hex-char `a…` namespace. The join to `SubagentStop.agent_id` exists only
transitively, via `PostToolUse[Task].tool_response.agentId`, and therefore only once the agent
has finished. Full detail and the committed fixtures: `## Verdict` above.

*(The paragraph this replaces said "NOT MEASURED — no claim is made in either direction." That
was correct for the blocked first run and is now superseded by measurement.)*

### A correction to the requirement, found while measuring

The requirement states the stop event carries **7** fields and specifically "**No
`agent_type`**". That is **wrong as a universal claim**. `agent_type` is already present on
**63 of 3,783** `subtask_complete` lines (1.7%) and on 79 `token_ledger` lines:

```
subtask_complete | agent_type present on 63 lines: {'loomwright:loomwright:worker': 63}
token_ledger     | agent_type present on 79 lines: {'loomwright:loomwright:code-reviewer': 79}
```

`emit-progress-event.sh` already copies `agent_type` additively when the payload offers it
(its `for opt in ("agent_type", "agent_id")` loop). It is absent on the other 98.3% of lines
because the **payload** omits it there, not because the emitter drops it.

**Consequence for the GO branch, whenever it is unblocked:** requirement scope item 3
("`agent_type` on the stop side too") is **already implemented** and needs no code change.
It should be struck from the GO branch rather than re-implemented. (The doubled
`loomwright:loomwright:` prefix is the known agent-type naming artifact, not a defect
introduced here.)

---

## Harness verification

The harness is the artifact that survives this blocked run, so its capture path was verified
independently of `claude`. This matters directly: if the sink were silently broken, a future
re-run would report "no payload fired" — a **false NO-GO** — which is precisely the R3 hazard
one level down.

| # | Control | Expectation | Result |
|---|---|---|---|
| **Plumbing** | Take the `PreToolUse[Task]` command **verbatim** from the generated `capture-settings.json` and pipe a marker payload into it | payload lands on disk | **PASS** — file written, byte-identical to stdin, `rc=0` |
| **MC1** | Delete the sink's `cat > "$out"` write, re-run the plumbing control | nothing captured | **FAILED AS EXPECTED** — 0 bytes captured |
| **MC1-revert** | Unmutated script, identical input | capture present | **PASS** — 7 bytes; the mutation was the sole cause |
| **MC2** | Degenerate stdin, each as its own case: empty · non-JSON · binary (`\x00\x01\xff`); plus unwritable sink dir; plus missing `--sink` argument | `rc=0` every time, never a crash | **PASS** — `rc=0` in all five |
| **MC3** | Capture counter over: no files · one empty file · one empty + one non-empty | `0 0` · `0 1` · `1 1` | **PASS** (run under `bash`, see note) |
| **MC4** | Probe mode with `claude` absent from `PATH` | reports `BLOCKED`, exits 0 | **PASS** |

### A defect MC1 found in this harness, now fixed

MC1 initially reported the mutated (write-deleted) sink as **FIRED**. Cause: `mktemp` creates
the capture file *before* stdin is written, so the original counter — which tested `[ -f ]` —
counted a **zero-byte** file as a successful capture. A completely broken sink would have
been reported as a captured payload: the mirror image of the false-NO-GO hazard.

Fixed by counting with `[ -s ]` and reporting empties separately, with a distinct
`PROBE_RESULT: FIRED-EMPTY` state for "the hook ran but delivered no stdin". MC3 pins all
three cases.

### Shell note (a real trap, hit during this run)

MC3 first appeared to fail with `no matches found` — a **zsh** error. The Claude Code Bash
tool runs **zsh**, while these scripts run under **bash**; zsh errors on a non-matching glob
where bash passes the literal pattern through (which the `[ -f ]` guard then skips). The
failure was in the inline reproduction, not in the script. MC3 was re-run with `bash
<file>` and passes. **Validate these scripts with `bash file.sh`, never by pasting their
body into the Bash tool.**

---

## Status of the brief's acceptance criteria

| AC | Status |
|---|---|
| #1 capture a real payload as a fixture | **MET** — 6 real captures committed under `progress-event-fixtures/spawn-probe-2026-09-02/`, observed not synthesized |
| #2 this record, with command + raw evidence + join measurement + verdict | **MET** |
| #3 NO-GO handling | **MET** — verdict is NO-GO, evidence and measured reason committed, remaining criteria recorded `not-applicable (NO-GO)` |
| #4, #5, #8 emitter / join demo / stop-side change | `not-applicable (NO-GO)` — no emitter written. Note the join itself IS demonstrated on two real event pairs (AC #5's evidentiary bar), but transitively and without an emitter |
| #6, #7 emitter degenerate inputs / worktree anchoring | `not-applicable (NO-GO)` — no emitter written |
| #9 consumers byte-identical | **VACUOUSLY MET** — no consumer-affecting file changed. Explicitly NOT claimed as a diff-proven result |
| #10, #11, #12 doc-surface lockstep | `not-applicable (NO-GO)` — hook count unchanged at **24** |
| #13 every new test case mutation-verified | **MET** for the harness controls (MC1 found a real defect in the harness itself) |

## Next step — for items 02–05, not for this item

This item is closed. The re-scope it hands forward:

1. **Live "who is working now" is achievable today** without any join: key on
   `PreToolUse[Task].tool_use_id` and read `subagent_type` + `description` straight off the
   spawn payload.
2. **Correlating with the historical `agent_id`-keyed corpus needs a second hook**
   (`PostToolUse[Task]`) and resolves only at agent completion. That is a design change worth
   its own requirement — hooks would go 24 → 26, and the brief that passed Plan Review
   budgeted for one new hook, not two.
3. **Item 01's scope item 3 was already done before it started** — `agent_type` is emitted on
   the stop side today (see the correction section above). Strike it from any successor.
4. **Do not assume payload shapes.** Three assumptions failed here: the matcher/`tool_name`
   mismatch, `effort` being an object in one payload and a string in another, and the
   already-implemented `agent_type`. Measure first; this harness makes that one command.
