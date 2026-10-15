# tr08b — single-lane mode (`/automate --parallel 1`): evidence

Requirement: `.supervisor/requirements/twin-remediation/08b-single-lane-sequential.md`. Contract: `loomwright/skills/automate-loop/lanes.md` "Single-lane mode (`--parallel 1`)".

## Validation 2 (running system) — NOT verified

The worker could not run it: it needs a detached headless Opus lane, a real PR and the owner's typed command, which cannot happen inside this item's own run. The operator runs it.

**Run:** on a checkout with branch mode ON (`bash loomwright/scripts/setup-memory.sh --root . mode` prints `on <branch>`), with a Queue of two trivial items (e.g. two one-line doc requirements):

```
/automate --parallel 1 --folder <dir holding the two trivial items>
# after item 1 parks: merge its PR on GitHub, then
/automate --resume <parent run_id>
```

**What it must show:**

1. Item 1 runs in `<primary>-lanes/<run_id>/L1/`; its `lane.json` carries `"single_lane": true`.
2. At the park the lane's `## Current` reads `- item: <item 1> | status: awaiting_merge | pr: <url> | branch: <b>` and `- pause_reason: awaiting_merge` (`cat <primary>-lanes/<run_id>/L1/.supervisor/automate/<run_id>-L1.md`).
3. The watcher survives the lane: after the lane's `claude -p` process has exited (`bash loomwright/scripts/automate-lanes.sh lane-status <parent_runfile>` no longer reads `running`), `<lane>/.supervisor/automate/<run_id>-L1.merge-watch` names a pid for which `kill -0 <pid>` succeeds and `ps -ww -p <pid> -o command=` shows `automate-merge-watch.sh … <pr_url>`.
4. No wave PR: no `wave/<run_id>-w*` branch on origin (`git ls-remote origin 'wave/*'`), no `wave built:` line in the parent `## Progress`.
5. The parent `## Progress` carries a `drain-guard: ok — …` line (`automate-helpers.sh lane-drain-check <lane>` at the park).
6. After the merge + `--resume`: `fleet-closeout` prints `tokens — L1 TOTAL=<n>` before `remove — L1 removed`, the parent `## Progress` carries `fleet closeout: L1 tokens TOTAL=<n>`, item 1 is `- [x]`, and item 2 runs in a NEW lane `L2` whose stream log's `system/init` session id differs from L1's (`grep -m1 '"subtype":"init"' <primary>-lanes/<run_id>/L1.stream.log <primary>-lanes/<run_id>/L2.stream.log`).

Fallback if step 3 fails (the watcher died with the lane process): the `--resume` → `fleet-closeout` → `lane-convert-ready` path still closes the lane out; record the failure here.

## AC 8 — the merge watcher outlives its launcher (committed test + a standalone run)

`loomwright/scripts/test-automate-lanes.sh` (group SL11) reads the launch line from `automate-merge-watch.sh`'s header, runs it from a short-lived `bash -c` parent against a stub `gh` that reports `OPEN`, waits for the parent to exit, sends the watcher SIGHUP (the hang-up a host's exit delivers), and asserts the marker pid is alive and is the watcher. A mutation control runs the same leg on a header whose line lost `nohup`. Suite output:

```
ok   - SL11 the documented launch line is found in the automate-merge-watch.sh header
ok   - SL11b a watcher launched with that line outlives its parent and the hang-up (marker pid alive, ps shows the watcher + pr_url)
ok   - SL11c mutation control: the line without nohup ⇒ the watcher dies with the hang-up (SL11b would be red)
```

The same steps as a standalone script (paths shortened to `<tmp>` / `<scripts>`):

```
documented line: env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh <runfile> <item> <pr_url> </dev/null >"<runfile dir>/<run_id>.merge-watch.log" 2>&1 &
launching parent pid 24944 exited
marker: pid=24946 pr_url=https://github.com/o/r/pull/881 started=2026-10-15T01:01:00Z 
after SIGHUP: kill -0 24946 ⇒ alive
ps: bash <scripts>/automate-merge-watch.sh <tmp>/w/.supervisor/automate/ws.md reqs/a.md https://github.com/o/r/pull/881
stopped with TERM; marker present: no
```

## AC 10 — `lane-drain-check` on a fixture lane

```
$ automate-helpers.sh lane-drain-check <lane>   # one owned drain after the last picked
drain-guard: ok — 1 owned drain(s), no dispatch marker, no config backup
$ automate-helpers.sh lane-drain-check <lane>   # a second plain drain + a leftover config backup
drain-guard: violation — 2 owned drain(s) after the last picked line (exactly 1 expected); config backup automate-2026-10-14-120000-L1.config-backup.json present (auto_review never restored)
$ automate-helpers.sh lane-drain-check <lane>   # run file removed
drain-guard: unknown — lane run file unreadable (automate-2026-10-14-120000-L1.md)
$ automate-helpers.sh lane-park --root <lane>
awaiting_merge
```
