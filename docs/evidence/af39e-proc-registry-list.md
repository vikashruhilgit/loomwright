# Evidence — af39e: `proc-registry.sh list` on this machine

Captured 2026-10-22 on macOS (Darwin 25.6.0; `bash` on PATH is GNU bash 5.3.20), from inside a Claude Code
session, against this branch's `loomwright/scripts/` (the registry script, the merge watcher and the postmortem
dispatcher as changed here). Home paths are written as `~`; scratch paths as `<scratch>`. `lstart` is shown in
UTC (`TZ=UTC0`), the way the registry itself reads it.

## 1. The real user-scope registry (read-only)

Nothing on this machine has run the registering launchers yet (the change is not merged), so the real registry
`~/.claude/loomwright/procs/` does not exist and `list` reports it empty. `list` creates nothing.

```
$ bash loomwright/scripts/proc-registry.sh list
# id	kind	pid	age	class	evidence
(no entries)
```

## 2. One row per class, in a scratch registry

**Method:** `LOOMWRIGHT_PROC_REGISTRY_DIR=<scratch>/procs` (never the real home). Two rows come from the REAL
launchers registering themselves: a merge watcher (`automate-merge-watch.sh`, gh stubbed to read the PR OPEN),
and a postmortem dispatch (`dispatch-pr-postmortem.sh`, a stub `claude` that sleeps, its cap overridden to 1 s
with `LOOMWRIGHT_PROC_MAX_S_POSTMORTEM=1` so it reads overdue after 2 s). The postmortem row's identity still
matches the live stub, which shows its registration hashed the command line after `nohup` and `env` exec'd, not
before. The other two rows are direct `register` calls on fixture processes: a `sleep` registered with a `--repo`
that is then removed (orphaned), and a `sleep` that is registered and then killed (finished). Every process was
stopped and the scratch dir removed afterwards.

```
$ bash loomwright/scripts/proc-registry.sh list
# id	kind	pid	age	class	evidence
24157-34eeaca0e11d108f	merge-watch	24157	3s	running	identity matches; age 3s <= cap 259200s
24373-86adfa3f5793279f	postmortem	24373	3s	overdue	age 3s > cap 1s
24404-349f8ad38e567650	drain	24404	4s	orphaned	repo dir missing: <scratch>/gone-repo
24928-bbc1b2c1d5262e80	phase	24928	-	finished	pid gone

# one ps line per row: ps -o pid=,lstart=,etime=,command= -p <pid>
[running] pid 24157: 24157 Thu Oct 22 09:02:32 2026     00:04 bash ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L2-af39e-2-dep/loomwright/scripts/automate-merge-watch.sh <scratch>/repo/.supervisor/automate/automate-demo.md item-a https://github.com/o/r/pull/1
[overdue] pid 24373: 24373 Thu Oct 22 09:02:32 2026     00:04 bash <scratch>/bin/claude -p /loomwright:pr-postmortem https://github.com/o/r/pull/2
[orphaned] pid 24404: 24404 Thu Oct 22 09:02:32 2026     00:04 sleep 300
[finished] pid 24928: (no such process — the pid is gone)

$ bash loomwright/scripts/proc-registry.sh reap   # dry run (the default): nothing signalled or changed
keep 24157-34eeaca0e11d108f (merge-watch, pid 24157, running)
would stop 24373-86adfa3f5793279f (postmortem, pid 24373, overdue): TERM, KILL after 10s if it still matches — age 4s > cap 1s
would stop 24404-349f8ad38e567650 (drain, pid 24404, orphaned): TERM, KILL after 10s if it still matches — repo dir missing: <scratch>/gone-repo
would prune 24928-bbc1b2c1d5262e80 (phase, pid 24928, finished): no signal — pid gone
(dry run — nothing signalled or changed; re-run with --apply)
```

What each `ps` line proves:

- **running** — the merge watcher is alive, its command line is the watcher's own (`bash …/automate-merge-watch.sh
  <run file> item-a <pr>`), and its age (4 s) is under the cap the watcher passed (259200 s, its default).
- **overdue** — the stub `claude -p /loomwright:pr-postmortem …` is alive with the registered command line, and its
  elapsed time is past the 1 s cap.
- **orphaned** — the `sleep 300` is alive and matches, but the repo dir it was registered with is gone.
- **finished** — `ps` finds no process for the pid, so the row is pruned on `--apply`, never signalled.

The dry-run `reap` lists what `--apply` would do and changes nothing: the running watcher is kept, the overdue and
orphaned processes would be stopped only if their start time and command line still match, and the finished
entry would be pruned without a signal.
