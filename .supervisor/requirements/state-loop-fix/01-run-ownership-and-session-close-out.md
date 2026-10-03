# A run that ends must stop owning the log — run ownership and session close-out

## Problem

`.supervisor/state.md` in this repo has been pinned at `status: running`, `phase: EXECUTE`
since **2026-07-29**, for a run whose brief is already in `.supervisor/jobs/done/`. That run
**never emitted a `session_end`** — there is not one anywhere in its log. Everything below
follows from that one fact, and it is a closed feedback loop, not a one-off.

### The loop (measured on this checkout, 2026-09-05)

1. `emit-token-ledger.sh` and `emit-progress-event.sh` each resolve their log join key from
   `state.md`, adopting the plugin `session_id` whenever `- status:` is `running` or
   `checkpoint`. The guard's own comment reads *"stale completed/failed → do not join to
   finished run"* — but the status never **becomes** `completed`/`failed`, so the guard is
   permanently vacuous.

2. Consequently **every SubagentStop firing from every later session in this repo** is appended
   to that one run's log. Measured: **14,416 lines, 3.9 MB, 140 distinct `cc_session_id`s** in
   `.supervisor/logs/8d43da72-9b5b-4793-8599-d06e27b3a8b3.jsonl`.

3. `build-state.sh` derives `status` from the **last** of `{subtask_complete, session_end}` in
   that same log. Because foreign `subtask_complete` lines keep arriving every few seconds, the
   last event is always `subtask_complete` ⇒ `running`, `phase: EXECUTE`.

4. Which keeps step 1 true. The stale `running` causes the fan-in; the fan-in re-asserts the
   stale `running`.

### What the user actually saw

The Floor (`/ui`) rendered four lanes labelled `identity unknown`, a `QUEUE 1` / `EXECUTE` /
`recorded run_status running` pipeline, and lane ages of 16–34 minutes — with **no work in
flight at all**. The lanes were ordinary interactive chat turns being logged as a Supervisor
run. The lane set changed while the user watched, because it tracks whichever session most
recently fired a hook.

### A second, independent gap

`agent_type` is copied verbatim from the hook payload by both emitters and is never inferred.
Only **215 of 15,481** recorded lines (1.4%) ever carried one, and only two distinct values
(`worker`, `code-reviewer`) exist in the whole history. Every matcher block in `hooks.json`
already **is** the agent type it matches, so the value is known at match time and discarded.

### A third observation, mechanism NOT established

Every firing writes **1 `subtask_complete` + 2 byte-identical `token_ledger` lines** (same
`ts`, same `token_proxy_transcript_bytes`) — a rigid 1:2 ratio across every untyped agent, with
N up to 18 per agent. By contrast a real `loomwright:worker` fires exactly **once**. This looks
like more than one matcher block running per firing, but that is a hypothesis, not a finding.

---

## Goal

A run that has ended stops owning its log, and a run that ends without completing says so.
After this change, an interactive session's hook firings can never be attributed to a finished
Supervisor run, and `.supervisor/state.md` can never sit at `running` indefinitely.

---

## Scope

### A. Run ownership gate (the root fix)

In **both** `loomwright/scripts/emit-token-ledger.sh` and
`loomwright/scripts/emit-progress-event.sh`, in the `state.md` resolution block that currently
ends with the `running|checkpoint)` case:

After `PLUGIN_SESSION_ID` resolves non-empty, add an ownership test. The **owner** is the
`cc_session_id` carried on the **first line** of `.supervisor/logs/<PLUGIN_SESSION_ID>.jsonl`.
If that owner is non-empty and differs from the incoming payload's `session_id`, blank
`PLUGIN_SESSION_ID` so the firing lands in its own `<cc_uuid>.jsonl` instead.

This is self-healing on the existing artifact with **no migration and no manual edit**: the
polluted log's first line already carries `cc_session_id: 8d43da72-…`, the run's own session,
so all 140 foreign sessions are rejected the moment this ships.

### B. `SessionEnd` close-out

New `loomwright/scripts/close-stranded-run.sh`, plus the **first ever** `SessionEnd` entry in
`loomwright/hooks/hooks.json` (`SessionEnd` is a real Claude Code hook event; the plugin
currently registers zero).

