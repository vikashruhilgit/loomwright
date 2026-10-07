# --------------------------------------------------------------------------- #
# §3 — run-file atomic write + append-only Progress + queue check-off
# --------------------------------------------------------------------------- #

# _progress_block <file> — the lines under the `## Progress` heading, up to the
# next `## ` heading (the heading itself excluded). Empty when there is none.
_progress_block() {
  awk '/^## Progress/ { p=1; next } p && /^## / { p=0 } p' "$1"
}

# _runfile_refusal <staged> <current> <full|title> — prints WHY <staged> must not
# be renamed over <current> (nothing when it may). SKILL §3 "Crash-safety
# contract" → "Validate before rename" is the spec: `full` (runfile-write) checks
# non-empty + `# Automate Run:` title + `## Status:` + `## Queue`; `title` (the
# in-place mutators, whose input was already checked to be a run file) checks
# non-empty + title only, so a hand-edited run file missing a section still takes
# progress lines. Both modes require the staged `## Progress` block to start with
# <current>'s block line-for-line when <current> is a run file — the APPEND-ONLY
# rule, enforced against a generator that died part-way and dropped the tail.
_runfile_refusal() {
  local staged="$1" cur="$2" mode="$3"
  if [ ! -s "$staged" ]; then echo "empty content"; return 0; fi
  if ! is_run_file "$staged"; then echo "content lacks the '# Automate Run:' title line"; return 0; fi
  if [ "$mode" = "full" ]; then
    grep -qE '^## Status:' "$staged" || { echo "content lacks a '## Status:' line"; return 0; }
    grep -qE '^## Queue' "$staged"   || { echo "content lacks the '## Queue' heading"; return 0; }
  fi
  if [ -f "$cur" ] && is_run_file "$cur"; then
    local old_blk new_blk n
    old_blk="$(mktemp "${staged}.old.XXXXXX")"; new_blk="$(mktemp "${staged}.new.XXXXXX")"
    _progress_block "$cur" > "$old_blk"
    n=$(( $(wc -l < "$old_blk") ))
    # n=0 (no prior Progress) is trivially a prefix — and BSD `head -n 0` is an
    # error, not an empty read. Otherwise two plain file reads, no
    # `producer | head` pipe: under pipefail an early head exit can SIGPIPE the
    # producer and fail a correct comparison.
    if [ "$n" -gt 0 ]; then
      _progress_block "$staged" > "$new_blk"
      if ! head -n "$n" "$new_blk" | cmp -s "$old_blk" -; then
        echo "content does not keep the existing ## Progress block ($n line(s)) as its prefix — Progress is append-only"
      fi
    fi
    rm -f "$old_blk" "$new_blk"
  fi
  return 0
}

# _runfile_install <staged> <out> <full|title> <verb> — validate, then rename.
# On refusal: remove <staged>, leave <out> byte-unchanged, exit 1 via die.
_runfile_install() {
  local staged="$1" out="$2" mode="$3" verb="$4" why
  why="$(_runfile_refusal "$staged" "$out" "$mode")"
  if [ -n "$why" ]; then
    rm -f "$staged"
    die "$verb: refused — $why; $out left unchanged [runfile_write_refused]"
  fi
  mv -f "$staged" "$out"
}

# runfile-write <runfile_path>   (content on stdin)
# Atomic write: stage to a temp file in the same dir, VALIDATE (SKILL §3
# "Validate before rename"), then rename into place. The helper cannot see the
# exit status of whatever generated its stdin (`awk … "$RF" | runfile-write "$RF"`
# with a failing awk delivers EOF and nothing else), so the payload itself is
# the only evidence — an empty or structureless one is refused, never installed.
runfile_write() {
  local out="$1" dir tmp
  dir="$(dirname "$out")"
  mkdir -p "$dir"
  tmp="$(mktemp "${out}.XXXXXX")"
  cat > "$tmp" || { rm -f "$tmp"; die "runfile-write: could not stage stdin; $out left unchanged"; }
  _runfile_install "$tmp" "$out" full runfile-write
}

