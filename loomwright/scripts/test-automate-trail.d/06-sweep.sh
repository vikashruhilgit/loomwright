# =============================================================================
echo "== SW. sweep: squash-safe sweep of plugin-made worktrees + local branches (af/39a) =="
# Real repos in $TOP; gh and lsof stubbed through the LOOMWRIGHT_GH_BIN /
# LOOMWRIGHT_LSOF_BIN seams. The sweep gh stub answers `pr list --head <B>` per branch.
SWBIN="$TOP/swbin"; mkdir -p "$SWBIN"
# The host's local settings file — the one harness-specific path these legs need, named
# once (vendor-coupling ratchet); its directory ${SW_HS%/*} also holds the app's worktree root.
SW_HS=".claude/settings.local.json"
cat > "$SWBIN/gh" <<'STUB'
#!/usr/bin/env bash
# `pr list --head <B>` ⇒ $SWGH/<B, `/` and space as `_`>.json ([] when absent); <that>.fail ⇒ exit 1.
set -u
d="$SWGH"; echo "$*" >> "$d/argv.log"
[ "${1:-} ${2:-}" = "pr list" ] || exit 0
h=""; while [ $# -gt 0 ]; do [ "$1" = --head ] && h="${2:-}"; shift; done
f="$d/$(printf '%s' "$h" | tr '/ ' '__').json"
[ -f "$f.fail" ] && exit 1
if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi
exit 0
STUB
cat > "$SWBIN/lsof" <<'STUB'
#!/usr/bin/env bash
# `lsof -a -d cwd -F pn` stand-in: pid 1 at / plus $SWGH/lsof.extra; $SWGH/lsof.fail ⇒ exit 1.
[ -f "$SWGH/lsof.fail" ] && exit 1
printf 'p1\nfcwd\nn/\n'
[ -f "$SWGH/lsof.extra" ] && cat "$SWGH/lsof.extra"
exit 0
STUB
chmod +x "$SWBIN/gh" "$SWBIN/lsof"
sw_repo() { # <n> — SWFX, SWP (primary `proj`, base branch main, no origin), SWGH
  SWFX="$TOP/sw$1"; SWP="$SWFX/proj"; SWGH="$SWFX/gh"; mkdir -p "$SWP" "$SWGH"; : > "$SWGH/argv.log"
  ( cd "$SWP" && git init -q && git symbolic-ref HEAD refs/heads/main \
    && printf '.supervisor/\n%s/\n' "${SW_HS%/*}" > .gitignore && echo base > README \
    && git add .gitignore README && git commit -qm init ) >/dev/null 2>&1
}
sw_branch() { # <name> [<parent>] — a branch carrying its own commit (no checkout)
  local c
  c="$(git -C "$SWP" commit-tree "$(git -C "$SWP" rev-parse 'main^{tree}')" -p "${2:-main}" -m "$1" 2>/dev/null)"
  git -C "$SWP" update-ref "refs/heads/$1" "$c"
}
sw_pr() { printf '%s\n' "$2" > "$SWGH/$(printf '%s' "$1" | tr '/ ' '__').json"; }   # <branch> <json array>
sw_merged() { # <branch> <number> [<headRefOid>] — newest PR MERGED at the branch tip (or <oid>)
  local o="${3:-$(git -C "$SWP" rev-parse "refs/heads/$1")}"
  sw_pr "$1" "[{\"number\":$2,\"state\":\"MERGED\",\"headRefOid\":\"$o\",\"mergedAt\":\"2026-10-01T00:00:00Z\"}]"
}
sw_wt() { sw_branch "$2"; git -C "$SWP" worktree add -q "$1" "$2" >/dev/null 2>&1; }   # <path> <branch>
sw_run() { (cd "$SWP" && SWGH="$SWGH" LOOMWRIGHT_GH_BIN="$SWBIN/gh" LOOMWRIGHT_LSOF_BIN="${SW_LSOF:-$SWBIN/lsof}" bash "${SW_T:-$T}" sweep "$@"); }
sw_sum() { { git -C "$SWP" worktree list --porcelain; git -C "$SWP" branch -v; } | cksum; }
sw_has() { git -C "$SWP" rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1; }
sw_line() { grep -qF -- "$2" <<<"$1"; }   # <out> <fixed substring>
sw_shape() { # <label> <out> <rc>: exit 0, exactly ONE summary line, and it is the last line
  local n last
  n="$(printf '%s\n' "$2" | grep -c '^sweep: summary — ')"; last="$(printf '%s\n' "$2" | tail -n1)"
  case "$last" in "sweep: summary — "*) [ "$3" -eq 0 ] && [ "$n" = 1 ] && { ok "$1: exit 0, exactly one sweep: summary line, last"; return 0; } ;; esac
  no "$1: rc=$3 summary lines=$n last='$last'"
}
SW_ROOT_UID=0; [ "$(id -u)" -eq 0 ] && SW_ROOT_UID=1   # root reads a 0000 file: the unreadable legs need a non-root uid

