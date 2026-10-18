# Evidence — automate-speed/11: the next-step driver for Supervisor Phases 0–4

Source requirement: `.supervisor/requirements/automate-speed/11-next-step-supervisor.md` (scope split by the owner on
2026-10-17: Phases 0–4 here, Phase 4.5 filed as the propose-only `automate-speed-11b`).
Driver: `loomwright/scripts/supervisor-next-step.sh`. Suite: `loomwright/scripts/test-supervisor-next-step.sh`. Per-case
drive files: `loomwright/scripts/fixtures/supervisor-golden/<case>/next-step.results`. Instruction schema:
`loomwright/docs/result-schemas/supervisor-result.md` §"supervisor next-step instruction" (the shared `do` enum is
`loomwright/docs/result-schemas/automate-run.md` §"next-step instruction"). Base commit `a8819a3`. macOS.

This file has two parts. Subtasks 1–2 (the driver) recorded the before-values, the driver legs, the mutation
verdicts and the Validation 3 drive. Subtask 3 (the prose migration) fills the after-values, the read-set sizes, the
GAP after-count and residual by kind, and the migration's suite results.

## Before / after

| Measure | Before (base `a8819a3`) | After |
|---|---|---|
| `wc -c loomwright/agents/supervisor.md` | `111067` | `105710` (−5357) |
| `wc -c loomwright/commands/supervisor.md` | `58190` | `60305` (+2115 — the new §"Next-step driver (Phases 0–4)" and the `--legacy` row outweigh the four shortened phase paragraphs) |
| `wc -c loomwright/skills/self-heal-advisory/SKILL.md` | `176146` | `176146` (Phase 4.5 — unchanged, item 11b) |
| `wc -c loomwright/skills/async-orchestration/SKILL.md` | `57308` | `49133` (−8175) |
| Default `/supervisor` read-set size, Phases 0–4 (inline: `commands/supervisor.md` + `skills/supervisor-config` + `skills/preflight-sync` + `skills/async-orchestration`) | `159806` | `148901` (−10905, −6.8%) |
| Same, delegated path (`agents/supervisor.md` in place of the command file) | `212683` | `194306` (−18377, −8.6%) |
| Loop-inventory `GAP` count (`loomwright/docs/loop-inventory/supervisor.md` `## Counts`) | `542` (rows 736) | `491` (rows 745) — residual by kind below |

Before-sizes: `git show a8819a3:<path> | wc -c`; after-sizes: `wc -c` on the branch. The read set counts the
Phase 0–4 files a default run loads (Step 0's `commands/supervisor.md`, or `agents/supervisor.md` on the delegated path,
plus the three phase skills Read at Phase 0, 1.5 and 2/4); `skills/supervisor-config/SKILL.md` 21274 → 18411 and
`skills/preflight-sync/SKILL.md` 23034 → 21052. Phase 4.5's `skills/self-heal-advisory/SKILL.md` (176146) is read
after the hand-over on both paths and did not change. The moved text — `loomwright/docs/supervisor-legacy-phases.md`,
45815 B — is read only on the legacy path.

## Prose migration (subtask 3)

**What moved.** 24 blocks, 254 lines, moved VERBATIM into `loomwright/docs/supervisor-legacy-phases.md`, which opens
with a banner naming `scripts/supervisor-next-step.sh` as the authority and the text as frozen at base `a8819a3`.
Checked by script: every block is a byte-identical substring of `git show a8819a3:<source>`, is present in the legacy
file, and is gone from its source (`24 blocks, 0 bad`). The blocks:
- `agents/supervisor.md`: the Phase 0 Entry paragraph and two exit bullets (Phase Flags, cost profile); Phase 1 action 4
  (the branch-guard snippet and its `exit 1` paragraph); the Phase 1.5 exit conditions; Phase 2 actions 1 and 4; the
  Parallel Path delegation, its result discriminator and the EXECUTE error table; Adjudication Handling steps 1–3 with
  both option sets; FINALIZE gate 1's Point 5 paragraph; the FINALIZE exit conditions.
- `skills/async-orchestration/SKILL.md` Part 2: step 1 (the pre-merge checklist, its verification commands, Point 5 in
  full), step 6.5 (the PR-base self-verify), step 7 and the FINALIZE scope reduction.
