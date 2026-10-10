## GROUND_TRUTH_JSON (System Twin ground-truth runner)

Emitted by `scripts/run-ground-truth.sh` — the System Twin **ground-truth instrument** (M2b slice
1a). It resolves a set of project-declared **executable acceptance checks**, runs each one (exit 0 =
pass, non-zero = fail), and emits a single hard PASS/FAIL signal. The script prints a human/grep
per-check block plus a `Checks passed: M/N` line, AND exactly ONE machine-readable line
`GROUND_TRUTH_JSON: {...}` (jq-built for injection safety). The runner ALWAYS exits 0 (a check's
non-zero exit is a normal `fail` tally, never a script crash). **Trust boundary (not a sandbox):** the
runner ITSELF performs no repo writes and makes no network calls, but a `cmd:` check runs an arbitrary
`bash -c` with full shell privileges — the "no writes / no network" property holds for the runner, NOT
for the trusted-by-construction checks it executes. Because Phase 4.5 runs this automatically and
unattended (incl. under `/autonomous`, where the `## Executable Acceptance` section is machine-authored
by Launch Pad), `cmd:` bullets are a trust-sensitive surface to review at Plan Review; `corpus-task`
ids are constrained to a single path segment so they cannot escape `eval-corpus`. **Safety valve:**
`--no-cmd` (or `GROUND_TRUTH_NO_CMD=1`) skips `cmd:`/bare checks entirely (recorded `unverified`,
reason `cmd_disabled` — never executed); `corpus-task:`/`qa-executor:` are unaffected. Supervisor
Phase 4.5 passes `--no-cmd` only when `NON_INTERACTIVE == true` (set by `--non-interactive-fallback`,
NOT by `/autonomous` alone — a default interactive `/autonomous "goal"` run leaves it unset). On every
OTHER path, a `cmd:`/bare bullet sourced from a brief is gated by the **content-keyed stamp gate**
described under §"`## Executable Acceptance` (brief convention)" below (red-team-hardening item 05,
"cmd: valve by provenance", v15.90.0) — this supersedes the prior framing that `--no-cmd` alone was
the only control on the unattended path; see that subsection for the full contract. It is consumed by
Supervisor Phase 4.5, which maps it onto the
`SUPERVISOR_RESULT.ground_truth` object and the flat `ground_truth_*` `session_end` fields (advisory
only — NEVER changes `heal_decision`, NEVER blocks the PR).

```json
GROUND_TRUTH_JSON: {
  "schema_version": 1,
  "ran": true,
  "status": "pass",
  "checks_total": 2,
  "checks_passed": 2,
  "pass_rate": "2/2",
  "per_check": [
    {"kind": "cmd", "target": "scripts/test-foo.sh", "status": "pass"},
    {"kind": "corpus-task", "target": "version-consistent", "status": "pass"}
  ],
  "commit": "268a6be",
  "date": "2026-06-07T15:43:00Z"
}
```

**Field contract (schema_version: 1):**
- `schema_version` — integer, required, always `1`.
- `ran` — boolean; `true` when ≥1 resolved check actually executed (a verifiable pass/fail), `false`
  on the no-source / no-`jq` / all-deferred fail-safe paths.
- `status` — one of:
  - `pass` — ≥1 check executed and passed, and ZERO checks failed (deferred `qa-executor` checks may
    coexist; they never block a pass).
  - `advisory_failures` — ≥1 resolved check exited non-zero (a `per_check` `fail` is present).
  - `unverified` — fail-safe tooling path: `jq` unavailable, OR checks resolved but NONE could be
    verified (zero passes AND zero fails AND ≥1 deferred — honest: nothing was actually verified).
  - `skipped` — no check source resolved (no `--check`, no `--brief` `## Executable Acceptance`
    section, no `--checks-file`/stdin, no `.supervisor/twin/ground-truth.json`). `ran:false`, `0/0`,
    empty `per_check`.
- `checks_total` — integer; count of resolved checks. `0` on the `skipped` (no source) and no-`jq`
  paths; **≥1 on the all-deferred `unverified` path** (a deferred `qa-executor` check is resolved and
  counts toward the total even though it executes nothing).
- `checks_passed` — integer; count whose check exited `0`.
- `pass_rate` — string `"M/N"` (e.g. `"2/2"`). `"0/0"` on the `skipped`/no-`jq` paths; the
  all-deferred `unverified` path reports the real `"0/N"` (N = the deferred checks counted in
  `checks_total`).
