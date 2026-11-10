# Dismissed follow-ups 03 — meta-sync group: dispositions

Base commit: `f071613abefa18cb4e4a94e2191364771db5e458`. Every re-verify check below ran on the base
text (`git show f071613:<path> | grep -nF '<anchor>'`) and hit. Pre-fix red runs: the new legs
(89–93, plus their mutation controls) ran with the suite's own prologue against a scratch
`git archive f071613 loomwright/scripts` copy (the base `meta-sync.sh`, its `meta-sync.d/` modules,
`setup-memory.sh` and `read-system-contract.sh`), the new test text taken from the fix branch:
4 passed, 6 failed. The 6 reds are legs 89, 90 and 91 (below) and the three mutation controls of
leg 92, which cannot build a mutant from base text that lacks the fix (expected). The 4 greens are
leg 90's live-holder control, which is meant to pass on both sides, and the F134 drift pin with its
two mutation controls (no behavior change, so green on base by design). The same run on the fix
branch: 10 passed, 0 failed. The full suite on the fix branch: see "Suite result" at the end.

| Finding | Re-verify check on base | Disposition | Test file :: leg | Pre-fix red result |
|---|---|---|---|---|
| F003 | `grep -nF 'if g push -q origin "$commit:refs/heads/$BRANCH" 2>"$WORK/push.err"; then' loomwright/scripts/meta-sync.d/commands.sh` (hit: a plain refspec push, no expected old value); repro below | fixed | `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` :: leg 89 `a branch deleted after the fetch: the push is refused, the re-fetch ends no_remote_branch, the branch stays absent and meta-base is untouched`; mutation control `03-mutants-scrub-allowlist.sh` :: leg 92 `mutation control (lease)` | `FAIL: a branch deleted after the fetch … (rc=0 receive-pack runs=1 out=meta_sync: pushed <sha> (1 path(s)); branch RE-CREATED at <sha>)`: base re-creates the deleted branch |
| F004 | `grep -nF 'case "$RESERVED_OWNERS" in *" $owner "*) continue ;; esac' loomwright/scripts/meta-sync.d/scrub.sh` and `grep -nF 'case "${s#*/}" in *[!.]*) : ;; *) continue ;; esac' …/scrub.sh` (both hit: `orgs/<x>` and `<x>/...` skip the owner) | fixed | `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` :: leg 91 `orgs/ users/ sponsors/ evilcorp and evilcorp/.../pull are forge_slug hits; owner behind orgs/ users/ and owner/.../pull (owner/repo allowlisted) are not`; mutation control leg 92 `mutation control (owner)` | `FAIL: orgs/ users/ sponsors/ evilcorp and evilcorp/.../pull are forge_slug hits … (rc=0 hits=)`: base reports none of the four |
| F005 | `grep -nF 'die "locked — another meta-sync (pid ${holder:-unknown}) holds $LOCK_DIR; waited ${LOCK_WAIT}s, nothing was changed"' loomwright/scripts/meta-sync.d/lock.sh` (hit: no hint) and `grep -nF '[ "$depth" -le 4 ] \|\| return 0' …/lock.sh` (hit: the depth bound, kept) | fixed | `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` :: leg 90 `a dead holder behind a 5-deep dead marker chain -> exit 1 'locked … the holder is not running: remove … by hand', nothing changed` (control `a live holder -> exit 1 'locked' with no hand-fix hint`, green both sides); mutation control leg 92 `mutation control (hint)` | `FAIL: a dead holder behind a 5-deep dead marker chain … (rc=1 out=meta_sync: locked — another meta-sync (pid <p>) holds <gitdir>/meta-sync.lock; waited 1s, nothing was changed)`: no hand-fix hint |
| F134 | `grep -nF` of `twin_field() { printf '%s' "$1" \| sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }` in `loomwright/scripts/meta-sync.d/learning-twin.sh` and of `field() { … }` (same expression) in `loomwright/scripts/read-system-contract.sh`, and `grep -nF 'prev="GENESIS"'` in both (all hit: identical copies, nothing pins them) | fixed (drift pin; no behavior change) | `loomwright/scripts/test-meta-sync.d/04-learning-stores.sh` :: leg 93 `twin_field and read-system-contract.sh's field carry a byte-identical sed expression and both walks start at prev="GENESIS"`, with two mutation controls on scratch copies: `([^\"]*)` → `([^\"]+)` in `twin_field`, and `prev="GENESIS0"` in the reader | Not applicable: the copies agree on base, so the pin is green there. Its red proof is the two mutation controls (`mutation control (twin drift)`, `mutation control (twin start)`), each green when it turns the pin red |