# ---- branch fixture: every AC1/AC2 case side by side ------------------------
sw_branch_fixture() { # <n>
  sw_repo "$1"
  local b t
  for b in team/done moved open-pr closed-pr no-pr gh-fail garbage curb held nooid; do sw_branch "$b"; done
  sw_merged team/done 11
  sw_merged moved 12; sw_branch moved-tmp moved; git -C "$SWP" update-ref refs/heads/moved "$(git -C "$SWP" rev-parse moved-tmp)"; git -C "$SWP" branch -q -D moved-tmp
  t="$(git -C "$SWP" rev-parse refs/heads/open-pr)"
  sw_pr open-pr "[{\"number\":20,\"state\":\"MERGED\",\"headRefOid\":\"$t\"},{\"number\":21,\"state\":\"OPEN\",\"headRefOid\":\"$t\"}]"
  sw_pr closed-pr "[{\"number\":30,\"state\":\"CLOSED\",\"headRefOid\":\"$(git -C "$SWP" rev-parse refs/heads/closed-pr)\"}]"
  : > "$SWGH/gh-fail.json.fail"
  printf 'not json\n' > "$SWGH/garbage.json"
  sw_pr nooid '[{"number":13,"state":"MERGED","headRefOid":null}]'
  sw_merged curb 40; git -C "$SWP" checkout -q curb 2>/dev/null
  git -C "$SWP" worktree add -q "$SWFX/proj-base" main >/dev/null 2>&1
  sw_merged held 50; git -C "$SWP" worktree add -q "$SWFX/proj-held wt" held >/dev/null 2>&1; echo wip > "$SWFX/proj-held wt/wip.txt"
}
sw_branch_fixture 1
s0="$(sw_sum)"
out="$(sw_run)"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
sw_shape "(SW1) dry run" "$out" "$rc"
[ "$s0" = "$(sw_sum)" ] && ok "(SW1) dry run: checksum of git worktree list --porcelain + git branch -v unchanged" || no "(SW1) dry run changed worktrees/branches"
sw_line "$out" "sweep: would-remove branch team/done — PR #11 MERGED, tip == merged head " && ok "(SW1) AC1 merged + tip == headRefOid ⇒ would-remove (a branch name with a slash)" || no "(SW1) team/done line"
sw_line "$out" "sweep: kept branch moved — tip " && sw_line "$out" "moved after merge (PR #12 merged head " && ok "(SW1) AC2 moved tip ⇒ sweep: kept branch moved — … moved after merge" || no "(SW1) moved line"
sw_line "$out" "sweep: kept branch open-pr — newest PR #21 is OPEN" && ok "(SW1) AC2 newest PR OPEN ⇒ kept (an older MERGED PR at the same tip does not count)" || no "(SW1) open-pr line"
sw_line "$out" "sweep: kept branch closed-pr — newest PR #30 is CLOSED unmerged" && ok "(SW1) AC2 CLOSED unmerged ⇒ kept" || no "(SW1) closed-pr line"
sw_line "$out" "sweep: kept branch no-pr — no PR for this branch" && ok "(SW1) AC2 no PR ⇒ kept" || no "(SW1) no-pr line"
sw_line "$out" "sweep: kept branch gh-fail — gh read failed (pr list --head, rc 1)" && ok "(SW1) AC2 gh read fails ⇒ kept" || no "(SW1) gh-fail line"
sw_line "$out" "sweep: kept branch garbage — gh read failed (unparseable pr list)" && ok "(SW1) AC2 unparseable gh output ⇒ kept" || no "(SW1) garbage line"
sw_line "$out" "sweep: kept branch curb — current branch of the primary" && ok "(SW1) AC2 the primary's current branch is never a candidate (even merged)" || no "(SW1) curb line"
sw_line "$out" "sweep: kept branch main — base branch" && ok "(SW1) AC2 the base branch is never a candidate" || no "(SW1) main line"
sw_line "$out" "sweep: kept branch held — checked out in worktree $SWFX/proj-held wt" && ok "(SW1) AC2 a branch in a kept worktree is never a candidate (path with a space)" || no "(SW1) held line"
sw_line "$out" "sweep: kept worktree $SWFX/proj-held wt — dirty (uncommitted changes on held)" && ok "(SW1) AC3 dirty worktree ⇒ kept" || no "(SW1) dirty worktree line"
sw_line "$out" "sweep: kept branch nooid — PR #13 merged but headRefOid/tip unreadable" && ok "(SW1) a MERGED PR without a headRefOid ⇒ kept (no tip proof)" || no "(SW1) nooid line"
sw_line "$out" "sweep: kept worktree $SWFX/proj-base — on the base branch main" && ok "(SW1) a worktree on the base branch ⇒ kept" || no "(SW1) base-branch worktree line"
for b in curb main; do
  grep -q -- "--head $b " "$SWGH/argv.log" && no "(SW1) excluded branch $b cost a gh call" || ok "(SW1) excluded branch $b: no gh call"
done
# held's ONE read is the worktree judgment's; the branch phase adds none.
[ "$(grep -c -- "--head held " "$SWGH/argv.log")" = 1 ] && ok "(SW1) a branch held by a kept worktree: the branch phase adds no gh call" || no "(SW1) held: $(grep -c -- "--head held " "$SWGH/argv.log") gh calls"
o2="$(cd "$TOP" && SWGH="$SWGH" LOOMWRIGHT_GH_BIN="$SWBIN/gh" LOOMWRIGHT_LSOF_BIN="$SWBIN/lsof" bash "$T" sweep --root "$SWFX/proj-held wt")"
[ "$o2" = "$out" ] && ok "(SW1) --root <a linked worktree> resolves to the primary (same report from another cwd)" || no "(SW1) --root from elsewhere differs: $(printf '%s' "$o2" | tail -n1)"
out="$(sw_run --apply)"; rc=$?
sw_shape "(SW1) --apply" "$out" "$rc"
sw_line "$out" "sweep: removed branch team/done — PR #11 MERGED" && ! sw_has team/done && ok "(SW1) AC1 --apply: sweep: removed branch team/done and the branch is gone" || no "(SW1) apply team/done: $(printf '%s' "$out" | grep team/done)"
sw_kept_all=1
for b in moved open-pr closed-pr no-pr gh-fail garbage curb main held nooid; do sw_has "$b" || { sw_kept_all=0; no "(SW1) --apply removed $b"; }; done
[ "$sw_kept_all" = 1 ] && ok "(SW1) AC2 --apply: every kept branch remains (moved, OPEN, CLOSED, no PR, gh failure, unparseable, current, base, held, no headRefOid)"
[ -d "$SWFX/proj-held wt" ] && ok "(SW1) --apply: the dirty worktree remains" || no "(SW1) dirty worktree removed"
out="$(sw_run --apply)"
[ "$(printf '%s\n' "$out" | tail -n1)" = "sweep: summary — applied: 0 removed, 12 kept (2 worktree(s), 10 branch(es) examined)" ] \
  && ok "(SW1) a second --apply removes nothing (idempotent)" || no "(SW1) second apply: $(printf '%s\n' "$out" | tail -n1)"