# progress-append <runfile_path> <line>
# Appends ONE line under "## Progress" WITHOUT rewriting any existing line. We
# rebuild the file via atomic write but the prior Progress lines are copied
# verbatim and the new line is inserted at the END of the Progress block — the
# invariant tested is "no prior Progress line is ever altered or dropped".
progress_append() {
  local out="$1" line="$2"
  [ -f "$out" ] || die "run file not found: $out"
  # A file without the run-file title is not a run file (an emptied one, a
  # sidecar, a wrong path) — appending would fabricate a titleless `## Progress`
  # stub that `remaining` reads as 0 and `resume-glob` never lists (SKILL §3).
  is_run_file "$out" || die "progress-append: refused — $out has no '# Automate Run:' title line (not a run file); left unchanged [runfile_write_refused]"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass the new line via the ENVIRONMENT (not awk -v): awk's -v assignment
  # interprets backslash escapes in the value, which would mangle a path/line
  # containing a literal backslash. ENVIRON[...] is read verbatim.
  AH_NEWLINE="- $line" awk '
    BEGIN { in_prog=0; appended=0; seen_prog=0; newline=ENVIRON["AH_NEWLINE"] }
    /^## Progress/ { print; in_prog=1; seen_prog=1; next }
    /^## / {
      if (in_prog && !appended) { print newline; appended=1; in_prog=0 }
      print; next
    }
    { print }
    # Fallback: if the (title-checked) run file had NO "## Progress" section,
    # create one rather than silently dropping the event (defensive — the
    # template always includes the section). A NON-run file never gets here.
    END {
      if (!appended) {
        if (!seen_prog) print "## Progress"
        print newline
      }
    }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "progress-append: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" title progress-append
  _progress_current_guard "$out" "$line"
}

# _progress_current_guard <runfile> <line> — the D2 `current_not_set` guard (SKILL
# §3 "`## Current` moves only through `current-set`"). Runs AFTER a successful
# append, so the line is always recorded (loud, never lossy). A line that says an
# item is in flight — `[<one token> ]picked …`, `ran /autonomous…`, `owned drain
# started…` — while `## Current`'s item is `null`, empty or absent means the engine
# skipped `current-set`: print `current_not_set: <line>` to stderr and exit 3
# (distinct from the refusal exit 1). A `picked <X>` line while `## Current` names a
# DIFFERENT non-null item whose status is not `done` exits 3 the same way (PICK
# skipped `current-set` on a later item). `parked …` is deliberately NOT guarded: a
# run-level park on a fresh run legitimately has a null item. <X> is the first
# whitespace-delimited token after `picked ` with trailing `;`/`,` stripped; both
# sides are compared after stripping a leading `./`.
_progress_current_guard() {
  local out="$1" line="$2"
  local re_g='^([^ ]+ )?(picked |ran /autonomous|owned drain started)'
  local re_p='^([^ ]+ )?picked ([^ ]+)'
  [[ "$line" =~ $re_g ]] || return 0
  local cl ci cs x
  cl="$(_current_item_line "$out")"
  ci="$(_current_field "$cl" item)"
  if [ -z "$ci" ] || [ "$ci" = "null" ]; then
    echo "current_not_set: $line" >&2; exit 3
  fi
  [[ "$line" =~ $re_p ]] || return 0
  x="${BASH_REMATCH[2]}"
  while :; do case "$x" in *";"|*",") x="${x%?}" ;; *) break ;; esac; done
  [ -n "$x" ] || return 0
  cs="$(_current_field "$cl" status)"
  if [ "${x#./}" != "${ci#./}" ] && [ "$cs" != "done" ]; then
    echo "current_not_set: $line" >&2; exit 3
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# §3 — `## Current` moves only through a helper (current-set / current-rebuild)
# --------------------------------------------------------------------------- #

# The documented enums (docs/RESULT_SCHEMAS.md §AUTOMATE_RUN "`## Current` fields";
# SKILL §3 template). Space-delimited so a `case " $ENUM " in *" $v "*)` test is exact.
CURRENT_STATUS_ENUM=" running awaiting_merge ready_for_release escalated failed rate_limit drain_died done "
CURRENT_PAUSE_ENUM=" awaiting_merge ready_for_release awaiting_go escalated limit_reached resume_ambiguous rate_limit drain_died token_ceiling run_lock_held meta_unreachable trail_pr_open closeout_leftover null "

# _current_item_line <runfile> — the FIRST `- item: ` line inside `## Current`, or nothing.
_current_item_line() {
  awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$1" 2>/dev/null || true
}

# _current_reason_line <runfile> — the FIRST `- pause_reason:` line inside `## Current`, or nothing.
_current_reason_line() {
  awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- pause_reason:/{print; exit}' "$1" 2>/dev/null || true
}

# _current_field <item_line> <key> — the value of `<key>: <value>` in a
# `- item: … | status: … | pr: … | branch: …` line (fields split on " | ", the
# same split closeout's `_co_field` uses). Prints nothing when the key is absent.
_current_field() {
  local rest="${1#- }" key="$2" f
  [ -n "$1" ] || return 0
  while :; do
    case "$rest" in
      *" | "*) f="${rest%% | *}"; rest="${rest#* | }" ;;
      *) f="$rest"; rest="" ;;
    esac
    case "$f" in "$key: "*) printf '%s' "${f#"$key: "}"; return 0 ;; esac
    [ -n "$rest" ] || return 0
  done
}

