## WORKER_RESULT

Produced by Worker agent on task completion.

```yaml
WORKER_RESULT:
  schema_version: 2                    # integer, required — v2 adds outputs_verified + outputs_gap (v1 still accepted during the v12.0.0 transition window)
  task_id: string                      # required — subtask identifier (e.g., "BD-15a" or "add-auth-guard")
  status: enum [completed, failed, partial]  # required
  files_modified: string[]             # required — when status=completed, at least one of files_modified/files_created/files_deleted must be non-empty, unless no_changes: true
  files_created: string[]              # optional — new files created
  files_deleted: string[]              # optional — additive, does NOT bump schema_version (stays 2); files the subtask deleted. `none` / `[]` / absent all mean no deletions (agents/worker.md emits `none` by default). Counts as a change for the completed-needs-a-file rule and the `no_changes` contradiction check (`scripts/validate-worker-result.py` rules 2 and 12); not otherwise shape-validated.
  tests_added: string[]                # optional — test files added or modified
  tests_passed: boolean                # optional — true if all tests pass
  outputs_verified: object[]           # required (v2) — itemized verification of every output the brief promised
    - kind: enum [file, symbol, type]  # required — what was checked
      path: string                     # required — repo-relative path the check was performed against
      name: string                     # optional — symbol/type name (required when kind in {symbol, type})
      status: enum [present, missing]  # required — outcome of the check
  outputs_gap: string                  # required (v2) — empty string when nothing missing; non-empty implies status MUST be partial
  out_of_lane: string[]                # optional — additive, does NOT bump schema_version (stays 2; D6, v15.20.0); absent by default or "[]" when nothing to report. Paths the worker touched that matched no glob in its OWN subtask's declared `lanes:` (skills/supervisor-readiness/SKILL.md §"Lane Declaration Schema"). REPORT-ONLY — never influences `status` or `outputs_gap`; see the dedicated invariant note below. Validated when present (unlike memory_candidates, which is never validated) — see check-contract-parity.sh's WORKER_RESULT MANIFEST row.
  deviations: string[]                 # optional — additive, does NOT bump schema_version (stays 2, same precedent as out_of_lane); absent by default or "[]" when explicitly nothing to report. Each entry is a non-empty string, by convention prefixed `plan:` (did something other than the subtask said), `edge:` (an edge case the brief did not name and how it was handled), `open:` (a decision the brief left open and which way it went), `test:` (a failing test's diagnosis), or `rule:` (a failing or unresolved human-stamped `must` house-rule check — produced ONLY by `scripts/worker-rule-selfcheck.sh` at worker Step 5, which prints at most 4 such lines: up to 3 per-rule-id lines, `rule: <id> — stamped must-check fails` / `rule: <id> — stamped must-check result unresolved`, plus one final `rule: +<K> more failing stamped must-checks (<N> total)` overflow line, each already truncated to fit 200 characters; this is the authoritative definition of that bound); an unprefixed entry is read as `other:` by consumers and is NEVER rejected for lacking a prefix. Bound: at most 12 entries, each at most 200 characters — the field rides in a ~200-token summary read (Execute Manager) and a capped Phase 4.5 advisory; longer stories belong in `.worker-summary.md` prose. REPORT-ONLY — never influences `status`, `outputs_gap`, or any other validation rule. Validated when present, same reason as `out_of_lane`: an unvalidated field lets malformed data through while `check-contract-parity.sh` stays green — see `scripts/validate-worker-result.py` rule 10 and check-contract-parity.sh's WORKER_RESULT MANIFEST row.
  memory_candidates: string[]          # optional — additive, does NOT bump schema_version (stays 2; an optional, backwards-compatible field needs no bump); absent by default. Durable, reusable structural facts about the codebase proposed for project memory; NEVER secrets/PII/tokens. Workers PROPOSE only — they never write memory (worktree-write ban / red-team F1); promotion is human-gated.
  not_verified: object[]               # optional — additive, does NOT bump schema_version (stays 2, same precedent as out_of_lane/deviations); absent by default; an empty list MUST be serialised as absent (never `not_verified: []`). One item per surface the worker's diff affects that it did not observe running (e.g. a rendered route/view, a CLI path, a consumer of a changed contract):
    - surface: string                  # required, non-empty — the surface not observed running
      reason: string                   # required, non-empty — e.g. "needs a write to a shared service", "no local runtime"
  no_changes: boolean                  # optional — additive, does NOT bump schema_version (stays 2); absent by default. `true` declares a read-only / verify-only subtask that correctly changed nothing — the ONE exemption from the completed-needs-a-file rule. `true` with a non-empty files_modified/files_created/files_deleted is rejected at any status. Validated when present (`scripts/validate-worker-result.py` rule 12).
  summary: string                      # required — max 200 tokens, what was done
  error: string                        # conditional — required when status=failed, describes what went wrong
```

