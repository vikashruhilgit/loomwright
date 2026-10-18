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
| `wc -c loomwright/agents/supervisor.md` | `111067` | _subtask 3_ |
| `wc -c loomwright/commands/supervisor.md` | `58190` | _subtask 3_ |
| `wc -c loomwright/skills/self-heal-advisory/SKILL.md` | `176146` | _subtask 3_ |
| `wc -c loomwright/skills/async-orchestration/SKILL.md` | `57308` | _subtask 3_ |
| Default `/supervisor` read-set size | _subtask 3_ | _subtask 3_ |
| Loop-inventory `GAP` count (`loomwright/docs/loop-inventory/supervisor.md` `## Counts`, rows 736) | `542` | _subtask 3 (with the residual by kind)_ |

The four before-sizes were read with `git show a8819a3:<path> | wc -c`; the GAP count from the inventory's
`## Counts` block, which this branch has not changed (`git diff --quiet a8819a3 -- loomwright/docs/loop-inventory/supervisor.md`).

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

- **A live `/supervisor` run on the driver path.** No command doc points at the driver until subtask 3, and a lane PR
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
