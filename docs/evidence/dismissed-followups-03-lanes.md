# Dismissed follow-ups 03 — lanes, fleet close-out, finalize and readiness

Per-finding record for the `lanes` group (Subtask 1) of `dismissed-followups/03`. Base commit for every
re-verify and every pre-fix-red run: `f071613abefa18cb4e4a94e2191364771db5e458`.

**Re-verify (AC1):** each anchor was grepped in the base version of its file —
`git show f071613:<path> | grep -nF -- '<anchor>'` — and every one was present (the finding was live).

**Pre-fix red (AC2):** `loomwright/` was copied to a scratch dir, the four changed source modules
(`automate-lanes.d/{wave,remove,readiness}.sh`, `automate-trail.d/finalize.sh`) were replaced by
`git show f071613:<path>`, and the suites were run there with the new test files:
`bash test-automate-lanes.sh` and `bash test-automate-trail.sh --group 3`. The same legs pass on the fixed
tree (`test-automate-lanes.sh` and `test-automate-trail.sh --group 3`, 0 failed).

Recorded totals: on base, `test-automate-lanes.sh` read `passed: 1259  failed: 27` (exactly the red legs
listed below) and `test-automate-trail.sh --group 3` read `232 passed, 6 failed` (the six (FNT) legs); on the
fixed tree `passed: 1286  failed: 0` and `238 passed, 0 failed`.

| Finding | Re-verify anchor (base file) | Disposition | Test file :: legs | Pre-fix red |
|---|---|---|---|---|
| F101 | `else cs="; closeout leftover: $(printf` (`automate-lanes.d/remove.sh`) and `if [ -f "$mk" ]; then _fc "human — $lane meta-push-failed:` (`wave.sh`) | fixed | `test-automate-lanes.d/04-fleet-closeout-to-optout.sh` :: AF15–AF15f; `test-automate-lanes.d/03-fixes-to-finalize.sh` :: AE6–AE6d | AF15–AF15f red (no marker; the lane was checked off and removed on the first call); AE6, AE6c red (no marker written); AE6d (the marker cleared by a complete closeout) is green on base too — base never writes one |
| F105 | `fin="lane-convert-ready: finalize skipped — metadata mode off"` (`remove.sh`) | fixed | `test-automate-trail.d/05-finalize-closeout-others.sh` :: (FNT) legs; `03-fixes-to-finalize.sh` :: AE4, AE4b, AE4d (rewritten in place), AE4c, AE5 (fixtures re-staged); `04-fleet-closeout-to-optout.sh` :: AF16–AF16c | (FNT) 6 red (`--no-trail` ignored: trail-pr opened a PR; `--no-trail` first ⇒ `run file not found`); AE4, AE4b, AE4d red; AF16, AF16b, AF16c red |
| F109 | `_fc "wave closed — lock released"` (`wave.sh`) | fixed | `04-fleet-closeout-to-optout.sh` :: AF17, AF17c | AF17, AF17c red (printed `wave closed — lock released` with the lock still held) |
| F103 | `"chore(supervisor): $LN_RUN ready_for_release -> awaiting_merge (wave end)"` (`remove.sh`) | fixed | `03-fixes-to-finalize.sh` :: AE7, AE7b, AE7c | AE7b, AE7c red (every phase used the conversion message) |
| F111 | `git check-ref-format --branch "$wb" >/dev/null 2>&1 \|\| { WV_WHY=` (`wave.sh`) | fixed | `04-fleet-closeout-to-optout.sh` :: AF18 (`a$(id)b`, `x&&y`), AF18b, AF18c | both AF18 legs red (the plan printed the name into its commands) |
| F068 | `echo "#   - a marker-only conflict is resolved in the merge commit itself"` (`wave.sh`) | fixed (doc + echoed text) | `04-fleet-closeout-to-optout.sh` :: AG1 (exact output, the rule added), AF19 | doc-only by AC2's carve-out; AG1 and AF19 are red on base (no such line) |
| F076 | `` \| Single write \| `lane-create` writes into a lane only `lane.json` `` (`docs/ARCHITECTURE_CONTRACTS.md`) | fixed (doc only) | — (the three-list diff is below) | doc-only (AC2 carve-out) |
| F262 | `ns_cm_ledger() { printf '%s/coordinator-model.jsonl'` (`automate-next-step.sh`); base `lanes.md` names no coordinator-model ledger | fixed (doc only) | — | doc-only (AC2 carve-out) |
| F077 | `eline="headline-repro: PASS — n/a (the Validation names no repro)"` (`readiness.sh`) | fixed | `test-automate-lanes.d/02-readiness-to-convert.sh` :: U16, U16b, U16c; `03-fixes-to-finalize.sh` :: Z-F5b (rewritten in place) | U16, U16b, Z-F5b red (`PASS — n/a`, total 5) |
| F133 | `function nrl(s) { return nrv(s) \|\| ph(s, "skipped") }` (`readiness.sh`) | fixed | `02-readiness-to-convert.sh` :: U17–U17e | U17, U17b red (`NL` for a count-prefixed `skipped`); U17c–U17e green on base too (the unchanged fail-closed side) |

## F076 — the three after-launch write lists at base, diffed

| After-launch coordinator write into a lane | `Single write` row | `automate-lanes.sh` `lane.json` comment (1)–(4) | `lanes.md` step 6 |
|---|---|---|---|
| `lane-answer`'s answer file | yes | yes (1) | yes |
| `lane-launch --no-cheap`'s removal of `cheap` from `lane.json` | **no** | **no** | yes |
| wave-end `lane-convert-ready` conversion + metadata push | yes | yes (2) | yes |
| … trail-pr's failure marker / Progress line | **no** | yes (2) | no |
| … merged re-run `closeout --no-trail` (stamp, check-off, `## Current` reconcile) | yes | yes (2) | no |
| … `finalize-empty`'s `## Status: done` + its Progress lines | **no** | yes (2, branch mode) | no |
| `lane-remove --abandon`'s record on a `gone` lane | yes | yes (3) | yes |
| `lane-scope-decide`'s writes on a `scope_hold` lane | **no** | yes (4) | no |
| the new `<run_id>.closeout-leftover` marker (F101) | — | — | — |

The row now carries the union of all three plus the marker and says it is the one list; the header comment
and `lanes.md` (step 6, and the INIT "Resume path" sentence that restated the same exceptions) cite it by
section name (`docs/ARCHITECTURE_CONTRACTS.md` §"Lanes", row `Single write`). `drop`'s parent Queue
check-off, named in the old header item (4), is a write to the PRIMARY's run file, not into a lane, so the
row does not list it.

## Notes on the chosen form

- **F101:** the marker is written only when the close-out leaves `## Current` at `done` — the case no re-run
  retries. A leftover that left `## Current` short of done (an unreadable PR state) is retried by the next
  re-run's closeout, so it gets no marker (an unconditional marker turned the existing Y5 / Y8b removal legs
  red for a case that heals itself).
- **F105:** `fleet-closeout`'s `*"finalize skipped"*` ⇒ `human —` branch stays for the branch-mode case whose
  finalize mode reader disagrees.
- **F133:** the bold pseudo-heading rule keeps its old phrase test inline, so no heading rule changes.
