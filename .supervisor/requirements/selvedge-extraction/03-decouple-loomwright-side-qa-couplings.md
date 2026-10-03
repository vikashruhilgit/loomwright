# 03 — Decouple the four loomwright-side QA couplings before the move

**Depends on:** 01 (unknowns B and C decide two of these four outright).
**May run in parallel with 02** — it touches no gate and no scaffold.

## Problem — four loomwright surfaces reach toward QA, and each needs a *decision*, not a port

Slice 04 is the atomic relocation. It is large because CI forces it to be. Everything that can be
decided and implemented **while the QA files are still in place** is pulled forward here, so 04
reduces to `git mv` plus mechanical pin updates. These four are the ones that qualify: none of them
requires the files to have moved, and each is a judgement call rather than a rename.

They are listed in descending order of consequence.

### (a) `/dreaming --agent qa-executor` — a LIVE spawn, mis-classified in the intake as a doc mention

`loomwright/commands/dreaming.md` spawns QA Executor in reflection mode. Evidence (verified
2026-08-18): the usage example `/dreaming --agent qa-executor`, the `--agent` flag row enumerating
`all | code-reviewer | red-team | qa-executor`, the spawn step ("each reflection Task spawn sets
`model: "sonnet"`"), the reflection-prompt template's per-agent role hint for QA Executor
("Focus on test-coverage and infrastructure-discovery patterns"), the tool-permission note naming the
three spawned agents, the sample output's `**Agents reflecting:** code-reviewer, red-team,
qa-executor` and `**[qa-executor]** _add_ →` proposal line, the `/qa-executor` forward-counterpart
row, and the "six agents have `memory: project`" enumeration.

`/dreaming` stays in loomwright. The agent leaves. **Three options — pick one:**

1. **Cross-plugin spawn** — `/dreaming` spawns `selvedge:qa-executor` (exact string per 01's
   unknown C). Preserves the feature. Only available if C resolved YES.
2. **Retire `--agent qa-executor` from `/dreaming`.** The `--agent` enum drops to
   `all | code-reviewer | red-team`, `all` covers two agents, and the reflection template's QA hint,
   the tool-permission note, the sample output, and the counterpart row are all swept. Honest and
   simple; loses QA reflection.
3. **Conditional/graceful** — `/dreaming` attempts the QA spawn and degrades cleanly with a stated
   message when selvedge is not installed. Best UX, most surface area, and it needs a **tested**
   not-installed path or it is worse than option 2 (a silent skip that looks like "nothing to
   reflect on" is exactly the failure class this repo keeps re-learning).

**Recommendation:** 1 if C resolved YES with a stable spawn string; otherwise 2. Option 3 only with a
tested absent-plugin branch. Whichever is chosen, **the `.claude/agent-memory/` store path changes
too** — see slice 06; `/dreaming`'s proposal-writing path names that store.

### (b) The QA telemetry + token-ledger fan-out — likely unrecoverable, and that is acceptable

The `SubagentStop` matcher `loomwright:qa-executor` carries **two** hooks. The second is the shared
fan-out:

```
payload=$(cat); printf '%s' "$payload" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry.sh" || true; \
printf '%s' "$payload" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-token-ledger.sh" || true
```

Per 01 unknown B, `${CLAUDE_PLUGIN_ROOT}` inside `selvedge/hooks/hooks.json` resolves to `selvedge/`,
so a selvedge hook **cannot** invoke those two loomwright scripts. And copying them into selvedge is
forbidden by owner decision 2 — they are shared with the `code-reviewer` matcher and others, so a
copy is duplication-that-drifts by definition.

What is downstream of that fan-out, and therefore at stake:

- `send-telemetry-core.sh` **Rubric C** — `schema = "QA_RESULT"`, task-type string `"qa-executor"`,
  pass rule `tests_passed == tests_generated AND gates >= 5`, with the `self_check_gates_passed`
  default of 5 and the `< 5` missing-gates branch.
- Golden fixtures `telemetry-fixtures/qa-failed.json` and
  `telemetry-fixtures/golden/qa-failed__allow_with_repo.golden.txt`.
- Token-ledger aggregation of `agent_type: "loomwright:qa-executor"` — asserted in
  `test-insights.sh` and `test-token-ledger.sh`.

**Three options — pick one:**

1. **Drop the QA fan-out.** Selvedge ships only the validator hook. Loomwright's Rubric C, fixtures,
   and ledger tests stay as-is (telemetry is opt-in and fails SAFE, so an unexercised rubric is inert,
   not broken). **Record explicitly that QA telemetry is no longer collected** — an unexercised rubric
   that nobody knows is unexercised is exactly the dead-tier failure this repo retired the graphify
   rung over.
2. **Retire Rubric C and its fixtures** along with the fan-out. Cleaner, deletes real code, and
   forecloses re-enabling QA telemetry later.
3. **Selvedge ships its own minimal emitter.** Violates owner decision 2 unless it is genuinely
   different rather than a copy. Requires justification, not just preference.

**Recommendation:** 1 — keep Rubric C dormant but **banner it as unexercised** in
`docs/TELEMETRY.md` with the reason and the date, so a future reader is not misled into thinking QA
telemetry flows. Do not silently leave it looking live.

**Consequence for slice 04's hook count:** dropping the fan-out means the whole matcher block leaves,
so loomwright goes **24 → 22**, not 24 → 23. If option 3 is chosen instead, re-derive the number from
`hooks.json` — never restate it from this brief.

### (c) `qa-executor:` in `run-ground-truth.sh` — a name reservation, not a port

`run-ground-truth.sh` recognizes an `## Executable Acceptance` bullet of the form
`qa-executor: <target>`, but it is **RECOGNIZED and DEFERRED to M2b slice 1b — it spawns nothing** and
records `unverified` with reason `qa_executor_dispatch_deferred_m2b_1b`. Mirrored in
`agents/plan-reviewer.md` (Criterion 14's classification rule), `skills/supervisor-readiness/SKILL.md`,
and `skills/self-heal-advisory/SKILL.md` (twice — the `unverified` fail-safe path and the trust-boundary
note).

Because it dispatches nothing, **nothing breaks either way.** But leaving it undecided leaves a
reserved name in loomwright pointing at an agent that no longer lives there.

**Two options:**
1. **Keep the reserved name in loomwright** and amend all four surfaces to say the eventual dispatch
   target is `selvedge:qa-executor` **when selvedge is installed**. Preserves the M2b design.
2. **Retire the reserved kind.** The classifier drops to `{cmd, corpus-task}`, plan-reviewer's
   Criterion 14 simplifies, and the deferred-reason string disappears.

**Recommendation:** 1 — it costs four prose edits and keeps a designed extension point. Whichever is
chosen, all four surfaces move together; a half-swept enumeration is precisely the agent↔command
mirror drift this repo has been bitten by, and no gate covers it.

### (d) Cosmetic transcript-grep regex lists — verify they are cosmetic, then leave or trim

`send-webhook.sh` and `notify-desktop.sh` each grep the last 200 transcript lines for a plugin-context
marker, and both alternations include `/qa-executor|/qa-strategist` alongside `loomwright:`. These are
**presence heuristics only** — they gate whether a notification fires, nothing else.

**Decision:** leave the command names in place (a user with selvedge installed still types
`/qa-executor`, and the marker still correctly indicates plugin context), but **update the surrounding
comments**, which currently mis-describe the alternation. `notify-desktop.sh`'s comment says the
patterns are "the 12 plugin slash commands" — after the move those two are another plugin's commands.
A comment that mis-describes its own regex is the "claim no check backs" class this repo already
generalized; fix the comment, do not churn the regex.

## Goal

Land all four decisions, implemented, with loomwright still owning every QA file. Zero count changes.

## Constraints / invariants

- **Counts unchanged:** agents 14, commands 21, skills 41, hooks 24. Nothing moves in this slice.
- Every decision is **recorded with its reasoning**, not just applied — options (a) and (b) foreclose
  user-visible capability and a future reader needs to know it was deliberate.
- Sweep enumerations **completely**. Decisions (a) and (c) each touch a documented enumeration
  repeated across several files; `check-doc-currency.sh` does **not** cover agent/command enumeration
  prose, so a half-sweep passes every gate and only a `consistency_audit` catches it. Grep the terms
  with flexible separators, and derive the search terms from the files' own vocabulary rather than
  guessing a form.
- Prompts are programs: `dreaming.md`, `plan-reviewer.md`, and the two skills being edited are
  executable logic. State-trace the `--agent` handling (what does `--agent all` do now? what does
  `--agent qa-executor` do when selvedge is absent?), do not just read for consistency.
- Fail-safe emitters keep `exit 0`; the `|| true` hook convention is untouched.

## Acceptance criteria

- [ ] (a) `/dreaming`'s QA handling decided, implemented, and swept across **every** surface in
      `dreaming.md` that names QA Executor — usage example, `--agent` row, spawn step, reflection
      prompt template hint, tool-permission note, sample output (both the "Agents reflecting" line and
      the `[qa-executor]` proposal line), the `memory: project` six-agent enumeration, and the
      forward-counterpart rows. Attach the grep proving zero stragglers.
- [ ] (a) If option 3 (graceful degrade) is chosen, the **selvedge-absent path is tested**, and it
      emits a distinguishable message rather than silently behaving like "nothing to reflect on".
- [ ] (b) Telemetry decision made and recorded in `docs/TELEMETRY.md` with reason and date. If
      Rubric C is kept dormant, it is **explicitly banner-marked unexercised** — not left reading as
      live.
- [ ] (b) The resulting loomwright hook count for slice 04 is **re-derived from `hooks.json`**
      (`jq '[.hooks[][].hooks[]] | length'`), stated in this file's decision record, and not copied
      from any prior estimate.
- [ ] (c) `qa-executor:` reserved-kind decision applied consistently across all four surfaces
      (`run-ground-truth.sh`, `plan-reviewer.md` Criterion 14, `supervisor-readiness/SKILL.md`,
      `self-heal-advisory/SKILL.md` ×2). `test-run-ground-truth.sh` still passes, and its coverage of
      the deferred path is preserved or its removal is justified.
- [ ] (d) `send-webhook.sh` and `notify-desktop.sh` comments accurately describe their own
      alternations post-split; regex behaviour verified unchanged.
- [ ] Counts provably unchanged; full CI green including the whole `test-*.sh` hard-gate loop.
- [ ] Every decision recorded with its **reasoning and the rejected alternatives**, in the file the
      behaviour lives in — not only in a PR description, which is not reachable from a clone.

## Out of scope

Any file relocation. Any count change. The `QA_RESULT` schema section's ownership (05). The
agent-memory store rename (06).

## Outcomes Rubric

- All four couplings decided and implemented while the QA files are still in place — 04 shrinks
- `/dreaming`'s live spawn is handled as a real capability decision, not a doc edit
- Telemetry loss (if chosen) is recorded and visibly banner-marked, never silently dormant
- The hook-count figure for 04 is re-derived from the file, not inherited
- Enumeration sweeps are complete and grep-proven, with terms derived from the files' own vocabulary
- Rejected alternatives are recorded alongside each decision, in the repo


## Status: done (PR #156, merge 742a6df)
- **Completed:** 2026-08-20T11:21:35Z
- **Brief:** .supervisor/jobs/failed/2026-08-20-decouple-loomwright-side-qa-couplings.md (brief file landed in failed/ although PR #156 merged)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/156
- **Reconciled:** 2026-09-21 by hand from the merged PR — the PR was merged outside the /automate loop, so nothing wrote this stamp at merge time.