- `per_check` — array of `{kind, target, status, reason?}` objects, one per resolved check. **Order is
  source-dependent:** explicit `--check` / `--brief` / `--checks-file` preserve declaration order, but
  the `.supervisor/twin/ground-truth.json` fallback is `LC_ALL=C`-sorted for determinism — downstream
  readers should not assume declaration order in the fallback case.
  - `kind` — one of `cmd | corpus-task | qa-executor`.
  - `target` — the shell command (`cmd`), corpus task-id (`corpus-task`), or QA target
    (`qa-executor`).
  - `status` — one of `pass | fail | unverified` (a non-zero exit is a normal `fail` tally, never a
    crash).
  - `reason` — optional short string. Known values: `corpus_task_not_found` (missing task dir /
    `check.sh` — a missing dogfood target is a real `fail`), `corpus_task_invalid_id`, `empty_cmd_target`
    (a bare `cmd:` with no command), `cmd_disabled` (a `cmd:`/bare check skipped under `--no-cmd` /
    `GROUND_TRUTH_NO_CMD=1`), `cmd_unapproved` (red-team-hardening item 05, v15.90.0 — a `--brief`-sourced
    `cmd:`/bare bullet whose `## Configuration` stamp is absent or stale against the CURRENT bullet
    list; see §"`## Executable Acceptance`" below), `qa_executor_dispatch_deferred_m2b_1b` (the
    deferred `qa-executor` kind), and the five `rule:`-kind reasons `rule_not_found`,
    `rule_cmd_disabled`, `rule_unapproved`, `rule_check_failed`, `rule_unresolved` (defined once in
    §"`## Executable Acceptance`" below).
- `commit` — short commit SHA at run time, or `"unknown"`. **Contextual — NOT part of any determinism
  invariant.**
- `date` — ISO 8601 UTC timestamp at run time, or `"unknown"`. **Contextual.**

**Distinct from EVAL_RESULT and BENCHMARK_JSON:** "ground-truth" ≠ "eval" ≠ "benchmark". `EVAL_RESULT`
(`scripts/run-eval.sh`) is the **eval instrument** — a fitness function scoring plugin output quality
over a fixed corpus. `BENCHMARK_JSON` (`scripts/run-benchmark.sh`) is the **canary benchmark** —
validating the `session_end` hard-signal fixtures. `GROUND_TRUTH_JSON` (`scripts/run-ground-truth.sh`)
executes the *actual acceptance checks a brief/project declares*. The three are kept distinct by name,
dir, and intent.

**Scope honesty (M2b slice 1a vs deferred):** slice 1a (shipped v14.19.0) wires the **generic
executable-acceptance path** — `cmd:`/bare shell checks and `corpus-task:` checks resolved from a
brief's `## Executable Acceptance` section (or `.supervisor/twin/ground-truth.json`) and run after the
Code Reviewer pass in Phase 4.5. The `qa-executor:` kind is RECOGNIZED but **DEFERRED to slice 1b**
(per-check `unverified`, reason `qa_executor_dispatch_deferred_m2b_1b`; it spawns nothing). Auto-running
the full Launch Pad→Supervisor agent loop in CI against the corpus, and wiring ground-truth into a
ground-truth-execution gate, are **part-2 follow-ups** (deferred). See `scripts/run-ground-truth.sh`
and `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` §4 (M2) for milestone status.

### `## Executable Acceptance` (brief convention)

The optional `## Executable Acceptance` section in a brief is a list of `- ` bullets, each either a
raw shell command or a `<kind>: <target>` line where `kind ∈ {cmd, corpus-task, qa-executor, rule}`:
- `cmd: <shell>` (or a **bare** bullet with no recognized `kind:` prefix) — a shell command run from
  the **project root** (`--project <dir>` if the runner was given one, else the git toplevel of the
  caller's CWD, else the caller's CWD; Supervisor Phase 4.5 pins repo-root CWD, so there the project
  root IS the repo root); exit `0` = pass. An empty command (a bare
  `cmd:`) is a `fail` (reason `empty_cmd_target`), never a false pass. A command that itself starts
  with a dash MUST use the `cmd:` prefix (`cmd: -flag …`) — a *bare* leading-dash bullet would have its
  dash stripped as a bullet marker at ingestion.
- `corpus-task: <id>` — runs `scripts/eval-corpus/<id>/check.sh` via `bash` from the task dir with
  `EVAL_PROJECT_ROOT` exported = the same project root (the check verifies the **caller's** project,
  never the plugin's install dir — `scripts/eval-corpus/README.md` §"Project root"; like `run-eval.sh`,
  though without run-eval's present-but-non-executable-`check.sh` fail guard — here the check is always
  invoked through `bash`); exit `0` = pass. A missing task dir / `check.sh` is a `fail`
  (reason `corpus_task_not_found`), not a silent drop. The `<id>` is a single path segment (a `/` or
  `..` is rejected as `corpus_task_invalid_id`).
