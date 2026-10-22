# Evidence — pa/18b `right-size` verdict and `merge-items`

Branch: the pa/18b subtask-4 branch (subtasks 1, 2 and 3 merged in), run 2026-10-22 on macOS (bash 3.2).
Every command below runs from the repository root against the branch's own dispatcher,
`loomwright/scripts/automate-helpers.sh`. Temp paths are `mktemp -d` dirs, removed afterwards.

## Running system: three hand-built items (2, 12 and 35 Touches files)

The script builds one requirement folder with three items. Each has two Scope bullets, one
acceptance criterion, `## Depends on` = `none` and N distinct `src/<slug>/fNN.sh` Touches lines.
The tree carries an empty companions table, so the counts are the declared files.

```bash
T="$(mktemp -d)"
mkdir -p "$T/.supervisor/requirements/size-demo" "$T/.agent"
printf '{"schema_version":1,"companions":[]}\n' > "$T/.agent/companions.json"
mk() {  # mk <slug> <touches-count>
  f="$T/.supervisor/requirements/size-demo/$1.md"
  {
    printf '# %s\n\n## Status: pending\n\n## Scope\n- one\n- two\n\n## Acceptance criteria\n- a\n\n## Depends on\nnone\n\n## Touches\n' "$1"
    i=1; while [ "$i" -le "$2" ]; do printf 'src/%s/f%02d.sh\n' "$1" "$i"; i=$((i + 1)); done
  } > "$f"
}
mk 01-two-files 2
mk 02-twelve-files 12
mk 03-thirty-five-files 35
for n in 01-two-files 02-twelve-files 03-thirty-five-files; do
  bash loomwright/scripts/automate-helpers.sh right-size "$T/.supervisor/requirements/size-demo/$n.md" --root "$T"
  echo "rc=$?"
done
rm -rf "$T"
```

Output (stdout and stderr, verbatim):

```
size-demo/01-two-files: small (2 files, 2 scope items, 1 criteria) — merge candidates: size-demo/02-twelve-files (0 shared files, same folder), size-demo/03-thirty-five-files (0 shared files, same folder)
rc=0
size-demo/02-twelve-files: ok (12 files, 2 scope items, 1 criteria)
rc=0
size-demo/03-thirty-five-files: large (35 files) — will not fit one PR: split by Part
rc=0
```

At the default thresholds (`right_size_small` 3, `right_size_large_files` 30, no config file in
the tree), 2 files reads `small`, 12 reads `ok`, and 35 reads `large` with only the `files` cause.
The item has no `## Part` headings, so the parts cause is not named. The small item's candidates
qualify only by sharing its folder, since no Touches path is shared. A merge candidate is any
eligible sibling, so a `large` sibling can still be named. Every verdict exits 0.

## Targeted tests (`<passed>/<total>`)

Each test ran once on the finished branch. The counts are taken from each test's own summary line.

| Command | Result |
|---|---|
| `bash loomwright/scripts/test-automate-helpers.sh 17-right-size 13-plan-waves 01-config` | 246/246 (`RESULT: 246 passed, 0 failed`) |
| `bash loomwright/scripts/test-propose-common.sh` | 56/56 (`propose-common: 56 passed, 0 failed`) |
| `bash loomwright/scripts/test-automate-dismissed.sh` | 261/261 (`test-automate-dismissed: 261 passed, 0 failed`) |
| `bash loomwright/scripts/test-propose-from-verify.sh` | 68/68 (`propose-from-verify: 68 passed, 0 failed`) |
| `bash loomwright/scripts/test-requirement-shape.sh` | 13/13 (`test-requirement-shape: 13 passed, 0 failed`) |
| `bash loomwright/scripts/test-wave-scope.sh` | 27/27 (`passed: 27  failed: 0`) |
| `bash loomwright/scripts/test-automate-helpers-dispatch.sh` | 48/48 (`RESULT: 48 passed, 0 failed, 0 skipped`) |
| `bash loomwright/scripts/test-loop-inventory.sh` | 43/43 (`RESULT: 43/43 passed`) |
| `bash loomwright/scripts/test-citation-drift.sh` | 26/26 (`citation-drift: 26 passed, 0 failed`) |
| `bash scripts/check-doc-currency.sh` | pass (`doc-currency: all checked version/count claims match the authoritative source.`) |
| `bash scripts/check-token-budget.sh` | pass, 0 breaches (`user-story-writing` 4452 of 4732, `automate-loop` 46155 of 48362, PO agent 15913 of 17356, PO command 9460 of 10258 proxy tokens) |
| `bash scripts/check-skills-index-sync.sh` | pass |
| `bash scripts/check-prompt-history-refs.sh` | pass (no runtime prompt above its baseline) |
| `bash scripts/check-version-bump.sh` | pass (`bumped 17.14.1 -> 17.15.0 (minor); the entry is the fold of: pa18b-right-size-check.md salvage-drain-records.md`) |

The four pass/fail gates print no per-check count, so they are recorded as pass. The full
`scripts/ci-local.sh` runs on GitHub CI.
