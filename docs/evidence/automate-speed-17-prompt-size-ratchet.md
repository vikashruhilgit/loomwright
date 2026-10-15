# Evidence — automate-speed/17: size ceilings for skills and commands

Recorded 2026-10-15 on branch `feature/as17-prompt-size-ratchet` (base `f5c2d0e`), macOS, bash 3.2 and the
PATH bash. Every command ran from the repo root. Nothing here touched a production service or a shared one.

## 1. Test and gate results (`<passed>/<total>`)

| Command | Result |
|---|---|
| `bash scripts/test-check-token-budget.sh` | 82/82 (exit 0), also 82/82 under `/bin/bash` 3.2.57 |
| `bash scripts/check-token-budget.sh` | exit 0 — `agents checked: 14 \| skill dirs checked: 42 \| command docs checked: 23 \| breaches: 0 \| errors: 0` |
| `bash scripts/check-doc-currency.sh` | exit 0 — ✓ doc-currency: all checked version/count claims match the authoritative source. |
| `bash scripts/check-version-bump.sh` | exit 0 — not bumped (version 17.3.0, the merge base's); 1 fragment(s) pending — legal |
| `bash scripts/check-test-hermetic.sh` | exit 0 — 167/167 covered tests source hermetic-test-env.sh first |
| `bash loomwright/scripts/test-citation-drift.sh` | 26/26 (exit 0) |
| `bash scripts/ci-local.sh --affected` | PASS — all 17 affected entries (an inner-loop check, not the pre-push gate) |

The counts in the gate row are what this run printed, not claims kept anywhere else.

## 2. Budget JSON size

| | `wc -c loomwright/docs/prompt-token-budgets.json` |
|---|---|
| Before (base `f5c2d0e`) | 36898 |
| After | 11009 (ceiling in AC5: 18449) |

Every `note` is one line under 200 chars (the longest is 160). Agent `budget` and `measured` values are
byte-equal to the base (`jq -S '.agents | map_values({budget, measured})'` diffs clean).

## 3. Mutation controls (Validation 2)

Each ran on a TEMP copy of the working tree (`mktemp -d`, `HOME` relocated). The checkout was not edited.
The unmutated copy exited 0 first, and each mutant was checked to differ from the original before its exit
code was read.

**(a) Append 10KB to a scratch skill.** `cksum loomwright/skills/commit/SKILL.md` went from 4532 bytes to
14772 bytes. `bash scripts/check-token-budget.sh` then exited **1**:

```
commit                     3693     1247  BREACH  over by 2446 proxy tokens (1 .md files) — raise .skills["commit"] in the same PR (one-line note) or trim it
check-token-budget: FAILED — prompt inventory ratchet tripped (see BREACH/ERROR rows above).
```

Restoring the file brought the copy back to exit 0.

**(b) Delete a `.commands` entry.** `jq '.commands | has("dreaming")'` went from `true` to `false`.
`bash scripts/check-token-budget.sh` then exited **1**:

```
dreaming                  34375        -  ERROR   no budget declared in loomwright/docs/prompt-token-budgets.json (add a .commands["dreaming"] entry)
dreaming                      -        -  ERROR   ghost mirror row: table lists a command doc with no .commands entry in loomwright/docs/prompt-token-budgets.json
check-token-budget: FAILED — prompt inventory ratchet tripped (see BREACH/ERROR rows above).
```

The second row is the mirror check: the `ARCHITECTURE_CONTRACTS.md` row for `dreaming` now has no JSON entry.

## 4. Pin mutations (the brief's table)

Each mutation was applied to `scripts/check-token-budget.sh` in a TEMP copy, then
`bash scripts/test-check-token-budget.sh` was run there. All twelve exited 1. The cases that went red:

| Mutation | Red cases |
|---|---|
| drop `exit_code=1` in the skill/command BREACH branch | case7a, case7b |
| drop `exit_code=1` in the no-budget branch | case7c (skill), case7d (command) |
| drop `exit_code=1` in the non-integer branch | case7g (skill), case7h (command) |
| drop `exit_code=1` in the orphan loop | case7e (skill), case7f (command) |
| drop the zero-skill-dir guard's `exit 1` | case7k, case7l |
| drop the zero-command guard's `exit 1` | case7i, case7j |
| drop `exit_code=1` in the mirror no-row branch | case8 missing skill row, missing command row |
| drop `exit_code=1` in the mirror budget-cell drift branch | case5f, case8 skill drift, case8 command drift |
| drop `exit_code=1` in the mirror MEASURED-cell drift branch | case5g, case8 skill drift, case8 command drift |
| drop `exit_code=1` in the ghost-row loop | case8 skill ghost, case8 command ghost |
| measure top level only (`find -maxdepth 1`) | case7b (nested `*.md`) |
| unbounded agent-table parse (skill/command rows read as agent rows) | case5f, case5g, case8 valid three-table mirror, case6 live repo |

The skill and command tables share one function per check, so a single mutation turns both tables' cases red.

## 5. Honest limits

- The proxy is `bytes / 4`, not an Anthropic token count. It tracks how much prompt text there is, not how a
  tokenizer counts it.
- A skill dir is measured from the working tree, so an untracked or gitignored `*.md` in a dev checkout counts
  too. That can only make the gate stricter locally. It cannot make CI pass when it should fail.
- The ceilings were measured on this branch. A sibling lane in the same wave that adds or grows a skill or
  command will fail the gate on the integrated branch until its entry is added or raised.