out="$(sw_run --bogus)"; rc=$?
[ "$out" = "sweep: summary — skipped: unknown argument --bogus (nothing examined)" ] && [ "$rc" -eq 0 ] && ok "(SW1) an unknown argument ⇒ one summary line, nothing examined, exit 0" || no "(SW1) bogus arg: '$out' rc=$rc"
out="$(sw_run --root)"; rc=$?
[ "$out" = "sweep: summary — skipped: unknown argument --root (no value) (nothing examined)" ] && [ "$rc" -eq 0 ] && ok "(SW1) --root without a value ⇒ refused, nothing examined, exit 0" || no "(SW1) bare --root: '$out' rc=$rc"
out="$(cd "$TOP" && bash "$T" sweep --root "$TOP/no-such-dir")"; rc=$?
[ "$out" = "sweep: summary — skipped: not a git checkout ($TOP/no-such-dir)" ] && [ "$rc" -eq 0 ] && ok "(SW1) not a checkout ⇒ one summary line, exit 0" || no "(SW1) not a checkout: '$out' rc=$rc"

# ---- worktree fixture: every AC3/AC4/AC5 origin and condition ----------------
sw_wt_fixture() { # <n>
  sw_repo "$1"
  WT_CLEAN="$SWFX/proj-clean wt"; sw_wt "$WT_CLEAN" wclean; sw_merged wclean 61
  mkdir -p "$WT_CLEAN/.supervisor/logs" "$WT_CLEAN/.supervisor/postmortem" "$WT_CLEAN/${SW_HS%/*}"
  printf '{"event":"session"}\n' > "$WT_CLEAN/.supervisor/logs/s1.jsonl"
  printf '{"automate_key":"k"}\n' > "$WT_CLEAN/.supervisor/postmortem/results.jsonl"
  printf '{"permissions":{"allow":[]}}\n' > "$WT_CLEAN/$SW_HS"
  rm -rf "$SWFX/expect"; mkdir -p "$SWFX/expect"; cp -pR "$WT_CLEAN/.supervisor" "$WT_CLEAN/${SW_HS%/*}" "$SWFX/expect/"
  WT_DIRTY="$SWFX/proj-dirty"; sw_wt "$WT_DIRTY" wdirty; sw_merged wdirty 62; echo wip > "$WT_DIRTY/wip.txt"
  mkdir -p "$SWP/${SW_HS%/*}/worktrees" "$SWFX/proj-lanes" "$SWFX/elsewhere" "$SWFX/logged" "$SWP/.supervisor/logs"
  WT_APP="$SWP/${SW_HS%/*}/worktrees/x"; sw_wt "$WT_APP" wapp; sw_merged wapp 63
  WT_LANE="$SWFX/proj-lanes/l1"; sw_wt "$WT_LANE" wlane; sw_merged wlane 64
  WT_OTHER="$SWFX/elsewhere/o1"; sw_wt "$WT_OTHER" wother; sw_merged wother 65
  WT_LOGGED="$SWFX/logged/r1"; sw_wt "$WT_LOGGED" wlogged; sw_merged wlogged 66
  WT_DET="$SWFX/proj-det"; git -C "$SWP" worktree add -q --detach "$WT_DET" main >/dev/null 2>&1
  WT_LIVE="$SWFX/proj-live"; sw_wt "$WT_LIVE" wlive; sw_merged wlive 67
  printf 'p4242\nfcwd\nn%s/sub\n' "$WT_LIVE" > "$SWGH/lsof.extra"
  WT_UNREAD="$SWFX/proj-unread"; sw_wt "$WT_UNREAD" wunread; sw_merged wunread 68
  mkdir -p "$WT_UNREAD/.supervisor/logs"; echo secret-log > "$WT_UNREAD/.supervisor/logs/a.jsonl"
  chmod 000 "$WT_UNREAD/.supervisor/logs/a.jsonl"
  WT_LOCK="$SWFX/proj-locked"; sw_wt "$WT_LOCK" wlock; sw_merged wlock 69; git -C "$SWP" worktree lock "$WT_LOCK" >/dev/null 2>&1
  WT_GONE="$SWFX/proj-gone"; sw_wt "$WT_GONE" wgone; sw_merged wgone 71; mv "$WT_GONE" "$SWFX/gone-moved-away"
  # worktree-audit.sh's log: the off-sibling path is recorded as created (⇒ plugin-made); so is
  # the app worktree, so only the app worktree-root exclusion keeps it (the pin mutation's target).
  { jq -nc --arg p "$WT_LOGGED" '{ts:"t",event:"created",path:$p,branch:"wlogged",confirmed:true,source:"direct"}'
    jq -nc --arg p "$WT_APP" '{ts:"t",event:"created",path:$p,branch:"wapp",confirmed:true,source:"direct"}'
    echo 'legacy garbage line'; } > "$SWP/.supervisor/logs/worktrees.log"
}
sw_unread_fix() { chmod 644 "$WT_UNREAD/.supervisor/logs/a.jsonl" 2>/dev/null; return 0; }
sw_wt_fixture 2
s0="$(sw_sum)"
out="$(sw_run)"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
sw_shape "(SW2) dry run" "$out" "$rc"
[ "$s0" = "$(sw_sum)" ] && ok "(SW2) dry run: worktree list + branch -v checksum unchanged" || no "(SW2) dry run changed worktrees/branches"
[ ! -e "$SWP/.supervisor/salvage" ] && ok "(SW2) dry run salvages nothing (no .supervisor/salvage created)" || no "(SW2) dry run wrote a salvage dir"
fb="$(printf '%s\n' "$out" | grep -n '^sweep: [a-z-]* branch ' | head -n1 | cut -d: -f1)"
lw="$(printf '%s\n' "$out" | grep -nE '^sweep: [a-z-]* (worktree|app|lane|other) ' | tail -n1 | cut -d: -f1)"
[ -n "$fb" ] && [ -n "$lw" ] && [ "$lw" -lt "$fb" ] && ok "(SW2) worktrees are judged before branches" || no "(SW2) order: last worktree line $lw, first branch line $fb"
sw_line "$out" "sweep: would-remove worktree $WT_CLEAN — branch wclean: PR #61 MERGED, tip == merged head " && ok "(SW2) AC3 clean merged sibling (path with a space) ⇒ would-remove" || no "(SW2) clean line"
sw_line "$out" "sweep: would-remove worktree $WT_LOGGED — branch wlogged: PR #66" && ok "(SW2) AC3 a worktree-audit.sh 'created' path off the sibling pattern is plugin-made" || no "(SW2) logged line"
sw_line "$out" "sweep: would-remove branch wclean — PR #61" && ok "(SW2) the branch of a worktree removed this run is a candidate in the same (dry) run" || no "(SW2) wclean branch line"
sw_line "$out" "sweep: kept worktree $WT_DIRTY — dirty (uncommitted changes on wdirty)" && ok "(SW2) AC3 dirty ⇒ kept" || no "(SW2) dirty line"
sw_line "$out" "sweep: kept app $WT_APP — clean and merged (branch wapp: PR #63 MERGED" && sw_line "$out" "the app removes its own worktrees" && ok "(SW2) AC5 app-made clean+merged worktree ⇒ kept app, naming clean+merged and that the app removes it" || no "(SW2) app line"
sw_line "$out" "sweep: kept lane $WT_LANE — use lane-remove" && ok "(SW2) AC5 lane clone path ⇒ kept lane — use lane-remove" || no "(SW2) lane line"
sw_line "$out" "sweep: kept other $WT_OTHER — origin unknown" && ok "(SW2) unknown origin ⇒ kept other — origin unknown" || no "(SW2) other line"
sw_line "$out" "sweep: kept worktree $WT_DET — detached HEAD (no branch to prove)" && ok "(SW2) detached HEAD ⇒ kept" || no "(SW2) detached line"
sw_line "$out" "sweep: kept worktree $WT_LIVE — live process 4242 has its cwd here" && ok "(SW2) AC3 a live process's cwd (below the worktree) ⇒ kept, pid named" || no "(SW2) live line"
sw_line "$out" "sweep: kept branch wapp — checked out in worktree $WT_APP" && ok "(SW2) the app worktree's branch is held" || no "(SW2) wapp branch line"
sw_line "$out" "sweep: kept worktree $WT_LOCK — locked" && ok "(SW2) a locked worktree ⇒ kept" || no "(SW2) locked line"
sw_line "$out" "sweep: kept worktree $WT_GONE — directory missing" && sw_line "$out" "sweep: kept branch wgone — checked out in worktree $WT_GONE" \
  && ok "(SW2) a worktree whose directory is gone ⇒ kept (and its branch held)" || no "(SW2) missing-dir line"
