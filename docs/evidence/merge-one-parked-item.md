# Evidence — `/automate --merge-parked <run_id>` (merge one parked item through the gate)

Captured 2026-11-06/07 on branch `feature/merge-one-parked-item-through-the-gate`, plugin version 17.33.0 (not yet
bumped), HEAD `6713379a6848951629e73d9c42d8563471aebae3`. Nothing in the fenced blocks below is hand-written except
path redaction: an absolute home path reads `<path>`.

## Validation 2 (the p14 probe on `vikashruhilgit/studio-sandbox`): NOT RUN — stopped before Run 1

**This file carries no PASS verdict line, on purpose.** The validation step is unrun. The `/automate` validation gate
should park it for the owner (`validation_unrun`).

Validation 2 asks for a NEW item parked `awaiting_merge` on the sandbox by this branch's plugin copy, and then one
`/automate --merge-parked <run_id>` that merges it through the gate, following
`probes/p14-loomwright-merge-one-parked-item.md` in `vikashruhilgit/loomwright-studio`. The procedure was read, and
the sandbox was checked read-only. Nothing was written to the sandbox: no clone, no branch, no PR, no merge. The
attempt stopped before Run 1, for three reasons:

1. **The probe says who runs it.** Its first line reads "**owner-run** (or the agent on the owner's word, with the
   owner watching: D33, D35)", and "The owner names the merge before the run". This worker ran as a background
   Supervisor subagent, so no owner was watching and no owner named the merge in this session.
2. **Run 1 is interactive.** The probe says to run it "in an ordinary terminal Claude Code session" and to "Answer
   the questions it asks". This session could only reach Run 1 through a detached headless `claude -p` session.
   That session would need its permission prompts turned off to push branches and open a PR on the sandbox, and an
   agent's instruction cannot authorize that permission change.