**Validation rules (schema_version: 2):**
- `schema_version` must equal `2`
- `task_id` must be non-empty string
- `status` must be one of: `completed`, `failed`, `partial`
- When `status=completed`: at least one of `files_modified`, `files_created` or `files_deleted` must be non-empty (create-only and delete-only subtasks are valid; the `none` placeholder is empty) — **unless** the block declares `no_changes: true` (see the `no_changes` note below)
- When `status=failed`: `error` must be present and non-empty
- `summary` must be present and under 200 tokens
- `outputs_verified` must be present (may be `[]` only when the brief promised no concrete outputs); each entry must have `kind`, `path`, `status`; entries with `kind ∈ {symbol, type}` must include `name`; entries MAY carry the script's `check_run` string (command + exit code) — `validate-worker-result.py` checks only the required keys and ignores extra ones
- `outputs_gap` must be present as a string; an empty string means all promised outputs were delivered
- **Cross-field invariant (hook-enforced):** if `outputs_gap` is non-empty AND `status=completed`, the SubagentStop hook rejects with `outputs_gap non-empty must map to status: partial`. A worker that did not deliver all promised outputs has not completed.
- **Runtime checks performed by the SubagentStop hook (not part of the schema, listed for transparency):** the hook also verifies that a `.worker-summary.md` file was written (or that the output records the literal `summary_file_write_failed` degradation marker — the worker prompt's best-effort path) and that no destructive commands (`rm -rf`, `git push`, `git reset --hard`, `DROP`, `TRUNCATE`) appear in the run output.
- `memory_candidates` is **optional and additive** — it does NOT bump `schema_version` (stays `2` — an optional, backwards-compatible field addition does not require a version bump; `schema_version` bumps only for breaking or required-field changes). When present it is an array of short strings; absent by default. Each candidate must be a **durable, reusable structural fact about the codebase** (not transient run notes) that is not already captured in `CLAUDE.md`. Candidates **MUST NEVER contain secrets, credentials, tokens, or PII**. Workers **PROPOSE only** and never write project memory — a worktree write would be lost on worktree removal (red-team F1), so workers never call `write-project-memory.sh`; promotion of any candidate into project memory is **human-gated** and happens at the repo root.
- `out_of_lane` is **optional, additive, and validated-but-OPTIONAL** — it does NOT bump `schema_version` (stays `2`, same precedent as `memory_candidates`: an optional, backwards-compatible field addition needs no version bump). Omitting it is accepted at any `schema_version`; **when present**, it must be an array of non-empty path strings (`scripts/validate-worker-result.py` rule 9 rejects a present-but-malformed value — null, non-array, or non-string/empty entries — while still accepting absence). **`out_of_lane` deliberately diverges from the unvalidated `memory_candidates` precedent**: `memory_candidates` is never validated at all, whereas `out_of_lane` IS validated when present — leaving it unvalidated would let the field silently accept malformed data while `scripts/check-contract-parity.sh`'s WORKER_RESULT MANIFEST pin stayed green, which is exactly the silent-under-enforcement failure that gate exists to prevent. **`out_of_lane` is REPORT-ONLY and independent of the `outputs_gap`/`status` invariant above** — a worker records here any path it touched (`files_modified`/`files_created`/`files_deleted`) that matched no glob in its OWN subtask's declared `lanes:` (`skills/supervisor-readiness/SKILL.md` §"Lane Declaration Schema"); it never substitutes for, derives from, or influences `outputs_gap` or `status`. Lane-collision escalation (an out-of-lane path landing inside a sibling subtask's declared lane, where the two subtasks are not sequentially ordered in the `requires` DAG) is decided and surfaced by the CONSUMER of this result — **Execute Manager's poll loop on the PARALLEL path** — through the existing adjudication (`EXECUTE_CHECKPOINT` / `adjudication_required`) surface, never by the worker itself. **On the SEQUENTIAL path the Supervisor records `out_of_lane` (into `state.md`'s `## Worker Results`) but never escalates it**: subtasks run strictly serially in one working tree, so the concurrent-sibling condition the collision rule tests can never hold (`agents/supervisor.md` §"Sequential Path").
- `deviations` is **optional, additive, and validated-but-OPTIONAL** — it does NOT bump `schema_version` (stays `2`, same precedent as `out_of_lane`). Omitting it is accepted at any `schema_version`; **when present**, it must be an array of at most 12 non-empty strings, each at most 200 characters (`scripts/validate-worker-result.py` rule 10 rejects a present-but-malformed value — null, non-array, empty-string entries, over-count, or over-length — while still accepting absence). Each entry is by convention prefixed `plan:`/`edge:`/`open:`/`test:`/`rule:` (`rule:` is emitted only by `scripts/worker-rule-selfcheck.sh`, at most 4 lines — bound defined in the field comment above; a FIX_RESULT never carries it); an unprefixed entry is read as `other:` and is never rejected for lacking a prefix — the prefix is a consumer convention, not a validation rule. **`deviations` is REPORT-ONLY, mirroring `out_of_lane`'s independence from the `outputs_gap`/`status` invariant**: it never substitutes for, derives from, or influences `status`, `outputs_gap`, or any other validation rule. It is fed to the Phase 4.5 code-reviewer lens as an advisory only (`skills/self-heal-advisory/SKILL.md` step 1g) — never to workers or fixers as an instruction, and it never changes `heal_decision`, adds no gate, and adds no schema field of its own downstream.
- `not_verified` is **optional, additive, and validated-but-OPTIONAL** — it does NOT bump `schema_version` (stays `2`, same precedent as `out_of_lane`/`deviations`). Omitting it is accepted at any `schema_version`; **when present**, it must be an array of dicts, each with non-empty string `surface` and `reason` (`scripts/validate-worker-result.py` rule 11 rejects a present-but-malformed value — null, non-array, or a malformed item — while still accepting absence). Absent by default; an empty list MUST be serialised as absent — `not_verified: []` is a claim that the worker checked and found nothing unverified, which is a different statement from "the field does not apply", so the worker prompt (`agents/worker.md` §Step 5.75) instructs omitting the field entirely rather than emitting `[]`. **`not_verified` is REPORT-ONLY, mirroring `out_of_lane`/`deviations`'s independence from the `outputs_gap`/`status` invariant**: it never substitutes for, derives from, or influences `status`, `outputs_gap`, or any other validation rule. It records a surface the worker's diff affects that it did not observe running (a rendered route/view, a CLI path, a consumer of a changed contract) alongside a reason such a verification was skipped.
- `no_changes` is **optional, additive, and validated-but-OPTIONAL** — it does NOT bump `schema_version` (stays `2`, same precedent as `out_of_lane`/`deviations`/`not_verified`). It is the **one sanctioned exemption** from the completed-needs-a-file rule: `status: completed` with `files_modified`, `files_created` and `files_deleted` all empty is accepted when, and only when, the block declares `no_changes: true` — a read-only or verify-only subtask (count, inspect, confirm) that correctly changed nothing. **Why an explicit flag, not an inference** (2026-09-27): a worker handed a read-only task honestly reported completed-with-empty-lists and was re-prompted by the hook on every `SubagentStop` until the runtime's continuation cap forced the stop — its only way to satisfy the old rule was to fabricate a file entry, and a capped worker leaves only `rejected: true` `subtask_complete` rows, so `check-children-settled.sh` never settles it (§"Completion authority join"). Inferring "read-only" from `outputs_verified: []` alone would also accept a worker that merely forgot to run `verify-provides.sh`; the flag makes the claim deliberate and auditable, and the consumer's on-disk `verify-provides.sh` re-run (disk wins, below) stays the backstop against a false one. **When present** it must be a YAML boolean (`scripts/validate-worker-result.py` rule 12 rejects null or any other spelling); `no_changes: true` alongside a non-empty `files_modified`/`files_created`/`files_deleted` is a self-contradiction and is rejected at **any** status — deletions included, because a `no_changes` subtask is dropped from `merge_order` and a false claim over real deletions would leave them uncommitted. `no_changes: false` and absence are identical — the completed-needs-a-file rule applies. It exempts nothing else: the summary-file check, the `outputs_gap`/`status` invariant, and every other rule still apply. `status` is unchanged — a `no_changes` subtask is an ordinary `completed` to every consumer, except that **it has no branch content to commit or merge**: Execute Manager omits it from `EXECUTE_RESULT.merge_order` (it stays in `subtasks_completed` and `worktrees`, for cleanup), so FINALIZE's per-subtask commit/merge steps never see it.

**`outputs_verified` is worker-REPORTED and cross-checked ON DISK by the consumer (v15.71.0).** The worker fills the two fields by running `scripts/verify-provides.sh <brief> <subtask-id> --root .` (the ONE implementation of the three checks below); the consumer — Execute Manager's poll-loop gate on the Parallel path (`agents/execute-manager.md` §"v12 outputs_verified gate"), the Supervisor's Single-Agent / Sequential gates inline — re-runs the SAME script against the tree the worker wrote to, and **disk wins**: a `provides` item missing on disk reaches the adjudication `EXECUTE_CHECKPOINT` regardless of the worker's `status`, and a worker that never emitted a `WORKER_RESULT` is verified on disk instead of silently passing (`worker_result_absent`). A disagreement between the two is recorded as `record_decision(... "provides_mismatch: worker=… disk=…")` — a `/dreaming` signal, not a second gate. The script's `--kind-table` output is the single source of the check commands; this is its ONE committed copy (the `test-verify-provides.sh` suite fails if it drifts):

> **Completion is `provides` present on disk AND a terminal lifecycle event, never disk alone (v15.80.0).** `provides` present on disk (this section) is necessary but not sufficient — it proves the files exist, not that the producing agent ever terminated (a still-running worker whose files land early would otherwise pass). The SECOND, INDEPENDENT condition — `scripts/check-children-settled.sh --agent-id <id>` finding a terminal row (`subtask_complete` / `token_ledger` / `agent_lifecycle: failed` / `agent_lifecycle: ended`) for that worker's `agent_id` in the session JSONL log — is documented in full under `## agent_lifecycle JSONL event records` below (see "Completion authority join", added there). On disk-present-but-not-yet-settled, the consumer records `record_decision(... "provides_present_agent_unsettled: ...")` — **distinct from `provides_mismatch` above** (that string is reserved for a disk/self-report DISAGREEMENT and is unchanged by this addition) — and does NOT mark the subtask complete; this is the expected transient state for a worker whose files land before its result message does, not an error. (The source requirement, `.supervisor/requirements/orca-derived/02-completion-authority.md`, drafted this mechanism under the working name `outputs_verified_contradicted`; the decision string actually recorded by the shipped implementation is `provides_present_agent_unsettled`, kept distinct from `provides_mismatch` per that requirement's own corrected problem statement — this parenthetical is the only place `outputs_verified_contradicted` appears, as a naming cross-reference.)

<!-- kind-table:begin -->
| `kind` | Verification command | PRESENT condition |
|--------|----------------------|-------------------|
| `file` | `test -f <root>/<path>` | exit 0 |
| `symbol` | `grep -nE -- '<escaped name>' <root>/<path>` | any match (exit 0) |
| `type` | `grep -nE -- '(type\|interface\|class\|enum)[[:space:]]+<escaped name>([^[:alnum:]_]\|$)' <root>/<path>` | any match (exit 0) |
<!-- kind-table:end -->

**Validation rules (schema_version: 1, legacy):**
- `schema_version` must equal `1`
- All v2 rules except `outputs_verified` and `outputs_gap` (which are not present in v1)
- v1 emissions remain accepted by the SubagentStop hook for the v12.0.0 transition window. Workers running on v12.0.0+ MUST emit v2.

**Example (v2, happy path):**
```
WORKER_RESULT:
  schema_version: 2
  task_id: add-jwt-guard
  status: completed
  files_modified: [src/auth/jwt.guard.ts, src/auth/jwt.strategy.ts]
  files_created: [src/auth/jwt.guard.spec.ts]
  tests_added: [src/auth/jwt.guard.spec.ts]
  tests_passed: true
  outputs_verified:
    - kind: file
      path: src/auth/jwt.guard.ts
      status: present
    - kind: symbol
      path: src/auth/jwt.guard.ts
      name: JwtGuard
      status: present
    - kind: file
      path: src/auth/jwt.guard.spec.ts
      status: present
  outputs_gap: ""
  out_of_lane: []
  summary: Implemented JWT guard with passport strategy. Added unit tests with 92% coverage.
```

**Example (v2, partial — gap reported):**
```
WORKER_RESULT:
  schema_version: 2
  task_id: add-jwt-guard
  status: partial
  files_modified: [src/auth/jwt.guard.ts]
  files_created: []
  outputs_verified:
    - kind: file
      path: src/auth/jwt.guard.ts
      status: present
    - kind: file
      path: src/auth/jwt.guard.spec.ts
      status: missing
  outputs_gap: "src/auth/jwt.guard.spec.ts"
  summary: Guard implemented but unit-test file deferred (Jest config absent in the worktree); status partial because outputs_gap names the missing spec.
```

---