## F003: the fixture differs from the brief's, and why

The brief's AC17 fixture is a `pre-push` hook (through `core.hooksPath`) that deletes the branch
in `origin.git`. A scratch probe (`git 2.55.0`) showed that this fixture cannot reach the defect.
`pre-push` runs after receive-pack has advertised its refs, so a plain push sends
`<advertised R> <new> refs/heads/<branch>`. receive-pack's ref transaction then checks that old
value and refuses with `cannot lock ref … reference does not exist`. Base and fix both refuse, so
the leg would be green on base, which fails AC2. The defect window is a deletion that lands BEFORE
the push connects. The same probe showed it there: a plain push re-creates the branch (rc 0), and
`--force-with-lease=refs/heads/<branch>:R` is rejected `(stale info)`, with the branch still absent.
Leg 89 therefore deletes the branch from a receive-pack wrapper (`remote.origin.receivepack` in the
pushing clone). The wrapper runs `update-ref -d` and then `exec git receive-pack`, so the deletion
lands after the SUT's fetch and before the advertisement. Fetch and `ls-remote` go through
upload-pack and do not see the wrapper.

AC17 also says the run "ends `push_failed`". It ends `no_remote_branch` (exit 1) instead, which is
the brief's Design for F003: "the retry re-fetches, and nothing is ever created". After the leased
push is refused, the retry loop re-fetches, finds the branch absent, and stops with the `init`
hint. It never tries the push again. The leg asserts the rejected attempt, the `no_remote_branch`
end, that the branch is absent on origin, and that meta-base is byte-unchanged.

Two existing legs forbade any `--force*` text: leg 19 (a static grep of the bundle) and leg 34 (the
push-argv shim). The lease is a refusal-only condition: the commit's parent is R, so the only update
the lease admits is the fast-forward R → commit. Each of the two legs now masks exactly the
R-pinned lease token (leg 19: `--force-with-lease="refs/heads/$BRANCH:$R"`; leg 34:
`--force-with-lease=refs/heads/<branch>:<40-hex>`) before its unchanged regex runs, so a bare
`--force`, a `-f`, a `+refspec` or an unpinned lease still fails both legs. Leg 19 also gained a
positive check that the publish push carries that exact lease.

## Suite result (fix branch)

`bash loomwright/scripts/test-meta-sync.sh`: `test-meta-sync: 377 passed, 0 failed`. That includes
the normal-push legs (2, 17 concurrent pushes, where the loser's leased push is refused, re-fetches
and lands) and the narrowed legs 19 and 34. The other suites that run `meta-sync.sh` also pass:
`test-meta-sync-modules.sh` 53/0, `test-meta-sync-rehearsal.sh` 42/0,
`test-mkdir-lock-false-win.sh` 43/0, `test-committed-twin-scrub.sh` 41/0 and
`test-migrate-branch-mode.sh` 161/0.

## Surfaces changed beside the brief's file list

- `loomwright/scripts/meta-sync.sh` — the SCRUB header's `forge_slug` paragraph now states the
  F004 owner rule (orgs/users/sponsors, and the owner-only check). Without this edit the header
  would contradict the code.
- `loomwright/scripts/fixtures/meta-sync-since-split.patch` — `test-meta-sync-modules.sh` compares
  the stripped bundle with the pre-split base plus this patch ("A change to meta-sync adds itself
  to the patch in the same PR"). It was regenerated with that suite's own `strip_split`, as
  `diff -u --label base.sh --label base.sh`. The same method reproduces the base commit's patch
  byte-for-byte, and the new patch differs from it only by this group's hunks.
- `loomwright/scripts/test-meta-sync.d/02-guards-mode-base.sh` — leg 34's argv check (above).
- `loomwright/scripts/test-meta-sync.sh` — its `Covers` index gains legs 89–93, and leg 34's entry
  names the lease exception.