# _current_build_line <old_line> <item> <status> <has_pr> <pr> <has_branch> <branch>
# Rebuilds the item line field-by-field: item/status (and pr/branch when given)
# replace their values in place, every other field keeps its text and position, a
# missing field is appended in template order. No old line ⇒ the template order.
_current_build_line() {
  local old="$1" item="$2" st="$3" hp="$4" pr="$5" hb="$6" br="$7"
  local rest f out="" si=0 ss=0 sp=0 sb=0
  if [ -n "$old" ]; then
    rest="${old#- }"
    while :; do
      case "$rest" in
        *" | "*) f="${rest%% | *}"; rest="${rest#* | }" ;;
        *) f="$rest"; rest="" ;;
      esac
      case "$f" in
        "item: "*) f="item: $item"; si=1 ;;
        "status: "*) f="status: $st"; ss=1 ;;
        "pr: "*) if [ "$hp" = 1 ]; then f="pr: $pr"; fi; sp=1 ;;
        "branch: "*) if [ "$hb" = 1 ]; then f="branch: $br"; fi; sb=1 ;;
      esac
      out="${out:+$out | }$f"
      [ -n "$rest" ] || break
    done
  fi
  if [ "$si" = 0 ]; then out="item: $item${out:+ | $out}"; fi
  if [ "$ss" = 0 ]; then out="$out | status: $st"; fi
  if [ "$sp" = 0 ] && [ "$hp" = 1 ]; then out="$out | pr: $pr"; fi
  if [ "$sb" = 0 ] && [ "$hb" = 1 ]; then out="$out | branch: $br"; fi
  printf -- '- %s\n' "$out"
}

