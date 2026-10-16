# lane-park [--root <dir>] — READ-ONLY: the READY park a run in <root> writes. Exactly one line, exit 0:
# `awaiting_merge` when <root>/.supervisor/lane.json is absent (not a lane — the sequential park) or
# carries `"single_lane": true`; `ready_for_release` when lane.json is present without it, or is
# unreadable / not a JSON object (fail toward the park that arms no watcher and waits for the
# coordinator). <root> defaults to the current checkout's top level (lane-info's default).
lanes_park() {
  local root=""
  if [ "${1:-}" = "--root" ]; then root="${2:-}"; [ -n "$root" ] || die "lane-park: --root needs a directory"; fi
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  local j="$root/.supervisor/lane.json"
  if [ ! -e "$j" ]; then echo awaiting_merge; return 0; fi
  if jq -e 'type == "object" and .single_lane == true' "$j" >/dev/null 2>&1; then echo awaiting_merge
  else echo ready_for_release; fi
  return 0
}

# _lanes_pr_hash <pr_url> — the review-dispatch marker name. The SAME derivation as dispatch-pr-review.sh's
# PR_HASH (shasum → sha1sum → cksum → sanitized URL; drain-rounds.sh mirrors it too), pinned against the
# dispatcher's own block by test-automate-lanes.sh, so the marker it names is the dispatcher's.
_lanes_pr_hash() {
  local u="$1" h=""
  if command -v shasum >/dev/null 2>&1; then h="$(printf '%s' "$u" | shasum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v sha1sum >/dev/null 2>&1; then h="$(printf '%s' "$u" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)"
  elif command -v cksum >/dev/null 2>&1; then h="$(printf '%s' "$u" | cksum 2>/dev/null | cut -d' ' -f1 || true)"; fi
  [ -n "$h" ] || h="$(printf '%s' "$u" | tr -c 'A-Za-z0-9' '-')"
  printf '%s' "$h"
}