When `state.md` exists, its status is non-terminal, **and this session is the recorded owner**
(same owner rule as A): append one `session_end` event carrying `status: failed` and
`reason: session_ended_without_completion`, then invoke `build-state.sh` to reproject. A
non-owner session does nothing at all.

### C. Staleness backstop in the projector

In `loomwright/scripts/build-state.sh`: when the derived status would be `running`, and the
newest **owner-originated** event in the log is older than a threshold (default 24h,
env-overridable), emit `failed` instead. This covers a session killed hard (SIGKILL, power
loss) where `SessionEnd` never fires.

### D. Agent identity on Floor lanes

In `loomwright/hooks/hooks.json`, prefix each emitting hook command with
`LOOMWRIGHT_AGENT_TYPE=<that matcher's agent type>`. In both emitters, take `agent_type` from
the payload first and fall back to that env var.

> **SUPERSEDED 2026-09-05 — withdrawn during execution, by owner decision.** D was implemented,
> then removed again in two steps (`6a9aaa6` for `emit-token-ledger.sh`, `e76472f` for
> `emit-progress-event.sh`); `LOOMWRIGHT_AGENT_TYPE` now appears **zero times** in the plugin.
> D rests on the premise that "every matcher block already *is* the agent type it matches", so
> the value is known at match time. **That premise was falsified by measurement, not by
> argument.** Grouping untyped events by `agent_id` on the live log yields a fixed
> 2 `token_ledger` : 1 `subtask_complete` in *every* bucket — (2,1)x125, (18,9)x107, (24,12)x63,
> (22,11)x61, (4,2)x45, (26,13)x37 — so the single `loomwright:worker` block runs on the **same
> untyped payloads** as the three ledger blocks. Registration under one matcher prevents
> DUPLICATION; it proves nothing about DISCRIMINATION. Injecting the matcher name would
> therefore stamp `agent_type: loomwright:worker` onto thousands of non-worker completions —
> which is precisely what **Non-negotiable 8 ("`agent_type` is never invented")** forbids, and
> it would also defeat the byte-identity dedupe guard, since two lines differing only in a
> fabricated `agent_type` can never compare equal. A secondary defect: the injected literal was
> single-prefix while the real payload vocabulary is doubled-prefix, so it would not have
> matched even on a genuine worker.
>
> **Non-negotiable 8 wins over Scope D.** Resolution in both emitters is now payload-only, key
> omitted entirely when absent. The Outcomes-Rubric line D was meant to serve — "the Floor stops
> attributing interactive chat turns to a Supervisor run" — **is still met**, by the Scope A
> ownership gate, which is what actually stops the misattribution. Lanes for untyped firings
> keep reading `identity unknown`; that is now a known, accepted gap rather than a silent one.
> Restoring agent identity from a *sound* source is separate, unscoped work.

### E. Duplicate `token_ledger` lines — probe first, fix only if confirmed

Establish the mechanism before changing anything. Only if a probe **confirms** multi-block
dispatch, add a per-firing idempotency guard. If the probe is inconclusive, say so in the
result and leave the emitter alone. Do not guess.

### F. Close out the existing stale run (one-time, data only)

**After A lands**, append one `session_end` for the 2026-07-29 run to its log so `state.md`
goes terminal.

---

## Decisions taken by the owner before planning (frozen — do not re-litigate)

- **D1.** The close-out records **`status: failed`** plus an explicit
  `reason: session_ended_without_completion`. `failed` is already inside the closed enum and is
  treated as terminal by every consumer; the `reason` field is what keeps it distinguishable
  from a genuine failure. **Do not** invent a new status word such as `abandoned`, and **do
  not** record an interrupted run as `completed`.
- **D2.** `paused` must **not** be emitted anywhere by this change. It is a trap: the two
  emitters use a positive allowlist (`running|checkpoint`) and would treat `paused` as dead,
  while `hook-dispatch-on-pr-create.sh` uses a negative denylist and would treat it as **live**
  and authorize a review drain. The word lands on opposite sides of the live/dead line
  depending on the reader.
- **D3.** The existing 3.9 MB log is **left intact**. All history is retained. Nothing is
  deleted, nothing is split, nothing is rewritten. Only `state.md` is closed out.