# current-set <runfile> [--item <path|null> --status <s|null>] [--pr <url|null>]
#             [--branch <b|null>] [--pause-reason <r>]
# SKILL §3 "`## Current` moves only through `current-set`" is the spec. Two legal forms:
#   ITEM form      — --item AND --status (the literal `null` only when BOTH are
#                    `null`: "nothing in flight"); --pr/--branch/--pause-reason optional.
#   RUN-LEVEL form — neither --item nor --status; --pause-reason required; no
#                    --pr/--branch (a run-level park never touches the item line).
# Rewrites ONLY the `## Current` block's first `- item:` line (item form) and/or its
# `- pause_reason:` line (appended to the block when absent), and — item form only —
# REMOVES a `- escalation_cause:` line when the new status is not `escalated` or the
# item changes (per-item park state, automate-followups/31: closeout's `done`, PICK's
# `running` and every non-escalated park clear it); every other line of the file is
# byte-unchanged. pr/branch retention: when --item equals the line's
# current item (compared after a leading `./` strip) an omitted --pr/--branch keeps
# the stored value; when --item CHANGES, an omitted --pr/--branch resets to `null`
# (never carry the previous item's PR into a new one). The item is stored exactly
# as passed. Refusals (exit 1, file byte-unchanged): an unknown status/pause_reason,
# a half-null item form, an item form missing --item or --status, a run-level form
# missing --pause-reason (or carrying --pr/--branch), an empty value or one holding
# `|` or a newline, a missing/non-run file, a file with no `## Current` heading.
# Values reach awk through the ENVIRONMENT (never awk -v — SKILL Anti-Patterns); the
# write goes through `_runfile_install … full` (runfile-write's validation).
# Idempotent: values already present ⇒ `current-set: unchanged`, nothing written.
current_set() {
  local out="${1:-}"
  [ "$#" -gt 0 ] && shift
  local CS="current-set: refused —"
  [ -n "$out" ] || die "$CS usage: current-set <runfile> [--item <path|null> --status <s|null>] [--pr <url|null>] [--branch <b|null>] [--pause-reason <r>]"
  local item="" st="" pr="" br="" reason="" hi=0 hs=0 hp=0 hb=0 hr=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --item|--status|--pr|--branch|--pause-reason)
        [ "$#" -ge 2 ] || die "$CS $1 needs a value; $out left unchanged"
        case "$1" in
          --item) item="$2"; hi=1 ;;
          --status) st="$2"; hs=1 ;;
          --pr) pr="$2"; hp=1 ;;
          --branch) br="$2"; hb=1 ;;
          --pause-reason) reason="$2"; hr=1 ;;
        esac
        case "$2" in
          "") die "$CS $1 value is empty; $out left unchanged" ;;
          *"|"*|*"$NL_CHAR"*) die "$CS $1 value contains '|' or a newline; $out left unchanged" ;;
        esac
        shift 2 ;;
      *) die "$CS unknown argument '$1'; $out left unchanged" ;;
    esac
  done
  if [ "$hi" != "$hs" ]; then
    die "$CS the item form needs both --item and --status; $out left unchanged"
  fi
  if [ "$hi" = 0 ]; then
    [ "$hr" = 1 ] || die "$CS the run-level form needs --pause-reason; $out left unchanged"
    if [ "$hp" = 1 ] || [ "$hb" = 1 ]; then die "$CS --pr/--branch need the item form (--item + --status); $out left unchanged"; fi
  else
    if { [ "$item" = null ] && [ "$st" != null ]; } || { [ "$item" != null ] && [ "$st" = null ]; }; then
      die "$CS half-null item form (--item $item --status $st) — 'null' only when both are null; $out left unchanged"
    fi
    if [ "$st" != null ]; then
      case "$CURRENT_STATUS_ENUM" in *" $st "*) ;; *) die "$CS unknown status '$st'; $out left unchanged" ;; esac
    fi
  fi
  if [ "$hr" = 1 ]; then
    case "$CURRENT_PAUSE_ENUM" in *" $reason "*) ;; *) die "$CS unknown pause_reason '$reason'; $out left unchanged" ;; esac
  fi
  [ -f "$out" ] || die "$CS run file not found: $out"
  is_run_file "$out" || die "$CS not a run file (no '# Automate Run:' title): $out; left unchanged [runfile_write_refused]"
  grep -q '^## Current' "$out" || die "$CS no '## Current' heading in $out; left unchanged"

  local old_line new_line="" old_reason new_reason="" change=0 drop_esc=0
  old_line="$(_current_item_line "$out")"
  if [ "$hi" = 1 ]; then
    local old_item; old_item="$(_current_field "$old_line" item)"
    if [ "${old_item#./}" != "${item#./}" ]; then
      if [ "$hp" = 0 ]; then pr=null; hp=1; fi
      if [ "$hb" = 0 ]; then br=null; hb=1; fi
    fi
    new_line="$(_current_build_line "$old_line" "$item" "$st" "$hp" "$pr" "$hb" "$br")"
    [ "$new_line" = "$old_line" ] || change=1
    # automate-followups/31: the `- escalation_cause:` line is per-item park state —
    # dropped by an item-form write that leaves `escalated` or changes the item.
    if { [ "$st" != escalated ] || [ "${old_item#./}" != "${item#./}" ]; } \
       && awk '/^## Current/ && !s { s=1; c=1; next } /^## / { c=0 } c && /^- escalation_cause:/ { f=1 } END { exit !f }' "$out"; then
      drop_esc=1; change=1
    fi
  fi
  if [ "$hr" = 1 ]; then
    old_reason="$(_current_reason_line "$out")"
    new_reason="- pause_reason: $reason"
    [ "$new_reason" = "$old_reason" ] || change=1
  fi
  if [ "$change" = 0 ]; then echo "current-set: unchanged"; return 0; fi

  local have_item=0; [ -n "$old_line" ] && have_item=1
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  CS_ITEM_ON="$hi" CS_NEW_ITEM="$new_line" CS_HAVE_ITEM="$have_item" \
  CS_REASON_ON="$hr" CS_NEW_REASON="$new_reason" CS_DROP_ESC="$drop_esc" awk '
    BEGIN { ion=ENVIRON["CS_ITEM_ON"]; nitem=ENVIRON["CS_NEW_ITEM"]; have=ENVIRON["CS_HAVE_ITEM"]
            ron=ENVIRON["CS_REASON_ON"]; nreason=ENVIRON["CS_NEW_REASON"]; desc=ENVIRON["CS_DROP_ESC"] }
    /^## Current/ && !seen {
      seen=1; c=1; print
      if (ion == 1 && have != 1) { print nitem; idone=1 }
      next
    }
    /^## / {
      if (c && ron == 1 && !rdone) { print nreason; rdone=1 }
      c=0; print; next
    }
    c && ion == 1 && !idone && /^- item: / { print nitem; idone=1; next }
    c && ron == 1 && !rdone && /^- pause_reason:/ { print nreason; rdone=1; next }
    c && desc == 1 && /^- escalation_cause:/ { next }
    { print }
    END { if (c && ron == 1 && !rdone) print nreason }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "current-set: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" full current-set
  echo "current-set: written"
}

