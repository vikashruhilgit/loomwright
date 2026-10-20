# Evidence — automate-speed/26: subagent prompt diet

Branch `feature/as26-diet-subagent-prompts`, base `ee3d7ea`. Every number below was read from a command whose output is pasted with it. Proxy tokens are `bytes / 4` (`scripts/check-token-budget.sh`), never a real token count.

## AC1 — spawn weight, before / after

Before: `bash scripts/check-token-budget.sh` at base `ee3d7ea` (before any edit):

```
code-reviewer             27473    27563  OK      90 headroom (5 preloaded skills)
execute-manager           31405    42568  OK      11163 headroom (3 preloaded skills)
plan-reviewer             12377    13614  OK      1237 headroom (0 preloaded skills)
worker                     9127     9949  OK      822 headroom (0 preloaded skills)
```

After: `bash scripts/check-token-budget.sh` on the branch, after the last prose edit:

```
code-reviewer             17681    27563  OK      9882 headroom (1 preloaded skills)
execute-manager           19283    42568  OK      23285 headroom (2 preloaded skills)
plan-reviewer              8566    13614  OK      5048 headroom (0 preloaded skills)
worker                     5810     9949  OK      4139 headroom (0 preloaded skills)
```

| Agent | Before | After | Cut | ≥30% target (≤) | Met |
|---|---|---|---|---|---|
| `code-reviewer` | 27473 | 17681 | −35.6% | 19231 | yes |
| `execute-manager` | 31405 | 19283 | −38.6% | 21983 | yes |
| `plan-reviewer` | 12377 | 8566 | −30.8% | 8663 | yes (97 tokens of margin) |
| `worker` | 9127 | 5810 | −36.3% | 6388 | yes |

The start figures matched the brief's Baseline table exactly. No `budget` changed.

## AC2 — interfaces unchanged

- `test-result-validators.sh`: `RESULT  pass=468  fail=0`. `test-validate-code-review-result.sh`: `RESULT  pass=86  fail=0`. `test-emit-block-parses.sh`: `test-emit-block-parses: 5/5 passed`. No validator, parser, validator test or fixture was edited.
- Emit templates: a scratch script compared every fenced block whose first line names `WORKER_RESULT` / `EXECUTE_RESULT` / `EXECUTE_CHECKPOINT` / `PLAN_REVIEW_RESULT` / `CODE_REVIEW_RESULT`, base vs branch: `code-reviewer 1 1 IDENTICAL`, `execute-manager 7 7 IDENTICAL`, `plan-reviewer 4 4 IDENTICAL`, `worker 3 3 IDENTICAL`.
- `bash loomwright/scripts/build-capabilities.sh --check` exits 0; `loomwright/capabilities.json` is not in the diff.

## AC3 — mutation control (scratch copy, never the working tree)

Command (from the PR tree, before the evidence and vendor-manifest commits — the mutated file is the same):

```
SCRATCH=$(mktemp -d); mkdir -p "$SCRATCH/tree" "$SCRATCH/home"
git archive HEAD | tar -x -C "$SCRATCH/tree"; cd "$SCRATCH/tree"
# delete the files_checked field (key + its two list items) from the CODE_REVIEW_RESULT: template
python3 -c '…s.replace("  files_checked:\n    - CLAUDE.md\n    - agents/code-reviewer.md\n", "")…'
```

Mutant checked valid first: `mutant valid (non-empty, differs)`; diff `392,394d391` removes `files_checked:` and its two items. Each suite run from inside the copy with `HOME="$SCRATCH/home"`:

| Suite | Result | Output line |
|---|---|---|
| `bash loomwright/scripts/test-result-validators.sh` | green (rc=0) | `RESULT  pass=468  fail=0` |
| `bash loomwright/scripts/test-emit-block-parses.sh` | green (rc=0) | `test-emit-block-parses: 5/5 passed` |
| `bash scripts/check-contract-parity.sh` | green (rc=0) | `✓ contract-parity: all hook-enforced fields present and all status/decision literals in-enum.` |
| `bash loomwright/scripts/build-capabilities.sh --check` | green (rc=0) | (no output — success is silent) |

**Gap, stated plainly: NO suite went red.** No gate pins the `CODE_REVIEW_RESULT:` template's field set. `check-contract-parity.sh` only asks that each hook-required field name appear *somewhere* in the prompt, and `files_checked` still appears in the prose (Output Format, Environment-Blocked rule 1, the checklist). This PR does not add a pin; it is listed under `not_verified` as a follow-up candidate.

## AC8 — running system

Runtime agent names come from `loomwright/capabilities.json` (`runtime_agent_type`: `loomwright:loomwright:plan-reviewer`, `loomwright:loomwright:code-reviewer`). Each run's `system/init` event (stream-json) lists the plugin as `{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline"}` and no other `loomwright` entry (only `loomwright-lanes@atelier`), so the worktree copy, not the installed plugin, was loaded. Peak context = the largest single assistant message's `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`, the way `loomwright/scripts/read-token-ledger.sh` computes it, read from the run's stream-json transcript.

| Spawn | Command | Session id | Result block | Peak context | Cost / turns |
|---|---|---|---|---|---|
| Plan Review (slim prompt) | `claude -p --plugin-dir <worktree>/loomwright --agent loomwright:loomwright:plan-reviewer --max-budget-usd 3 --output-format stream-json --verbose < <"Output a PLAN_REVIEW_RESULT block." + this brief's text>` | `05b30f27-cc2e-4bbb-801e-bc38848f664d` | `PLAN_REVIEW_RESULT` emitted, `decision: PASS`, 3 LOW issues — but **not valid**: `validate-plan-review-result.py` returns `decision: block` (`line 16: unterminated quoted scalar`), because `summary:` spans several lines | 52690 | $0.59 / 16 |
| Code review (slim prompt) | `claude -p --plugin-dir <worktree>/loomwright --agent loomwright:loomwright:code-reviewer --max-budget-usd 5 --output-format stream-json --verbose < <"review_mode: diff_review. Review the diff git diff ee3d7ea...HEAD …">` | `c5e8e7a7-2481-4241-81e1-5b3e2603f196` | valid `CODE_REVIEW_RESULT` (`validate-code-review-result.py` prints `{}`), `decision: FAIL`. It escalated itself to `consistency_audit` (agents/ trigger). Its HIGH finding was real: `check-vendor-coupling.sh` failed on the new on-demand Read lines and the new rationale doc, now fixed in this PR. Its MEDIUM finding was this evidence file not existing yet. | 101498 | $1.64 / 29 |

PLAN_REVIEW_CONTROL_PLACEHOLDER

## AC10 — CI

CI_PLACEHOLDER