# lsof absent: liveness unverifiable ⇒ every removable worktree is kept under --apply.
out="$(SW_LSOF="$TOP/no-such-lsof" sw_run --apply)"; rc=$?
sw_shape "(SW2) --apply, lsof absent" "$out" "$rc"
sw_line "$out" "sweep: kept worktree $WT_CLEAN — liveness unverifiable (lsof absent or failing)" && [ -d "$WT_CLEAN" ] && sw_has wclean \
  && ok "(SW2) AC3 lsof absent ⇒ kept (liveness unverifiable), worktree + branch remain" || no "(SW2) lsof absent: $(printf '%s\n' "$out" | grep -F "$WT_CLEAN")"
: > "$SWGH/lsof.fail"; out="$(sw_run --apply)"; rm -f "$SWGH/lsof.fail"
sw_line "$out" "sweep: kept worktree $WT_CLEAN — liveness unverifiable (lsof absent or failing)" && [ -d "$WT_CLEAN" ] \
  && ok "(SW2) AC3 lsof failing ⇒ kept" || no "(SW2) lsof failing: $(printf '%s\n' "$out" | grep -F "$WT_CLEAN")"
[ ! -e "$SWP/.supervisor/salvage" ] && ok "(SW2) a worktree kept before the salvage step leaves no salvage dir" || no "(SW2) salvage written for a kept worktree"
out="$(sw_run --apply)"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
sw_shape "(SW2) --apply" "$out" "$rc"
sw_line "$out" "sweep: removed worktree $WT_CLEAN — branch wclean: PR #61" && [ ! -d "$WT_CLEAN" ] && ! grep -qxF "worktree $WT_CLEAN" < <(git -C "$SWP" worktree list --porcelain) \
  && ok "(SW2) AC3 --apply removes the clean merged plugin worktree (git worktree remove)" || no "(SW2) clean worktree not removed: $(printf '%s\n' "$out" | grep -F "$WT_CLEAN")"
sw_salv="$(ls -d "$SWP/.supervisor/salvage/proj-clean wt-"* 2>/dev/null | head -n1)"
sw_ign_ok=1
for e in .supervisor/logs/s1.jsonl .supervisor/postmortem/results.jsonl "$SW_HS"; do
  if [ -n "$sw_salv" ] && cmp -s "$SWFX/expect/$e" "$sw_salv/ignored/$e"; then :; else sw_ign_ok=0; no "(SW2) AC4 $e not byte-identical under ignored/ (salvage '$sw_salv')"; fi
done
[ "$sw_ign_ok" = 1 ] && ok "(SW2) AC4 all 3 gitignored runtime entries are byte-identical under <salvage>/ignored/ (copied before the removal)"
sw_line "$out" "gitignored salvage verified (ignored: ok 3)" && ok "(SW2) the removed line names the verified verdict" || no "(SW2) verdict not named"
sw_line "$out" "sweep: removed branch wclean — PR #61" && ! sw_has wclean && ok "(SW2) the freed branch is removed in the same --apply run" || no "(SW2) wclean branch remains"
sw_line "$out" "sweep: removed worktree $WT_LOGGED" && [ ! -d "$WT_LOGGED" ] && ! sw_has wlogged && ok "(SW2) the log-recorded worktree + its branch are removed" || no "(SW2) logged worktree"
if [ "$SW_ROOT_UID" = 0 ]; then
  sw_line "$out" "sweep: kept worktree $WT_UNREAD — gitignored salvage not verified: ignored: failed .supervisor/logs — copy failed" && [ -d "$WT_UNREAD" ] && sw_has wunread \
    && ok "(SW2) AC4 a forced copy failure keeps the worktree, naming the failed entry" || no "(SW2) unreadable: $(printf '%s\n' "$out" | grep -F "$WT_UNREAD")"
else echo "  note: running as root — the unreadable-entry copy-failure leg is skipped"; fi
sw_kept_all=1
for w in "$WT_APP" "$WT_LIVE" "$WT_DIRTY" "$WT_LANE" "$WT_OTHER" "$WT_DET" "$WT_LOCK"; do [ -d "$w" ] || { sw_kept_all=0; no "(SW2) --apply removed $w"; }; done
grep -qxF "worktree $WT_GONE" < <(git -C "$SWP" worktree list --porcelain) && sw_has wgone && sw_has wlock || { sw_kept_all=0; no "(SW2) --apply dropped the missing-dir worktree record or a held branch"; }
[ "$sw_kept_all" = 1 ] && ok "(SW2) AC5 --apply leaves the app, live, dirty, lane, other, detached, locked and missing-dir worktrees in place"
sw_line "$out" "sweep: kept app $WT_APP — clean and merged" && ok "(SW2) AC5 --apply still reports the app worktree (kept app)" || no "(SW2) app line under --apply"
sw_unread_fix