# lane-drain-check <lane_dir> — READ-ONLY drain guard (single-ownership, CLAUDE.md "/automate
# single-drain ownership"), run by the coordinator at the lane's park. One line, exit 0:
#   `drain-guard: violation — <reason>[; <reason>…]` when (a) <lane>/.supervisor/review-dispatch/ holds the
#     marker named by _lanes_pr_hash of the lane `## Current` `pr:` URL (a detached default dispatch
#     fired), (b) after the LAST `picked` line of the lane run file's `## Progress` there are 0 or ≥ 2
#     plain owned-drain starts, or ≥ 2 fix-now re-drain starts, or (c)
#     <lane>/.supervisor/automate/<run_id>.config-backup.json exists (the auto_review toggle was never
#     restored). A line is matched after one OPTIONAL timestamp token — the same `^([^ ]+ )?` convention
#     as `picked`, _lanes_vg_has and progress-append's `current_not_set` guard: `owned drain started (fix-now`
#     is a fix-now re-drain start (the pinned `… (fix-now re-drain) — …`); any other `owned drain started`
#     followed by a space, `:` or the line end is a plain start (pinned `<ts> owned drain started — <drain
#     invocation> @ <head sha>`, per-item-loop.md §6 step 3; legacy `owned drain started: …` is tolerated);
#   `drain-guard: ok — <n> owned drain(s), no dispatch marker, no config backup` otherwise;
#   `drain-guard: unknown — <reason>` when the lane, its run file, its PR or its `picked` line cannot be
#     read (observation fails SAFE — never `ok` on what it could not read).
lanes_drain_check() {
  local dir="${1:-}" G="drain-guard:" rf pr after plain fix why=""
  _lane_ctx "$dir" || { echo "$G unknown — not a lane: ${dir:-<none>}"; return 0; }
  rf="$LN_DIR/.supervisor/automate/$LN_RUN.md"
  [ -f "$rf" ] && [ -r "$rf" ] || { echo "$G unknown — lane run file unreadable ($LN_RUN.md)"; return 0; }
  grep -q '^## Progress' "$rf" 2>/dev/null || { echo "$G unknown — lane run file has no ## Progress ($LN_RUN.md)"; return 0; }
  pr="$(_lanes_dash "$(_lanes_runfile_fields "$rf" | cut -f3)")"
  case "$pr" in ''|null) echo "$G unknown — no PR in the lane ## Current ($LN_RUN.md)"; return 0 ;; esac
  after="$(awk '
    /^## / { inp = ($0 ~ /^## Progress/); next }
    !inp { next }
    { n++; line[n] = $0; l = $0; sub(/^- /, "", l); if (l ~ /^([^ ]+ )?picked /) last = n }
    END { if (!last) exit 1; for (i = last + 1; i <= n; i++) print line[i] }' "$rf" 2>/dev/null)" \
    || { echo "$G unknown — no picked line in the lane ## Progress ($LN_RUN.md)"; return 0; }
  # One pass, one classification per line: the unstripped rest first, then with one timestamp token
  # stripped (optional timestamp — an untimestamped line is never mis-read by stripping its first word).
  read -r plain fix <<<"$(printf '%s\n' "$after" | awk '
    function kind(s,  r) {
      if (index(s, "owned drain started") != 1) return ""
      r = substr(s, length("owned drain started") + 1)
      if (index(r, " (fix-now") == 1) return "fix"
      if (r == "" || substr(r, 1, 1) == " " || substr(r, 1, 1) == ":") return "plain"
      return "" }
    { l = $0; if (sub(/^- /, "", l) == 0) next
      k = kind(l); if (k == "") { sub(/^[^ ]+ /, "", l); k = kind(l) }
      if (k == "plain") p++; else if (k == "fix") f++ }
    END { print p + 0, f + 0 }')"
  [ -e "$LN_DIR/.supervisor/review-dispatch/$(_lanes_pr_hash "$pr")" ] \
    && why="${why:+$why; }review-dispatch marker for $pr (a detached default drain was dispatched)"
  [ "$plain" = 1 ] || why="${why:+$why; }$plain owned drain(s) after the last picked line (exactly 1 expected)"
  [ "$fix" -lt 2 ] || why="${why:+$why; }$fix fix-now re-drains after the last picked line (at most 1)"
  [ -e "$LN_DIR/.supervisor/automate/$LN_RUN.config-backup.json" ] \
    && why="${why:+$why; }config backup $LN_RUN.config-backup.json present (auto_review never restored)"
  if [ -n "$why" ]; then echo "$G violation — $why"
  else echo "$G ok — $((plain + fix)) owned drain(s), no dispatch marker, no config backup"; fi
  return 0
}

