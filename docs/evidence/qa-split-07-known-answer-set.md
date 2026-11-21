# qa-split 07 — the known-answer set, Validation step 2 (running system)

Recorded 2026-11-21 (UTC 15:08) on the owner's machine, branch `feature/qa-split-07-known-answer-set`,
Node v24.11.1, with the real outside folder `~/.claude/selvedge-eval/held-out/`
(`SELVEDGE_EVAL_HELD_OUT` unset). This is one dated measurement, not a live claim: the set's current
sizes come from `node selvedge/eval/eval-set.mjs count`.

## Result

Two of the four floors are `met` and two are `open`. The open ones are the two that need the
planted-defect set (source (a)), which this run did not write (owner decision 2026-11-21). So this
file carries **no PASS verdict line for Validation 2**; the owner decides at the READY park.

| Floor | Measured | State | Why |
|---|---|---|---|
| known-FAIL ≥ 100 | 33 | open | every FAIL so far is a real bug's parent commit; planted defects are needed to reach it |
| known-PASS ≥ 100 | 165 | met | the real bugs' fix commits plus non-defect criteria on the same commits |
| real-bug known-FAIL ≥ 30 | 33 | met | 33 sports-management bugs whose defect was observed on localhost |
| held-out known-FAIL ≥ 60 | 21 | open | the held-out side gets about 60% of the groups; planted defects are needed to reach it |

## `count`

```
$ node selvedge/eval/eval-set.mjs count
cases: 198 (tuning 72, held-out 126) in 33 group(s)
known-FAIL              33   floor 100   open
known-PASS             165   floor 100   met
real-bug known-FAIL     33   floor  30   met
held-out known-FAIL     21   floor  60   open
exit 0
```

## `manifest check`: pass, one changed byte, restored

The outside folder holds one file, `answers.json`. One byte of it was changed in place (byte 26, the
`P` of the first `"PASS"`, to `Q`), the check was run, and the file was restored from a copy taken
before the change (its sha256 compared equal to the one taken before).

```
$ node selvedge/eval/eval-set.mjs manifest check
eval-set: OK — /Users/vikashruhil/.claude/selvedge-eval/held-out matches selvedge/eval/held-out/manifest.sha256
exit 0
```

```
$ node selvedge/eval/eval-set.mjs manifest check   # after one byte of answers.json was changed
eval-set: FAIL manifest_mismatch: answers.json
exit 1
```

```
$ node selvedge/eval/eval-set.mjs manifest check   # after the byte was restored
eval-set: OK — /Users/vikashruhil/.claude/selvedge-eval/held-out matches selvedge/eval/held-out/manifest.sha256
exit 0
```

`check-leak` on the same tree: `eval-set: OK — no held-out answer or variant in the tracked files
under selvedge/eval/`.

## How the real bugs were taken

From the merged `fix` PRs of `karch4162/sports-management` (`gh pr list --search 'fix in:title'`),
43 were tried: ones whose fix shows on a page or an API route of the app running on localhost. Each
was revived at its `parent_sha` (the merge commit's first parent) and its `fix_sha` (the merge
commit) in a scratch clone of the GitHub remote, never the owner's checkout: `npm ci` when the
lockfile changed, `supabase db reset` (that commit's migrations and seed) on a separate Supabase
project id and ports (`selvedge-eval-sm`, 553xx), so the owner's own stack was never touched, and a
fresh `next dev` per commit. A probe then checked the criterion over HTTP at both commits. The exact
steps per commit are each entry's `setup` in `selvedge/eval/real-bugs.json`, and what the probe saw
is its `observed`.

An entry is `used` only when the criterion **failed at the parent and held at the fix** on
localhost; the answers are then the observed ones, not only the PR's label. Every other entry is
`skipped` with its reason, never forced:

- 33 used: #226, #286, #289, #298, #305, #328, #333, #340, #357, #362, #363, #365, #367, #368,
  #376, #377, #378, #379, #384, #387, #398, #406, #407, #411, #420, #421, #422, #426, #468, #469,
  #470, #483, #486.
- 2 did not revive: #190 (`supabase db reset` fails on its parent's migrations), #370 (`next dev`
  never served `/login` at its parent within 900 s).
- 8 did not show the defect on the seeded data (the criterion as written gave the same answer at
  both commits): #249, #283, #334, #361, #410, #417, #425, #454.

#483's parent first failed to start the same way #370's did and was re-run once; the second run
revived it, and `real-bugs.json` records that (`attempts`).

Non-defect criteria (132 cases) are generic behaviour checked by the same probes at the same commits
(the login form, signing in, refusing a wrong password, the plans on `/pricing`, and so on). A
non-defect case was kept only where its probe was observed to hold at that commit, so each one's
PASS is observed too.

Environment needed only to revive the commits (recorded in each `setup`): `.env.local` with the local
Supabase keys, a local session secret, dummy Stripe test keys and `BETA_CLUB_CAP=0` (club signup
closed, which several pricing and home-page criteria are about). Turbopack rejects the
`fonts.gstatic.com/l/font?kit=…` URLs Google serves its own font request, so each commit's
`next/font/google` CSS was fetched once with a desktop Chrome user agent and supplied through
`NEXT_FONT_GOOGLE_MOCKED_RESPONSES`; no app source was changed.

## Split and leak limits

The split seed (`qa-split-07-2026-11-21`) was written to `selvedge/eval/split.json` before any case
existed. 12 groups landed in tuning and 21 in held-out. As `selvedge/eval/README.md` says, a real
bug's answers can be worked out from the committed `parent_sha` / `fix_sha` and the public history;
the outside folder keeps the non-defect answers, and later the planted variants, out of the
repository.

One defect in the tooling showed up only on real data and was fixed here: sports-management often
merges two fixes back to back, so one commit is one bug's `fix_sha` and the next bug's `parent_sha`
(#367/#368, #377/#378, #406/#407, #421/#422). `validate` kept one role per commit, so the last entry
overwrote the other and rejected good cases. A case on a shared commit now takes its role from its
own entry (`group_id`, default `sm-pr-<pr>`), and `selvedge/tests/test-eval-set.sh` pins both
directions.
