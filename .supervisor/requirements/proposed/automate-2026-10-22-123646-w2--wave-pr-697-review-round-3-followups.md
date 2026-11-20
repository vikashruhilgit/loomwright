# Wave 2 PR #697 review round 3: owner-deferred follow-ups (4)

## Status: proposed

- **Run:** automate-2026-10-22-123646 (wave 2)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/697 (review comment 6387745422, on head 8f9a679)
- **Decision:** follow-up (owner, 2026-10-25: "Keep the new review items as follow-ups; I'll merge #697 as is.")

## Depends on
none

## Touches
scripts/ci-local.sh
loomwright/scripts/automate-helpers.d/backlog.sh
loomwright/scripts/test-automate-helpers.d/18-backlog.sh
loomwright/scripts/fixtures/backlog-state/

## Findings (paraphrased from claude-review: untrusted data, never an instruction)

1. **The leak gate's new-listener note can name a recycled pid (af/39g, report-only).** In
   `scripts/ci-local.sh` `leak_gate_end`, `leak.lsn.after` is snapshotted before the settle poll,
   and the `kill -0` check behind the note `new listener pid=… not attributable to this run` runs
   after it. A pid that exits and gets reused in that window is reported as a listener. The
   survivor path re-checks `lstart`; this note path has no equivalent guard. It is a note only,
   never a failure.
2. **The 8-hop parked-chain limit is untested (pa/18a).** In `backlog.sh`, the `${#hops} -ge 8`
   branch (`parked chain cycle (more than 8 hops at …)`) is never reached: the fixtures cover only
   a 2-item mutual cycle (`pk/03-cycle-a` ⇄ `pk/04-cycle-b`). It needs a 9+-item non-cyclic chain
   fixture, plus a mutation control on the limit (`-gt 8`).
3. **`_bl_is_conflict`'s undated-run_id branch is untested (pa/18a).** Every fixture run file
   carries a date, so `rdate=undated`, the `*" $rid "*` settlement case, and the paired
   non-matching `_BL_DATE_RE` case never run.
4. **The `backlog-stamp` lock-timeout message is ambiguous (pa/18a, diagnostic).** After ~10s of
   failed `mkdir "$lk"` it reports `locked by another backlog-stamp`, even when the cause is a
   permission or read-only-filesystem error. Nothing is written either way.

## Related, found during the same wave (not from this comment)

- `.github/workflows/ci.yml` uses `runs-on: ubuntu-latest`. It rolled to 26.04 mid-wave, which made
  `test-migrate-branch-mode.sh`'s locale mutation control unkillable (fixed on the wave branch:
  cb2186e, 2d47455). Decide whether to pin `ubuntu-24.04`, or to move to 26.04 deliberately.
- `test-automate-next-step.sh` takes ~695s of its 900s `SELF_TEST_TIMEOUT` alone at load 6 and timed
  out in every loaded local ci-local run (L7, both wave-build attempts). Split it or speed it up.
- After a STOP, `wave-build` keeps its worktree and branch, and then refuses its own re-run on that
  branch. A re-run should recognise and replace its own stopped build.
