# Evidence — session-resume / telemetry / host-mode test gaps (dismissed-followups 05, group E)

Four dismissed `/automate` follow-up findings (F338, F360, F359, F098), each re-checked on the
worktree base `26eda742` before any edit, then fixed in the suite that owns the behaviour. Production
scripts (`session-resume.sh`, `host-mode.sh`, `send-telemetry-core.sh`) were not changed: every
finding was a test-side gap. All runs below were captured 2026-11-02 on macOS (bash 3.2 userland) in
`mktemp -d` scratch dirs; mutants were built on scratch copies, each gated on non-empty, differs from
the original, and `bash -n`.

## Dispositions

| Finding | Re-verified | Disposition | Leg / reason |
|---------|-------------|-------------|--------------|
| F338 | re-verified: present | fixed | `test-telemetry-threads.sh` T8 — `T8_<name>_sentinel_present` (×5, now in the parent shell) + `T8_every_sentinel_checked_in_parent_shell` |
| F360 | re-verified: present | fixed | `test-session-resume.sh` (bn2) — byte-identical leg compares against the pinned pre-change blob `93e1361b` (named `SKIP` when the commit is absent, e.g. CI's depth-1 clone) |
| F359 | re-verified: present | fixed | `test-session-resume.sh` (bn6) — host mode, no valid state dir (empty `SR_STATE`) ⇒ zero reader calls, zero bytes; valid-state-dir control; gated mutant M5 |
| F098 | re-verified: present | fixed | `test-host-mode.sh` (g) — `hm_tmp_cleanup` (EXIT trap + three stand-in legs `(g) cleanup: …`) and `(g) skip predicate` with a named `SKIP` for a blocked pre-existing root |

## F338 — T8 sentinel check ran inside a discarded subshell

**Re-verification (base):** `mutant()` called `ok`/`bad "T8_${name}_sentinel_present"` inside
`M="$(mutant … | tail -1)"`. A base run printed **0** `sentinel_present` lines, `RESULT total=121`.

**Fix:** a `sentinel_present <name> <sentinel>` helper runs in the parent shell before each of the five
`M="$(mutant …)"` substitutions; `mutant()` now only builds the copy and prints its path (the
`| tail -1` call sites are unchanged). A tally leg, `T8_every_sentinel_checked_in_parent_shell`,
compares the parent-shell call count with the number of `M="$(mutant ` call sites in the file
(non-zero), so it cannot pass vacuously. Post-fix: 5 sentinel lines + the tally, `total=127 passed=127`.

**Red on pre-fix (pin mutation):** the sentinel call moved back inside `mutant()` and the five
parent-shell calls deleted (scratch copy, gated) ⇒ 0 `sentinel_present` lines and
`FAIL T8_every_sentinel_checked_in_parent_shell mutant_calls=5 parent_checks=0`, rc 1.

## F360 — (bn2) byte-identical leg compared against a moving `origin/main`

**Re-verification (base):** the leg ran only when `origin/main`'s `session-resume.sh` lacked
`backlog_nudge_line`; main carries it, so a base run printed
`skipped: origin/main's pre-change hook unavailable (or already carries the nudge …)`.

**Fix (pinned baseline, not removal):** `BN_BASE=93e1361b3b657646d3547f2aab36d3b578b6b36e`, the parent
of `74719671 feat(session-resume): once-a-day SessionStart backlog stamp nudge`, the commit
`git log -S backlog_nudge_line` names as the one that added it. It follows the shape of
`test-automate-trail-modules.sh`'s `BASE=`: `git cat-file -e` and then `git show` of the blob, a named
`SKIP: (bn2) pre-change baseline … not in this clone (shallow checkout?)` when the commit is missing,
and a FAIL (not a skip) when the pinned blob already carries `backlog_nudge_line` (a wrong pin). The
zero-byte (bn2) leg is kept as it was. Post-fix (full clone):
`ok: (bn2) … byte-identical to the pinned pre-change arm 93e1361b… (reader ran)`, suite 399/0
(392 at base + this leg + the six bn6 lines).

**The leg can now go red:** before the fix it could only skip. In a full local clone, I changed the
nudge append to `[ -n "$body" ] && body="$body$nl$backlog"`, which adds a trailing newline only when
another block already printed. The pinned leg then fails with
`FAIL: (bn2) differs from the pinned pre-change arm …: old=445 new=447 bytes`, and the zero-byte
(bn2) leg stays `ok`. That mutant also reddens other legs in the suite, (p-b) and (bn1) among them,
so it is not isolated to this leg.

**CI shallow-clone consequence:** CI's `actions/checkout` fetches depth 1, so the pinned commit is
absent there and CI prints the named SKIP. This was observed on a `git clone --depth 1` of this branch:
`SKIP: (bn2) pre-change baseline 93e1361b… not in this clone`, suite rc 0. The comparison therefore
runs only in full-history checkouts (local `bash scripts/ci-local.sh`). A later deliberate change to
the curation-pending startup output would turn this leg red locally. That is what the leg claims: it
is pinned to the pre-nudge arm. In that case re-decide the pin; do not loosen it.

## F359 — empty-`SR_STATE` skip had no case

**Re-verification (base):** (bn1)–(bn5) never ran the nudge under host mode. `session-resume.sh`'s
`[ -n "$marker" ] || return 0` had no case and no mutation pin.

**Fix — new (bn6):** a hook copy beside the stub reader **and the real `host-mode.sh`** runs with
`LOOMWRIGHT_HOST_MODE=1` and `LOOMWRIGHT_HOST_STATE_DIR` unset. `lw_state_dir` then fails, `SR_STATE`
is empty, and there is no marker. The fixture would print the line if the reader ran (one
`merged_unstamped` item). Assertions: zero reader calls, zero bytes, no marker in the repo, rc 0,
empty stderr. **Control:** the same fixture with a valid state dir outside the repo makes one reader
call, prints the line and writes the marker (today) in the state dir, not the repo. This proves the
copied hook loads host mode, so zero calls is not a hook that bailed at load.

**Red on pre-fix (pin mutation, committed as M5):** `[ -n "$marker" ] || return 0` is deleted on a
gated scratch copy, which reaches the reader with an empty marker. Result:
`ok: (bn6) M5: without the empty-marker return the reader runs and the line prints — the (bn6) assertion turns red`.
That is one reader call plus the line.

## F098 — leg (g) left `/tmp/loomwright-host-<uid>` behind

**Re-verification (base):** after a base run, `/tmp/loomwright-host-501` existed, empty, with an
mtime bumped by that run. The EXIT trap removed only the per-repo `<hash>` dirs in `cleanup.list`.
Leg (g) had no guard for a pre-existing root that the resolver refuses.

**Fix:** `G_ROOT_PRE` records at suite start (before any leg) whether the root existed.
`hm_tmp_cleanup <list> <root> <preexisted>` removes each listed gate dir, then `rmdir`s the root only
when the suite created it. It never uses `rm -rf`, so a concurrent run's gate dir inside keeps the
root. The EXIT trap calls it on the real root. Leg (g) calls it in a subshell on scratch stand-ins:
- a created root is removed;
- a pre-existing root is left;
- a created root that still holds an unlisted entry is left.

`g_root_blocked` reuses the resolver's own `_lw_private_dir`. When a pre-existing root fails it, the
three fallback cases are replaced by
`SKIP: (g) pre-existing <root> fails _lw_private_dir (symlink, foreign-owned, or group/world-writable)`.
The predicate is pinned on stand-ins: absent and mode-700 run the legs, while mode-777 and a symlink
are skipped. Post-fix suite: 493/0 (489 at base + 4).

**Red on pre-fix (pin mutation):** the root `rmdir` was removed from `hm_tmp_cleanup` (scratch copy
beside the suite, gated). Result: `FAIL: (g) cleanup: the created root was left behind`, 492/1, rc 1.
**Skip branch:** in a scratch copy with `G_ROOT` pointed at a mode-777 scratch dir, the run printed
the named `SKIP` and kept the stand-in and predicate legs, 481/0, rc 0. The hostile dir was left in
place because it pre-existed.

## Honest limits

- The removal of the REAL `/tmp/loomwright-host-<uid>` at EXIT was not observed on this machine. The
  root already existed before this session's first run (most likely left by an earlier run of the
  pre-fix suite), so `G_ROOT_PRE=1` and it is correctly kept.
  The removal path is covered only through the same function on the stand-in.
- A concurrent run can create the root between this suite's start and its exit. This suite would
  then `rmdir` it at exit if it is empty, and a run that is just about to create its gate dir inside
  could lose the root. The window is narrow, and `rmdir` never removes a non-empty root.
- (bn2)'s pinned comparison is local-only, as described above.