# ---- real lsof (when it can see a child's cwd): live ⇒ kept; gone ⇒ removed --
if command -v lsof >/dev/null 2>&1; then
  sw_repo 3; WT_RL="$SWFX/proj-rl"; sw_wt "$WT_RL" wrl; sw_merged wrl 70
  ( cd "$WT_RL" && exec sleep 60 ) & sw_pid=$!
  if wait_for_cmd 10 sh -c "lsof -a -p $sw_pid -d cwd -F n 2>/dev/null | grep -xF 'n$WT_RL' >/dev/null"; then
    out="$(SW_LSOF=lsof sw_run --apply)"
    sw_line "$out" "sweep: kept worktree $WT_RL — live process $sw_pid has its cwd here" && [ -d "$WT_RL" ] \
      && ok "(SW3) real lsof: a live process's cwd keeps the worktree (pid named)" || no "(SW3) real lsof live: $(printf '%s\n' "$out" | grep -F "$WT_RL")"
    kill "$sw_pid" 2>/dev/null; wait "$sw_pid" 2>/dev/null
    out="$(SW_LSOF=lsof sw_run --apply)"
    sw_line "$out" "sweep: removed worktree $WT_RL" && [ ! -d "$WT_RL" ] && ok "(SW3) real lsof: once the process is gone the worktree is removed" || no "(SW3) real lsof gone: $(printf '%s\n' "$out" | grep -F "$WT_RL")"
  else
    kill "$sw_pid" 2>/dev/null; wait "$sw_pid" 2>/dev/null
    echo "  note: this lsof cannot see a child's cwd — real-lsof leg skipped (the stubbed legs above cover the logic)"
  fi
else
  echo "  note: lsof absent — real-lsof leg skipped"
fi

# ---- review fixes: unsalvaged gitignored content; a non-ASCII path lsof escapes --
# proj-env: merged + clean, but a gitignored `.env` no salvage list covers ⇒ kept, dry run
# and --apply alike. proj-nm: only a top-level node_modules/ beside the committed package.json
# beyond the list ⇒ removed (regenerable). proj-nest: `build/` is ignored and hand-written
# src/build/notes.md sits beside the tracked src/main.c with no manifest there ⇒ kept, named.
# proj-café: lsof under a C/POSIX locale prints the cwd of the process living there as
# `proj-caf\xc3\xa9` (the stub prints exactly that n-line), which never equals the path ⇒
# without the escaped-byte check it reads "not live" and --apply removes it.
sw_rev_fixture() { # <n>
  sw_repo "$1"
  ( cd "$SWP" && printf '.env\nnode_modules/\nbuild/\n' >> .gitignore && printf '{}\n' > package.json && mkdir -p src \
    && printf 'int main;\n' > src/main.c && git add .gitignore package.json src/main.c && git commit -qm "ignore more" ) >/dev/null 2>&1
  WT_ENV="$SWFX/proj-env"; sw_wt "$WT_ENV" wenv; sw_merged wenv 81; printf 'SECRET=1\n' > "$WT_ENV/.env"
  WT_NM="$SWFX/proj-nm"; sw_wt "$WT_NM" wnm; sw_merged wnm 82
  mkdir -p "$WT_NM/node_modules/pkg"; printf 'x\n' > "$WT_NM/node_modules/pkg/i.js"
  WT_NEST="$SWFX/proj-nest"; sw_wt "$WT_NEST" wnest; sw_merged wnest 84
  mkdir -p "$WT_NEST/src/build"; printf 'hand-written\n' > "$WT_NEST/src/build/notes.md"
  WT_UTF="$SWFX/proj-café"; sw_wt "$WT_UTF" wutf; sw_merged wutf 83
  printf 'p4343\nfcwd\nn%s\n' "$SWFX/proj-caf\\xc3\\xa9" > "$SWGH/lsof.extra"
}
sw_rev_fixture 8
out="$(sw_run)"; rc=$?
printf '%s\n' "$out" | sed 's/^/    | /'
sw_shape "(SW6) dry run" "$out" "$rc"
sw_line "$out" "sweep: kept worktree $WT_ENV — unsalvaged ignored content: .env" && ok "(SW6) dry run: a gitignored .env no list covers ⇒ kept worktree — unsalvaged ignored content: .env" || no "(SW6) env dry: $(printf '%s\n' "$out" | grep -F "$WT_ENV")"
sw_line "$out" "sweep: would-remove worktree $WT_NM — branch wnm: PR #82" && ok "(SW6) dry run: only a node_modules/ beside its package.json ⇒ would-remove" || no "(SW6) nm dry: $(printf '%s\n' "$out" | grep -F "$WT_NM")"
sw_line "$out" "sweep: kept worktree $WT_NEST — unsalvaged ignored content: src/build/" && ok "(SW6) dry run: hand-written src/build/notes.md (no manifest beside it) ⇒ kept, src/build/ named" || no "(SW6) nest dry: $(printf '%s\n' "$out" | grep -F "$WT_NEST")"
sw_line "$out" "sweep: kept worktree $WT_UTF — liveness unverifiable (the path holds a byte lsof escapes" && ok "(SW6) dry run: a non-ASCII path ⇒ kept, liveness unverifiable" || no "(SW6) utf dry: $(printf '%s\n' "$out" | grep -F "proj-caf")"
out="$(sw_run --apply)"; rc=$?
sw_shape "(SW6) --apply" "$out" "$rc"
sw_line "$out" "sweep: kept worktree $WT_ENV — unsalvaged ignored content: .env" && [ "$(cat "$WT_ENV/.env" 2>/dev/null)" = "SECRET=1" ] && sw_has wenv \
  && ok "(SW6) --apply: the .env worktree is kept, its secret intact, its branch held" || no "(SW6) env apply: $(printf '%s\n' "$out" | grep -F "$WT_ENV")"