3. **Time.** One full `/automate` item (Launch Pad, Supervisor, the owned drain and the sandbox's CI) takes far
   longer than the foreground waits this worker can make.

What the sandbox looked like when the attempt stopped:

```text
$ gh repo view vikashruhilgit/studio-sandbox --json visibility,defaultBranchRef,isPrivate
{"defaultBranchRef":{"name":"main"},"isPrivate":false,"visibility":"PUBLIC"}
$ gh api repos/vikashruhilgit/studio-sandbox/branches/main/protection --jq '{checks: .required_status_checks.contexts, reviews: .required_pull_request_reviews.required_approving_review_count}'
{"checks":["ci"],"reviews":null}
$ gh pr list --repo vikashruhilgit/studio-sandbox --state all --limit 5 --json number,state,title,headRefName,createdAt
[{"createdAt":"2026-11-05T09:49:49Z","headRefName":"feature/add-greeting-script","number":6,"state":"OPEN","title":"2026-11-05-add-greeting-script: Add a root-level greeting.sh script that prints `hello` and exits 0"},{"createdAt":"2026-11-05T08:47:22Z","headRefName":"feature/add-ping","number":5,"state":"CLOSED","title":"2026-11-05-add-ping: Add a ping script"},{"createdAt":"2026-10-29T15:04:43Z","headRefName":"studio-live-mvtocg90-injection","number":4,"state":"CLOSED","title":"studio-live mvtocg90: a change with a note"},{"createdAt":"2026-10-29T15:04:39Z","headRefName":"studio-live-mvtocg90-ordinary","number":3,"state":"CLOSED","title":"studio-live mvtocg90: an ordinary change"},{"createdAt":"2026-10-29T12:16:07Z","headRefName":"studio-live-mvtibnkg-injection","number":2,"state":"CLOSED","title":"studio-live mvtibnkg: a change with a note"}]
$ gh pr view 6 --repo vikashruhilgit/studio-sandbox --json state,headRefOid,createdAt --jq '{state,headRefOid,createdAt}'
{"createdAt":"2026-11-05T09:49:49Z","headRefOid":"7f499b7919e3c505a6e45de2fc034e8e6948f320","state":"OPEN"}
```

The sandbox is public, and `main` requires the `ci` check, so gate condition 4 can be exercised without
`--trust-unprotected`. PR #6 is an older open item. It does not count as the NEW item the validation needs: it was
parked by a plugin from before this change, so its run file has no `- ready_sha:` line, and `--merge-parked` would
park it `ready_sha_missing` (AC15) rather than merge it. Its run file lives in another clone, which this worker
neither read nor touched.

**To finish Validation 2 (owner):** in a terminal session with this branch's plugin copy loaded
(`claude --plugin-dir <checkout>/loomwright`), run the probe's Run 1 (`/loomwright:automate --folder stories
--limit 1`) on a clean sandbox clone. Then run `/loomwright:automate --merge-parked <run_id>` once. Paste that run's
output here, together with `gh pr view <n> --repo vikashruhilgit/studio-sandbox --json state,mergedAt,mergedBy` and
the run file's `## Queue` / `## Current` / last `## Progress` lines. Write the verdict line only after that output
is pasted.

## What did run: the driver's `--merge-parked` legs against a scratch run (stubbed `gh`, real driver)

`bash loomwright/scripts/test-automate-next-step.d/13-merge-parked.sh` ran the real `automate-next-step.sh` and the
real run-file writers, with `gh` stubbed by a table and `gate-eval` / `closeout` replaced by recording spies. Honest
limit: neither the real gate nor the real closeout runs here (each has its own suites). The legs:

```text
== test-automate-next-step.sh — driver: <path> — part 13-merge-parked
  ok: driver passes bash -n
-- MP. --merge-parked: one parked item through the existing gate, the durable READY record
  ok: MP AC1: MERGE ⇒ gate-eval once, closeout once WITH its trail + --session-id, one check-off, items remain ⇒ awaiting_go (the entry's message), no pick, no spawn, mode: safe
  ok: MP AC3: no items remain ⇒ the done termination, trail included
  ok: MP AC5: --resume first, then the entry ⇒ the ctx carries the recorded ready_sha, READY and termination_reason
  ok: MP AC6: a fix-now re-drain rewrites the ready line in place (its sha and termination_reason, one line)
  ok: MP AC24: a READY report without ready_sha writes no line; an item change drops it, a same-item current-set keeps it
  ok: MP AC7: the live head is not ready_sha ⇒ PARK: head_sha_moved, a person must decide, no gate-eval
  ok: MP AC8: a comment / review after ready_at ⇒ ready_stale_feedback, no gate-eval (a comment 1 s before does not park — AC1)
  ok: MP AC9: compare behind_by > 0 ⇒ base_moved_since_ready, no gate-eval
  ok: MP AC10: the checkout is off the PR head ⇒ checkout_not_on_pr_head naming the branch, HEAD and the tree unchanged
  ok: MP AC15: no recorded ready_sha ⇒ ready_sha_missing, the live head never substituted
  ok: MP AC11: the run lock is held across gate-eval (a watcher's lock-less acquire refused), one closeout, one check-off, the lock free after
  ok: MP AC12: a park keeps awaiting_merge + one PARK line, releases the lock, one watcher (none armed beside a live one); a gate PARK reruns no decision step
  ok: MP AC13: undecided per-finding dismissed drafts stay undecided after MERGE (pending_decisions recorded)
  ok: MP AC14: --resume --auto-merge on the parked open PR names --merge-parked, keeps no flag_mode; plain --resume unchanged
  ok: MP AC16: ## Current not awaiting_merge after READY ⇒ refused by status, nothing written
  ok: MP AC17: a lane / a --parallel parent ⇒ refused by name, nothing written
  ok: MP AC18: MERGED at entry ⇒ closeout with no gate; CLOSED ⇒ RECONCILE's report, never checked off
  ok: MP LEFT: a closeout leftover kept ⇒ the entry's own tail (awaiting_go)
  ok: MP HOST: LOOMWRIGHT_HOST_STATE_DIR set ⇒ nothing written under it; the run file and sidecar under the automate dir
  ok: MP UNREAD: an unreadable PR head / review-comment / compare read parks (fail CLOSED), a late review comment parks, a held run lock refuses with nothing written
  ok: MP USAGE: --merge-parked with --resume / --start / --result ⇒ exit 2, nothing written; the driver names no pr merge
PASS: 50 FAIL: 0 (part 13-merge-parked)
rc=0
```

(The 28 `MP pin …` lines, each turning one leg red under its mutation, are left out above. All of them read `ok`.)

## Host-mode finding (requirement Assumption 3)

- **Verified, at the script level:** `automate-next-step.sh` never reads `LOOMWRIGHT_HOST_STATE_DIR`. That variable
  is read only by `host-mode.sh`, `build-capabilities.sh` and `guard-test-integrity.sh`. With it set to a scratch
  directory, the `HOST` leg above shows the entry reading and writing the run file and the
  `<run_id>.next-step.json` sidecar under the automate dir, and writing nothing under the host state directory. The
  entry prints no `spawn`, so it needs no phase relay and runs the same under `--inline-phases`.
- **Not verified:** a real host session (Loomwright Studio's kernel, or an Agent SDK session) running
  `/automate --merge-parked`. That needs Validation 2, or probe p15.

## `ready_at` finding (requirement Assumption 2)

`ready_at` is stamped when the drain's READY report is recorded (`ns_ts` in `drain-result`). The guard parks
`ready_stale_feedback` on any comment or review newer than that time, so the drain's own comments must come before
it. No real run carries a `- ready_sha:` line yet. The nearest real timestamp is the `<ts> drain READY` Progress
line, which the same `drain-result` call writes. Here it is compared with the last feedback on five real READY drains
of this repo, from the run files `automate-2026-11-03-145833` and `automate-2026-11-04-220637` in the primary
checkout (read-only `gh api`):

```text
PR 822 issues/822/comments last: 2026-11-05T13:41:08Z claude[bot] (ready_at-equivalent 2026-11-04T19:58:57Z)
PR 830 issues/830/comments last: 2026-11-05T15:28:26Z vikashruhilgit (ready_at-equivalent 2026-11-05T15:29:14Z)
PR 816 issues/816/comments last: 2026-11-04T05:41:35Z vikashruhilgit (ready_at-equivalent 2026-11-04T05:42:12Z)
PR 818 issues/818/comments last: 2026-11-04T11:16:30Z vikashruhilgit (ready_at-equivalent 2026-11-04T11:17:10Z)
PR 813 issues/813/comments last: 2026-11-04T02:06:35Z vikashruhilgit (ready_at-equivalent 2026-11-04T02:07:22Z)
```

The `pulls/<n>/reviews` and `pulls/<n>/comments` endpoints returned no entries for these PRs, so they print no line.

- **Verified:** on PRs 830, 816, 818 and 813, the drain's last comment (its `<!-- loomwright:dismissed round=1 -->` /
  `<!-- loomwright:clean round=2 -->` round comment, posted from the owner's account; bodies of PRs 830 and 816
  checked) comes 37–48 s BEFORE the READY report was recorded. So a `ready_at` stamped at report time does not park
  a re-entry on the drain's own comments.
- **PR 822** shows the guard doing its job. Commits were pushed after READY (the last commit is dated
  2026-11-05T13:39:40Z), and `claude[bot]` reviewed them later. `--merge-parked` would park it, on `head_sha_moved`
  first, and on `ready_stale_feedback` too.
- **Not verified:** a live re-entry whose `ready_at` came from the new line, and a drain that posts a comment AFTER
  its report is recorded. The 1 s boundary is pinned only by the AC8 leg's stubbed comment.
