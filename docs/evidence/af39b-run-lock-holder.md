# Evidence — af39b: the run lock records a live holder under any harness

Captured 2026-10-14 on macOS (Darwin 25.6.0; `bash` on PATH is GNU bash 5.3.20), from inside a Claude Code
session, against this branch's `loomwright/scripts/run-lock.sh`.
Scratch paths are shown as `<scratch>`.

## Validation 2 (AC 14) — a degraded acquire and a pinned acquire

**Method:** (a) the orphaned double-fork from the brief —
`env -u CLAUDE_PID -u CLAUDECODE -u LOOMWRIGHT_HOLDER_PID bash -c '( sleep 2; …; bash run-lock.sh acquire --owner v2:plain --root <scratch> 2><scratch>/err; cp …/meta <scratch>/meta.plain ) & exit 0'`,
then waiting for `meta.plain`. The outer shell exits first, so the acquiring shell is reparented; on this
machine the reparent target is pid 1 (`/sbin/launchd`, probed inside the subshell before the acquire), so the
walk ends there and the lock degrades to `ppid`. No owner-run Terminal.app acquire was needed.
(b) `LOOMWRIGHT_HOLDER_PID=$$` exported by a shell that stays alive across the acquire.
Script: the scratch `v2.sh` (both legs), run once.

```
## (a) double-fork, no holder env
acquiring shell pid 88667, its parent after the outer shell exited: pid 1 (/sbin/launchd)
$ cat meta.plain
pid	88667
owner	v2:plain
session_id	
ts	1791971869
pid_source	ppid
pid_start	Wed Oct 14 15:27:47 2026
$ cat err
run_lock_degraded: pid_source=ppid ttl_only=1800s
## (b) LOOMWRIGHT_HOLDER_PID=$$ from a long-lived shell
acquire rc=0 holder shell pid=90758
kill -0 90758 while the shell lives: alive
$ cat meta.pinned
pid	90758
owner	v2:pinned
session_id	
ts	1791971869
pid_source	holder_env
pid_start	Wed Oct 14 15:27:49 2026
$ cat err.pinned   # empty: no degraded line
```

(a) records the invoking shell with `pid_source ppid` and prints exactly the one degraded line on stderr;
(b) records the pinned shell with `pid_source holder_env`, alive while it lives, and prints nothing on stderr.

## Validation 3 (AC 12) — the BASE script reads a new-code meta

`git show adce64f:loomwright/scripts/run-lock.sh > <scratch>/old.sh`; a new-code acquire (live `CLAUDE_PID`, so
`pid_start` is written); then the base script's `status`, and a dead-pid / old-ts reclaim against that meta.

```
$ # Validation 3 (AC 12): new-code meta, read by the BASE (adce64f) script
$ cat meta   # written by the new run-lock.sh
pid	46716
owner	new:v12
session_id	s-v12
ts	1791971824
pid_source	claude_pid
pid_start	Wed Oct 14 15:27:04 2026
$ bash old.sh status --root <scratch>
LOCKED owner=new:v12 pid=46716 age=0
rc=0
$ # meta edited: pid 999999 (dead), ts 1 (old); pid_start kept
$ bash old.sh acquire --owner old:reclaimer --root <scratch>
rc=0
$ bash old.sh status --root <scratch>
LOCKED owner=old:reclaimer pid=19640 age=0
rc=0
$ cat meta   # rewritten by the base script
pid	19640
owner	old:reclaimer
session_id	
ts	1791971824
pid_source	claude_pid
```

The base script's `status` reads the new meta unchanged, and its reclaim (BOTH dead pid AND age >= 1800 s)
fires against it: the appended `pid_start` key is invisible to the base reader. The committed, depth-1-safe
check of the same property is `test-run-lock.sh` test 29 (a frozen copy of the base `meta_get`).