# ---- leak check (Validation 5) ----------------------------------------------------------------------
# _lanes_leak_lanes_dir <primary> <parent> — the `## lanes-dir` section: one line per entry of
# <primary>-lanes/, except that THIS run's own directory is listed by its contents minus the run's
# kept artifacts, matched by EXACT name (never a glob): `salvage` (lane-create / lane-remove salvage)
# and, for every lane in this run's table, `L<n>.stream.log`, `L<n>.stdin.json`, `L<n>.died`. A lane
# directory still present (`<parent>/L<n>`) or any other file there is listed, so it reads as a leak.
# After a clean wave this run's directory contributes nothing — the same as at wave start, when it
# does not exist yet, and the same once item 21 removes it (parallel-automate/23 F9).
_lanes_leak_lanes_dir() {
  local p="$1" parent="${2:-}" e f keep="salvage" l nl
  nl="$(printf '\nx')"; nl="${nl%x}"
  [ -d "$p-lanes" ] || return 0
  if [ -n "$parent" ] && [ -f "$p/.supervisor/automate/$parent.lanes" ]; then
    for l in $(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ { print $1 }' "$p/.supervisor/automate/$parent.lanes"); do
      keep="$keep$nl$l.stream.log$nl$l.stdin.json$nl$l.died"
    done
  fi
  ls -1 "$p-lanes" 2>/dev/null | while IFS= read -r e; do
    if [ -n "$parent" ] && [ "$e" = "$parent" ] && [ -d "$p-lanes/$e" ]; then
      ls -1 "$p-lanes/$e" 2>/dev/null | while IFS= read -r f; do
        grep -qxF -- "$f" <<<"$keep" || printf '%s/%s\n' "$e" "$f"
      done
    else
      printf '%s\n' "$e"
    fi
  done
}

# _lanes_leak_watchers <primary> <parent> — the `## merge-watch v2` section body: one `<pid> <pr_url>`
# line per LIVE merge watcher, sorted, read from the `*.merge-watch` markers through _lanes_live_watchers
# (the marker's pid still runs automate-merge-watch for that marker's PR) — for the primary's
# `.supervisor/automate/` and for every lane path in this run's lane table (a removed lane's directory
# has no markers left). Never a process-table pattern match: `pgrep -lf automate-merge-watch` (v1) also
# matched any process whose argv merely NAMED the script — a `grep … scripts/automate-merge-watch.sh`
# in the coordinator read as `leaks: found — merge-watch` with no watcher running (wave W3, 2026-10-11).
# Honest limit: a watcher with no marker (or whose marker was deleted) is not listed; every watcher this
# plugin starts writes one (automate-merge-watch.sh), and lane-remove reads the same markers.
_lanes_leak_watchers() {
  local p="$1" parent="${2:-}" tbl l
  {
    _lanes_live_watchers "$p"
    tbl="$p/.supervisor/automate/$parent.lanes"
    if [ -n "$parent" ] && [ -f "$tbl" ]; then
      awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ && $2 != "" && $2 != "-" { print $2 }' "$tbl" | while IFS= read -r l; do
        [ -d "$l" ] && _lanes_live_watchers "$l"
      done
    fi
  } | tr '\t' ' ' | env LC_ALL=C sort -u
  return 0
}

# _lanes_path_tied <path> <run_root> <lane_dirs> — 0 when <path> is a lane directory of this run: under
# <run_root>/ (`<primary>-lanes/<parent>`, '' for none) or equal to / under one of <lane_dirs> (newline
# list, the lane table's path column). <path> may also be a wrapper's argv tail (`<lane_dir> <log> …`):
# it is matched from its start, so a lane path containing spaces is never cut at the first one.
_lanes_path_tied() {
  local x="$1" root="$2" d
  [ -n "$x" ] || return 1
  if [ -n "$root" ]; then case "$x" in "$root"/*) return 0 ;; esac; fi
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$x" in "$d"|"$d"/*|"$d "*) return 0 ;; esac
  done <<<"$3"
  return 1
}

# _lanes_leak_claude <primary> <parent> — the `## claude-p v2` section body: one `<pid> <command>` line
# per process of THIS run, sorted, from ONE `ps` read: a `_lane-run <lane_dir>` wrapper (an `sh`/`bash`
# running this script) whose lane_dir _lanes_path_tied accepts, every headless-session child of such a
# wrapper (by parent pid), and any other headless session whose working directory is such a lane
# directory (a lane process whose wrapper is gone, or a drain a lane detached). Never a machine-wide
# match: v1 (a `pgrep -lf` of the headless command) listed every one on the machine, so another repo's healthy wave read as
# `leaks: found — claude-p` (closing wave 1 of automate-2026-10-15-163325, 2026-10-16). The argv is no
# tie: `--plugin-dir` is the same plugin root for every coordinator on the machine, and the prompt goes
# in on stdin. An unreadable process table — or a candidate to attribute with no working-directory
# reader (lsof, /proc) — prints the one line `unknown — <why>`, which lanes_leaks reports as unknown,
# never as found. Honest limit: a headless session of this run whose wrapper is gone and whose working
# directory is outside every lane directory is not listed.
_lanes_leak_claude() {
  local p="$1" parent="${2:-}" root="" dirs="" tbl ps_out pid ppid cmd w1 r w2 rest wr=" " cand="" out="" pids cw x
  local lsof="${LOOMWRIGHT_LANES_LSOF:-lsof}" proc="${LOOMWRIGHT_LANES_PROC:-/proc}"
  tbl="$p/.supervisor/automate/$parent.lanes"
  if [ -n "$parent" ]; then
    root="$p-lanes/$parent"
    [ -f "$tbl" ] && dirs="$(awk -F'\t' '$1 ~ /^L[0-9][0-9]?$/ && $2 != "" && $2 != "-" { print $2 }' "$tbl" 2>/dev/null)"
  fi
  ps_out="$("${LOOMWRIGHT_LANES_PS:-ps}" -ax -ww -o pid= -o ppid= -o command= 2>/dev/null)"
  [ -n "$ps_out" ] || { echo "unknown — the process table is unreadable (ps)"; return 0; }
  [ -n "$root$dirs" ] || return 0
  while read -r pid ppid cmd; do   # this run's wrappers
    w1="${cmd%% *}"; r="${cmd#* }"; w2="${r%% *}"; rest="${r#* }"
    case "$w1" in sh|bash|*/sh|*/bash) ;; *) continue ;; esac
    case "$w2" in automate-lanes.sh|*/automate-lanes.sh) ;; *) continue ;; esac
    case "$rest" in "_lane-run "*) rest="${rest#_lane-run }" ;; *) continue ;; esac
    _lanes_path_tied "$rest" "$root" "$dirs" || continue
    wr="$wr$pid "; out="$out$pid $cmd"$'\n'
  done <<<"$ps_out"
  while read -r pid ppid cmd; do   # their headless children; every other headless session is a cwd candidate
    case "$cmd" in *"automate-lanes.sh _lane-run "*) continue ;; *"claude -p"*) ;; *) continue ;; esac
    case "$wr" in *" $ppid "*) out="$out$pid $cmd"$'\n'; continue ;; esac
    cand="$cand$pid"$'\t'"$cmd"$'\n'
  done <<<"$ps_out"
  if [ -n "$cand" ]; then
    pids="$(printf '%s' "$cand" | cut -f1 | paste -sd, -)"
    if command -v "$lsof" >/dev/null 2>&1; then
      cw="$("$lsof" -a -d cwd -Fn -p "$pids" 2>/dev/null | awk '/^p/ { q = substr($0, 2) } /^n/ { print q "\t" substr($0, 2) }')"
    elif [ -d "$proc/self" ]; then
      cw="$(for x in ${pids//,/ }; do printf '%s\t%s\n' "$x" "$(readlink "$proc/$x/cwd" 2>/dev/null)"; done)"
    else
      echo "unknown — no reader for a process's working directory (lsof, /proc)"; return 0
    fi
    while IFS=$'\t' read -r pid cmd; do
      [ -n "$pid" ] || continue
      x="$(printf '%s\n' "$cw" | awk -F'\t' -v q="$pid" '$1 == q { print $2; exit }')"
      _lanes_path_tied "$x" "$root" "$dirs" && out="$out$pid $cmd"$'\n'
    done <<<"$cand"
  fi
  printf '%s' "$out" | env LC_ALL=C sort -u
  return 0
}