- **D4.** All of A–F are in scope for this change.

---

## Non-negotiables

1. **Both emitters keep failing SAFE.** They are runtime side-effect emitters, so per
   CLAUDE.md §Failure-Mode Invariants they must **always `exit 0`**. "Fails closed" here means
   refuse-to-adopt, never a non-zero exit. The `|| true` in their `hooks.json` entries stays
   legal only because of this.
2. **The unknown-owner case adopts, it does not refuse.** An absent, empty or unreadable log,
   or a first line carrying no `cc_session_id`, means *no owner recorded* ⇒ **adopt**
   (unchanged behavior). This preserves the property `agents/context-keeper.md` documents —
   that the first worker completion of a fresh run joins on the seeded plugin id, rather than
   falling back to the CC uuid. Refusing here would silently regress every fresh run.
3. **The two emitters stay byte-parallel.** They are deliberately pinned to each other;
   `emit-progress-event.sh` carries a `[pins:]` citation at the sibling's `running|checkpoint)`
   line. If that line moves, the pin must move with it.
4. **Staleness is measured over owner-originated lines only.** Measuring over all lines is
   precisely what made the original loop circular — foreign traffic kept "last event" fresh
   forever.
5. **`close-stranded-run.sh` never runs for a non-owner session**, and never writes when
   `state.md` is already terminal. It is an emitter, so it always exits 0.
6. **No new status word.** `status` and `phase` must land inside the closed enums in
   `skills/state-management/SKILL.md` §"State File Schema". Using only `failed` keeps
   `scripts/check-contract-parity.sh`'s per-file status-literal allowlists untouched.
7. **Reuse, do not reinvent.** The JSONL append and main-worktree anchoring idiom already
   exists in `emit-progress-event.sh` (resolve the main worktree by name from
   `git worktree list --porcelain`, with a `--show-toplevel` cross-check that aborts on
   mismatch — never bare `$PWD`). `close-stranded-run.sh` uses that, not a new one.
8. **`agent_type` is never invented.** Payload first, env second, key omitted entirely when
   neither has a value — the same additive-if-present discipline already used for
   `LOOMWRIGHT_ORIENTATION_SOURCE` and `LOOMWRIGHT_SHARED_PREFIX`.

---

## Non-goals

- Do **not** edit `.github/workflows/`. `anthropics/claude-code-action` skips itself on any PR
  that modifies a workflow file and still exits 0, so the PR could never review itself. CI
  already auto-globs `loomwright/scripts/test-*.sh`, so a new test needs no workflow edit.
- Do **not** split, rotate, prune or rewrite the existing log (D3).
- Do **not** attempt to type lanes retroactively. D only affects firings from the seven
  matcher-gated plugin agents, going forward.
- Do **not** add a prompt instruction telling an agent to "flip the status". That is the exact
  anti-pattern the one-writer mechanism exists to delete (`docs/PITFALLS.md` records the
  measured miss rate: 560 hook-written events vs 6 agent-written ones).
- Do **not** add a new gate. Nothing in this change may block a run.

---

## Depends on

Nothing. This branch is cut from `origin/main` at `b3ef8f3`.

---

## Release-surface obligations

- `loomwright/docs/TELEMETRY.md` — the ownership rule, the updated status-derivation table
  (§"Progress state"), and the honest limit in B below. **Also** the hard-coded
  `117 assertions` claim about `test-progress-state.sh`, which is the only assertion count in
  the docs and will go stale the moment cases are added. No mechanical gate catches it.
- `loomwright/docs/HOOKS.md` — one new row for the `SessionEnd` hook.
- `loomwright/skills/state-management/SKILL.md` — the ownership note.
- `.claude-plugin/README.md` — the `N quality gate hooks` / `N hooks centralized` counts.
  Adding a hook moves the number `scripts/check-doc-currency.sh` derives from `hooks.json`, and
  CI fails if these are not updated in the same commit.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump. Update the
  `description` counts **in place**; never append another version clause.
- **Citations:** any new `file.ext:N` in committed prose must carry
  `` [pins: `<literal>`] `` or use a descriptive anchor. `test-citation-drift.sh` fails any new
  bare citation, and its allowlist holds exactly one grandfathered entry.

