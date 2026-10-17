# ==================================================================================================
# lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]
lanes_create() {
  local runfile="" item="" n="" par="" maxt="" a single=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --parallel) _lanes_need "$#" lane-create "$1"; par="$2"; shift 2; if [ "$par" = 1 ]; then single=1; else single=0; fi ;;
      --max-tokens) _lanes_need "$#" lane-create "$1"; maxt="$2"; shift 2 ;;
      *) if [ -z "$runfile" ]; then runfile="$1"; elif [ -z "$item" ]; then item="$1"; elif [ -z "$n" ]; then n="$1"
         else die "lane-create: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  [ -n "$runfile" ] && [ -n "$item" ] && [ -n "$n" ] || die "usage: lane-create <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]"
  # The lane NUMBER is an identity across the whole run (waves and re-run lanes included), not the
  # parallel count, so every caller takes 1..99 and a FRESH number (the table refusal below). Single-lane
  # mode is an EXPLICIT `--parallel 1` — never inferred from `par`, whose default is n.
  case "$n" in [1-9]|[1-9][0-9]) ;; *) die "lane-create: lane number must be 1..99 (got '$n')" ;; esac
  if [ -z "$par" ]; then
    case "$n" in [1-9]|10) par="$n" ;; *) die "lane-create: lane number $n needs an explicit --parallel N (the default N is the lane number)" ;; esac
  fi
  case "$par" in [1-9]|10) ;; *) die "lane-create: --parallel must be 1..10 (got '$par')" ;; esac
  case "$maxt" in ''|*[!0-9]*) [ -z "$maxt" ] || die "lane-create: --max-tokens must be a whole number" ;; esac
  case "$item" in /*|*..*) die "lane-create: item must be the canonical repo-relative path (got '$item')" ;; esac
  [ -f "$runfile" ] || die "lane-create: run file not found: $runfile"
  local rdir parent primary
  rdir="$(cd "$(dirname "$runfile")" && pwd -P)"; parent="$(basename "$runfile" .md)"
  case "$parent" in ''|*/*|.*|*-L[0-9]|*-L[0-9][0-9]) die "lane-create: bad parent run file name '$parent'" ;; esac
  [ "$(basename "$rdir")" = automate ] && [ "$(basename "$(dirname "$rdir")")" = .supervisor ] \
    || die "lane-create: run file must live in <primary>/.supervisor/automate/"
  primary="$(cd "$rdir/../.." && pwd -P)"
  [ "$(git -C "$primary" rev-parse --show-toplevel 2>/dev/null)" = "$primary" ] || die "lane-create: $primary is not a git checkout root"
  [ -f "$primary/$item" ] || die "lane-create: item not found in the primary: $item"
  local url; url="$(git -C "$primary" remote get-url origin 2>/dev/null)"
  [ -n "$url" ] || die "lane-create: refused — the primary has no origin remote"
  local lane="L$n" lroot="$primary-lanes/$parent" C run_id="$parent-L$n" table="$rdir/$parent.lanes"
  C="$lroot/$lane"
  local spent=""
  # Every lane takes a FRESH number: one already in this run's table (live, removed or abandoned) is
  # refused — its run id, salvage, logs and `<run_id>-L<n>` metadata on the meta branch belong to an
  # earlier item, and reusing it would overwrite them. Nothing is created.
  if [ -f "$table" ] && awk -F'\t' -v l="$lane" '$1 == l { f = 1 } END { exit !f }' "$table" 2>/dev/null; then
    echo "lane-create: refused — lane $lane already used in this run (each lane takes a fresh number)" >&2
    return 1
  fi
  if [ "$single" = 1 ]; then
    # Whole-run token ceiling (owner decision 3): T bounds the RUN, not each lane.
    if [ -n "$maxt" ]; then
      if ! spent="$(_lanes_single_spent "$table" "$runfile")"; then
        echo "lane-create: refused — token_ceiling ledger_unreadable" >&2; return 1
      fi
      if [ "$spent" -ge "$((10#$maxt))" ]; then
        echo "lane-create: refused — token_ceiling total=$spent max=$((10#$maxt))" >&2; return 1
      fi
    fi
  fi
  if [ -e "$C" ]; then
    local sv; sv="$(_lanes_salvage "$C" "$lroot/salvage" "$lane-leftover")"
    echo "lane-create: refused — leftover lane directory $C (salvaged to ${sv:-<salvage failed>}); never reused" >&2
    return 1
  fi
  mkdir -p "$lroot" || die "lane-create: cannot create $lroot"
  _abort() { rm -rf "$C"; echo "lane-create: aborted $lane — $1 (clone removed)" >&2; return 1; }
  git clone -q --local "$primary" "$C" 2>/dev/null || { _abort "clone failed"; return 1; }
  # origin = the primary's remote URL BEFORE any fetch; prune the refs the --local clone inherited.
  git -C "$C" remote set-url origin "$url" || { _abort "could not set origin"; return 1; }
  git -C "$C" fetch -q --prune origin 2>/dev/null || { _abort "fetch from origin failed"; return 1; }
  git -C "$C" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r a; do
    git -C "$C" rev-parse -q --verify "$a" >/dev/null 2>&1 || git -C "$C" update-ref -d "$a" 2>/dev/null
  done
  git -C "$C" remote set-head origin -a >/dev/null 2>&1
  local base; base="$(git -C "$C" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; base="${base#origin/}"
  [ -n "$base" ] || base=main
  git -C "$C" checkout -q -B "$base" "origin/$base" 2>/dev/null || { _abort "base branch origin/$base not found"; return 1; }
  # metadata pull (always --branch); non-zero ⇒ abort the lane.
  local mb
  if ! mb="$(_lanes_meta_branch "$C")"; then _abort "metadata mode unknown"; return 1; fi
  if [ -n "$mb" ]; then
    bash "$META_SYNC" pull --branch "$mb" --root "$C" >/dev/null 2>&1 || { _abort "meta-sync pull --branch $mb failed"; return 1; }
  fi
  [ -f "$C/$item" ] || { _abort "item $item absent in the lane after the metadata pull"; return 1; }
  mkdir -p "$C/.supervisor/automate" "$C/.supervisor/inbox/questions" "$C/.supervisor/inbox/answers" || { _abort "cannot create .supervisor"; return 1; }
  local cf
  for cf in config.json notify-config.json; do
    if [ -f "$primary/.supervisor/$cf" ]; then cp -p "$primary/.supervisor/$cf" "$C/.supervisor/$cf" || { _abort "cannot copy $cf"; return 1; }; fi
  done
  local mt=null
  if [ -n "$maxt" ]; then
    if [ "$single" = 1 ]; then mt=$((10#$maxt - spent)); else mt=$((10#$maxt / par)); fi
  fi
  # Policy carry (parallel-automate/21 B5): `lane-policy.sh resolve` runs HERE, in the primary — the rules
  # stamp is keyed per clone, so a lane can never verify the project policy itself. Its report lines
  # (`lane-policy: project policy ignored — …`, `lane-policy: dropped …`) reach this command's stderr
  # verbatim. Anything but a non-empty answers object with a policy_sha (no policy, a usage error, an
  # unreadable result) carries `"policy": null` — the lane then relays every question as before.
  local pol pj=null ps=none
  pol="$(bash "$POLICY" resolve "$runfile" --root "$primary" </dev/null)" || pol=""
  if jq -e 'type == "object" and (.policy_sha | type) == "string" and (.answers | type) == "object"
      and (.answers | length) > 0' >/dev/null 2>&1 <<<"$pol"; then
    pj="$(jq -c . <<<"$pol")"; ps="$(jq -r '"\(.policy_sha[0:12]):\(.answers | length)"' <<<"$pol")"
  fi
  jq -n --arg lane "$lane" --arg run "$run_id" --arg parent "$parent" --arg primary "$primary" \
    --argjson parallel "$par" --argjson mt "$mt" --arg created "$(now_utc)" --argjson policy "$pj" \
    --argjson single "$single" \
    '{schema_version: 1, lane: $lane, run_id: $run, parent_run_id: $parent, primary: $primary,
      parallel: $parallel, max_tokens: $mt, created: $created, policy: $policy}
      + (if $single == 1 then {single_lane: true} else {} end)' > "$C/.supervisor/lane.json" \
    || { _abort "cannot write lane.json"; return 1; }
  printf -- '- [ ] %s\n' "$item" > "$C/.supervisor/lane-backlog.md" || { _abort "cannot write the backlog"; return 1; }
  _lanes_merge_hooks "$C/.claude/settings.local.json" "bash \"$PLUGIN_ROOT/scripts/automate-lanes.sh\" relay-hook" \
    || { _abort "cannot merge the relay hooks"; return 1; }
  local porc; porc="$(git -C "$C" status --porcelain 2>/dev/null)"
  [ -z "$porc" ] || { _abort "lane is not clean after setup: $(printf '%s' "$porc" | head -3 | tr '\n' ' ')"; return 1; }
  _lt_lock "$table" || { _abort "lane table lock busy (live holder): $table.lock"; return 1; }
  if [ ! -s "$table" ]; then
    { printf '%s\n' "$LT_HEADER"
      printf '# not carried into lanes: .claude/settings.local.json (relay hooks only), the rules stamp, Claude auto-memory\n'; } > "$table"
  fi
  # Re-check under the lock (the fresh-number refusal above ran unlocked): a row that appeared since is
  # never replaced.
  if awk -F'\t' -v l="$lane" '$1 == l { f = 1 } END { exit !f }' "$table" 2>/dev/null; then
    _lt_unlock "$table"; _abort "lane $lane already used in this run (each lane takes a fresh number)"; return 1
  fi
  printf '%s\t%s\t%s\t%s\t-\t-\t-\tcreated\t-\t-\n' "$lane" "$C" "$(_clean "$item")" "$run_id" >> "$table"
  _lt_unlock "$table"
  echo "lane-create: $lane $C run_id=$run_id item=$item meta=${mb:-off} policy=$ps"
}