- `skills/supervisor-config/SKILL.md`: steps 3a–5, 5a items 0.5–2.5 and 3–5, steps 6–7.
- `skills/preflight-sync/SKILL.md`: actions 1 (skip check) and 6 (acting on the classification).
- `commands/supervisor.md`: the Phase 0 / 1 / 1.5 / 4 paragraphs of §"What This Does" and the `state.json`
  session-identification paragraph.

**What stayed in place.** Everything that is not a step the driver runs: the Can't-ask rule and its statuses, the
Phase 4.5 completion-tail guard, the `--skip-self-heal` warning, FINALIZE's numbered gate list (the WHAT), the
Observability `awk` snippet, §"Inline-path canonical state writes" (its `state.json` HOW now points at the `acquire`
step), the run-lock acquire, the Resume validation gate, the INIT config questions, the Phase 4.5 flags, the Phase 1.5
classification (actions 2–5), Phase 2's parallelism analysis (it fills the Execute Manager spawn's Parallelism graph),
the Single-Agent / Sequential per-subtask gates, the `--sdk-runner` branch, Adjudication step 4 and its hard rule,
FINALIZE steps 2–6, the PR Body Template, the Subagent Spawn Contracts and the Execute Manager's poll loop.

**Pointers.** Each moved spot now names the driver step that runs it. `commands/supervisor.md` has a new
§"Next-step driver (Phases 0–4)", which covers the entry call after the run-lock acquire, the `--result` loop and the
`done` hand-over to Phase 4.5, and a new `--legacy` Usage line and Parameters row. `agents/supervisor.md` gets the same
driver paragraph above Phase 0 and a `--legacy` Flags row.

**Legacy path scope (a decision of this subtask).** The driver needs a `job:` brief on a fresh start. It does not
run `--continue` resume (a fresh entry would re-run `init` and hit `acquire_branch_collision` on a branch that holds
work), a run with no `job:` brief (`task:`, interactive or auto-select), or `--sdk-runner` (no SDK runner support, and
its result has no worktrees for pre-merge point 3). So the pointers route those runs to the legacy file as well as
`--legacy` itself. Without that, moving the prose would have silently dropped their protocol.

**Inventory (AC6).** 71 rows now have home `script:supervisor-next-step.sh <step>` (each step a real `case` arm) and
test cell `test-supervisor-next-step.sh`. They are the 62 migrated rows plus the six SV-737+ pointer rows homed on the
driver. Five rows whose prose stays (gate list items, path selection, the `state.json` lead) name the driver as
`implemented by`. Three rows are re-anchored (SV-117, SV-690) or newly added as honest GAP rows (SV-738, SV-741,
SV-745 — the legacy-path trigger is prose-only). Nine rows were added: SV-737–SV-745. The Execute Manager poll-loop rows
(SV-599, SV-624…SV-631, SV-641) and every Phase 4.5 row stay `prose`. Result: GAP 542 → 491 (54 closed, 3 opened);
`test-loop-inventory.sh` green.