- `qa-executor: <target>` — RECOGNIZED but DEFERRED to slice 1b (per-check `unverified`).
- `rule: <id>` — a house rule (`.agent/rules/`), resolved by DELEGATION to `scripts/rules-check.sh`;
  `run-ground-truth.sh` never reads the rules store and never runs a `check` itself (`rules-check.sh`
  stays the one executor — `skills/rules/SKILL.md` §9). Each call runs at most ONCE per run, cwd = the
  project root, stdin `</dev/null`. Per-check reasons (the authoritative list — other surfaces point here):
  - `rule_not_found` (`fail`) — `<id>` is not printed by `rules-check.sh --list-selected` (absent id,
    an `advisory` rule, or a null-`check` rule): named, never a silent pass. Aggregate status is then
    `advisory_failures`.
  - `rule_cmd_disabled` (`unverified`) — `--no-cmd` / `GROUND_TRUTH_NO_CMD=1`: `rules-check.sh
    --if-stamped` is NOT invoked and nothing is parsed (a check is arbitrary shell, and its echoed text
    could forge a result line).
  - `rule_unapproved` (`unverified`) — `--if-stamped` printed `  [SKIP] all (unstamped)`: nothing ran.
  - `rule_check_failed` (`fail`) — exactly one whole-line `  [FAIL] <id>` and no other result line for
    the id.
  - `rule_unresolved` (`unverified`) — anything ambiguous: duplicate or conflicting result lines, a
    near-miss line, no line, a missing/mismatched `Checks passed: N/M` trailer, an rc outside {0,1},
    or a failed `--list-selected` call. A forged or ambiguous line only DEGRADES a result: a stamped
    check's echoed text can pre-print a forged `  [PASS] <id>` for ANY listed id (not only its own), so
    another rule's FAIL can be masked to `rule_unresolved`, but never promoted to `pass`.
  - `pass` requires exactly one whole-line `  [PASS] <id>` and no other result line for the id.

  A `rule:` bullet carries no shell, so it is machine-authorable (Launch Pad Phase 5 action 6a), is
  never hashed into the brief `sha256:` stamp, and is never flagged by Criterion 14. Its only
  authorization is the USER-SCOPE rules stamp (`skills/rules/SKILL.md` §8.1 — two stamps, never
  conflated). Honest limit: `--if-stamped` replays the WHOLE stamped must-set, not just the named ids;
  only the named ids are reported. So when a brief carries `rule:` bullets, Supervisor Phase 4.5 runs
  the stamped must-set TWICE per self-heal iteration — once via the rules-check (gate) replay
  (`skills/self-heal-advisory/SKILL.md` §"Rules-check replay", through `rules-gate-verdict.sh`) and once here; checks with side effects
  run twice. Plan Reviewer **Criterion 17** (`rule_conformance`) fails a brief
  that omits the `rule: <id>` bullet for an applicable checkable `must` rule.

Supervisor Phase 4.5 passes this section to `run-ground-truth.sh` via `--brief <brief_path>` (falling
back to `.supervisor/twin/ground-truth.json` when the brief has no such section).

**Authoring convention (trust boundary).** A **machine-authored** brief (Launch Pad, especially under
`/autonomous`) MUST emit `corpus-task:` bullets ONLY — never `cmd:`/bare shell (`agents/launch-pad.md`
Phase 5; `skills/supervisor-readiness/SKILL.md` §"`## Executable Acceptance`"). `cmd:` bullets are
reserved for human authorship. On the unattended/`--non-interactive` path Supervisor passes
`run-ground-truth.sh --no-cmd`, so a `cmd:` bullet there is skipped (`unverified`, reason
`cmd_disabled`) and never runs regardless of anything below — `--no-cmd` always wins.

**Content-keyed stamp gate (red-team-hardening item 05, "cmd: valve by provenance" — supersedes the
prior M3-forward-note framing; this is now the shipped behavior, not a future milestone).** On every
OTHER path (any run where `--no-cmd` is not passed — including a default, interactive `/autonomous`
run, where `NON_INTERACTIVE == false`; see `skills/autonomous-loop/SKILL.md`), a `--brief`-sourced
`cmd:`/bare bullet executes ONLY when the brief's `## Configuration` section carries a line
`- **Executable Acceptance Approved:** sha256:<hash>` whose `<hash>` equals
`scripts/exec-acceptance-hash.sh <brief>`'s CURRENT output — a `sha256:<hex>` of the
whitespace-normalized, newline-joined list of `cmd:`/bare bullets ONLY (`corpus-task:`/`qa-executor:`
excluded), or the literal `none` when that filtered list is empty. Both `exec-acceptance-hash.sh` (the
human-facing/authoring side) and `scripts/run-ground-truth.sh` (the enforcement side) source ONE
shared definition — `scripts/exec-acceptance-lib.sh` — so the classification/hash rule cannot silently
diverge between the two.

