## VERIFY_EVIDENCE

The line schema of `.supervisor/verify/<run_id>/evidence.jsonl`, the **append-only evidence store** a
`/verify` run writes one fact at a time. Like §`session_end` and §QA_SESSION this is a **JSONL
state-file schema, not a hook-validated emitted result block**: no agent emits a `VERIFY_EVIDENCE`
block and no `SubagentStop` hook parses one. Validation is a **CLI gate** — `scripts/validate-verify-evidence.py`,
consumed by `verify-helpers.sh evidence-append`, which appends a line only when the validator exits 0
— so `## Validation Location` below is deliberately unchanged: this is not hook-layer validation.
The store exists because the QA lane's accounting layer failed in exactly the way this shape forbids:
an agent-written `coverage.json` reported a `failed` scope as `completed`, per-scope results had no
schema, and the roll-up was overwritten per scope. Here every fact is one validated appended line,
every human-readable summary is **derived** from those lines, and a total can only be computed, never
written.

**Layout of `.supervisor/verify/<run_id>/`** (gitignored with the rest of `.supervisor/`):

| path | writer | contents |
|---|---|---|
| `evidence.jsonl` | `verify-helpers.sh evidence-append` — ONE `>>` write per validated line, never read-modify-write | one fact per line, this schema |
| `rejected.jsonl` | `evidence-append` | every refused input, wrapped (shape below) — valid JSONL even when the input was not |
| `artifacts/<ac_id>/` | the walkthrough executor (item 03) | Playwright screenshots / traces / response bodies, referenced from `ac.artifacts[]` by path relative to `<run_dir>/` |
| `.notify-enabled` | `verify-run.sh preflight --notify` / `verify-run.sh notify-enable` | presence-only marker — cross-process signal telling the Task-spawned executor that `--notify` was passed (the flag itself is parsed by the `/verify` main thread, a separate process) |
| `.notified-needs_auth` / `.notified-first_fail` / `.notified-run_end` | `verify-helpers.sh evidence-append`'s `verify_notify_once` | presence-only, one per named event — guards each of the three `--notify` events (§ below) to fire at most once per run |
| `summary.md` | `verify-helpers.sh summary-build` — regenerated on EVERY append, atomic temp + `mv` | **DERIVED** from the lines; never hand-edited (an edit is overwritten on the next append) |
| `run.md` | item 07 (named here so the layout is complete; not created by the store) | the run's narrative report |

**One record shape, `event`-discriminated.** Every line carries the four common keys; the `event` value
selects which further keys are required. Unknown additive keys are **tolerated** on every event
(forward-compat) — the ONLY forbidden keys are `counts` / `totals` on `run_end`.