sw_line "$out" "sweep: removed worktree $WT_NM" && [ ! -d "$WT_NM" ] && ok "(SW6) --apply: the node_modules-only worktree is removed (regenerable)" || no "(SW6) nm apply: $(printf '%s\n' "$out" | grep -F "$WT_NM")"
sw_line "$out" "sweep: kept worktree $WT_NEST — unsalvaged ignored content: src/build/" && [ "$(cat "$WT_NEST/src/build/notes.md" 2>/dev/null)" = hand-written ] && sw_has wnest \
  && ok "(SW6) --apply: the src/build/ worktree is kept, notes.md intact, its branch held" || no "(SW6) nest apply: $(printf '%s\n' "$out" | grep -F "$WT_NEST")"
sw_line "$out" "sweep: kept worktree $WT_UTF — liveness unverifiable (the path holds a byte lsof escapes" && [ -d "$WT_UTF" ] && sw_has wutf \
  && ok "(SW6) --apply: the non-ASCII worktree is kept and remains" || no "(SW6) utf apply: $(printf '%s\n' "$out" | grep -F "proj-caf")"
# Real lsof with LANG/LC_ALL/LC_CTYPE unset (the C locale escapes the path's bytes): a live
# process's cwd in a non-ASCII worktree keeps it, whatever the host's own locale is.
if command -v lsof >/dev/null 2>&1; then
  sw_repo 9; WT_RU="$SWFX/proj-ré"; sw_wt "$WT_RU" wru; sw_merged wru 90
  ( cd "$WT_RU" && exec sleep 120 ) & sw_pid=$!
  if wait_for_cmd 10 sh -c "env -u LANG -u LC_ALL -u LC_CTYPE lsof -a -p $sw_pid -d cwd -F n 2>/dev/null | grep '^n/' >/dev/null"; then
    out="$(cd "$SWP" && env -u LANG -u LC_ALL -u LC_CTYPE SWGH="$SWGH" LOOMWRIGHT_GH_BIN="$SWBIN/gh" LOOMWRIGHT_LSOF_BIN=lsof bash "$T" sweep --apply)"
    sw_line "$out" "sweep: kept worktree $WT_RU — liveness unverifiable (the path holds a byte lsof escapes" && [ -d "$WT_RU" ] && kill -0 "$sw_pid" 2>/dev/null \
      && ok "(SW6) real lsof, no LANG/LC_ALL/LC_CTYPE: a live process in a non-ASCII worktree keeps it (the dir remains)" || no "(SW6) real lsof utf: $(printf '%s\n' "$out" | grep -F "proj-r")"
  else
    echo "  note: this lsof cannot see a child's cwd — real-lsof non-ASCII leg skipped (the stubbed leg above covers it)"
  fi
  kill "$sw_pid" 2>/dev/null; wait "$sw_pid" 2>/dev/null
fi

# ---- a git read/write that fails ⇒ kept (the fail-closed arms) ----------------
# A git on PATH that fails ONE subcommand, chosen by SW_GIT_FAIL (everything else is the
# real git): `lsfiles` (default) — `ls-files … --ignored`, so worktree-salvage.sh
# --check-ignored prints `ignored-check: failed — …`, neither `ok` nor `unsalvaged` ⇒ the
# `*)` arm keeps it; `status` — `status --porcelain` ⇒ "(git status failed)" reads dirty;
# `remove` — `worktree remove` ⇒ "git worktree remove refused".
SW_REAL_GIT="$(command -v git)"; export SW_REAL_GIT
SWGITBIN="$TOP/swgitbin"; mkdir -p "$SWGITBIN"
cat > "$SWGITBIN/git" <<'STUB'
#!/usr/bin/env bash
case "${SW_GIT_FAIL:-lsfiles}: $* " in
  lsfiles:*" ls-files "*" --ignored "*|status:*" status --porcelain"*|remove:*" worktree remove "*)
    echo "stub: git $1 refused" >&2; exit 128 ;;
esac
exec "$SW_REAL_GIT" "$@"
STUB
chmod +x "$SWGITBIN/git"
sw_uv_fixture() { sw_repo "$1"; WT_UV="$SWFX/proj-uv"; sw_wt "$WT_UV" wuv; sw_merged wuv 91; }
SW_UV_WHY="gitignored content unverifiable: ignored-check: failed — cannot list the gitignored entries of"
sw_uv_fixture 12
out="$(PATH="$SWGITBIN:$PATH" sw_run)"; rc=$?
sw_shape "(SW7) dry run, coverage listing failing" "$out" "$rc"
sw_line "$out" "sweep: kept worktree $WT_UV — $SW_UV_WHY $WT_UV" && sw_line "$out" "sweep: kept branch wuv — checked out in worktree $WT_UV" \
  && ok "(SW7) dry run: the coverage check cannot list ⇒ kept worktree — gitignored content unverifiable (and its branch held)" || no "(SW7) dry: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
out="$(PATH="$SWGITBIN:$PATH" sw_run --apply)"; rc=$?
sw_shape "(SW7) --apply, coverage listing failing" "$out" "$rc"
sw_line "$out" "sweep: kept worktree $WT_UV — $SW_UV_WHY $WT_UV" && [ -d "$WT_UV" ] && sw_has wuv && [ ! -e "$SWP/.supervisor/salvage" ] \
  && ok "(SW7) --apply: kept, the worktree and its branch remain, nothing salvaged" || no "(SW7) apply: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
out="$(sw_run)"
sw_line "$out" "sweep: would-remove worktree $WT_UV — branch wuv: PR #91" && ok "(SW7) control: the same worktree with a working git reads would-remove (the stub alone keeps it)" || no "(SW7) control: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
out="$(SW_GIT_FAIL=status PATH="$SWGITBIN:$PATH" sw_run)"
sw_line "$out" "sweep: kept worktree $WT_UV — dirty (uncommitted changes on wuv)" \
  && ok "(SW7) dry run: git status failing ⇒ kept as dirty (an unreadable tree is never read as clean)" || no "(SW7) status: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
