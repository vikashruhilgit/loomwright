# escalation-cause replay fixtures (automate-followups/31)

Consumed by `test-automate-helpers.sh` section ESC (`escalation-cause` legs). Wave S2's two
temporary escalations, replayed through a stubbed `gh`:

- `s2c-log-failed.txt` — verbatim output of
  `gh run view 37254186674 --log-failed --attempt 1` (PR #381, head
  `a7f995344bbb9c33663b58fb7d0f691ddd9d513f`): the required `ci` check went red on a
  1-second `ci-slot` timeout inside `scripts/test-ci-local.sh`, a file the PR does not touch.
- `s2c-rollup.json` / `s2c-files.json` — that head's check rollup (`ci` FAILURE on run
  37254186674, `claude-review` SUCCESS) and the PR's 8 changed files, as `gh pr view --json` returns them.
- `s2d-rollup.json` — PR #386 at head `1e35336` (only the short sha was recorded): `ci`
  green, `claude-review` IN_PROGRESS on run 37259136927 at the 1200 s bound.

The run ids 37254186674 (s2-c `ci`) and 37259136927 (s2-d `claude-review`) are the real ones;
the other run ids and every `/job/<n>` segment in the rollups are illustrative.

Expected: s2-c ⇒ `check_red_unrelated check=ci`, s2-d ⇒ `check_pending check=claude-review`.