```yaml
VERIFY_EVIDENCE:                       # one JSON object per line
  schema_version: 1                    # integer, required — always 1 (a JSON `true` is NOT 1)
  ts: string                           # required — ISO-8601 UTC, `YYYY-MM-DDTHH:MM:SS[.fff]Z`
  run_id: string                       # required — `verify-<YYYYMMDDTHHMMSSZ>-<slug>` as minted by `verify-helpers.sh run-id`; must start with `verify-`
  event: enum [run_start, env, auth, ac, issue, pause, resume, run_end, impact_surfaces, spec_replay, spec_rederived]   # required

  # --- per-event required keys -------------------------------------------------
  run_start:
    ticket_path: string                # required — the requirement / brief being verified
    ticket_kind: enum [requirement, brief]   # required
    branch: string                     # required
    head_sha: string                   # required
    base_sha: string                   # required
    env_contract_hash: string|null     # REQUIRED KEY, NULLABLE VALUE — sha256 of `.agent/verify.json`; null when the contract is absent
  env:
    step: enum [non_prod_assert, start, health, seed, reset, stop]   # required
    outcome: enum [pass, fail, skipped]                              # required
    reason: string                     # REQUIRED non-empty when outcome is `fail`; optional otherwise
  auth:
    state: enum [authenticated, anonymous, needs_auth, expired]      # required
  ac:
    ac_id: string                      # required, non-empty — e.g. `AC3`; the key the summary groups by
    text: string                       # required — the acceptance criterion verbatim
    scope: enum [ticket, impact]       # required — the ticket's own AC, or an impact-surface check
    verdict: enum [PASS, FAIL, BLOCKED, NOT_VERIFIABLE]              # required
    classification: enum [REAL_BUG, DISCOVERY_GAP, ENVIRONMENT_ISSUE]|null
                                       # REQUIRED when verdict is FAIL or BLOCKED; MUST be null/absent on PASS and NOT_VERIFIABLE
    steps: string[]                    # required — may be empty
    artifacts: string[]                # required — may be empty; paths RELATIVE to <run_dir>/ (never absolute or `~`-anchored; a `..` segment is rejected — the path must stay inside the run dir)
    reason: string                     # REQUIRED non-empty for every non-PASS verdict; optional on PASS
    surfaces: string[]                 # OPTIONAL (item 06, additive) — surface names this AC exercises, matched against a LATER run's `impact_surfaces` for prior-AC regression; absent on every pre-item-06 line
    # NOTE (harness-port/04): `<run_dir>/impact-manifest.json` (a JSON array of `{id, text, source,
    # surfaces}`, authored by `agents/qa-executor.md` Phase 8.5, consumed by `verify-run.sh walk
    # --scope impact --manifest`) is NOT itself a documented schema in this file, and its `source`
    # field has NO enumerated value set here — it is free-form, like `PLAN_REVIEW_RESULT.issues[].
    # category` above, with three values used by convention: `prior_ac:<run_id>/<ac_id>`, `smoke`,
    # and `not_verified` (harness-port/04's addition). Do not infer an enum from this list.
  issue:
    text: string                       # required
    severity: enum [BLOCKING, HIGH, MEDIUM, LOW]                     # required
    route: string                      # optional
    artifacts: string[]                # optional — relative paths, as on `ac`
  pause:
    reason: string                     # required non-empty
  resume:
    reason: string                     # required non-empty
  run_end:
    status: enum [completed, aborted]  # required
    # NO `counts` / `totals` key at ANY depth — the validator rejects the line (`run_end_carries_counts`).
    # Counts exist only in the derived summary.
  impact_surfaces:                     # item 06 — ONE line per run, the diff→surfaces classification the impact pass recorded
    files: string[]                    # required — the mechanical `git diff --name-only base_sha...head_sha` file listing; may be empty
    surfaces: object                   # required — {<surface name>: [file, ...]}; may be `{}` (nothing classified yet); values are the files (from `files`, or a brief-sourced name with no files) mapped into it
    unmapped: string[]                 # required — `files` entries no surface claimed; may be empty
    brief_surfaces: string[]           # required — subsystem names sourced from a done brief Blast-Radius section; may be empty (the common case — real briefs rarely populate this section)
    limit: integer                     # required, >= 0 — the --impact-limit bound the prior-AC regression pass used (default 10)
  spec_replay:                         # token-economy 07 — one line per spec copied byte-for-byte from a prior same-ticket run
    ac_id: string                      # required, non-empty
    source_run_id: string               # required, non-empty — the sibling run_id the spec was copied FROM
    text_sha: string                   # required, non-empty — sha256 of the whitespace-normalised AC text (matched against the source run)
    churn_files: integer|null          # REQUIRED KEY, NULLABLE VALUE — >= 0 file-overlap count when measurable, else null (NEVER 0 as a stand-in for "unmeasurable")
  spec_rederived:                      # token-economy 07 — one line per re-authored replayed spec (at most one per ac_id per run)
    ac_id: string                      # required, non-empty
    reason: string                     # required, non-empty — the harness-classification BLOCKED reason that triggered re-derivation (e.g. spec_skipped, spec_not_run)
```

**Latest-per-`ac_id` rule.** A run may re-verify an AC (resume after a pause, a retry after an
environment fix). Every `ac` line stays in the file as history — the store is append-only — but the
summary counts **only the newest `ac` line per `ac_id`** (`group_by(.ac_id) | map(last)` over the
file's input order). Two lines for `AC1`, PASS then FAIL, therefore count as one FAIL and zero PASS.

**A FORCED pause-verdict is not "already verdicted" — `verify-helpers.sh first-unverdicted`'s
resume-eligibility rule.** `verify-run.sh walk`'s AC5 expiry override (`walk_apply_expiry_override`)
writes `ac` lines with `reason: session_expired` (the AC that actually hit the 401/403) or
`reason: run_paused_session_expired` (every later AC, forced regardless of its own spec result) — and
these two reasons are the ONLY place either string is ever written by that override. `first-unverdicted`
(the resume-position derivation AC6 relies on) computes its done-set over the LATEST `ac` line per
`ac_id` (the same latest-per-`ac_id` rule above) and treats an `ac_id` whose latest line carries one of
these two reasons as **NOT yet genuinely verdicted** — it re-enters the "still needs a spec" set on
resume. Every other verdict (a real PASS/FAIL, a BLOCKED for any other reason, NOT_VERIFIABLE) still
counts as done: a genuinely-decided AC is never re-run on resume, only the ones the expiry override
itself forced. Without this exclusion `first-unverdicted` would report "nothing left" for every AC from
the pause point onward the moment a session expires (existence-based, not reason-aware), permanently
stranding the resume — the store's append-only "latest wins" semantics are exactly what let the later,
genuine verdict from the retried `walk` supersede the forced one once the human signs back in.

**Three invariants the validator enforces so the summary cannot lie the old way:** a `run_end` line
**cannot carry totals** (any `counts`/`totals` key at any depth is `run_end_carries_counts`); a
**non-PASS verdict cannot omit its reason** (`non_pass_without_reason`); and a **FAIL/BLOCKED cannot
omit its classification** while a PASS/NOT_VERIFIABLE cannot carry one (`missing_classification` /
`classification_on_pass`) — so every failing fact says *what kind* of failure it is before it is
recorded, not in a roll-up written afterwards.

**Validator contract (`scripts/validate-verify-evidence.py`) — a CLI gate, so its EXIT STATUS is the
decision.** This is a deliberate, documented deviation from the sibling `validate-*.py` scripts, which
are `SubagentStop` hook emitters and MUST always exit 0 (a non-zero hook exit is masked by `|| true`).
This one is consumed by `evidence-append`, which appends only on exit 0 — a swallowed status would let
an invalid fact into the store, which is the failure the store exists to prevent. Stdlib-only (`json`,
`re`, `sys`); it does **not** import `result_block_parser` (YAML result blocks, not JSON lines).

| invocation | exit | stdout |
|---|---|---|
| `--line '<json>'`, valid | 0 | `{"ok": true}` |
| `--line '<json>'`, invalid | 1 | `{"ok": false, "reason": "<code>", "line": null}` |
| `<file>`, every non-blank line valid (an empty file is valid) | 0 | `{"ok": true}` |
| `<file>`, some line invalid | 1 | `{"ok": false, "reason": "<code>", "line": <n>}` — `n` is the 1-based **physical** line number of the FIRST offending line (blank lines are skipped but counted) |
| no / malformed arguments, unreadable file | 2 | nothing — the message is on stderr |

The reason set is **closed** (snake_case, grep-stable; the validator's docstring lists the same twelve
and `test-verify-evidence.sh` provokes every one and asserts both surfaces name them):

| reason | fires when |
|---|---|
| `not_json` | the line is not parseable JSON |
| `not_object` | parsed, but the root is not an object |
| `schema_version_mismatch` | `schema_version` absent or not the integer `1` |
| `missing_key:<k>` | a required key is absent — common keys, per-event keys, and the conditional ones: `env.reason` on `outcome: fail`, `pause`/`resume` `reason` (absent, null and `""` all report `missing_key:reason`) |
| `bad_type:<k>` | a present key has the wrong type or shape — incl. `ts` not ISO-8601 UTC, `run_id` not starting with `verify-`, an `artifacts[]` entry that is empty, absolute, `~`-anchored, or carries a `..` segment |
| `unknown_event` | `event` outside its enum |
| `unknown_verdict` | `ac.verdict` outside its enum |
| `unknown_enum:<k>` | any OTHER enum field outside its enum (`ticket_kind`, `step`, `outcome`, `state`, `scope`, `classification`, `severity`, `status`) |
| `non_pass_without_reason` | an `ac` line with a non-PASS verdict and an absent/null/empty `reason` |
| `missing_classification` | an `ac` line with verdict FAIL or BLOCKED and no (or null) `classification` |
| `classification_on_pass` | an `ac` line with verdict PASS or NOT_VERIFIABLE carrying a non-null `classification` |
| `run_end_carries_counts` | a `run_end` line with a `counts` or `totals` key at any depth |

Checks run in a fixed order (parse → object → `schema_version` → common keys → `event` → per-event
keys), so a line with several defects reports the first, deterministically.

**`rejected.jsonl` wrapper.** A refused input is never lost and never corrupts the store: `evidence-append`
wraps it with `jq --arg` (so the file is valid JSONL even when the input was not) and appends
`{"rejected_at": "<ts>", "reason": "<validator reason>", "line": "<raw input string>"}` — `reason` is
the validator's own code verbatim (e.g. `non_pass_without_reason`), or `validator_unavailable` when
`python3` is absent, or `validator_error:<rc>` for any other non-zero exit. `evidence.jsonl` is
byte-identical before and after a refusal.

**Stored bytes are validated bytes.** `evidence-append` canonicalises the input to ONE compact JSON
line (`jq -c`) *before* validation and writes exactly that line — `json.loads` accepts a pretty-printed
record, and written verbatim it would be N physical lines for one fact (a wrong `derived_from:` count,
and file-mode re-validation of the store fails at line 1). Input that is not exactly one JSON value is
left raw so the validator's own `not_json` names it; `rejected.jsonl` always carries the raw input. A
`summary-build` failure *after* a successful append is named on stderr and the exit status stays 0 —
the fact IS stored, and an exit 1 there would be indistinguishable from a refusal (a caller retrying on
it would replay the append and duplicate the fact).

**Frozen example — one line per event.** These are format illustrations with fixed sample values
(`ts`, `run_id`, the shas); per the `check-doc-currency.sh` header convention they are **not** current
claims and MUST NOT be "fixed" on a version bump.

```jsonl
{"schema_version":1,"ts":"2026-09-14T10:00:00Z","run_id":"verify-20260914T100000Z-example","event":"run_start","ticket_path":".supervisor/requirements/example/01-login.md","ticket_kind":"requirement","branch":"feature/login","head_sha":"0123456789abcdef0123456789abcdef01234567","base_sha":"fedcba9876543210fedcba9876543210fedcba98","env_contract_hash":null}
{"schema_version":1,"ts":"2026-09-14T10:00:01Z","run_id":"verify-20260914T100000Z-example","event":"env","step":"non_prod_assert","outcome":"pass"}
{"schema_version":1,"ts":"2026-09-14T10:00:02Z","run_id":"verify-20260914T100000Z-example","event":"env","step":"seed","outcome":"fail","reason":"prisma db seed exited 1"}
{"schema_version":1,"ts":"2026-09-14T10:00:03Z","run_id":"verify-20260914T100000Z-example","event":"auth","state":"authenticated"}
{"schema_version":1,"ts":"2026-09-14T10:00:04Z","run_id":"verify-20260914T100000Z-example","event":"ac","ac_id":"AC1","text":"Given a registered user, when they log in, then the dashboard loads","scope":"ticket","verdict":"PASS","classification":null,"steps":["open /login","submit valid credentials"],"artifacts":["artifacts/AC1/dashboard.png"]}
{"schema_version":1,"ts":"2026-09-14T10:00:05Z","run_id":"verify-20260914T100000Z-example","event":"ac","ac_id":"AC2","text":"Given a wrong password, when submitted, then an error is shown","scope":"ticket","verdict":"FAIL","classification":"REAL_BUG","reason":"no error rendered; form silently resets","steps":["open /login","submit wrong password"],"artifacts":["artifacts/AC2/after-submit.png","artifacts/AC2/trace.zip"]}
{"schema_version":1,"ts":"2026-09-14T10:00:06Z","run_id":"verify-20260914T100000Z-example","event":"issue","text":"Console error on every page: hydration mismatch","severity":"MEDIUM","route":"/","artifacts":["artifacts/console.txt"]}
{"schema_version":1,"ts":"2026-09-14T10:00:07Z","run_id":"verify-20260914T100000Z-example","event":"pause","reason":"needs_auth: storage state expired"}
{"schema_version":1,"ts":"2026-09-14T10:05:00Z","run_id":"verify-20260914T100000Z-example","event":"resume","reason":"storage state refreshed"}
{"schema_version":1,"ts":"2026-09-14T10:06:00Z","run_id":"verify-20260914T100000Z-example","event":"run_end","status":"completed"}
```