**Residual GAP by kind (491):** rule 237 · deterministic 213 · story 21 · judgment 20. By source: Phase 4.5's
`skills/self-heal-advisory/SKILL.md` 157 (deterministic 77, rule 74, judgment 3, story 3 — item 11b); the other three
sources 334 (rule 163, deterministic 136, story 18, judgment 17). The 136 deterministic rows outside Phase 4.5 are
mostly the Execute Manager's poll loop and worktree lifecycle, the per-subtask gates of the Single-Agent and
Sequential paths (kept as the model's — the driver routes their `passed` / `paused` report), the `--sdk-runner`
branch, FINALIZE steps 2–6 (merge, salvage, commit, re-fold, push — model work), the Phase 4.5 / Phase 5 stanzas of
`agents/supervisor.md`, and the tool-budget / error tables. None of them was faked closed.

**Pins (AC8).** None of the 15 Feasibility-row-5 seam suites needed a needle change. Each anchor they read either
stayed in place (rules, gate list, completion-tail guard, Can't-ask rule) or is still named in its file by the pointer
that replaced the HOW. For example, `check-children-settled.sh --all`, `--expect-id`, `children_unsettled`,
`--skip-children-check` and `rejected_stop_ids` stay in the Point 5 / step 1 pointers, and `#### Adjudication Handling`
still names `adjudication_required_non_interactive`. The moved text did shift line numbers under four pinned
citations (`citation-drift` pins), and those were repointed. Their mutation verdicts are under "Repoint mutation
controls" below.
- `loomwright/scripts/reconcile-resume-state.sh` (header, 3 pins): `async-orchestration/SKILL.md:572` → `:536`,
  `:579-581` → `:543-545`. This file is outside this subtask's declared lane; the line move forced the change.
- `loomwright/scripts/test-reconcile-resume-state.sh`: `:582-584` → `:546-548`.

**ENUMS row (`scripts/check-contract-parity.sh`).** The legacy file carries bare `status: checkpoint` / `status: failed`
(moved from `skills/preflight-sync/SKILL.md` and the agent stanzas), so it gets the row
`docs/supervisor-legacy-phases.md|status|` with the union allowlist of the rows its text came from (the
`agents/supervisor.md` set, which contains the preflight-sync and supervisor-config sets). It carries no
`heal_decision:` literal, so it gets no heal_decision row. `test-check-contract-parity.sh`'s fixture tree now provides the file
(the gate errs on a missing scoped file), and a new leg covers it: an out-of-enum `status: parked` in the legacy file
fails (20/20).

**Vendor coupling.** The 17 install-root / orchestration references the moved text carries move with it, net zero:
`agents/supervisor.md` 51 → 40, `skills/async-orchestration/SKILL.md` 26 → 23, `skills/preflight-sync/SKILL.md`
4 → 2, `skills/supervisor-config/SKILL.md` 9 → 8, and the legacy file 17, all with reasons. The same run also
surfaced a breach already present at `590ffd2`. Sixteen of subtask 2's golden session logs carry the progress
emitter's stop-hook flag field, which the point-5 join reads, so they are declared as fixture allowances with a
reason. One case's `source` line was reworded ("a lagging subagent-stop hook") rather than raising an allowance for
prose. `check-vendor-coupling.sh` is green.

## Validation 1 — suites (driver legs)

```
bash loomwright/scripts/test-supervisor-next-step.sh            PASS: 105 FAIL: 0   (105/105, Homebrew bash 5.3)
PATH="/bin:$PATH" /bin/bash loomwright/scripts/test-supervisor-next-step.sh
                                                                PASS: 105 FAIL: 0   (105/105, macOS /bin/bash 3.2.57)
bash loomwright/scripts/test-automate-next-step.sh              PASS: 105 FAIL: 0   (105/105)
bash loomwright/scripts/test-check-children-settled.sh          RESULT: 61 passed, 0 failed
bash loomwright/scripts/test-guard-finalize-publish.sh          RESULT: 154 passed, 0 failed
bash loomwright/scripts/test-result-schemas-split.sh            RESULT: 14 passed, 0 failed
bash loomwright/scripts/test-citation-drift.sh                  citation-drift: 26 passed, 0 failed
bash loomwright/scripts/test-loop-inventory.sh                  RESULT: 43/43 passed
bash scripts/check-vendor-coupling.sh                           exit 0
bash scripts/check-doc-currency.sh                              ✓ all checked version/count claims match
bash scripts/check-contract-parity.sh                           ✓ all hook-enforced fields present, literals in-enum
bash scripts/check-version-bump.sh                              exit 0
```

`test-supervisor-next-step.sh` covers 27 golden cases — the brief's 26 `REQUIRED_CASES` (Phases 0–2 from subtask 1,
the 12 Phase 3–4 cases below) plus `validation-3-drive`. Each case's `source` file names the real run it was built
from or says `synthetic` and why: no kept run took the Parallel Path or reached FINALIZE, so every Phase 3–4 case is
synthetic; the four `finalize-*` single-agent cases take their inputs (the `## Session` block, worker
`ac394bd015ea3ff94`'s Worker Results record and its terminal log rows) from the real run
`ae60dadd-8fcf-4650-976a-93bf87a87708`, trimmed.

Phase 3–4 golden cases: `execute-result-complete`, `execute-result-partial`, `execute-result-all-failed`,
`execute-adjudication-ask`, `execute-adjudication-non-interactive`, `execute-manager-crash`,
`finalize-premerge-gate-fail`, `finalize-children-unsettled`, `finalize-marker-written`, `finalize-pr-base-verified`,
`finalize-pr-base-mismatch`, `finalize-pr-base-gh-retry`.

**bash 3.2 finding (fixed here).** Run under macOS `/bin/bash` 3.2.57, the suite as subtask 1 committed it failed
(`PASS: 33 FAIL: 12`, 9 of them golden cases): bash 3.2 brace-expands the source text of a double-quoted `"$(…)"` passed as a command argument,
single quotes notwithstanding, so jq programs and instruction texts holding `{…, …}` reached jq split into words (a
jq compile error, or a truncated `then` text). Its earlier `46/46` was a bash-5 result. Minimal repro:
`/bin/bash -c 'echo "$(jq -cn '"'"'{t: "x {a: 1, b: 2}"}'"'"')"'` prints two words; with `set +B` first, one. The
driver now runs with `set +B` (it uses no brace expansion — every `{n,m}` in it is a regex quantifier); the K leg pins
it and, where `/bin/bash` is 3.x, drives a spawn under it.

AC3 is also checked by mechanism: the P leg probes, after every call that printed the publish spawn, that the
finalize-gate marker exists and names HEAD (6 publish spawns across the golden cases, all with the marker); and
`guard-finalize-publish.sh` / `check-children-settled.sh` are byte-unchanged since the merge-base `a8819a3`.

## Validation 1 — suites after the prose migration (subtask 3)

Run on the migrated tree (macOS, Homebrew bash):

```
bash loomwright/scripts/test-supervisor-next-step.sh            PASS: 105 FAIL: 0   (105/105)
bash loomwright/scripts/test-loop-inventory.sh                  RESULT: 43/43 passed   (GAP supervisor: 491)
bash loomwright/scripts/test-automate-next-step.sh              PASS: 105 FAIL: 0   (105/105)
bash loomwright/scripts/test-rules-seams.sh                     RESULT: 135 passed, 0 failed
bash loomwright/scripts/test-not-verified-transport-seam.sh     RESULT: 25 passed, 0 failed
bash loomwright/scripts/test-check-children-settled.sh          RESULT: 61 passed, 0 failed
bash loomwright/scripts/test-verify-provides.sh                 RESULT: 163 passed, 0 failed
bash loomwright/scripts/test-context-digest.sh                  ALL TESTS PASSED (37/37)
bash loomwright/scripts/test-release-refold.sh                  RESULT: 26 passed, 0 failed
bash loomwright/scripts/test-phase45-rounds-seam.sh             61 passed, 0 failed
bash loomwright/scripts/test-non-interactive-gates-seam.sh      RESULT: 64 passed, 0 failed
bash loomwright/scripts/test-run-lock.sh                        RESULT: 82 passed, 0 failed
bash loomwright/scripts/test-build-handoff.sh                   RESULT: 93 passed, 0 failed
bash loomwright/scripts/test-worktree-salvage.sh                RESULT: 71 passed, 0 failed
bash loomwright/scripts/test-reconcile-resume-state.sh          23 passed, 0 failed
bash loomwright/scripts/test-pr-body-evidence-seam.sh           77 passed, 0 failed
bash loomwright/scripts/test-check-contract-parity.sh           20/20 passed
bash loomwright/scripts/test-citation-drift.sh                  26 passed, 0 failed
bash scripts/check-doc-currency.sh                              ✓ all checked version/count claims match
bash scripts/check-token-budget.sh                              OK (commands.supervisor 15076 of 16002)
bash scripts/check-contract-parity.sh                           ✓ all hook-enforced fields present, literals in-enum
bash scripts/check-vendor-coupling.sh                           OK
bash scripts/check-version-bump.sh                              OK — not bumped, 1 fragment pending
```

Also green after the migration: `test-guard-finalize-publish.sh` 154/154, `test-lane-policy.sh` 71/71,
`test-worktree-audit.sh` 176/176, `test-result-validators.sh` 458/458.

## Repoint mutation controls (subtask 3)

Each mutant flips or deletes the protected literal at its NEW location, never the pin's own needle. It is applied in
place, the suite is run, and the file is restored from a backup in the same call (the mutant is checked to differ
first):

```
ok: C1 citation pin: the merge line at its new place (async-orchestration :546) reworded ⇒ test-citation-drift red (2 pinned citations DRIFTED)
ok: C2 citation pin: the worker commit line at its new place (:539) reworded ⇒ test-citation-drift red (2 pinned citations DRIFTED)
ok: P1 the step-1 pointer drops rejected_stop_ids ⇒ test-check-children-settled red
ok: P2 the Point 5 pointer drops both --expect-id mentions ⇒ test-check-children-settled red (dropping one alone stays green: the line names it twice, for the join and for write-marker)
ok: P3 the Adjudication pointer drops adjudication_required_non_interactive ⇒ test-non-interactive-gates-seam red
ok: E1 a scratch copy of the legacy file with status: parked ⇒ check-contract-parity.sh reports the enum-literal breach (also a permanent leg in test-check-contract-parity.sh)
```

## Validation 2 — mutation controls

Each mutant is a driver copy built by `build_mutant` (anchor occurring once, non-empty, differs, `bash -n`):

```
ok: M2a: the publish spawn before write-marker ⇒ P red
ok: M2b: a driver writing state.md ⇒ W red ( init-flags-non-interactive acquire-job-move)
ok: M2c: the retry removed ⇒ A4 red
ok: M2c: … and the gh-retry golden case goes red
ok: M2d: an auto-picked adjudication ⇒ A5 red
ok: MB: brace expansion on ⇒ K red (the driver has no top-level 'set +B' line)
ok: MD: an undocumented case arm ⇒ D red
ok: MS: an unguarded merge-command line ⇒ S red
ok: MR: a code-reviewer spawn ⇒ R red (the driver source names a code-reviewer spawn)
```

## Validation 3 — one item from Phase 0 to the Phase 4.5 hand-over (hermetic)

The `validation-3-drive` golden case, re-run by the suite's V leg (`SN_V3_PRINT=1` prints it): a scratch `git init`
repo with a local bare `origin`, a pending two-subtask brief, gh stubbed (no network). Each spawn is answered with a
fixed result (the Context-Keeper confirmations, a CLEAR pre-flight report, an `EXECUTE_RESULT`); the agents' own git
work runs for real — the Execute Manager's two worktrees, FINALIZE's per-worktree commits, the `--no-ff` merges in
`merge_order`, `worktree-salvage.sh` then the worktree removal, `release-refold.sh` (a no-op here) and the push to the
bare origin. `check-children-settled.sh --all` and `guard-finalize-publish.sh write-marker` run for real, and the
fail-CLOSED PreToolUse guard is invoked on the push command twice: exit 2 (deny) before `write-marker`, exit 0 (allow)
after it. One line per instruction, `do` + `step`:

```
spawn init
spawn preflight
spawn preflight-route
spawn execute
spawn finalize-merge
spawn publish
done handover
```

The hand-over reads `base_verify: verified`, `children_check: settled`, `preflight_sync: clear`.

## Not verified

- **A live `/supervisor` run on the driver path.** The command doc now points at the driver (subtask 3), but a lane PR
  cannot run one real item through Supervisor on the driver (the installed plugin is running this very item). The
  requirement's "paste the Phase 4.5 iteration lines" also belongs to Phase 4.5, which is item 11b. Validation 3 above
  is a hermetic drive; the merges, the push and the guard are real, gh is stubbed.
- **Real `gh` against GitHub.** Step 6.5's `gh pr view --json baseRefName` and the PR creation are stubbed in every
  case; the stubbed shapes follow `gh`'s documented `--jq .baseRefName` output.
- **The inline-path per-subtask gates.** On the Single-Agent / Sequential paths the driver routes the gate outcome it
  is handed (`passed` / `paused`); `record_worker_result`, `verify-provides.sh`, the pin-mutation gate, the `--agent-id`
  join, the inline adjudication of a disk gap and the Sequential Path's per-subtask token-ceiling check stay the
  model's (prose). The Execute Manager's own poll loop is out of scope (it stays `prose` in the inventory).
- **A real Execute Manager's `EXECUTE_RESULT` / `EXECUTE_CHECKPOINT`.** The blocks in the cases are the shapes of
  `docs/result-schemas/execute-result.md` / `execute-checkpoint.md`, parsed by the validators' shared parser
  (`result_block_parser.py`); no kept run emitted one.
- **The legacy path itself.** `/supervisor --legacy`, and the runs routed to it (`--continue`, no `job:` brief,
  `--sdk-runner`), were not run: the legacy file is the base prose, checked byte for byte, but no run has followed it
  as a separate file. The routing that sends those runs there is prose-only (inventory GAP rows SV-738, SV-741, SV-745).