sw_uv_remove() { # <script> — --apply with `git worktree remove` failing
  sw_uv_fixture "$1"; out="$(SW_GIT_FAIL=remove PATH="$SWGITBIN:$PATH" SW_T="${2:-$T}" sw_run --apply)"
}
sw_uv_remove 14
grep -qxF "sweep: kept worktree $WT_UV — git worktree remove refused" <<<"$out" && [ -d "$WT_UV" ] && sw_has wuv \
  && ok "(SW7) --apply: git worktree remove refused ⇒ kept, named, the worktree and its branch remain" || no "(SW7) remove: $(printf '%s\n' "$out" | grep -F "$WT_UV")"

# ---- one gh read per examined branch: a removable worktree + its branch ------
# The worktree phase and the branch phase both judge wpair with the squash-safe rule; the
# per-run memo answers the second judgment, so the pair costs exactly ONE `pr list` read.
sw_pair_fixture() { sw_repo "$1"; WT_PAIR="$SWFX/proj-pair"; sw_wt "$WT_PAIR" wpair; sw_merged wpair 95; }
sw_pair_reads() { grep -c -- "--head wpair " "$SWGH/argv.log"; }
sw_pair_fixture 17
out="$(sw_run)"
sw_line "$out" "sweep: would-remove worktree $WT_PAIR — branch wpair: PR #95" && sw_line "$out" "sweep: would-remove branch wpair — PR #95" \
  && [ "$(sw_pair_reads)" = 1 ] && ok "(SW8) dry run: a removable worktree + its branch (both would-remove) cost exactly ONE gh pr list read" \
  || no "(SW8) dry run: $(sw_pair_reads) gh reads for wpair; $(printf '%s\n' "$out" | grep wpair | tr '\n' '|')"
: > "$SWGH/argv.log"
out="$(sw_run --apply)"
sw_line "$out" "sweep: removed worktree $WT_PAIR" && sw_line "$out" "sweep: removed branch wpair — PR #95" && [ ! -d "$WT_PAIR" ] && ! sw_has wpair \
  && [ "$(sw_pair_reads)" = 1 ] && ok "(SW8) --apply: the pair is removed (worktree, then branch) on ONE gh pr list read" \
  || no "(SW8) --apply: $(sw_pair_reads) gh reads for wpair; $(printf '%s\n' "$out" | grep wpair | tr '\n' '|')"

# ---- closeout step 3a: the same --ignored gate (AC4's closeout half) ---------
closeout_fixture 240
mkdir -p "$FX/wt-pr/.supervisor/logs"; printf '{"event":"x"}\n' > "$FX/wt-pr/.supervisor/logs/x.jsonl"
cp "$FX/wt-pr/.supervisor/logs/x.jsonl" "$FX/exp-x.jsonl"; cp "$FX/wt-pr/.supervisor/postmortem/results.jsonl" "$FX/exp-pm.jsonl"
out="$(run_closeout)"
co_salv="$(ls -d "$P/.supervisor/salvage/wt-pr-"* 2>/dev/null | head -n1)"
[ ! -d "$FX/wt-pr" ] && [ -n "$co_salv" ] && cmp -s "$FX/exp-x.jsonl" "$co_salv/ignored/.supervisor/logs/x.jsonl" \
  && cmp -s "$FX/exp-pm.jsonl" "$co_salv/ignored/.supervisor/postmortem/results.jsonl" \
  && ok "(SW4) closeout 3a: 2 gitignored runtime entries salvaged byte-identical, then the worktree removed" || no "(SW4) closeout salvage: salv='$co_salv' out=$(printf '%s' "$out" | grep -F worktree)"
sw_co_unread() { # <fixture-n> <helpers-dir> — closeout with an unreadable gitignored log in wt-pr
  closeout_fixture "$1"
  mkdir -p "$FX/wt-pr/.supervisor/logs"; echo log > "$FX/wt-pr/.supervisor/logs/a.jsonl"; chmod 000 "$FX/wt-pr/.supervisor/logs/a.jsonl"
  out="$(cd "$P" && bash "$2/automate-helpers.sh" closeout "$RF_REL" "$REQ" "$PRURL")"
  chmod 644 "$FX/wt-pr/.supervisor/logs/a.jsonl" 2>/dev/null
}
if [ "$SW_ROOT_UID" = 0 ]; then
  sw_co_unread 241 "$SPYD"
  sw_line "$out" "closeout: skipped — kept worktree $FX/wt-pr (gitignored salvage not verified: ignored: failed .supervisor/logs — copy failed)" && [ -d "$FX/wt-pr" ] \
    && ok "(SW4) closeout 3a: a forced copy failure keeps the worktree in the 'skipped — kept worktree …' form, naming the entry" || no "(SW4) closeout unread: $(printf '%s' "$out" | grep -F worktree)"
  grep -q "^leftover	.*	worktree	" < <(printf '%s\n' "$out" | bash "$H" closeout-classify --run "$RUN_ID" --item "$REQ" --pr "$PRURL") \
    && ok "(SW4) closeout-classify still reads that kept line as a leftover" || no "(SW4) closeout-classify: $(printf '%s\n' "$out" | bash "$H" closeout-classify --run "$RUN_ID" --item "$REQ" --pr "$PRURL" | tr '\t\n' ' |')"
fi

# ---- static: nothing runs --apply unattended; no --force / rm -rf in sweep_run --
sw_body="$(awk '/^sweep_run\(\) \{/{s=1} s{print} s&&/^}/{exit}' "$TB")"
[ -n "$sw_body" ] && ! grep -qE 'worktree remove[^"]*--force|rm -rf' < <(grep -v '^[[:space:]]*#' <<<"$sw_body") \
  && ok "(SW5) sweep_run never runs git worktree remove --force or rm -rf" || no "(SW5) sweep_run body has --force / rm -rf (or was not found)"
sw_calls="$(grep -n 'sweep_run --' "$TB" | grep -v '^[0-9]*:[[:space:]]*#')"
[ -n "$sw_calls" ] && ! grep -q -- '--apply' <<<"$sw_calls" \
  && ok "(SW5) every in-script sweep_run call is a dry run (no --apply): $(printf '%s\n' "$sw_calls" | wc -l | tr -d ' ') call(s)" || no "(SW5) sweep_run calls: $sw_calls"