# current-escalation <runfile> --cause <c> [--check <c>] [--run-id <id>] [--attempt <n>] [--sha <sha>]
# automate-followups/31: the ONLY writer of `## Current`'s optional line
#   - escalation_cause: <cause> | check: <c|null> | run_id: <id|null> | attempt: <n|null> | sha: <sha|null>
# recorded at an `escalated` park (the cause comes from `escalation-cause` for a
# check-driven escalation, else `findings`/`other`). Placement: replaces an existing
# `- escalation_cause:` line in the block; else inserted right after the block's
# `- pause_reason:` line; else appended at the end of the block (current-set's own
# append rule). `--cause null` removes the line (absent ⇒ unchanged). An omitted
# field is `null`. Refusals (exit 1, file byte-unchanged): an unknown cause, a
# missing --cause, an empty value or one holding `|` or a newline, a non-numeric
# --run-id/--attempt (other than `null`), field flags with `--cause null`, a
# missing/non-run file, no `## Current` heading. Values reach awk through the
# ENVIRONMENT (never awk -v); the write goes through `_runfile_install … full`.
# Idempotent: the identical line already present ⇒ `current-escalation: unchanged`.
# The only OTHER thing that removes the line is an item-form current-set leaving
# `escalated` or changing the item (the line is per-item state, never carried over).
ESCALATION_CAUSE_ENUM=" check_pending check_red_unrelated check_red findings other null "
current_escalation() {
  local out="${1:-}"
  [ "$#" -gt 0 ] && shift
  local CE="current-escalation: refused —"
  [ -n "$out" ] || die "$CE usage: current-escalation <runfile> --cause <c> [--check <c>] [--run-id <id>] [--attempt <n>] [--sha <sha>]"
  local cause="" chk=null rid=null att=null sha=null hc=0 hf=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cause|--check|--run-id|--attempt|--sha)
        [ "$#" -ge 2 ] || die "$CE $1 needs a value; $out left unchanged"
        case "$2" in
          "") die "$CE $1 value is empty; $out left unchanged" ;;
          *"|"*|*"$NL_CHAR"*) die "$CE $1 value contains '|' or a newline; $out left unchanged" ;;
        esac
        case "$1" in
          --cause) cause="$2"; hc=1 ;;
          --check) chk="$2"; hf=1 ;;
          --run-id) rid="$2"; hf=1 ;;
          --attempt) att="$2"; hf=1 ;;
          --sha) sha="$2"; hf=1 ;;
        esac
        shift 2 ;;
      *) die "$CE unknown argument '$1'; $out left unchanged" ;;
    esac
  done
  [ "$hc" = 1 ] || die "$CE --cause is required; $out left unchanged"
  case "$ESCALATION_CAUSE_ENUM" in *" $cause "*) ;; *) die "$CE unknown cause '$cause'; $out left unchanged" ;; esac
  case "$rid" in null) ;; *[!0-9]*) die "$CE --run-id '$rid' is not numeric; $out left unchanged" ;; esac
  case "$att" in null) ;; *[!0-9]*) die "$CE --attempt '$att' is not numeric; $out left unchanged" ;; esac
  if [ "$cause" = null ] && [ "$hf" = 1 ]; then die "$CE --cause null takes no field flags; $out left unchanged"; fi
  [ -f "$out" ] || die "$CE run file not found: $out"
  is_run_file "$out" || die "$CE not a run file (no '# Automate Run:' title): $out; left unchanged [runfile_write_refused]"
  grep -q '^## Current' "$out" || die "$CE no '## Current' heading in $out; left unchanged"

  local old_line new_line=""
  old_line="$(awk '/^## Current/ && !s { s=1; c=1; next } /^## / { c=0 } c && /^- escalation_cause:/ { print; exit }' "$out")"
  [ "$cause" = null ] || new_line="- escalation_cause: $cause | check: $chk | run_id: $rid | attempt: $att | sha: $sha"
  if [ "$new_line" = "$old_line" ]; then echo "current-escalation: unchanged"; return 0; fi

  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  CE_NEW="$new_line" awk '
    BEGIN { nl=ENVIRON["CE_NEW"]; have=0 }
    { lines[NR]=$0 }
    END {
      # pass 1: locate the block, an existing line, and the pause_reason line
      for (i=1; i<=NR; i++) {
        if (!seen && lines[i] ~ /^## Current/) { seen=1; c=1; start=i; continue }
        if (c && lines[i] ~ /^## /) { c=0; endb=i; continue }
        if (c && !ex && lines[i] ~ /^- escalation_cause:/) ex=i
        if (c && !pr && lines[i] ~ /^- pause_reason:/) pr=i
      }
      for (i=1; i<=NR; i++) {
        if (ex && i == ex) { if (nl != "") print nl; continue }
        if (!ex && nl != "" && !endb_done && endb && i == endb && !pr) { print nl; endb_done=1 }
        print lines[i]
        if (!ex && nl != "" && pr && i == pr) print nl
      }
      if (!ex && nl != "" && !pr && !endb) print nl
    }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "current-escalation: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" full current-escalation
  echo "current-escalation: written"
}

# current-wave <runfile> --wave <k> [--items <i1,i2,…>] | --wave null
# parallel-automate/05 (Scope 2 "`## Current` names the wave"): the ONLY writer of
# `## Current`'s optional run-level line
#   - wave: <k> | items: <i1>, <i2>, …
# written by a `--parallel N>1` parent run only (a sequential run never calls it, so
# its file never carries the line). `ready_for_release` (a lane's terminal park,
# Scope 5) is the matching `## Current` status/pause_reason enum value above.
# Placement: replaces an existing `- wave:` line in the block; else appended at the
# end of the block. `--wave null` removes it (absent ⇒ unchanged). `--items` omitted
# ⇒ `items: null`. Refusals (exit 1, file byte-unchanged): a missing --wave, a wave
# that is not a positive integer (other than `null`), an empty value or one holding
# `|` or a newline, `--items` with `--wave null`, a missing/non-run file, no
# `## Current` heading. Values reach awk through the ENVIRONMENT; the write goes
# through `_runfile_install … full`. Identical line ⇒ `current-wave: unchanged`.
current_wave() {
  local out="${1:-}"
  [ "$#" -gt 0 ] && shift
  local CW="current-wave: refused —"
  [ -n "$out" ] || die "$CW usage: current-wave <runfile> --wave <k|null> [--items <i1,i2,…>]"
  local wave="" items=null hw=0 hi=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --wave|--items)
        [ "$#" -ge 2 ] || die "$CW $1 needs a value; $out left unchanged"
        case "$2" in
          "") die "$CW $1 value is empty; $out left unchanged" ;;
          *"|"*|*"$NL_CHAR"*) die "$CW $1 value contains '|' or a newline; $out left unchanged" ;;
        esac
        case "$1" in --wave) wave="$2"; hw=1 ;; --items) items="$2"; hi=1 ;; esac
        shift 2 ;;
      *) die "$CW unknown argument '$1'; $out left unchanged" ;;
    esac
  done
  [ "$hw" = 1 ] || die "$CW --wave is required; $out left unchanged"
  case "$wave" in null) ;; ""|0|*[!0-9]*) die "$CW --wave '$wave' is not a positive integer; $out left unchanged" ;; esac
  if [ "$wave" = null ] && [ "$hi" = 1 ]; then die "$CW --wave null takes no --items; $out left unchanged"; fi
  [ -f "$out" ] || die "$CW run file not found: $out"
  is_run_file "$out" || die "$CW not a run file (no '# Automate Run:' title): $out; left unchanged [runfile_write_refused]"
  grep -q '^## Current' "$out" || die "$CW no '## Current' heading in $out; left unchanged"
  # `a,b` and `a, b` both render as `a, b` (one canonical spelling ⇒ idempotent).
  [ "$items" = null ] || items="$(printf '%s' "$items" | awk -F',' '{ o=""; for (i=1;i<=NF;i++) { v=$i; gsub(/^[ ]+|[ ]+$/, "", v); if (v != "") o = (o == "" ? v : o ", " v) } print o }')"
  [ -n "$items" ] || die "$CW --items holds no item; $out left unchanged"

  local old_line new_line=""
  old_line="$(awk '/^## Current/ && !s { s=1; c=1; next } /^## / { c=0 } c && /^- wave:/ { print; exit }' "$out")"
  [ "$wave" = null ] || new_line="- wave: $wave | items: $items"
  if [ "$new_line" = "$old_line" ]; then echo "current-wave: unchanged"; return 0; fi

  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  CW_NEW="$new_line" awk '
    BEGIN { nl=ENVIRON["CW_NEW"] }
    { lines[NR]=$0 }
    END {
      for (i=1; i<=NR; i++) {
        if (!seen && lines[i] ~ /^## Current/) { seen=1; c=1; continue }
        if (c && lines[i] ~ /^## /) { c=0; endb=i; continue }
        if (c && !ex && lines[i] ~ /^- wave:/) ex=i
      }
      # the append point: after the block'"'"'s last non-blank line (before trailing blanks)
      if (!ex) { last = (endb ? endb - 1 : NR); while (last > 0 && lines[last] ~ /^[ \t]*$/) last--; }
      for (i=1; i<=NR; i++) {
        if (ex && i == ex) { if (nl != "") print nl; continue }
        print lines[i]
        if (!ex && nl != "" && i == last) print nl
      }
    }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "current-wave: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" full current-wave
  echo "current-wave: written"
}

# current-rebuild <runfile> — SKILL §4 RECONCILE repair for a `## Current` an
# engine never set (lane w1-10: one creation write, then Progress-only updates).
# Acts ONLY when `## Progress` has a `picked ` line AND `## Current`'s item is
# null/empty/absent — or names an item with `status: done` that differs (after a
# leading `./` strip) from the LAST `picked` line's item (a PICK after a close-out
# that skipped its `current-set`; the progress-append guard exempts that case).
# Item: from the LAST Progress line matching `^- ([^ ]+ )?picked `
# — the first whitespace-delimited token after `picked `, trailing `;`/`,` stripped
# — and it must be a Queue row (`- [ ] <item>` or `- [x] <item>…`). PR: ONLY from a
# `ran /autonomous` line AFTER that last `picked` line (its first
# `https?://…/pull/<n>` token) — never from any other Progress line (closeout step
# lines, `cross-run closeout` lines, trail and reconcile-status lines carry OTHER
# PRs' URLs). Branch: one `gh pr view <pr> --json headRefName,state,mergedAt`.
# Status: ALWAYS `running` (OPEN, MERGED, CLOSED or unreadable) — a rebuild never
# claims awaiting_merge/READY/escalated and never triggers a close-out; the
# observed state is named in the line for the owner. Writes via current-set, then
# progress-appends and prints `current_rebuilt: <item> pr <url|null> state
# <OPEN|MERGED|CLOSED|unknown|none>` (`none` = no PR found). Set and not `done`, or
# `done` and naming the last picked item ⇒ `current-rebuild: skipped — ## Current
# set`. Exit 0 except a refused write (1).
current_rebuild() {
  local out="${1:-}" R="current-rebuild: skipped —"
  [ -n "$out" ] || die "current-rebuild: refused — usage: current-rebuild <runfile>"
  [ -f "$out" ] || die "current-rebuild: refused — run file not found: $out"
  is_run_file "$out" || die "current-rebuild: refused — not a run file (no '# Automate Run:' title): $out; left unchanged [runfile_write_refused]"
  local cl ci cs cur_set=0
  cl="$(_current_item_line "$out")"
  ci="$(_current_field "$cl" item)"
  if [ -n "$ci" ] && [ "$ci" != null ]; then
    cur_set=1; cs="$(_current_field "$cl" status)"
    # A set item that is not `done` is in flight — never second-guessed here.
    [ "$cs" = done ] || { echo "$R ## Current set"; return 0; }
  fi
  local picked_ln item
  picked_ln="$(_progress_block "$out" | awk '/^- ([^ ]+ )?picked /{n=NR; l=$0} END{if (n) print n "\t" l}')"
  if [ -z "$picked_ln" ]; then
    [ "$cur_set" = 1 ] && { echo "$R ## Current set"; return 0; }
    echo "$R no picked line in ## Progress"; return 0
  fi
  local tab=$'\t'
  local pnum="${picked_ln%%"$tab"*}" pline="${picked_ln#*"$tab"}" re_p='^- ([^ ]+ )?picked ([^ ]+)'
  if [[ "$pline" =~ $re_p ]]; then item="${BASH_REMATCH[2]}"; else item=""; fi
  while :; do case "$item" in *";"|*",") item="${item%?}" ;; *) break ;; esac; done
  # A `done` `## Current` is stale only when the LAST `picked` line names a
  # DIFFERENT item (compared after a leading `./` strip, the guard's rule): the
  # next PICK skipped its `current-set` after a close-out (progress-append's guard
  # exempts a `done` Current, so this is the only place that case is caught).
  if [ "$cur_set" = 1 ] && { [ -z "$item" ] || [ "${item#./}" = "${ci#./}" ]; }; then
    echo "$R ## Current set"; return 0
  fi
  if [ -z "$item" ] || ! AH_ITEM="$item" awk '
      BEGIN { it=ENVIRON["AH_ITEM"] }
      /^## Queue/ { q=1; next } /^## / { q=0 }
      q && ($0 == "- [ ] " it || $0 == "- [x] " it || index($0, "- [x] " it " ")==1) { f=1 }
      END { exit !f }' "$out"; then
    echo "$R picked item not in Queue"; return 0
  fi
  local pr
  pr="$(_progress_block "$out" | PN="$pnum" awk '
    NR > ENVIRON["PN"]+0 && /^- ([^ ]+ )?ran \/autonomous/ {
      if (match($0, /https?:\/\/[^ ]*\/pull\/[0-9]+/)) u=substr($0, RSTART, RLENGTH)
    }
    END { if (u != "") print u }')"
  local state="none" branch="null"
  if [ -n "$pr" ]; then
    local view s m h
    state="unknown"
    if view="$("$GH" pr view "$pr" --json headRefName,state,mergedAt 2>/dev/null)"; then
      s="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null || true)"
      m="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null || true)"
      h="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null || true)"
      if [ "$s" = MERGED ] || [ -n "$m" ]; then state=MERGED
      elif [ "$s" = OPEN ] || [ "$s" = CLOSED ]; then state="$s"; fi
      case "$h" in ""|*"|"*|*" "*) ;; *) branch="$h" ;; esac
    fi
  else
    pr=null
  fi
  current_set "$out" --item "$item" --status running --pr "$pr" --branch "$branch" >/dev/null
  local msg="current_rebuilt: $item pr $pr state $state"
  progress_append "$out" "$msg"
  echo "$msg"
}

