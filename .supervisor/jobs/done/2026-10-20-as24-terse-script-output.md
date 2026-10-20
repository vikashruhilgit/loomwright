# Supervisor Job: Plugin scripts print one line by default; full output behind --verbose (automate-speed/24)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L23
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/24-terse-script-output.md
- **Base commit:** ee3d7ea3bb069c50a07c3b37222c52c88202263b

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq scripts with co-located `test-*.sh`. No new dependency. |
| 2 | Dependency Availability | GO | Depends-on items 19 and 21 have landed: `loomwright/scripts/automate-lanes.d/` and `loomwright/scripts/automate-helpers.d/` exist on `main`. |
| 3 | Architecture Fit | CAUTION | Three of the five defaults are already one line or one line per item: `classify-bot-review.sh` prints one compact JSON array, `verify-provides.sh` prints one JSON object, and `plan-waves` prints `wave <k>:` / `blocked` lines. Their machine and LLM consumers read fields in that JSON, so most of them must switch to `--verbose`. The real saving is therefore small, as the requirement's own Honest limit says. |
| 4 | Scope vs Supervisor Capability | CAUTION | About 25 files across five scripts, their tests and their consumers. That is above one worker's context, so the work is split by script family (`genuine-parallelism`, three groups with no shared files) plus one integration subtask. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** CAUTION

## Task
**Goal:** By default, the five plugin scripts with the most output print one summary line, or one line per item for list commands. Each keeps its current full output, byte for byte, behind `--verbose`, and every consumer that parses the current output is switched in the same change.

**Problem Statement:**
The main session (the model running `/automate`, `/supervisor` and `/review-pr`) has to read less Bash output, because each session takes in 300–500K chars. Currently `classify-bot-review.sh` (2.1%), `automate-lanes.sh lane-status` (1.8%), `automate-helpers.sh plan-waves` (0.8%), `read-project-memory.sh` (1.1%) and `verify-provides.sh` (0.7%) print their full detail on every call. This adds context the caller mostly does not act on. Success looks like this: each default call prints a status plus the fields the caller acts on, `--verbose` reproduces today's bytes exactly, and no machine consumer's parse breaks.

**Design (each subtask implements its own part; wording of the summary may be refined, the shape may not):**
- A `--verbose` flag is accepted by all five entry points. With it, stdout is byte-identical to today's default. The `--verbose` case arm must sit before any catch-all positional arm. `verify-provides.sh`'s `*)` arm would otherwise read `--verbose` as the brief path.
- Mode flags keep today's output unchanged: `lane-status --json` (the pane reads it), `--inbox`, `--leaks`, `--resources`, `--tokens`; `plan-waves --touches` (`lane-readiness` reads it), `--explain`; `verify-provides.sh --parse-only` (Launch Pad pastes it to Plan Reviewer) and `--kind-table`. The terse rule changes only each script's DEFAULT invocation.
- **`classify-bot-review.sh`** default prints one line, `classify-bot-review: kept <K> of <N> (skipped_self <S>)`. On every current fail-safe path (empty or blank stdin, invalid JSON, not an array, jq missing, stdin timeout) it prints `classify-bot-review: kept 0 of 0 (reason <token>)` and exits 0. The `<token>` is exactly one of `empty_input`, `invalid_json`, `not_array`, `jq_missing` or `stdin_timeout`. `--verbose` prints today's compact JSON array.
- **`lane-status`** plain view (the default, no mode flag) prints today's header line plus one line per lane. Each lane line is today's first per-lane line. `--verbose` is today's full `_lanes_render`. `--watch` keeps the full view, because `_lanes_watch` calls `lanes_status` with `--verbose` on BOTH branches (with and without a runfile). `--keep-awake` still prints its `keep-awake:` START line, which the pane reads. `_lanes_keep_awake_start` prints that line before any rendering, so it always stays. The terse view drops only `_lanes_render`'s wave PR, `policy:`, next-wave, steps, question, readiness and `machine:` / `keep-awake:` STATUS lines. So Subtask 2 MUST rewrite every `skills/automate-loop/lanes.md` sentence that documents those lines in the default view, including the "Visible and batched" bullet and the RECONCILE/close-wave steps. Each rewritten sentence names `lane-status <parent_runfile> --verbose` (or `--inbox` for questions), and the matching `docs/loop-inventory/automate-loop.md` row is updated with it.
- **`plan-waves`** `--max`, `--lint` and `--touches` already print one line per wave, item or path. Their bytes stay unchanged, `--verbose` is accepted as a no-op on them, and `--explain` stays the opt-in detail. The evidence file records this decision and why.
- **`read-project-memory.sh`** default prints one header line that carries the count, `## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins) — <E> verified`, then one line per verified entry. With no store, no sha tool or no verified entries it prints only that header line with a named reason, `— 0 verified (<token>)`, and exits 0. The `<token>` is exactly one of `no_store`, `no_sha_tool` or `no_verified_entries`. The banner text is kept, because it is the subordination framing. `--verbose` is today's bytes, including the empty output when there is no store.
- **`verify-provides.sh`** default (no `--parse-only` / `--kind-table`) prints one line, `verify-provides: subtask <id> <verified|gap|unverifiable> — present <P>/<T>[, gap <outputs_gap>][, reason <reason>]`, and exits 0 on every path. `--verbose` prints today's JSON object.
- **Consumer rule:** a consumer that parses JSON, or that reads or records `outputs_verified` records, `check_run`, `parse_warnings` or the memory digest bytes, switches to `--verbose`. In a script, `--verbose` goes immediately after the script path. A consumer that only needs status, gap or reason may read the summary. A prose mention that runs nothing gets no change.