- **Absent or STALE stamp** (the hash no longer matches — e.g. a bullet was edited/added/removed after
  the stamp line was written): the bullet is recorded `per_check {status: "unverified", reason:
  "cmd_unapproved"}` and executes NOTHING. `cmd_unapproved` is distinct from `--no-cmd`'s
  `cmd_disabled` reason.
- **This gate applies ONLY to bullets sourced from `--brief`'s `## Executable Acceptance` section.** An
  explicit `--check '<line>'` or `--checks-file <path>` bullet (including a `cmd:` one) is COMPLETELY
  unaffected, even in a mixed invocation that also passes an unstamped `--brief` in the same run —
  `run-ground-truth.sh` tracks per-line source provenance (`--check` | `--brief` | `--checks-file` |
  the `.supervisor/twin/ground-truth.json` fallback) precisely so the two never cross-contaminate.
- **`--no-cmd` always wins** over a valid stamp — the stamp only ever ENABLES execution on a path that
  isn't already disabled by the safety valve; it never overrides `--no-cmd`.
- A machine-authored brief never carries the stamp by construction (Launch Pad only ever emits
  `corpus-task:` bullets per the authoring convention above), so any `cmd:`/bare bullet that slips into
  one is unapproved by default.

Plan Reviewer **Criterion 14** (`agents/plan-reviewer.md`) surfaces any `cmd:`/bare bullet that appears
in a brief as an `executable_acceptance` issue, and escalates the review `decision` to **NEEDS_HUMAN**
(a dedicated Decision Matrix row) when no well-formed stamp is present — Plan Reviewer is structurally
read-only (no `Bash`) so it checks stamp-line *presence/well-formedness* only; the actual hash-content
match is enforced by `run-ground-truth.sh` at Phase 4.5 execution time, independently. Launch Pad's
Phase 6 resolves a Criterion 14 NEEDS_HUMAN via `approve-and-stamp` / `strip-cmd-bullets` / `discard`
on the interactive path, or an automatic strip (never a silent pass-through) on the non-interactive
path — see `agents/launch-pad.md` Phase 6 action 2a and the `LAUNCH_PAD_RESULT`
`cmd_bullets_stripped_non_interactive` field below. See `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md §7`.

---

### `- **Source requirement:**` (brief `## Environment` field — provenance)

The optional `- **Source requirement:** {repo-root-relative path}` field under a brief's `## Environment`
section records the originating `.supervisor/requirements/*.md` file the brief was planned from. It is
the producer half of the Beads-optional requirement→brief→done close-out loop.

- **Who writes it:** Launch Pad (the producer) at Phase 5 step 3a (`agents/launch-pad.md`), but ONLY when
  Phase 2 step 0 resolved the `goal:`/`feature:`/`problem:` input to a `.supervisor/requirements/*.md`
  file (held in session memory as `source_requirement`). A literal-string goal, or a repo file outside
  `.supervisor/requirements/`, leaves it unset.
- **Optional / backward-compatible:** when no requirement file was resolved, the line is **omitted
  entirely** — never an empty or `"none"` placeholder. Pre-feature briefs and direct `/supervisor task:`
  runs that never stamped a pointer are unaffected; the consumer treats an absent line as a no-op.
- **Format / safety:** the value is a repo-root-relative path under `.supervisor/requirements/`
  (e.g. `.supervisor/requirements/{slug}.md`). Mirrors the brief template in
  `skills/supervisor-readiness/SKILL.md` §`## Environment`.

**No schema_version bump** — this is a brief file-convention addition, not a result-block schema change.

### `## Status` (requirement-file close-out convention — post-merge only)

The optional `## Status` block stamped onto a `.supervisor/requirements/*.md` file is the consumer half
of the close-out loop. Where the brief's `## Outcome` records Phase 4.5's result on the *brief*, this
block records on the *originating requirement file* that **its PR merged** — `automate-helpers.sh`'s
`is_done` (folder intake, `plan-waves`, `resolve-backlog`, `reconcile-status`) reads it as done.

The current block (the only shape any writer emits today) carries the value **on the `## Status:`
heading line**, opened by the namespaced HTML-comment sentinel the idempotency guard keys off:

```markdown
<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** {ISO 8601 timestamp}
- **Brief:** {done/ brief path}
- **PR:** {PR URL}
```

- **Who writes it:** `automate-helpers.sh closeout` (`scripts/automate-trail.sh` step 5 — its `printf`
  is the byte-shape authority; this copy is illustrative), only after its evidence gate reads the PR
  `MERGED` (`skills/automate-loop/SKILL.md` §6 "Post-merge close-out"). The Brief is the newest
  `.supervisor/jobs/done/` brief whose `- **Source requirement:**` equals the item.
- **Who does NOT write it:** Supervisor Phase 4.5's completion tail. Its step 2.5
  (`skills/self-heal-advisory/SKILL.md`) writes nothing to the requirement; the heal verdict lives on the
  brief's `## Outcome` block (`completed` / `completed_with_escalation`, `**Heal reason:**`).
- **Idempotent (block-keyed):** `closeout` appends the block only when no real stamp block is present —
  the sentinel alone on its line, the NEXT line a `## Status: done` / `done_with_escalation` heading
  (`closeout: skipped — already stamped` otherwise; a sentinel quoted in prose does not count,
  automate-followups/38); the requirement file is stamped **in place** and never moved.
- **Other writers of a `## Status:` heading (not this block):** `reconcile-status --apply` (human-run,
  evidence-gated on a merged PR) writes `## Status: done (PR #<n>, merge <sha>)` without the sentinel,
  and an owner's `# abandoned:` decision becomes `## Status: done_with_escalation — ABANDONED (…)`;
  `stamp-requirement-status.sh` writes `## Status: brief-shipped`, deliberately not a done value.
- **Honest limit — one path gets no automatic done stamp:** a plain `/supervisor` / `/autonomous` run
  outside `/automate`. `closeout` needs an `/automate` run file and a caller: its callers are
  `/automate --resume`'s RECONCILE (`skills/automate-loop/SKILL.md` §6 step 1, this run's `## Current`
  item), the merge watcher (`automate-merge-watch.sh`, armed only at an `/automate` park),
  `closeout-others` (another run's `## Current` item), `--auto-merge` SYNC (§6 step 5,
  `closeout --no-trail` right after `gate-eval` merged the PR) and a merged `--parallel` lane's
  `lane-convert-ready` re-run (§14, `closeout --no-trail` inside the lane) — automate-followups/38 —
  so a requirement is closed out only as an `/automate` run's item whose PR merged; for other
  requirements `/automate --resume` runs `reconcile-status` as a dry run only. For that path, recovery
  after the merge is a human step: `reconcile-status --apply`, or a
  hand-written `## Status: done`. Until then the requirement reads `brief-shipped` (or nothing) and
  `resolve-folder` keeps listing the merged item. `stamp-requirement-status.sh`
  (run on session start and when a Supervisor runner agent finishes — its two `hooks.json` seams) writes that `brief-shipped` heading on
  a status-less requirement once its brief lands in `done/`. **Caveat:** `reconcile-status --apply`
  promotes any not-done requirement on merged-PR evidence EXCEPT one already marked `brief-shipped`
  (a `pending`, `in-progress` or status-less heading is promoted); a `brief-shipped` one is listed as an
  `info` row and left unchanged, so it needs a hand-written `## Status: done`. Promoting a merged
  `brief-shipped` requirement in `reconcile-status` is an open follow-up, an explicit non-goal today.
- **Vocabulary (intentional):** the requirement uses `done`, the brief `## Outcome` uses `completed` /
  `completed_with_escalation`. The split is deliberate — the requirement is "done", the brief is
  "completed" — do **not** harmonize them.

**Historical shapes (no current writer — a requirement may still carry them):**

- **Before automate-followups/37**, Phase 4.5's completion tail (step 2.5) stamped this block itself,
  while the PR was still OPEN, on PASS / loop-skipped / ESCALATED; the ESCALATED variant read
  `## Status: done_with_escalation` plus a `- **Heal:** {reason} — {heal_remaining_issues} remaining`
  line. That early stamp is why `trail-pr`'s evidence gate exists, and why a whole-lane
  `meta-sync.sh push` (which bypasses the gate) once carried done claims for never-merged items.
  `is_done` still reads `done_with_escalation` as done.
- **Before v15.39.0**, the documented block put the value in a `- **Status:** done` bullet under a bare
  `## Status` heading. `is_done` reads only the heading line, so that shape left a closed-out
  requirement re-enqueueable (`docs/PITFALLS.md`, the `- **Status:**`-bullet pitfall).

**No schema_version bump** — this is a requirement-file convention addition, not a result-block schema
change.

---