_lanes_leak_sections() { # <primary> <parent>
  local p="$1"
  echo "## worktrees"; git -C "$p" worktree list --porcelain 2>/dev/null | awk '/^worktree /'
  echo "## lanes-dir"; _lanes_leak_lanes_dir "$p" "${2:-}"
  # The format tag IS the header: lanes_leaks compares a tagged section only against a snapshot section
  # written in the same format (a v1 `## claude-p` / `## merge-watch` section is read as not compared).
  echo "## claude-p v2"
  _lanes_leak_claude "$p" "${2:-}"   # >>> claude-p body
  echo "## merge-watch v2"
  _lanes_leak_watchers "$p" "${2:-}"   # >>> merge-watch body
  echo "## config-checksum"
  if [ -f "$p/.supervisor/config.json" ]; then cksum < "$p/.supervisor/config.json" | awk '{ print $1, $2 }'; else echo absent; fi
  echo "## git-status"; git -C "$p" status --porcelain 2>/dev/null | awk '!/\.leaks-snapshot$/'
  return 0
}

# lanes_leaks <primary> <parent> [snapshot 0|1] — `--snapshot` records the wave-start state; otherwise
# compares now against it. First line: `leaks: none` | `leaks: found — <sections>` | `leaks: unknown — …`.
lanes_leaks() {
  local p="$1" parent="$2" snap="${3:-0}" sf tmp sec found="" body="" d hd nc="" v1 unk=""
  sf="$p/.supervisor/automate/$parent.leaks-snapshot"
  if [ "$snap" = 1 ]; then
    # The ONE exception to observation's exit 0: a snapshot request that wrote nothing exits 1 naming
    # why, because the end-of-wave check against a missing baseline can never read `none`.
    if { echo "# leaks snapshot $(now_utc)"; _lanes_leak_sections "$p" "$parent"; } > "$sf.tmp.$$" 2>/dev/null && mv "$sf.tmp.$$" "$sf"; then
      echo "leaks: snapshot written — $sf"
    else rm -f "$sf.tmp.$$"; echo "leaks: snapshot not written (unwritable) — $sf"; return 1; fi
    return 0
  fi
  if [ ! -f "$sf" ]; then
    echo "leaks: unknown — no snapshot (take one at wave start: lane-status --leaks --snapshot)"
    _lanes_leak_sections "$p" "$parent" | sed 's/^/  /'; return 0
  fi
  tmp="$(mktemp -d 2>/dev/null)" || { echo "leaks: unknown — no temp dir"; return 0; }
  _lanes_leak_sections "$p" "$parent" > "$tmp/now"
  for sec in worktrees lanes-dir claude-p merge-watch config-checksum git-status; do
    hd="## $sec"; v1=""
    case "$sec" in
      claude-p) hd="## claude-p v2"; v1="the run-scoped process list (v1 matched every such process on the machine)" ;;
      merge-watch) hd="## merge-watch v2"; v1="the marker-based watcher list (v1)" ;;
    esac
    # A snapshot taken before a tagged section's format (its section is the v1 process-name match, or
    # absent) is NOT compared on that section: two formats never diff into a false `found`.
    if [ -n "$v1" ] && ! grep -qxF -- "$hd" "$sf"; then
      nc="$nc${nc:+; }$sec not compared — pre-v2 snapshot"
      body="$body- $sec: not compared — the wave-start snapshot predates $v1