## Acceptance Criteria
- [ ] 1. Given each script's default invocation (`classify-bot-review.sh` on a stdin array; `automate-lanes.sh lane-status <runfile>`; `automate-helpers.sh plan-waves <input> --max N` / `--lint` / `--touches`; `read-project-memory.sh`; `verify-provides.sh <brief> <id> [--root <dir>]`), when it runs, then stdout is one line, or one header line plus one line per item for the list commands (lanes, waves or items, verified entries).
- [ ] 2. Given `--verbose` on each of those invocations, when it runs on the same input, then stdout is byte-identical to the base-commit script's default output. Each script's test pins this against at least one exact-bytes golden, captured by running the PRE-change script on that test's own fixture before the script is edited.
- [ ] 3. Given the repo-wide consumer grep `grep -rnF '<script name>' --exclude=CHANGELOG.md .` for each of the five (plus `lane-status` and `plan-waves`), when the change is complete, then a committed evidence file `docs/evidence/as24-terse-script-output.md` lists every hit that executes or parses the script, together with how it was switched (`--verbose` / summary / no change: mode flag / no change: prose mention only), and the PR body links to it.
- [ ] 4. Given the machine consumers, when the change is complete, then `lane-status --json`, `plan-waves --touches`, `verify-provides.sh --parse-only` and `--kind-table` output is unchanged, and `bash scripts/test-lanes-addon.sh` (the pane reads `--json` and the `keep-awake:` line) passes.
- [ ] 5. Given a fail-safe path of each reader (bad stdin for `classify-bot-review.sh`, unreadable status for `lane-status`, an `unverifiable` subtask for `verify-provides.sh`, no store for `read-project-memory.sh`), when the default runs, then it exits 0 and its one line names the reason.
- [ ] 6. Given the validation set, when it is run, then the committed evidence file `docs/evidence/as24-terse-script-output.md` records `<passed>/<total>` for `test-classify-bot-review.sh`, `test-automate-lanes.sh`, `test-automate-helpers.sh`, `test-project-memory.sh`, `test-verify-provides.sh`, `scripts/test-lanes-addon.sh`, `test-build-handoff.sh`, `test-review-heal-next-step.sh`, `test-pr-postmortem-gather.sh` and `test-loop-inventory.sh`. It also holds the default line(s) of one real run of each script, with and without `--verbose`. The PR body links to it.
- [ ] 7. Given the release rule, when the branch is finalized, then `changelog.d/as24-terse-script-output.md` exists (a patch-level fragment) and `bash scripts/check-version-bump.sh` passes.

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| classify (Subtask 1) | `loomwright/scripts/classify-bot-review.sh`, `loomwright/scripts/test-classify-bot-review.sh`, `loomwright/scripts/review-heal-next-step.sh`, `loomwright/scripts/pr-postmortem-gather.sh`, `loomwright/docs/result-schemas/review-heal-next-step.md` (only if it restates the classifier's output) | `loomwright/scripts/fixtures/terse-output/classify-bot-review/` (verbose golden) | HIGH |
| lanes + plan-waves (Subtask 2) | `loomwright/scripts/automate-lanes.sh` (usage header), `loomwright/scripts/automate-helpers.sh` (only the `#:  lane-status` help line), `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden`, `loomwright/scripts/automate-lanes.d/status.sh`, `loomwright/scripts/automate-lanes.d/status-read.sh`, `loomwright/scripts/test-automate-lanes.sh` and/or `loomwright/scripts/test-automate-lanes.d/*.sh`, `loomwright/scripts/automate-helpers.d/plan-waves.sh`, `loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden`, `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh`, `loomwright/skills/automate-loop/*.md` + `loomwright/docs/loop-inventory/automate-loop.md` (only where prose reads plain `lane-status` lines) | `loomwright/scripts/fixtures/terse-output/lane-status/`, `loomwright/scripts/fixtures/terse-output/plan-waves/` | MEDIUM |
| memory + verify (Subtask 3) | `loomwright/scripts/read-project-memory.sh`, `loomwright/scripts/test-project-memory.sh`, `loomwright/scripts/build-handoff.sh`, `loomwright/scripts/test-build-handoff.sh` (only if pins move), `loomwright/scripts/verify-provides.sh`, `loomwright/scripts/test-verify-provides.sh`, `loomwright/agents/execute-manager.md`, `loomwright/agents/supervisor.md`, `loomwright/agents/worker.md`, `loomwright/scripts/supervisor-next-step.sh` + `loomwright/scripts/fixtures/supervisor-golden/**` (only if the gate text it emits names the command), `loomwright/docs/result-schemas/worker-result.md`, `loomwright/docs/FAILURE_ESCALATION.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/loop-inventory/supervisor.md` (where a `q:` anchor quotes an edited sentence) | `loomwright/scripts/fixtures/terse-output/read-project-memory/`, `loomwright/scripts/fixtures/terse-output/verify-provides/` | MEDIUM |
| integration (Subtask 4) | `loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" (only if a prompt budget is exceeded) | `docs/evidence/as24-terse-script-output.md`, `changelog.d/as24-terse-script-output.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `loomwright/scripts/test-loop-inventory.sh` (its `q:` anchors quote agent and skill prose verbatim) and `loomwright/scripts/test-citation-drift.sh` scan files this change edits. Files they scan may need updates, and `bash scripts/ci-local.sh` covers all of them.

**Total estimated files:** ~22 modify + ~6 create

## Touched-file invariants

> Grounded at base `ee3d7ea3bb069c50a07c3b37222c52c88202263b`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/classify-bot-review.sh`**
  - Keep the fail-safe contract `FAIL-SAFE: empty input, missing/blank stdin, non-array input, invalid JSON,` (always exit 0) and the bounded read `NEVER-HANGS: the stdin read is BOUNDED`. The regexes stay defined only here.
  - Reuse the existing case-arm idiom (`--skip-marker=*)`), and update the `INTERFACE (PIN)` block's `OUTPUT (stdout): a JSON ARRAY (compact, one line)` paragraph to describe the default summary and `--verbose`.
  - Mirror both machine callers, which must pass `--verbose`:
    - `loomwright/scripts/review-heal-next-step.sh`: `bash "$HERE/classify-bot-review.sh" --trusted-actors "$TRUSTED" 2>/dev/null || echo '[]'`
    - `loomwright/scripts/pr-postmortem-gather.sh`: `BOT_REVIEW_JSON="$(printf '%s' "$COMMENTS_JSON" | bash "$CLASSIFY_BIN" 2>/dev/null)" || BOT_REVIEW_JSON='[]'`
  - Pinned by: `test-classify-bot-review.sh`, `test-review-heal-next-step.sh`, `test-pr-postmortem-gather.sh`.
- **`loomwright/scripts/automate-lanes.d/status.sh`**
  - Keep `if [ "$json" = 1 ]; then printf '%s\n' "$doc"; else _lanes_render "$doc"; fi`: the `--json` branch stays byte-identical.
  - Keep the unknown-flag arm `-*) echo "lane-status: unknown flag '$1'" >&2; return 2 ;;`, with the `--verbose` arm added before it.
  - Keep the fail-safe `echo "lane-status: unknown — status unreadable"; return 0`.
  - Fired by: the `_lanes_watch` loop line `if [ -n "${1:-}" ]; then lanes_status "$1"; else lanes_status; fi`, which must pass `--verbose` so `--watch` keeps the full view.
  - Pinned by: `test-automate-lanes.sh` / `test-automate-lanes.d/*.sh`, `test-wave-build.sh`, `test-token-ledger.sh`, `test-guard-lane-wait-armed.sh`, `test-automate-lanes-modules.sh`.
- **`loomwright/scripts/automate-lanes.d/status-read.sh`**
  - Keep `_lanes_render() { # <status JSON> — the plain view` as the verbose renderer, and add the terse renderer beside it rather than inside it.
  - Keep the keep-awake line `echo "keep-awake: started (opt-in --keep-awake)`.
  - Mirror the pane in `loomwright-lanes/hooks/register.tsx`: `r.out.split('\n').find(x => x.startsWith('keep-awake:'))`.
- **`loomwright/scripts/automate-lanes.sh`**
  - Keep the usage header line `#   lane-status [<parent_runfile>] [--json] [--watch] [--refresh-readiness] [--keep-awake]`, extended with `[--verbose]`.
  - Keep the module order checked by `test-automate-lanes-modules.sh`.
  - Reword the usage comment that lists the default view's per-lane content (`one line per lane:`) to describe the terse default and `--verbose`.
- **`loomwright/scripts/automate-helpers.sh`**
  - Only the `#:  lane-status` help line changes: add `[--verbose]` and describe the terse default. It is a restated copy of the view `status-read.sh` owns (house rule 2).
  - Pinned by: `loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden`, which is regenerated in the same change. The `_AH_HELP_SEGMENTS` order stays unchanged.
- **`loomwright/scripts/automate-helpers.d/plan-waves.sh`**
  - Keep `exit 1 + empty stdout on usage` and the `_pw_usage()` contract. The `--touches` output (`known` then paths, or `unknown <why>`) stays byte-identical.
  - Mirror `loomwright/scripts/automate-lanes.d/readiness.sh`: `plan-waves "$d/$item" --touches --root "$d" 2>/dev/null)" || tw=""`.
  - Pinned by: the `#:  plan-waves` help lines against `fixtures/automate-helpers-help/plan-waves.golden`, and `test-automate-helpers.d/13-plan-waves.sh`.
- **`loomwright/scripts/read-project-memory.sh`**
  - Keep `set -uo pipefail   # \`set -e\` intentionally omitted — a read must NEVER fail its caller.` and the final `exit 0`. Drops still go to stderr and `memory.log`, never to stdout.
  - Keep the banner text `## Advisory project memory — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)`.
  - Mirror `loomwright/scripts/build-handoff.sh`: `mem_out="$(bash "$HELPERS_DIR/read-project-memory.sh" 2>/dev/null || true)"`, which must pass `--verbose` so the handoff digest is unchanged.
  - Pinned by: `test-project-memory.sh`, `test-build-handoff.sh`.
- **`loomwright/scripts/verify-provides.sh`**
  - Keep `--parse-only) parse_only=1; shift ;;` and `--kind-table) print_kind_table; exit 0 ;;` unchanged in output.
  - Keep always-exit-0 and the reasons `brief_unreadable` / `subtask_not_found` / `no_contracts` / `jq_missing` / `bad_args`.
  - Keep `"source":"verify-provides.sh"` in the verbose JSON.
  - The `--verbose` arm must sit before `else printf '%s: unexpected argument %s (ignored)\n' "$SELF" "$1" >&2`'s `*)` arm.
  - Mirror `loomwright/agents/execute-manager.md` (``disk = Bash(`bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-provides.sh" {brief_path} {subtask_id} --root {worktree_path}`)``, which reads `disk.outputs_verified` / `disk.reason` / `disk.source`), plus `agents/supervisor.md` Single-Agent and Sequential gates and `agents/worker.md` Step 5.5.
  - Pinned by: `test-verify-provides.sh`, `test-check-children-settled.sh`, `test-phase45-rounds-seam.sh`.
  - The `check_run` strings that `execute-manager.md` records (`check_run: "verify-provides.sh {brief_path} {subtask_id} --root {worktree_path} → unverifiable/{disk.reason} (exit 0)"`) are updated together with the invocation they describe, so a recorded command never misstates what ran.
- **`loomwright/scripts/supervisor-next-step.sh`**
  - Keep the emitted gate text `(verify-provides.sh on disk, the pin-mutation gate, the check-children-settled.sh --agent-id join)` byte-identical. It names the script but not its flags, so it needs no change.
  - Pinned by: the `loomwright/scripts/fixtures/supervisor-golden/**` `expected.out` fixtures, which `test-supervisor-next-step.sh` checks. Re-run that test if the text is edited for any reason.

## Closed enumerations touched

> Sibling grep at base `ee3d7ea3bb069c50a07c3b37222c52c88202263b`: `grep -rnF 'jq_missing' --exclude=CHANGELOG.md .` → 40 hits in 15 files (excluding `.git` and `.supervisor`).

- **`empty_input` / `invalid_json` / `not_array` / `jq_missing` / `stdin_timeout`** (classify summary reasons) and **`no_store` / `no_sha_tool` / `no_verified_entries`** (memory summary reasons). Sibling: `jq_missing`. These are a new, open set owned by each script's own header (`classify-bot-review.sh` `INTERFACE (PIN)` block; `read-project-memory.sh` usage header), and they appear only in human/LLM-read summary lines.
  - `loomwright/scripts/verify-provides.sh`, `loomwright/scripts/test-verify-provides.sh`, `loomwright/scripts/check-children-settled.sh`, `loomwright/agents/{execute-manager,supervisor,worker}.md`, `loomwright/docs/loop-inventory/supervisor.md`, `loomwright/docs/supervisor-legacy-phases.md`. Each of these hits is verify-provides' JSON `reason` set. No change: the verbose JSON reasons are unchanged, and its summary line reuses them verbatim.
  - `loomwright/scripts/classify-risk.sh` + its test, `prove-rule-check.sh` + its test, `guard-finalize-publish.sh`, `run-pin-mutations.sh`. Each of these hits is a different script's own reason vocabulary. No change: none of them is a closed list for these new tokens.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-review-heal-next-step.sh` — classify channel findings | flip `classify-bot-review.sh" --verbose` → `classify-bot-review.sh"` in `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-pr-postmortem-gather.sh` — bot review JSON | flip `bash "$CLASSIFY_BIN" --verbose` → `bash "$CLASSIFY_BIN"` in `loomwright/scripts/pr-postmortem-gather.sh` |
| `loomwright/scripts/test-build-handoff.sh` — memory section bytes | flip `read-project-memory.sh" --verbose` → `read-project-memory.sh"` in `loomwright/scripts/build-handoff.sh` |
| `loomwright/scripts/test-automate-lanes.sh` — `--watch` shows the full view (new case) | flip `lanes_status "$1" --verbose` → `lanes_status "$1"` in `loomwright/scripts/automate-lanes.d/status.sh` |
| `loomwright/scripts/test-classify-bot-review.sh` — default is one summary line (new case) | make the default branch print the `--verbose` JSON array instead of the summary in `loomwright/scripts/classify-bot-review.sh` |
| `loomwright/scripts/test-classify-bot-review.sh` — `--verbose` equals the pre-change golden (new case) | drop the `--skip-marker` filter from the `--verbose` path in `loomwright/scripts/classify-bot-review.sh` |
| `loomwright/scripts/test-verify-provides.sh` — default summary carries `gap` for a missing item (new case) | omit the `, gap <outputs_gap>` clause from the summary line in `loomwright/scripts/verify-provides.sh` |
| `loomwright/scripts/test-verify-provides.sh` — `--verbose` before the brief path is not read as the brief (new case) | delete the `--verbose` case arm in `loomwright/scripts/verify-provides.sh` |
| `loomwright/scripts/test-project-memory.sh` — header line carries the verified count (new case) | print the bare banner without the `— <E> verified` suffix in `loomwright/scripts/read-project-memory.sh` |
| `loomwright/scripts/test-automate-lanes.sh` — default plain view is header + one line per lane (new case) | route the default branch to `_lanes_render` in `loomwright/scripts/automate-lanes.d/status.sh` |
| `loomwright/scripts/test-automate-lanes.sh` — `--watch` with no runfile shows the full view (new case) | flip `else lanes_status --verbose; fi` → `else lanes_status; fi` in `loomwright/scripts/automate-lanes.d/status.sh` |
| `loomwright/scripts/test-classify-bot-review.sh` — bad stdin ⇒ `kept 0 of 0 (reason invalid_json)`, exit 0 (new case) | drop the `(reason …)` clause from the fail-safe branch in `loomwright/scripts/classify-bot-review.sh` |
| `loomwright/scripts/test-automate-lanes.sh` — unreadable status ⇒ one `lane-status: unknown — status unreadable` line, exit 0 (existing assertion, re-pinned on the default view) | delete `echo "lane-status: unknown — status unreadable"; return 0` in `loomwright/scripts/automate-lanes.d/status.sh` |
| `loomwright/scripts/test-verify-provides.sh` — `unverifiable` default line carries `reason subtask_not_found`, exit 0 (new case) | omit the `, reason <reason>` clause from the summary line in `loomwright/scripts/verify-provides.sh` |
| `loomwright/scripts/test-project-memory.sh` — no store ⇒ one header line ending `0 verified (no_store)`, exit 0 (new case) | make the no-store path exit 0 with empty stdout on the default (non-verbose) path in `loomwright/scripts/read-project-memory.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `classify-bot-review.sh` terse default + switch its two machine callers | 1, 2, 5 (classify); 3 (rows for classify) | 4–5 modify, 1 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `lane-status` terse plain view + `plan-waves --verbose`; `--watch`/`--json`/`--touches` kept | 1, 2, 4, 5 (lane-status, plan-waves); 3 (rows) | 6–9 modify, 2 create | `skills/automate-loop/SKILL.md` | LAUNCHABLE |
| 3 | `read-project-memory.sh` + `verify-provides.sh` terse default + switch handoff and agent consumers | 1, 2, 4, 5 (memory, verify); 3 (rows) | 8–12 modify, 2 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 4 | Integration: evidence file, changelog fragment, budgets, full validation | 3, 6, 7 | 0–2 modify, 2 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1, #2, #3) |

Each of subtasks 1–3 reports in its WORKER_RESULT the consumer rows for its scripts, using the consumer grep from AC 3: hit, kind (script, prompt, hook, test, prose), and switch. It also reports the default and `--verbose` line(s) from one real run. Subtask 4 assembles these into the evidence file and re-verifies them with the same grep. A worker edits prompt prose only where a consumer must change. It keeps the net token change of each edited prompt at or below zero where it can. Any budget it would exceed is reported for subtask 4 to resolve; the worker does not edit `prompt-token-budgets.json` itself.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/classify-bot-review.sh"}
  - {kind: "symbol", path: "loomwright/scripts/classify-bot-review.sh", name: "--verbose"}
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "classify-bot-review.sh\" --verbose"}
  - {kind: "symbol", path: "loomwright/scripts/pr-postmortem-gather.sh", name: "bash \"$CLASSIFY_BIN\" --verbose"}
requires: []
lanes:
  - "loomwright/scripts/classify-bot-review.sh"
  - "loomwright/scripts/test-classify-bot-review.sh"
  - "loomwright/scripts/review-heal-next-step.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/pr-postmortem-gather.sh"
  - "loomwright/scripts/test-pr-postmortem-gather.sh"
  - "loomwright/docs/result-schemas/review-heal-next-step.md"
  - "loomwright/scripts/fixtures/terse-output/classify-bot-review/**"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/status.sh", name: "--verbose"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/status.sh", name: "lanes_status \"$1\" --verbose"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/plan-waves.sh", name: "--verbose"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/automate-lanes.d/status.sh"
  - "loomwright/scripts/automate-lanes.d/status-read.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.d/*.sh"
  - "loomwright/scripts/test-wave-build.sh"
  - "loomwright/scripts/test-token-ledger.sh"
  - "loomwright/scripts/test-guard-lane-wait-armed.sh"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
  - "loomwright/scripts/automate-helpers.d/plan-waves.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden"
  - "loomwright/scripts/fixtures/automate-helpers-help/plan-waves.golden"
  - "loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh"
  - "loomwright/skills/automate-loop/*.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/scripts/fixtures/terse-output/lane-status/**"
  - "loomwright/scripts/fixtures/terse-output/plan-waves/**"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/read-project-memory.sh", name: "--verbose"}
  - {kind: "symbol", path: "loomwright/scripts/verify-provides.sh", name: "--verbose"}
  - {kind: "symbol", path: "loomwright/scripts/build-handoff.sh", name: "read-project-memory.sh\" --verbose"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "verify-provides.sh\" --verbose"}
requires: []
lanes:
  - "loomwright/scripts/read-project-memory.sh"
  - "loomwright/scripts/test-project-memory.sh"
  - "loomwright/scripts/build-handoff.sh"
  - "loomwright/scripts/test-build-handoff.sh"
  - "loomwright/scripts/verify-provides.sh"
  - "loomwright/scripts/test-verify-provides.sh"
  - "loomwright/scripts/test-check-children-settled.sh"
  - "loomwright/scripts/test-phase45-rounds-seam.sh"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/worker.md"
  - "loomwright/scripts/supervisor-next-step.sh"
  - "loomwright/scripts/test-supervisor-next-step.sh"
  - "loomwright/scripts/fixtures/supervisor-golden/**"
  - "loomwright/docs/result-schemas/worker-result.md"
  - "loomwright/docs/FAILURE_ESCALATION.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/scripts/fixtures/terse-output/read-project-memory/**"
  - "loomwright/scripts/fixtures/terse-output/verify-provides/**"
external_requires: []

# Subtask 4
provides:
  - {kind: "file", path: "docs/evidence/as24-terse-script-output.md"}
  - {kind: "file", path: "changelog.d/as24-terse-script-output.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/classify-bot-review.sh", name: "--verbose"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-lanes.d/status.sh", name: "--verbose"}
  - {from: "3", kind: "symbol", path: "loomwright/scripts/verify-provides.sh", name: "--verbose"}
lanes:
  - "docs/evidence/as24-terse-script-output.md"
  - "changelog.d/as24-terse-script-output.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┼──→ Subtask 4
Subtask 3 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 3 | Subtask 4 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | YES (4 requires 3: legal sequential share) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel)
- **Batch 2:** Subtask 4 (after 1, 2, 3)
- **Recommended workers:** 3
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` (fail-safe exit-0 paths) |
| 2 | `skills/automate-loop/SKILL.md` (lanes: `lane-status` / `plan-waves` contracts) |
| 3 | `skills/error-handling/SKILL.md` (fail-safe reader; the fail-CLOSED `outputs_verified` gate consumer) |
| 4 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| A missed machine consumer of `classify-bot-review.sh` reads the summary line as non-JSON. Both callers fall back to `[]`, so the drain or postmortem would read the run as "no findings": a fail-safe reader read as clean by a gate. | HIGH | Both callers pass `--verbose` (pins in `## Pin mutations`). Subtask 4 re-runs the AC 3 grep and confirms that every executing hit passes `--verbose` before writing the evidence file. `test-review-heal-next-step.sh` must assert that a real finding survives the classify step. |
| An agent prompt that parses `verify-provides.sh` JSON (`disk.outputs_verified`) gets the summary line. | MEDIUM | Consumer rule: any reader of records, `check_run` or `parse_warnings` passes `--verbose`. The consumer fails CLOSED to the existing checkpoint on unparseable output, so this cannot pass silently, but it would cost a checkpoint. |
| Feasibility (Phase 2.5): three of the five defaults are already one line, and most consumers need `--verbose`, so the measured saving is close to zero for `classify-bot-review.sh`, `verify-provides.sh` and `plan-waves`. | MEDIUM | State this plainly in the evidence file. For each script, record the default's char count before and after on the AC 6 run; do not claim a saving the run does not show. |
| Feasibility (Phase 2.5): about 25 files across five scripts. | MEDIUM | Split by script family with zero file overlap. Subtask 4 owns the shared files (evidence, changelog, budgets). |
| `verify-provides.sh`'s `*)` arm reads an unknown first argument as the brief path, so `--verbose` placed first would be read as the brief. | MEDIUM | Add the `--verbose` arm before `*)`. A pin case runs `--verbose <brief> <id>`. |
| `--watch` and the pane break: `_lanes_watch` calls `lanes_status`, and the pane reads `--json` plus the `keep-awake:` line. | MEDIUM | Add `--verbose` in `_lanes_watch`. `--json` and the keep-awake line stay unchanged. Run `bash scripts/test-lanes-addon.sh`. |
| `test-loop-inventory.sh` `q:` anchors quote agent and skill sentences verbatim, so editing a quoted sentence fails the gate. | LOW | The subtask that edits the source prose updates the matching inventory row (`docs/loop-inventory/supervisor.md` in 3, `automate-loop.md` in 2). |
| Prompt token budgets: adding `--verbose` to agent prompts grows them. | LOW | Keep the net change at or below zero. Subtask 4 alone raises a budget (JSON plus the mirror row), and only if a measured overrun remains. |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** genuine-parallelism

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-20-as24-terse-script-output.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-20T11:15:56Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/635
- **Branch:** feature/as24-terse-script-output
- **Files changed:** 60
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Five plugin scripts print one summary line by default, with full output byte-identical behind --verbose; every parsing consumer switched to --verbose. Phase 4.5 code review PASS (consistency_audit) with 2 LOW prose findings dismissed below the MEDIUM floor; required CI green; rules gate none. Children check skipped by owner (subtask-4 worker a761de3ec027c0260 hit its turn limit; Supervisor finished its work).

## Not verified
- **Execute Manager / Supervisor / worker prompts actually running verify-provides.sh --verbose** — prompt behaviour; first observable on the next job after plugin reinstall (subtask 3)
- **loomwright-lanes /lanes pane in a live Claude Code session** — only test-lanes-addon.sh (mocked) run (subtask 2)
