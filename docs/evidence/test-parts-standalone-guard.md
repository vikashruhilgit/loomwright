# Trail test parts refuse to run standalone: the incident replayed (Validation 2)

**What this proves:** the command that deleted a live `/automate` run file and its run history (issue #994),
`bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` run from a checkout, now exits 2
before running any command, prints one stderr line naming `test-automate-trail.sh`, and leaves the checkout's
`.supervisor/automate/` sentinel in place. The same replay at the base commit deletes the sentinel, so the replay
tells the two apart.

Verdict: PASS for Validation 2

**How it was run:** in a `git clone` of this branch into `mktemp -d`, never the real checkout's `.supervisor/`. The
clone's HEAD was the branch's code commit (`ccdb120`). Later commits on the branch change no part file, so the
replayed part is byte-identical at the branch tip. The control clone was checked out at `6febfe0`, the branch's base
on `main`, with `HOME` relocated into the scratch dir and a 300 s alarm on the part.

**Honest limit:** this replays one part, 05, by hand. The suites pin the rest. Each runner's `SG2` legs first check
that a part's first command is the exact guard, and report a part without it red without running it, because running
an unguarded part is the incident. They then run every part on its own from a scratch checkout under the suite's
temp root, holding the sentinels `sentinel-run.md` and `sentinel.next-step.json`, and check the exit code, the exact
stderr line and both sentinels.
The `cd "$X" || exit 1` form stops a group on a missing directory. Under macOS `/bin/bash` 3.2, `cd ""` succeeds
and stays in the current directory, so for an EMPTY `$X` the standalone guard is the protection that counts there.
Under bash 5, `cd ""` fails and the group stops too.

## Exact commands

The replay, `bash ac5.sh <repo>`:

```bash
#!/usr/bin/env bash
# ac5.sh <repo> — Validation 2: the incident command, run from a scratch clone holding a sentinel.
set -u
REPO="$1"
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
echo "\$ git clone -q --branch feature/test-parts-refuse-standalone-trail-meta <repo> \"\$S/clone\""
git clone -q --branch feature/test-parts-refuse-standalone-trail-meta "$REPO" "$S/clone"
cd "$S/clone" || exit 1
echo "\$ git log --oneline -1"; git log --oneline -1
echo '$ mkdir -p .supervisor/automate && printf '"'"'sentinel run\n'"'"' > .supervisor/automate/sentinel-run.md'
mkdir -p .supervisor/automate && printf 'sentinel run\n' > .supervisor/automate/sentinel-run.md
echo '$ ls .supervisor/automate/'; ls .supervisor/automate/
echo '$ bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh </dev/null >"$S/out" 2>"$S/err"; echo "exit=$?"'
bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh </dev/null >"$S/out" 2>"$S/err"; echo "exit=$?"
echo '$ wc -c < "$S/out"   # stdout bytes'; wc -c < "$S/out" | tr -d " "
echo '$ cat "$S/err"   # stderr'; cat "$S/err"
echo '$ ls .supervisor/automate/'; ls .supervisor/automate/
echo '$ cat .supervisor/automate/sentinel-run.md'; cat .supervisor/automate/sentinel-run.md
```

The control, `bash ac5-control.sh <repo>`, the same replay at the base commit:

```bash
#!/usr/bin/env bash
# ac5-control.sh <repo> — the same replay at the base commit (no guard, `&&;` cd group): the control.
set -u
REPO="$1"
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
mkdir -p "$S/home"
git clone -q "$REPO" "$S/clone" && git -C "$S/clone" checkout -q 6febfe0
cd "$S/clone" || exit 1
echo "\$ git log --oneline -1"; git log --oneline -1
mkdir -p .supervisor/automate && printf 'sentinel run\n' > .supervisor/automate/sentinel-run.md
echo '$ ls .supervisor/automate/'; ls .supervisor/automate/
echo '$ HOME="$S/home" bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh </dev/null >"$S/out" 2>"$S/err"; echo "exit=$?"'
HOME="$S/home" perl -e 'alarm 300; exec @ARGV' bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh </dev/null >"$S/out" 2>"$S/err"; echo "exit=$?"
echo '$ grep -c "run via test-automate-trail.sh" "$S/err"'; grep -c "run via test-automate-trail.sh" "$S/err"
echo '$ ls -A .supervisor/automate/'; ls -A .supervisor/automate/; echo "(listing ends)"
```

## Output — the branch

```text
$ git clone -q --branch feature/test-parts-refuse-standalone-trail-meta <repo> "$S/clone"
$ git log --oneline -1
ccdb120 test: trail and meta-sync test parts refuse to run standalone; cd groups stop on a failed cd
$ mkdir -p .supervisor/automate && printf 'sentinel run\n' > .supervisor/automate/sentinel-run.md
$ ls .supervisor/automate/
sentinel-run.md
$ bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh </dev/null >"$S/out" 2>"$S/err"; echo "exit=$?"
exit=2
$ wc -c < "$S/out"   # stdout bytes
0
$ cat "$S/err"   # stderr
05-finalize-closeout-others.sh: run via test-automate-trail.sh, never standalone (its fixtures need the suite's $TOP)
$ ls .supervisor/automate/
sentinel-run.md
$ cat .supervisor/automate/sentinel-run.md
sentinel run
```

Exit code 2, nothing on stdout, the one stderr line naming `test-automate-trail.sh`, and the sentinel still present
with its bytes unchanged.

## Output — the control (base commit)

```text
$ git log --oneline -1
6febfe0 feat: Product Owner and Orchestrator publish requirement files to the metadata branch (#999)
$ ls .supervisor/automate/
sentinel-run.md
$ HOME="$S/home" bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh </dev/null >"$S/out" 2>"$S/err"; echo "exit=$?"
exit=127
$ grep -c "run via test-automate-trail.sh" "$S/err"
0
$ ls -A .supervisor/automate/
(listing ends)
```

Without the guard the part runs to its end. Its `( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f
"$AUTD"/*.md )` step runs the `rm` in the clone, and the sentinel is gone: the incident, reproduced in a scratch
clone.
