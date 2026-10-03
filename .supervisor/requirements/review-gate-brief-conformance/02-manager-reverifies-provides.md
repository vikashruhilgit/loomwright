# 02 — Manager re-verifies `provides:` on disk (stop trusting the worker's self-report)

## Problem
The per-subtask gate is the worker's own claim. `agents/worker.md` Step 5.5 has the worker run
`test -f` / `grep -nE` over its `provides:` list and emit `outputs_verified` + `outputs_gap`; the consumers
(`agents/execute-manager.md` §"v12 outputs_verified gate"; `agents/supervisor.md` Single-Agent Path step 3 and
Sequential Path gate) **parse that block and never re-run the checks** — the checkpoint even records
`check_run: "worker self-verification (Step 5.5)"`. Consequences already observed: a worker that dies before
emitting `WORKER_RESULT` leaves the gate with no input and nothing flags it (memory
`outputs-verified-silent-noop-on-dead-worker`); a worker that mis-reports `present` is believed. The only
on-disk verification the manager does today is Step 2b, and that checks a consumer's `requires`, not the
producer's `provides`. No script implements the check — it exists only as a prompt table, duplicated in
worker.md Step 5.5 and execute-manager.md Step 2b.

## Goal
One deterministic script implements the three `provides` checks; the manager (and the Supervisor on the inline
paths) runs it against the tree the worker wrote to, and its result — not the worker's — decides whether the
subtask passes the gate. A missing deliverable, or a worker that never reported, reaches the adjudication
checkpoint every time.