**Honest limit to document, not to paper over:** a run resumed under a *different* Claude Code
session id will no longer join its original log. State it plainly in `docs/TELEMETRY.md`. Do
not add a heuristic to guess around it.

---

## Acceptance criteria

**AC-1 (ownership, positive).** A payload whose `session_id` equals the log's first-line
`cc_session_id` still joins on the plugin session id — the existing behavior is preserved.

**AC-2 (ownership, negative).** A payload whose `session_id` is a foreign uuid writes to
`<foreign-uuid>.jsonl` and **not** to the owned log. Assert on the owned log's line count being
unchanged, not merely on the new file existing.

**AC-3 (ownership, unknown owner).** Absent / empty / unreadable log, and a first line with no
`cc_session_id`, each adopt the plugin session id (non-negotiable 2). All four cases tested
separately; a single "degenerate input" case does not satisfy this.

**AC-4 (close-out fires).** With a non-terminal `state.md` owned by this session,
`close-stranded-run.sh` appends exactly one `session_end` carrying `status: failed` and
`reason: session_ended_without_completion`, and `state.md` is terminal afterwards.

**AC-5 (close-out withholds).** For a non-owner session, and separately for an already-terminal
`state.md`, it writes nothing and exits 0. Both cases tested.

**AC-6 (staleness backstop).** A log whose newest owner-originated line is older than the
threshold projects `failed`, not `running` — **and** a log with fresh foreign lines but a stale
owner line still projects `failed`. The second case is the actual bug; the first alone does not
prove the fix.

**AC-7 (agent identity).** ~~With `LOOMWRIGHT_AGENT_TYPE` set and no payload `agent_type`, the
emitted line carries the env value. With both present, the payload wins.~~ **SUPERSEDED
2026-09-05 — see Scope D above.** The env fallback was withdrawn from both emitters
(`6a9aaa6`, `e76472f`) because the measurement showed the matcher does not discriminate, so
adopting its name would *invent* an `agent_type` in violation of Non-negotiable 8. **The
surviving, testable half of AC-7 is unchanged and still holds:** with a payload `agent_type`
the emitted line carries it, and **with none, the key is absent — not empty-string, not
null.** Any test asserting the env-fallback half is obsolete and must be retired rather than
kept green against a mechanism that no longer exists.

**AC-8 (fail-safe preserved).** Every new path exits 0, including unreadable state.md,
unreadable log, absent `jq`/`python3`, and a malformed first line. Assert the exit code
explicitly.

**AC-9 (mutation control).** For the ownership gate specifically, a test must **fail** when the
gate is reverted. An assertion that passes with the mechanism deleted is vacuous and does not
count toward AC-1..3.

**AC-10 (real-artifact end-to-end).** After F, `.supervisor/state.md` in the main checkout
reads a terminal status, and `.supervisor/logs/8d43da72-….jsonl` **stops growing** across
several minutes of ordinary session activity. This is the single clearest signal the loop is
broken.

**AC-11 (suite green).** `bash scripts/check-doc-currency.sh`,
`bash loomwright/scripts/test-citation-drift.sh`, and every
`loomwright/scripts/test-*.sh` exit 0. Run each with `bash`, never pasted inline — the Bash
tool's shell is zsh and inline execution produces false failures.

**AC-12 (E reported honestly).** The result states either the confirmed duplicate mechanism
with its fix, or that the probe was inconclusive and the emitter was left alone. An unexplained
silence on E fails this criterion.

---

## Outcomes Rubric

- The self-reinforcing loop is broken at its cause — a finished run cannot capture a live session's events — not merely patched by resetting `state.md`.
- A run that ends without completing now says so mechanically, with no agent instructed to remember to do it.
- Both emitters still always exit 0, and the unknown-owner path still adopts.
- The ownership assertions are mutation-controlled and demonstrably non-vacuous.
- The Floor stops attributing interactive chat turns to a Supervisor run.
- The known limit (resume under a different session id) is documented rather than hidden.
- Every doc surface that states a count, a status vocabulary, or an assertion total is updated in the same commit.
- Nothing in the change can block a run.

## Status: brief-shipped

Job `.supervisor/jobs/done/auto-2026-09-05-121712-run-ownership-and-session-close-out.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