# ---- pin mutations (scratch copies; each must turn its leg red) ---------------
sw_mutant() { # <name> <sed program> → SW_MD=$TOP/swm-<name> (every script copied, automate-trail.sh mutated)
  SW_MD="$TOP/swm-$1"; mkdir -p "$SW_MD"; cp "$HERE"/*.sh "$HERE"/*.py "$SW_MD/"; cp -R "$HERE/automate-helpers.d" "$SW_MD/"; cp -R "$HERE/automate-trail.d" "$SW_MD/"; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$SW_MD/"
  sed "$2" "$TB" > "$SW_MD/automate-trail.sh"
  if cmp -s "$TB" "$SW_MD/automate-trail.sh" || ! bash -n "$SW_MD/automate-trail.sh" 2>/dev/null; then no "(SWM) mutant $1 not built (sed matched nothing or broke the syntax)"; return 1; fi
  return 0
}
if sw_mutant tip '/\[ "\$tip" != "\$oid" \]/d'; then
  sw_branch_fixture 5
  out="$(SW_T="$SW_MD/automate-trail.sh" sw_run)"
  sw_line "$out" "sweep: would-remove branch moved — " && ok "(SWM) control: without the tip == headRefOid comparison the moved-tip leg is red (moved reads would-remove)" || no "(SWM) tip mutant did not discriminate: $(printf '%s\n' "$out" | grep ' moved ')"
fi
if sw_mutant app '/"\$SW_PRI\/\$SW_APP_WT\/"\*) kind=app ;;/d'; then
  sw_wt_fixture 6
  out="$(SW_T="$SW_MD/automate-trail.sh" sw_run --apply)"
  [ ! -d "$WT_APP" ] && ok "(SWM) control: without the app worktree-root exclusion --apply removes the app worktree (the app leg is red)" || no "(SWM) app mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "$WT_APP")"
  sw_unread_fix
fi
if [ "$SW_ROOT_UID" = 0 ] && sw_mutant verdict 's/case "\$sw_verdict" in "ignored: ok "\*) ;;/case "$sw_verdict" in *) ;;/'; then
  sw_wt_fixture 7
  out="$(SW_T="$SW_MD/automate-trail.sh" sw_run --apply)"
  [ ! -d "$WT_UNREAD" ] && ok "(SWM) control: a sweep that ignores the salvage verdict removes the copy-failure worktree (that leg is red)" || no "(SWM) verdict mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "$WT_UNREAD")"
  sw_unread_fix
fi
if sw_mutant coverage 's/"ignored-check: ok") ;;/*) ;;/'; then
  sw_rev_fixture 10
  out="$(SW_T="$SW_MD/automate-trail.sh" sw_run)"
  sw_line "$out" "sweep: would-remove worktree $WT_ENV" && ok "(SWM) control: a sweep that ignores the coverage check reports the .env worktree would-remove (that leg is red)" || no "(SWM) coverage mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "$WT_ENV")"
fi
if sw_mutant unverif 's/\*) v="gitignored content unverifiable: \${ic:-no verdict}" ;;/*) ;;/'; then
  sw_uv_fixture 13
  out="$(PATH="$SWGITBIN:$PATH" SW_T="$SW_MD/automate-trail.sh" sw_run)"
  sw_line "$out" "sweep: would-remove worktree $WT_UV" && ok "(SWM) control: without the fail-closed arm an unlistable worktree reads would-remove (the SW7 leg is red)" || no "(SWM) unverif mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
fi
if sw_mutant gitstatus '1,/dirty="(git status failed)"/s/|| dirty="(git status failed)"/|| dirty=""/'; then
  sw_uv_fixture 15
  out="$(SW_GIT_FAIL=status PATH="$SWGITBIN:$PATH" SW_T="$SW_MD/automate-trail.sh" sw_run)"
  sw_line "$out" "sweep: would-remove worktree $WT_UV" && ok "(SWM) control: a failed git status read as clean ⇒ would-remove (the SW7 status leg is red)" || no "(SWM) gitstatus mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
fi
if sw_mutant rmrefused 's/if \[ -z "\$v" \] && git -C "\$SW_PRI" worktree remove "\$p" >\/dev\/null 2>&1; then/if [ -z "$v" ] \&\& { git -C "$SW_PRI" worktree remove "$p" >\/dev\/null 2>\&1 || :; }; then/'; then
  sw_uv_remove 16 "$SW_MD/automate-trail.sh"
  sw_line "$out" "sweep: removed worktree $WT_UV" && [ -d "$WT_UV" ] && ok "(SWM) control: a refused remove reported as removed (the SW7 remove leg is red)" || no "(SWM) rmrefused mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "$WT_UV")"
fi
if sw_mutant bytes 's/|| return 3$/|| :/'; then
  sw_rev_fixture 11
  out="$(SW_T="$SW_MD/automate-trail.sh" sw_run --apply)"
  [ ! -d "$WT_UTF" ] && ok "(SWM) control: without the escaped-byte check --apply removes the non-ASCII worktree under its (escaped) live cwd (that leg is red)" || no "(SWM) bytes mutant did not discriminate: $(printf '%s\n' "$out" | grep -F "proj-caf")"
fi
if sw_mutant prcache '/SW_PR_CACHE="\$SW_PR_CACHE\$b/d'; then
  sw_pair_fixture 18
  out="$(SW_T="$SW_MD/automate-trail.sh" sw_run)"
  [ "$(sw_pair_reads)" = 2 ] && ok "(SWM) control: without the per-run gh memo the removable pair costs 2 pr list reads (the SW8 leg is red)" || no "(SWM) prcache mutant did not discriminate: $(sw_pair_reads) reads"
  sw_line "$out" "sweep: would-remove worktree $WT_PAIR" && sw_line "$out" "sweep: would-remove branch wpair" \
    && ok "(SWM) control: the memo changes no verdict (the uncached sweep reads the same would-remove pair)" || no "(SWM) prcache verdicts: $(printf '%s\n' "$out" | grep wpair | tr '\n' '|')"
fi
if [ "$SW_ROOT_UID" = 0 ] && sw_mutant coverdict 's/case "\$co_verdict" in "ignored: ok "\*) co_ign=ok ;; esac/co_ign=ok/'; then
  sw_co_unread 242 "$SW_MD"
  [ ! -d "$FX/wt-pr" ] && ok "(SWM) control: a closeout 3a that ignores the salvage verdict removes the copy-failure worktree (that leg is red)" || no "(SWM) closeout verdict mutant did not discriminate: $(printf '%s' "$out" | grep -F worktree)"
fi