# queue-checkoff <runfile_path> <item> [reason] [mark]
# Flips "- [ ] <item>" to "- [x] <item>". With a reason, writes the excluded form
# "- [x] <item>  # <mark>: <reason>" where <mark> is "skipped" (default) or
# "abandoned" (§5 — both are checked-off so the item is never re-picked and does not
# block ## Status: done). Atomic write. Idempotent on already-checked items
# (leaves them untouched).
queue_checkoff() {
  local out="$1" item="$2" reason="${3:-}" mark="${4:-skipped}"
  case "$mark" in skipped|abandoned) ;; *) die "queue-checkoff: mark must be skipped|abandoned (got '$mark')" ;; esac
  [ -f "$out" ] || die "run file not found: $out"
  is_run_file "$out" || die "queue-checkoff: refused — $out has no '# Automate Run:' title line (not a run file); left unchanged [runfile_write_refused]"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass item/reason via the ENVIRONMENT (not awk -v): -v interprets backslash
  # escapes in the value, which would mangle a path/reason containing a literal
  # backslash. ENVIRON[...] is read verbatim.
  AH_ITEM="$item" AH_REASON="$reason" AH_MARK="$mark" awk '
    BEGIN { item=ENVIRON["AH_ITEM"]; reason=ENVIRON["AH_REASON"]; mark=ENVIRON["AH_MARK"] }
    {
      line=$0
      # Match an unchecked queue line whose payload (after "- [ ] ") equals item.
      if (line ~ /^- \[ \] /) {
        payload=substr(line, 7)
        if (payload == item) {
          if (reason != "")
            print "- [x] " item "  # " mark ": " reason
          else
            print "- [x] " item
          next
        }
      }
      print line
    }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "queue-checkoff: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" title queue-checkoff
}