## Scope
1. **`loomwright/scripts/verify-provides.sh <brief_path> <subtask_id> [--root <dir>] [--kind-table]`**
   - Parses the named subtask's `provides:` list from the brief's `## Subtask Contracts` YAML (the exact shape
     in `skills/supervisor-readiness/SKILL.md` §"Complete example": `{kind, path, name?}` entries; `provides: []`
     is valid and yields an empty array).
   - Runs, per entry, the SAME checks as worker.md Step 5.5 / execute-manager.md Step 2b (`file` → `test -f`,
     `symbol` → `grep -nE '<escaped name>'`, `type` → `grep -nE '(type|interface|class|enum)\s+<escaped name>\b'`),
     relative to `--root` (default `.`). **Escape the name for ERE** — names containing `$`, `.`, `(`, `[`
     must match literally (add a fixture for each).
   - Prints ONE JSON object on stdout: `{"subtask_id","outputs_verified":[{kind,path,name?,status,check_run}],
     "outputs_gap":"<comma-separated missing items or empty string>","source":"verify-provides.sh"}`. The
     `outputs_gap` string format is byte-identical to the worker's (`path` or `path:name`) so consumers can
     diff the two.
   - **Emitter is fail-SAFE:** always exit 0. On unreadable brief / subtask not found / no `## Subtask Contracts`
     it prints `{"subtask_id":..., "status":"unverifiable","reason":"<brief_unreadable|subtask_not_found|no_contracts>"}`
     and the reason on stderr. Never writes anything; never executes brief content.
   - **`--kind-table`** prints the three-row check table as markdown — so worker.md and execute-manager.md can
     cite the script as the single definition instead of carrying two copies (D: replace both prompt tables with
     a pointer + the script's `--kind-table` output kept in sync by test, see 5).
2. **Execute Manager poll loop** (`agents/execute-manager.md` §"v12 outputs_verified gate"): after reading
   `.worker-summary.md` / `WORKER_RESULT`, run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-provides.sh" "$brief_path" "$subtask_id" --root "$worktree_path"`
   and apply the **consumer fails CLOSED** rule:
   - any on-disk `status: missing` ⇒ adjudication `EXECUTE_CHECKPOINT` **regardless of the worker's `status`**,
     `missing_outputs[].check_run` = the script's `check_run` string (command + exit code), not the
     self-verification label;
   - script `unverifiable` ⇒ checkpoint with `reason: "provides unverifiable: <reason>"` (a gate that cannot
     read its contract does not pass);
   - worker reported `present` but disk says `missing` (or vice-versa) ⇒ `record_decision(... "provides_mismatch:
     worker=<x> disk=<y>")` — disk wins; the disagreement is a signal for `/dreaming`, not a second gate;
   - **no `WORKER_RESULT` at all** (dead worker, turn-limit exit) ⇒ still run the script; its result is the
     gate input — this closes the silent no-op.
   Tool-call budget: +1 Bash per subtask; note it in the manager's tool-budget accounting.
3. **Supervisor inline paths** (`agents/supervisor.md` Single-Agent Path step 3 and Sequential Path gate): same
   call with `--root .` (main checkout on the feature branch), same fail-CLOSED rule, same `record_decision`.
   Cite the script by anchor, not line number (that reference "has drifted twice" per the file's own note).
4. **Worker** (`agents/worker.md` Step 5.5): keep the worker's self-verification (it is what lets a worker
   fix its own gap before reporting) but have it call the same script instead of the inline table, so there is
   one implementation. `WORKER_RESULT` v2 shape unchanged; `validate-worker-result.py` unchanged.
5. **Tests — `loomwright/scripts/test-verify-provides.sh`:** per-kind present/missing; ERE-special names match
   literally; `provides: []` → empty array + `""` gap; unreadable brief / unknown subtask / no contracts → the
   three `unverifiable` reasons, exit 0, stderr reason; `--root` honoured (fixture in a temp dir, cwd elsewhere);
   `outputs_gap` string byte-identical to the worker format for a two-item miss. **Seam grep-gate** (same suite
   or `test-provides-seams.sh`): execute-manager.md's poll-loop gate, both supervisor.md inline gates, and
   worker.md Step 5.5 each cite `verify-provides.sh`; the `--kind-table` output equals the table embedded in
   `docs/RESULT_SCHEMAS.md` (single committed copy). Mutation control: remove the script call from the
   execute-manager gate → the seam gate must fail. Register in the CI `test-*.sh` loop.
6. **Docs:** `docs/RESULT_SCHEMAS.md` WORKER_RESULT section — one paragraph: `outputs_verified` is
   worker-reported and is now cross-checked on disk by the consumer; `docs/ARCHITECTURE_CONTRACTS.md` Execute
   Manager / Worker invariant rows updated; CHANGELOG bullet. Update memory
   `outputs-verified-silent-noop-on-dead-worker` on close-out (the lesson becomes "closed by verify-provides.sh").

## Non-goals
- No semantic check. `symbol` still matches any line containing the name (a comment mentioning it passes) —
  a known weakness, recorded here, NOT fixed in this item: tightening the regex changes brief-authoring rules
  and belongs in its own item.
- No change to Step 2b (`requires` pre-spawn check) beyond optionally pointing at the shared table.
- No new gate: the adjudication checkpoint and its four options are unchanged; only the input to the existing
  gate stops being self-reported.
- Nothing runs in the detached `/review-pr` drain or in Phase 4.5.

## Acceptance criteria
- A fixture brief + worktree where the worker's `WORKER_RESULT` says `status: completed, outputs_gap: ""` but
  one `provides` file is absent: the manager's protocol yields an `EXECUTE_CHECKPOINT` with
  `adjudication_required: true` and a `check_run` string starting with `test -f`; state-trace shows the
  subtask is NOT marked complete.
- Same fixture with NO `WORKER_RESULT` (simulated dead worker): same checkpoint.
- A fixture where every `provides` item is present and the worker agrees: no checkpoint, no
  `provides_mismatch` decision, exactly one extra Bash call.
- `verify-provides.sh` with a name `Foo$Bar` and a file containing the literal `Foo$Bar` reports `present`; a
  file containing `FooXBar` reports `missing`.
- `verify-provides.sh` on a brief without `## Subtask Contracts` exits 0, prints `status: unverifiable`,
  `reason: no_contracts`, and the consumer protocol routes that to a checkpoint.
- `test-verify-provides.sh` passes; deleting the poll-loop script call fails the seam gate. Full `test-*.sh`
  loop, `check-doc-currency.sh`, `check-token-budget.sh` green before push.

## Evidence to record on close-out
The seam-gate mutation run (before/after), and one real Supervisor run's `record_decision` lines showing the
script ran per subtask.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-13T08:40:25Z
- **Brief:** .supervisor/jobs/done/2026-09-13-manager-reverifies-provides.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/217