"
      continue
    fi
    awk -v s="$hd" '/^## / { on = ($0 == s); next } on' "$sf" | env LC_ALL=C sort > "$tmp/a"
    awk -v s="$hd" '/^## / { on = ($0 == s); next } on' "$tmp/now" | env LC_ALL=C sort > "$tmp/b"
    # An unreadable side (`unknown — <why>`, the claude-p body's fail-SAFE line) is unknown, never found.
    # claude-p only: another section's body is data (a lanes-dir entry may be named anything).
    if [ "$sec" = claude-p ] && grep -q '^unknown — ' "$tmp/a" "$tmp/b" 2>/dev/null; then
      unk="$unk${unk:+, }$sec"
      body="$body- $sec: $(cat "$tmp/b" "$tmp/a" | grep -m1 '^unknown — ')
"
      continue
    fi
    if cmp -s "$tmp/a" "$tmp/b"; then body="$body- $sec: same
"
    else
      found="$found${found:+, }$sec"
      d="$(env LC_ALL=C comm -13 "$tmp/a" "$tmp/b" | sed 's/^/  + /'; env LC_ALL=C comm -23 "$tmp/a" "$tmp/b" | sed 's/^/  - /')"
      body="$body- $sec: changed
$d
"
    fi
  done
  rm -rf "$tmp"
  if [ -n "$found" ]; then [ -n "$unk" ] && nc="$nc${nc:+; }$unk unknown"; echo "leaks: found — $found${nc:+ ($nc)}"
  elif [ -n "$unk" ]; then echo "leaks: unknown — $unk unreadable (vs snapshot $sf${nc:+; $nc})"
  else echo "leaks: none (vs snapshot $sf${nc:+; $nc})"; fi
  printf '%s' "$body"
  return 0
}