# remaining <runfile_path>
# Counts ONLY unchecked "- [ ]" lines (skipped/checked items excluded), so a
# skipped item never blocks ## Status: done (§3/§5).
remaining() {
  local out="$1"
  [ -f "$out" ] || die "run file not found: $out"
  grep -c '^- \[ \] ' "$out" || true
}

# ceiling-check <runfile_path> <max_tokens> [--root <checkout>]
# §6 step 1 PICK-time token ceiling. Sums the run's ledger via
# `read-token-ledger.sh --run-id <runfile>` (§1.5) and compares its TOTAL
# against <max_tokens>. Always prints exactly ONE line and returns 0 (a PARK
# is a normal, expected outcome here — same fail-CLOSED-but-never-crash
# convention gate_eval already uses, never a shell failure the caller has to
# special-case):
#   "OK total=<n> max=<n>"                          — under the ceiling, proceed
#   "PARK: token_ceiling total=<n> max=<n>"          — strictly exceeding the ceiling (total > max; exactly at max is OK)
#   "PARK: ledger_unreadable"                        — reader could not sum anything
# This is the load-bearing seam mutation-control targets (test-automate-helpers.sh
# §"ceiling-check"): a ledger reader that always reports 0 real tokens must
# never let this print "OK" when the true spend is over <max_tokens>.
ceiling_check() {
  local out="$1" max="$2" root=""
  shift 2 2>/dev/null || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) root="${2:-.}"; shift 2 2>/dev/null || shift ;;
      *) shift ;;
    esac
  done
  [ -f "$out" ] || die "run file not found: $out"
  case "$max" in
    ''|*[!0-9]*) die "ceiling-check: max_tokens must be a non-negative integer (got '$max')" ;;
  esac
  local reader="$(dirname "$0")/read-token-ledger.sh"
  local args=(--run-id "$out")
  [ -n "$root" ] && args+=(--root "$root")
  local ledger_out=""
  if [ -x "$reader" ] || [ -f "$reader" ]; then
    ledger_out="$(bash "$reader" "${args[@]}" 2>/dev/null || true)"
  fi
  # Here-string / built-in regex, never `printf | grep -q` or `| head -1`: under
  # `set -euo pipefail` an early-exiting reader (grep -q on its first match,
  # head -1) can SIGPIPE the producer and fail the pipeline on a correct answer.
  if [ -z "$ledger_out" ] || grep -q 'LEDGER_UNREADABLE=1' <<<"$ledger_out"; then
    echo "PARK: ledger_unreadable"
    return 0
  fi
  local total="" re_total='TOTAL=([0-9]+)'
  if [[ "$ledger_out" =~ $re_total ]]; then total="${BASH_REMATCH[1]}"; fi
  if [ -z "$total" ]; then
    echo "PARK: ledger_unreadable"
    return 0
  fi
  if [ "$total" -gt "$max" ]; then
    echo "PARK: token_ceiling total=${total} max=${max}"
    return 0
  fi
  echo "OK total=${total} max=${max}"
  return 0
}

