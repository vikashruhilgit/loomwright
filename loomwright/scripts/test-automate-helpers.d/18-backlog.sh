# =============================================================================
# Run directly (`bash <this file>`, as run-pin-mutations.sh runs a pin), this fragment re-executes the
# suite for this one part, so its assertions run against the helpers beside it; sourced by the
# runner, BASH_SOURCE[0] is this file and $0 the runner, and the guard never fires.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-automate-helpers.sh" 18-backlog; fi
echo "== BL. item-state / backlog / backlog-stamp (parallel-automate/18a; hermetic trees copied from fixtures/backlog-state/) =="
# Every tree is a fresh copy of fixtures/backlog-state/tree/ (README there: one row per item and the
# state it must read); no leg reads the live .supervisor/requirements/. `gh`, `lane-status --json`
# and (where named) `right-size --json` are stubs; nothing reaches GitHub.
BL="$(mktemp -d)"; BL="$(cd "$BL" && pwd -P)"
BL_FIX="$HERE/fixtures/backlog-state"
BL_MUT="$(dirname "$H")/bl-mutant.sh"
mkdir -p "$BL/bin"
cat > "$BL/bin/gh" <<'STUB'
#!/usr/bin/env bash
# gh stub: one line per call to $BL_GH_LOG; BL_GH_FAIL=1 fails every call; `pr list --state
# merged|open` prints the fixture lists; reconcile-status's `--search` gets [].
echo "$*" >> "$BL_GH_LOG"
[ "${BL_GH_FAIL:-0}" = 1 ] && exit 1
case " $* " in *" --search "*) printf '[]'; exit 0 ;; esac
case " $* " in
  *" pr list "*"--state merged"*) cat "$BL_FIXDIR/gh/merged.json" ;;
  *" pr list "*"--state open"*) cat "$BL_FIXDIR/gh/open.json" ;;
  *) exit 1 ;;
esac
STUB
printf '#!/usr/bin/env bash\ncat "$BL_FIXDIR/lane-status.json"\n' > "$BL/bin/lanes"
cat > "$BL/bin/rsize" <<'STUB'
#!/usr/bin/env bash
# right-size stub: one line per call to $BL_RS_LOG; BL_RS_FAIL=1 exits 1; else every listed item `ok`.
echo "call $(grep -c . "$1") $2 $3" >> "$BL_RS_LOG"
[ "${BL_RS_FAIL:-0}" = 1 ] && exit 1
jq -R -s 'split("\n") | map(select(length > 0) | sub("^\\.supervisor/requirements/"; "") | sub("\\.md$"; "") | {item: ., verdict: "ok"})' "$1"
STUB
chmod +x "$BL/bin/gh" "$BL/bin/lanes" "$BL/bin/rsize"
# bl_tree <name> — a fresh copy of the fixture tree; prints its root
bl_tree() { mkdir -p "$BL/$1" && cp -R "$BL_FIX/tree/dot-supervisor" "$BL/$1/.supervisor" && printf '%s' "$BL/$1"; }
# bl_run <helper> <args...> — stdout BL_OUT, stderr BL_ERR, exit BL_RC (gh + lane-status stubbed)
bl_run() {
  local h="$1"; shift
  BL_RC=0
  BL_OUT="$(BL_FIXDIR="${BL_FIXDIR_OVR:-$BL_FIX}" BL_GH_LOG="$BL/gh.log" BL_RS_LOG="$BL/rs.log" LOOMWRIGHT_GH_BIN="$BL/bin/gh" \
    LOOMWRIGHT_LANE_STATUS_BIN="$BL/bin/lanes" bash "$h" "$@" 2>"$BL/err")" || BL_RC=$?
  BL_ERR="$(cat "$BL/err")"
}
bl_is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — got '$(printf '%s' "$2" | tr '\n' '|')', want '$(printf '%s' "$3" | tr '\n' '|')'"; fi; }
bl_sum() { (cd "$1" && find .supervisor -type f -exec cksum {} \; | sort); }
# bl_mut_check <label> <anchor> <replacement|__DELETE__> <scenario_fn> <expected> — a COPY of the bundle
# with the FIRST line containing <anchor> replaced (or deleted), trusted only when the anchor is unique,
# the mutant non-empty, different and `bash -n` clean; <scenario_fn> must then print something other
# than <expected> (its leg turns red).
bl_mut_check() {
  local got
  BL_A="$2" BL_R="$3" awk 'BEGIN { a = ENVIRON["BL_A"]; r = ENVIRON["BL_R"] }
    !d && index($0, a) { d = 1; if (r == "__DELETE__") next; print r; next } { print }' "$H" > "$BL_MUT"
  if [ "$(grep -cF -- "$2" "$H")" = 1 ] && [ -s "$BL_MUT" ] && ! cmp -s "$H" "$BL_MUT" && bash -n "$BL_MUT" 2>/dev/null; then
    got="$("$4" "$BL_MUT")"
    if [ "$got" != "$5" ]; then ok "BL mutant ($1) turns its leg red"; else no "BL mutant ($1) did NOT discriminate: '$got'"; fi
  else
    no "BL mutant ($1) not gated (anchor not unique, mutant empty, identical, or bash -n failed)"
  fi
  rm -f "$BL_MUT"
}

# The README's state table is the expected answer: `| <item> | <state> | …` rows.
BL_WANT="$(awk -F '|' '/^\| `[a-z]/ { i = $2; s = $3; gsub(/[ `]/, "", i); gsub(/[ `]/, "", s); print i "\t" s }' "$BL_FIX/README.md" | env LC_ALL=C sort)"
T0="$(bl_tree t0)"

# ---- BL1 (AC1, AC4) the board reads every fixture item in the README's state, each counted once.
bl_run "$H" backlog --json --root "$T0"
BL_DOC="$BL_OUT"
bl_is "BL1 the board's per-item states equal the README table (every state has a fixture item)" \
  "$(jq -r '.items[] | "\(.item)\t\(.state)"' <<<"$BL_DOC" | env LC_ALL=C sort)" "$BL_WANT"
bl_is "BL1 every state of the closed set has at least one fixture item" \
  "$(jq -r '[.totals | to_entries[] | select(.value == 0) | .key] | join(",")' <<<"$BL_DOC")" ""
# item count, independently: the fixture's *.md files minus the five the skip list drops
BL_NFILES="$(find "$T0/.supervisor/requirements" -type f -name '*.md' | wc -l | tr -d ' ')"
bl_is "BL4 totals sum to the item count, which is the fixture's item files minus the 5 skipped (00-*, _*, README*, operator-run/, top-level -plan)" \
  "$(jq -r '"\(.totals | add) \(.item_count) \(.items | length)"' <<<"$BL_DOC")" "$((BL_NFILES - 5)) $((BL_NFILES - 5)) $((BL_NFILES - 5))"
bl_is "BL4 --json is ONE JSON object that round-trips (jq -c . | jq -e equal)" \
  "$(jq -s 'length' <<<"$BL_DOC") $([ "$(jq -S -c . <<<"$BL_DOC")" = "$(jq -c . <<<"$BL_DOC" | jq -e -S -c .)" ] && echo equal)" "1 equal"
bl_is "BL4 the totals object carries exactly the closed set, in order" \
  "$(jq -r '.totals | keys_unsorted | join(" ")' <<<"$BL_DOC")" "done abandoned parked proposed follow_up brief_shipped merged_unstamped pr_open in_flight conflict open unknown"
bl_run "$H" backlog --json --state conflict --root "$T0"
bl_is "BL4 --state conflict filters the rows; totals stay whole-tree" \
  "$(jq -r '"\([.items[].state] | unique | join(",")) \(.items | length) \(.totals | add) \(.state_filter)"' <<<"$BL_OUT")" "conflict 2 $((BL_NFILES - 5)) conflict"
bl_run "$H" backlog --state nonsense --root "$T0"
bl_is "BL4 an unknown --state exits 1 with nothing on stdout" "$BL_RC|$BL_OUT" "1|"
bl_run "$H" backlog --root "$T0"
bl_is "BL4 the table's totals line adds up and the header says github: verified" \
  "$(grep -c '^totals: .* = 24 of 24 items$' <<<"$BL_OUT") $(head -n1 <<<"$BL_OUT")" "1 backlog: 24 items — github: verified — right-size: ok"
bl_use() { bl_run "$H" "$@" --root "$T0"; printf '%s|%s' "$BL_RC" "$BL_OUT"; }
bl_is "BL4 usage errors exit 1 with nothing on stdout: --unknown with --verify-list, a stray argument, an unknown flag, a missing named item, two items to item-state" \
  "$(bl_use backlog --unknown --verify-list) $(bl_use backlog bl/14-open) $(bl_use backlog --bogus) $(bl_use backlog --verify-list bl/nope) $(bl_use item-state bl/14-open bl/15-unknown)" "1| 1| 1| 1| 1|"
bl_s4() { bl_run "$1" backlog --json --root "$T0"; jq -r '"\(.totals | add)/\(.item_count)"' <<<"$BL_OUT"; }
bl_mut_check "pin AC4: one state dropped from the totals reduction" '    | ($states | split(" ")) as $S' \
  '    | ($states | split(" ") | .[1:]) as $S' bl_s4 "24/24"

# ---- BL1 (AC1) item-state's named cases: the appended stamp, no status line, a lane claim, a parked
# item named by an unfinished run (that run stale_run), a pending item with an older abandoned row.
bl_run "$H" item-state bl/01-done-appended --root "$T0"
bl_is "BL1 first-line pending + an appended done stamp ⇒ done (is_done reads ANY ## Status: line)" "$BL_RC|$BL_OUT" \
  "0|done	bl/01-done-appended	## Status: done"
bl_s1() { bl_run "$1" item-state bl/01-done-appended --root "$T0"; cut -f1 <<<"$BL_OUT"; }
bl_mut_check "pin AC1: the stamp step reads only the FIRST ## Status: line" '  if is_done "$f"; then   # the stamp step' \
  '  if case "$fs" in "## Status: done"*) true ;; *) false ;; esac; then' bl_s1 "done"
bl_run "$H" item-state bl/15-unknown --root "$T0"
bl_is "BL1 no status line ⇒ unknown with 'no status line'" "$BL_OUT" "unknown	bl/15-unknown	no status line"
bl_run "$H" item-state bl/16-off-enum --root "$T0"
bl_is "BL1 an off-enum status ⇒ unknown naming the offending line" "$BL_OUT" "unknown	bl/16-off-enum	off-enum status line: ## Status: in review — PR #9"
bl_run "$H" item-state bl/10-lane --root "$T0"
bl_is "BL1 an item named by a live lane in lane-status --json ⇒ in_flight with the lane name" "$BL_OUT" "in_flight	bl/10-lane	lane L2 (running) from lane-status"
bl_run "$H" item-state bl/14-open --root "$T0"
bl_is "BL1 a removed lane's item is no claim ⇒ the item's own ready status reads open" "$BL_OUT" "open	bl/14-open	## Status: ready"
bl_run "$H" item-state bl/03-parked --root "$T0"
bl_is "BL1 a parked item named by an unfinished run's ## Current ⇒ parked, and that run stale_run" "$BL_OUT" \
  "parked	bl/03-parked	## Status: parked
stale_run	.supervisor/automate/automate-2026-10-10-100000.md	its ## Current item bl/03-parked reads parked"
bl_run "$H" item-state bl/17-in-flight --root "$T0"
bl_is "BL1 an unfinished run's ## Current with no PR ⇒ in_flight naming the run" "$BL_OUT" \
  "in_flight	bl/17-in-flight	## Current of unfinished run .supervisor/automate/automate-2026-10-12-100000.md"
bl_run "$H" item-state bl/09-pr-open --json --root "$T0"
bl_is "BL1 a claim whose PR is in the OPEN list ⇒ pr_open with the PR" "$(jq -r '"\(.state) \(.pr) \(.pr_state)"' <<<"$BL_OUT")" \
  "pr_open https://github.com/acme/widgets/pull/109 open"
bl_run "$H" item-state bl/11-conflict --json --root "$T0"
bl_is "BL1 a pending item with an older run's # abandoned: row ⇒ conflict, both sources with their dates" \
  "$(jq -r '"\(.state)|\(.conflict.run_file)|\(.conflict.run_date)|\(.conflict.row)|\(.conflict.item_stamp_date)"' <<<"$BL_OUT")" \
  "conflict|.supervisor/automate/automate-2026-09-01-100000.md|2026-09-01|- [x] .supervisor/requirements/bl/11-conflict.md  # abandoned: owner dropped it|undated"
bl_is "BL1 the conflict evidence line names the row's run file, its run date and the item's own status" \
  "$(jq -r '.evidence' <<<"$BL_OUT")" \
  "- [x] .supervisor/requirements/bl/11-conflict.md  # abandoned: owner dropped it in .supervisor/automate/automate-2026-09-01-100000.md (run automate-2026-09-01-100000, 2026-09-01) vs the item's own ## Status: pending (last dated stamp: undated)"
bl_run "$H" item-state no/such-item --root "$T0"
bl_is "BL1 an item that does not exist exits 1 with nothing on stdout" "$BL_RC|$BL_OUT" "1|"

# ---- BL2 (AC2) a pending item checked `- [x]` in a run file ⇒ merged_unstamped naming the line.
bl_s2() { bl_run "$1" backlog --root "$T0"; grep -F '06-merged-unstamped' <<<"$BL_OUT" | cut -f2,6; }
bl_is "BL2 a plain - [x] row ⇒ merged_unstamped (never open), naming the run-file line" "$(bl_s2 "$H")" \
  "merged_unstamped	— run file .supervisor/automate/automate-2026-09-01-100000.md: - [x] .supervisor/requirements/bl/06-merged-unstamped.md"
bl_mut_check "pin AC2: the plain check-off evidence lookup deleted" '  if [ -n "$P_X" ]; then BL_S=merged_unstamped' __DELETE__ \
  bl_s2 "merged_unstamped	— run file .supervisor/automate/automate-2026-09-01-100000.md: - [x] .supervisor/requirements/bl/06-merged-unstamped.md"
bl_is "BL2 a fleet closeout line and a slug-named merged PR are merge evidence too" \
  "$(jq -r '.items[] | select(.item == "bl/08-fleet" or .item == "bl/07-merged-pr") | "\(.state) \(.pr)"' <<<"$BL_DOC")" \
  "merged_unstamped https://github.com/acme/widgets/pull/107
merged_unstamped https://github.com/acme/widgets/pull/108"
bl_is "BL2 the slug-named PR's evidence names the key and where it matched" \
  "$(jq -r '.items[] | select(.item == "bl/07-merged-pr") | .evidence' <<<"$BL_DOC")" "merged PR #107 names 07-merged-pr (head feature/bl-07-merged-pr)"
# A false PR match would hide steps 3-5, so a merged PR is evidence only on a whole-token,
# distinctive key: decoy #901's title contains the id-less basename `spec`, decoy #902's head
# `feature/x11-conflict` and title `fix: x11-conflict cleanup` hold `11-conflict` with no boundary,
# decoy #950's title names the longer sibling slug `11-conflict-guard`, and decoys #951 (title) /
# #952 (head) name the longer sibling folder's `sub-bl/spec`.
bl_s2b() { bl_run "$1" backlog --json --root "$T0"; jq -r '[.items[] | select(.item == "bl/spec" or .item == "bl/11-conflict") | "\(.item)=\(.state)"] | join(" ")' <<<"$BL_OUT"; }
bl_is "BL2 a title merely containing an id-less basename, a head ending with the slug at no boundary, and a longer sibling slug or folder in a title or head, are no merge evidence (the conflict stays visible)" \
  "$(bl_s2b "$H")" "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: the head match loses its / or - boundary (x11-conflict masks the conflict)" '    return (c == "/" || (c == "-" && !fq))' '    return 1' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: a folder-qualified head key admits a - before it (feature/sub-bl/spec names bl/spec)" '    return (c == "/" || (c == "-" && !fq))' '    return (c == "/" || c == "-")' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: an id-less slug counts as a distinctive key (spec matches the decoy title)" '    K1 = (slug ~ /^[0-9]+[a-z]?-./) ? slug : ""' '    K1 = slug' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: the title match loses its token boundary" '      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9_\/-]/) return 1' '      return 1' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: the title match admits _/- after the key (11-conflict-guard masks the conflict)" '      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9_\/-]/) return 1' '      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9\/]/) return 1' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: a folder-qualified title key admits _/- before it (sub-bl/spec names bl/spec)" '      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9_\/-]/) return 1' '      if (b !~ /[A-Za-z0-9]/ && a !~ /[A-Za-z0-9_\/-]/) return 1' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_mut_check "pin: a title key admits / after it (bl/spec/notes names bl/spec, 11-conflict/notes masks the conflict)" '      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9_\/-]/) return 1' '      if (b !~ /[A-Za-z0-9]/ && !(fq && b ~ /[_-]/) && a !~ /[A-Za-z0-9_-]/) return 1' bl_s2b "bl/11-conflict=conflict bl/spec=open"
bl_run "$H" backlog --verify-list bl/spec --root "$T0"
bl_is "BL2 the decoy is still offered as a --verify-list candidate (a candidate, never evidence)" \
  "$(grep -c '^  candidate: #901 https://github.com/acme/widgets/pull/901 — feat(verify): spec replay$' <<<"$BL_OUT")" "1"
# the folder-qualified key IS evidence for an id-less item: a PR whose title names `bl/spec`
mkdir -p "$BL/fixq/gh"; cp "$BL_FIX/lane-status.json" "$BL/fixq/"; cp "$BL_FIX/gh/open.json" "$BL/fixq/gh/"
printf '[{"number":903,"url":"https://github.com/acme/widgets/pull/903","title":"feat: ship bl/spec","headRefName":"feature/ship"}]' > "$BL/fixq/gh/merged.json"
BL_FIXDIR_OVR="$BL/fixq" bl_run "$H" item-state bl/spec --json --root "$T0"
bl_is "BL2 the folder-qualified key (bl/spec as a whole token in a title) is merge evidence for an id-less item" \
  "$(jq -r '"\(.state) \(.pr) \(.evidence)"' <<<"$BL_OUT")" "merged_unstamped https://github.com/acme/widgets/pull/903 merged PR #903 names bl/spec (title)"
# A key two items share names neither: fixtures/backlog-state/collision/ adds pk/05-shared + qq/05-shared
# (one id-prefixed slug, two folders) and x/bl/spec (folder-qualified key bl/spec, like bl/spec). One
# merged PR per case: a pk-qualified head or title is pk's evidence and never qq's, a bare 05-shared
# title is neither's, and with x/bl/spec present a title naming bl/spec is no item's.
TC="$(bl_tree tc)"; cp -R "$BL_FIX/collision/." "$TC/.supervisor/requirements/"
bl_coll() { # <helper> — `<case>:<bl/spec>/<pk>/<qq>` (board order) per merged-PR case
  local c t h
  for c in 'head|feature/pk-05-shared|chore' 'slash|feature/pk/05-shared|chore' 'title|feature/x|feat: pk/05-shared done' 'bare|feature/x|fix: 05-shared' 'spec|feature/x|feat: ship bl/spec'; do
    h="${c#*|}"; t="${h#*|}"; h="${h%%|*}"
    jq -n -c --arg h "$h" --arg t "$t" '[{number: 960, url: "https://github.com/acme/widgets/pull/960", title: $t, headRefName: $h}]' > "$BL/fixq/gh/merged.json"
    BL_FIXDIR_OVR="$BL/fixq" bl_run "$1" backlog --json --root "$TC"
    printf '%s:%s ' "${c%%|*}" "$(jq -r '[.items[] | select(.item == "pk/05-shared" or .item == "qq/05-shared" or .item == "bl/spec") | .state] | join("/")' <<<"$BL_OUT")"
  done
}
BL_COLL_WANT="head:open/merged_unstamped/open slash:open/merged_unstamped/open title:open/merged_unstamped/open bare:open/open/open spec:open/open/open "
bl_is "BL2 a key two items share is no evidence: a pk/05-shared head or title is pk's alone, a bare 05-shared or (with x/bl/spec) bl/spec title names no item" \
  "$(bl_coll "$H")" "$BL_COLL_WANT"
bl_mut_check "pin: a key another item shares stays a key (the pk/05-shared PR is qq/05-shared's evidence too)" \
  '  function own(k, f) { return (k == "" || (k in KS) || ((k in KO) && KO[k] != f)) ? "" : k }' '  function own(k, f) { return k }' bl_coll "$BL_COLL_WANT"

# ---- BL3 (AC3) parked (merged … into `X` as Part B — …) with X done ⇒ done, naming X; a cycle ⇒ unknown.
bl_s3() { bl_run "$1" item-state pk/01-merged-into --json --root "$T0"; jq -r '"\(.state) \(.via)"' <<<"$BL_OUT"; }
bl_is "BL3 an item parked into a done X reads done and names X" "$(bl_s3 "$H")" "done pk/02-target"
bl_mut_check "pin AC3: the follow-into-X line deleted (the item reads parked)" "        case \"\$x\" in '\`'*)" __DELETE__ bl_s3 "done pk/02-target"
bl_run "$H" item-state pk/03-cycle-a --root "$T0"
bl_is "BL3 a parked chain that comes back to itself ⇒ unknown (parked chain cycle)" "$(cut -f1 <<<"$BL_OUT") $(grep -c 'parked chain cycle' <<<"$BL_OUT")" "unknown 1"

# ---- BL5 (AC5) gh failing ⇒ every PR field unverified, header github: unverified, no pr_open, and a
# claim stays in_flight (never open).
bl_s5() {
  BL_GH_FAIL=1 bl_run "$1" backlog --json --root "$T0"
  jq -r '"\(.github) \([.items[] | select(.pr_state != "unverified")] | length) \(.totals.pr_open) \(.items[] | select(.item == "bl/09-pr-open") | .state)"' <<<"$BL_OUT"
}
bl_is "BL5 gh failing ⇒ github unverified, 0 items with a verified PR field, 0 pr_open, the claimed item in_flight" "$(bl_s5 "$H")" "unverified 0 0 in_flight"
BL_GH_FAIL=1 bl_run "$H" backlog --root "$T0"
bl_is "BL5 the table header says github: unverified" "$(head -n1 <<<"$BL_OUT")" "backlog: 24 items — github: unverified — right-size: ok"
BL_UNV="$BL_OUT"
BL_GH_FAIL=1 bl_run "$H" backlog --json --root "$T0"
bl_s5b() {
  BL_GH_FAIL=1 bl_run "$1" backlog --json --root "$T0"
  jq -r '"\(.totals.open) \([.items[] | select(.state == "unknown" and (.evidence | endswith("(merged-PR lookup unverified)")) and (.evidence | startswith("## Status: pending") or startswith("## Status: ready"))) | .item] | sort | join(","))"' <<<"$BL_OUT"
}
bl_is "BL5 no item reads open under the failure: every pending/ready item with no other evidence (07's only evidence is a PR) reads unknown, naming the unverified lookup" \
  "$(bl_s5b "$H")" "0 bl/07-merged-pr,bl/12-kept-open,bl/14-open,bl/spec"
bl_mut_check "pin AC5: a pending item reads open although the merged-PR lookup failed" '    if [ "$_BL_GH" = verified ]; then BL_S=open; else BL_S=unknown; fi' '    BL_S=open' bl_s5b "0 bl/07-merged-pr,bl/12-kept-open,bl/14-open,bl/spec"
BL_GH_FAIL=1 bl_run "$H" backlog --verify-list bl/14-open --root "$T0"
bl_is "BL5 --verify-list under the failure says its candidates are unverified, never 'none'" \
  "$(grep -c '^  candidate: none' <<<"$BL_OUT") $([ "$(grep -c '^  candidate: unverified ' <<<"$BL_OUT")" = "$(grep -c '^verify	' <<<"$BL_OUT")" ] && echo all-unverified)" "0 all-unverified"
BL_GH_FAIL=1 bl_run "$H" backlog --unknown --root "$T0"
bl_is "BL5 --unknown under the failure tells a pending item to re-run with gh, not to add a status line" \
  "$(grep -F 'bl/14-open' <<<"$BL_OUT" | grep -c 'fix: re-run when gh can read the merged-PR list')" "1"
bl_mut_check "pin AC5: a failed gh pr list read as a verified empty list" '  _BL_GH=unverified' '  _BL_GH=verified' bl_s5 "unverified 0 0 in_flight"
bl_is "BL5 exactly two gh reads per pass (merged + open), both pr list" \
  "$(: > "$BL/gh.log"; bl_run "$H" backlog --root "$T0"; grep -c '^pr list --state merged ' "$BL/gh.log") $(grep -c '^pr list --state open ' "$BL/gh.log") $(grep -c . "$BL/gh.log")" "1 1 2"

# ---- BL6 (AC1, AC6) Kept open: a marker dated ON the abandoning run's date settles it (open); a later
# run's row raises the conflict again.
bl_s6() { bl_run "$1" item-state bl/12-kept-open --root "$T0"; cut -f1 <<<"$BL_OUT"; }
bl_is "BL6 a Kept-open marker dated on the run's own date ⇒ the item reads its own status (open)" "$(bl_s6 "$H")" "open"
bl_mut_check "pin AC6: the run-date comparison <= flipped to <" '      if [ "$rdn" -le "$kd" ]; then continue; fi' \
  '      if [ "$rdn" -lt "$kd" ]; then continue; fi' bl_s6 "open"
bl_mut_check "pin AC6: the Kept-open lookup deleted" '    if [ -n "$d" ] && [ "${d//-/}" -gt "$kd" ]; then kd="${d//-/}"; fi' __DELETE__ bl_s6 "open"
bl_run "$H" item-state bl/13-kept-reraised --root "$T0"
bl_is "BL6 the same marker, then a LATER run's # skipped: row ⇒ conflict again (naming the later run)" \
  "$(cut -f1 <<<"$BL_OUT") $(grep -c 'automate-2026-10-01-100000, 2026-10-01' <<<"$BL_OUT")" "conflict 1"
T6="$(bl_tree t6)"
printf '# Automate Run: a later run\n## Status: done\n## Queue\n- [x] .supervisor/requirements/bl/12-kept-open.md  # abandoned: dropped again\n## Current\n- item: null\n## Progress\n' \
  > "$T6/.supervisor/automate/automate-2026-09-20-100000.md"
bl_run "$H" item-state bl/12-kept-open --root "$T6"
bl_is "BL6 a later run's # abandoned: row for the kept-open item ⇒ conflict again" "$(cut -f1 <<<"$BL_OUT") $(grep -c '2026-09-20' <<<"$BL_OUT")" "conflict 1"

# ---- BL7 (AC8) the right-size column: ONE call over the whole item list; a failure ⇒ unknown there only.
: > "$BL/rs.log"
LOOMWRIGHT_RIGHT_SIZE_BIN="$BL/bin/rsize" bl_run "$H" backlog --json --root "$T0"
bl_is "BL7 right-size is called once, over all 24 items, and its verdict fills the column" \
  "$(grep -c '^call ' "$BL/rs.log") $(awk '/^call /{ print $2, $3 }' "$BL/rs.log") $(jq -r '[.items[] | select(.right_size == "ok")] | length' <<<"$BL_OUT")" "1 24 --json 24"
bl_is "BL7 the states are the same with the right-size column on" \
  "$(jq -r '.items[] | "\(.item)\t\(.state)"' <<<"$BL_OUT" | env LC_ALL=C sort)" "$BL_WANT"
BL_RS_FAIL=1 LOOMWRIGHT_RIGHT_SIZE_BIN="$BL/bin/rsize" bl_run "$H" backlog --json --root "$T0"
bl_is "BL7 a right-size failure ⇒ every right_size unknown, the header field unknown, the states unchanged" \
  "$(jq -r '"\([.items[] | select(.right_size != "unknown")] | length) \(.right_size)"' <<<"$BL_OUT") $([ "$(jq -r '.items[] | "\(.item)\t\(.state)"' <<<"$BL_OUT" | env LC_ALL=C sort)" = "$BL_WANT" ] && echo same)" "0 unknown same"
bl_run "$H" backlog --json --root "$T0"
bl_is "BL7 the real right-size (no stub): the one item with a Touches section reads small, a Touches-less one unknown" \
  "$(jq -r '[.items[] | select(.item == "bl/14-open" or .item == "bl/15-unknown") | .right_size] | join(" ")' <<<"$BL_OUT")" "small unknown"

# ---- BL8 (AC9) --unknown and --verify-list list, suggest and write nothing.
BL_BEFORE="$(bl_sum "$T0")"
bl_run "$H" backlog --unknown --root "$T0"
bl_is "BL8 --unknown lists every unknown and brief_shipped item, each with a suggested fix" \
  "$(cut -f1,2 <<<"$BL_OUT" | env LC_ALL=C sort | tr '\n' ' ') $(grep -c '	fix: ' <<<"$BL_OUT")" \
  "bl/05-brief-shipped	brief_shipped bl/15-unknown	unknown bl/16-off-enum	unknown pk/03-cycle-a	unknown pk/04-cycle-b	unknown  5"
bl_is "BL8 the brief_shipped fix names its candidate merged PR; an unknown one offers status / stamp / abandon" \
  "$(grep -c 'bl/05-brief-shipped.*candidate #105 ' <<<"$BL_OUT") $(grep -c 'bl/15-unknown.*add ## Status: pending, stamp done with the PR that shipped it, or mark abandoned' <<<"$BL_OUT")" "1 1"
bl_run "$H" backlog --verify-list bl/14-open --root "$T0"
bl_is "BL8 --verify-list lists brief_shipped, unknown and conflict items plus the named one" \
  "$(awk -F '\t' '$1 == "verify" { print $2 }' <<<"$BL_OUT" | env LC_ALL=C sort | tr '\n' ' ')" \
  "bl/05-brief-shipped bl/11-conflict bl/13-kept-reraised bl/14-open bl/15-unknown bl/16-off-enum pk/03-cycle-a pk/04-cycle-b "
bl_is "BL8 --verify-list shows candidate merged PRs from the cached list" \
  "$(grep -c '^  candidate: #105 https://github.com/acme/widgets/pull/105 — docs: brief-shipped work$' <<<"$BL_OUT")" "1"
bl_is "BL8 --unknown and --verify-list wrote nothing" "$(bl_sum "$T0")" "$BL_BEFORE"

# ---- BL9 (AC10) backlog-stamp: nothing without --confirm; the engine shape with it; every refusal
# exit 1 with nothing written.
T9="$(bl_tree t9)"; BL_B9="$(bl_sum "$T9")"
bl_s9() { bl_run "$1" backlog-stamp bl/14-open done --pr https://github.com/acme/widgets/pull/114 --root "$T9"; printf '%s %s' "$BL_RC" "$([ "$(bl_sum "$T9")" = "$BL_B9" ] && echo unchanged || echo written)"; }
bl_is "BL9 backlog-stamp without --confirm exits 1 and writes nothing" "$(bl_s9 "$H")" "1 unchanged"
bl_mut_check "pin AC10: the --confirm guard deleted" '  [ "$confirm" = 1 ] || {' __DELETE__ bl_s9 "1 unchanged"
rm -rf "$T9"; T9="$(bl_tree t9)"; BL_B9="$(bl_sum "$T9")"
bl_refuse() { # <label> <args...> — exit 1, stdout empty, the tree byte-unchanged
  local l="$1"; shift
  bl_run "$H" backlog-stamp "$@" --root "$T9" --confirm
  bl_is "BL9 refused: $l (exit 1, nothing written)" "$BL_RC $([ "$(bl_sum "$T9")" = "$BL_B9" ] && echo unchanged)" "1 unchanged"
}
bl_refuse "an already-done item" bl/01-done-appended done --pr https://github.com/acme/widgets/pull/1
bl_refuse "a path outside the requirements tree" .supervisor/automate/automate-2026-09-01-100000.md done --pr https://github.com/acme/widgets/pull/1
bl_refuse "an absolute home path in an argument" bl/14-open abandoned --reason "see /Users/alice/notes"
bl_refuse "an absolute home path as the item" /home/alice/proj/.supervisor/requirements/bl/14-open.md abandoned --reason gone
bl_refuse "done without a --pr" bl/14-open done
bl_refuse "an unknown stamp" bl/14-open finished --pr https://github.com/acme/widgets/pull/1
bl_refuse "kept-open without --supersedes" bl/11-conflict kept-open
bl_refuse "done_with_escalation without --owed" bl/14-open done_with_escalation --pr https://github.com/acme/widgets/pull/1
bl_refuse "abandoned without --reason" bl/14-open abandoned
bl_refuse "a flag another stamp owns (done with --reason)" bl/14-open done --pr https://github.com/acme/widgets/pull/1 --reason x
bl_refuse "a --pr that is not an https url" bl/14-open done --pr widgets#1
bl_refuse "a --date that is not YYYY-MM-DD" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2026/09/01
bl_refuse "a --supersedes that is not a run_id" bl/11-conflict kept-open --supersedes 'a b'
bl_refuse "a --pr carrying an embedded newline and a heading" bl/14-open done --pr "https://github.com/acme/widgets/pull/1
## Status: done"
bl_refuse "a --pr with a space" bl/14-open done --pr "https://github.com/acme/widgets/pull/1 extra"
bl_refuse "a --pr that is not a /pull/<n> url" bl/14-open done --pr https://github.com/acme/widgets
bl_refuse "a kept-open --date later than today (it would settle future runs' rows)" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2099-01-01
bl_refuse "a --date with an impossible month" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2026-13-01
bl_refuse "a --date with no value" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date
bl_refuse "a --date that is no calendar day (February 31)" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2026-02-31
bl_refuse "a --date that is no calendar day (April 31)" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2026-04-31
bl_refuse "a --date of February 29 outside a leap year" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2025-02-29
bl_refuse "a --date of February 29 in a century non-leap year" bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 1900-02-29
bl_refuse "a control character in --reason" bl/14-open abandoned --reason "$(printf 'gone\033[2J')"
bl_refuse "a multi-line --owed" bl/14-open done_with_escalation --pr https://github.com/acme/widgets/pull/1 --owed "$(printf 'a\n## Status: done')"
bl_s9d() { bl_run "$1" backlog-stamp bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2099-01-01 --root "$T9" --confirm; printf '%s %s' "$BL_RC" "$([ "$(bl_sum "$T9")" = "$BL_B9" ] && echo unchanged || echo written)"; }
bl_mut_check "pin: the future --date refusal deleted" '      [ "$((10#${date//-/}))" -le "$((10#${today//-/}))" ]' '      : ;;' bl_s9d "1 unchanged"
rm -rf "$T9"; T9="$(bl_tree t9)"; BL_B9="$(bl_sum "$T9")"
ln -s "$T9/.supervisor/requirements/bl/14-open.md" "$T9/.supervisor/requirements/bl/18-link.md"; BL_B9="$(bl_sum "$T9")"
bl_refuse "a symlinked item" bl/18-link abandoned --reason gone
rm -f "$T9/.supervisor/requirements/bl/18-link.md"; BL_B9="$(bl_sum "$T9")"
bl_run "$H" backlog-stamp bl/14-open done --pr https://github.com/acme/widgets/pull/114 --pr https://github.com/acme/widgets/pull/115 --root "$T9" --confirm
bl_is "BL9 done --confirm appends closeout's line set: sentinel, ## Status: done, Completed, the done/ brief, one PR line per --pr" \
  "$BL_RC|$(tail -n 7 "$T9/.supervisor/requirements/bl/14-open.md" | sed -E 's/^(- \*\*Completed:\*\* )[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/\1<ts>/')" \
  "0|
<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** <ts>
- **Brief:** .supervisor/jobs/done/2026-09-20-bl-14-open.md
- **PR:** https://github.com/acme/widgets/pull/114
- **PR:** https://github.com/acme/widgets/pull/115"
bl_run "$H" item-state bl/14-open --root "$T9"
bl_is "BL9 the stamped item now reads done" "$(cut -f1 <<<"$BL_OUT")" "done"
bl_run "$H" backlog-stamp bl/17-in-flight done_with_escalation --pr https://github.com/acme/widgets/pull/117 --owed "the docs pass" --root "$T9" --confirm
bl_is "BL9 done_with_escalation: the same lines under its own heading, Brief unknown when no done/ brief, plus Owed" \
  "$BL_RC|$(tail -n 6 "$T9/.supervisor/requirements/bl/17-in-flight.md" | sed -E 's/^(- \*\*Completed:\*\* ).*$/\1<ts>/')" \
  "0|<!-- loomwright:requirement-closeout -->
## Status: done_with_escalation
- **Completed:** <ts>
- **Brief:** unknown
- **PR:** https://github.com/acme/widgets/pull/117
- **Owed:** the docs pass"
bl_run "$H" backlog-stamp bl/16-off-enum abandoned --reason "superseded by bl/14-open" --root "$T9" --confirm
bl_is "BL9 abandoned: ## Status: done_with_escalation — ABANDONED (<reason>), and the item reads abandoned" \
  "$BL_RC|$(tail -n 1 "$T9/.supervisor/requirements/bl/16-off-enum.md")|$(bl_run "$H" item-state bl/16-off-enum --root "$T9"; cut -f1 <<<"$BL_OUT")" \
  "0|## Status: done_with_escalation — ABANDONED (superseded by bl/14-open)|abandoned"
bl_run "$H" backlog-stamp bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2026-09-01 --root "$T9" --confirm
bl_is "BL9 kept-open writes the D-conflict-1 marker, which settles the conflict" \
  "$BL_RC|$(tail -n 1 "$T9/.supervisor/requirements/bl/11-conflict.md")|$(bl_run "$H" item-state bl/11-conflict --root "$T9"; cut -f1 <<<"$BL_OUT")" \
  "0|- **Kept open:** 2026-09-01 — supersedes automate-2026-09-01-100000|open"
for bl_i in 1 2 3 4; do
  BL_FIXDIR="$BL_FIX" bash "$H" backlog-stamp bl/12-kept-open kept-open --supersedes "automate-2026-10-2${bl_i}-100000" --root "$T9" --confirm >/dev/null 2>&1 &
done
wait
bl_is "BL9 four concurrent stamps on one item keep all four lines and leave no lock behind (one writer at a time)" \
  "$(grep -c '^- \*\*Kept open:\*\* ' "$T9/.supervisor/requirements/bl/12-kept-open.md") $(find "$T9/.supervisor" -name '*.lock' | wc -l | tr -d ' ')" "5 0"
# The lock must not rest on the `mkdir` command: uutils mkdir (ubuntu-latest's default) can exit 0 for
# two racers, and two holders lose a line, which is how the leg above flaked with `4 0`. The shim exits
# 0 whenever the directory exists, so that behaviour is present every time, on every platform.
mkdir -p "$T9/false-win-bin"
printf '#!/bin/sh\n"%s" "$@" 2>/dev/null && exit 0\nfor a in "$@"; do l="$a"; done\n[ -d "$l" ] && exit 0\nexit 1\n' "$(command -v mkdir)" > "$T9/false-win-bin/mkdir"
chmod +x "$T9/false-win-bin/mkdir"
for bl_i in 5 6 7 8; do
  PATH="$T9/false-win-bin:$PATH" BL_FIXDIR="$BL_FIX" bash "$H" backlog-stamp bl/12-kept-open kept-open --supersedes "automate-2026-10-2${bl_i}-100000" --root "$T9" --confirm >/dev/null 2>&1 &
done
wait
bl_is "BL9 a mkdir that lets racers win changes nothing: four more concurrent stamps keep all four lines" \
  "$(grep -c '^- \*\*Kept open:\*\* ' "$T9/.supervisor/requirements/bl/12-kept-open.md") $(find "$T9/.supervisor" -name '*.lock' | wc -l | tr -d ' ')" "9 0"
bl_is "BL9 no stamp wrote an absolute home path" "$(grep -rlE '/(Users|home)/' "$T9/.supervisor/requirements" | wc -l | tr -d ' ')" "0"
# The home-path scan covers every written / item-naming value but NOT the --root locator: an absolute
# checkout under /Users or /home is the normal case. `hr+/home/alice/proj` is home-shaped (the `+`
# before /home is a non-word char, so the scan's regex matches it), unlike a mktemp root.
TH="$(bl_tree 'hr+/home/alice/proj')"
bl_is "BL9 the home-shaped fixture root really matches the scan's regex" \
  "$(printf '%s\n' "$TH" | grep -cE '(^|[^A-Za-z0-9._-])/(Users|home)/[^/]')" "1"
bl_run "$H" backlog-stamp bl/14-open done --pr https://github.com/acme/widgets/pull/114 --root "$TH" --confirm
bl_is "BL9 an explicit --root under a home-shaped path stamps (exit 0, the item reads done, no home path written)" \
  "$BL_RC|$(bl_run "$H" item-state bl/14-open --root "$TH"; cut -f1 <<<"$BL_OUT")|$(grep -rlE '/(Users|home)/' "$TH/.supervisor/requirements" | wc -l | tr -d ' ')" "0|done|0"
BL_BH="$(bl_sum "$TH")"
bl_run "$H" backlog-stamp bl/16-off-enum abandoned --reason "see /Users/alice/notes" --root "$TH" --confirm
bl_is "BL9 refused: a home path in --reason even when --root is home-shaped (exit 1, nothing written)" \
  "$BL_RC $([ "$(bl_sum "$TH")" = "$BL_BH" ] && echo unchanged)|$BL_ERR" "1 unchanged|backlog-stamp: refused — an absolute home path in an argument (nothing written)"
bl_sh1() { bl_run "$1" backlog-stamp bl/16-off-enum abandoned --reason gone --root "$TH"; head -n 1 <<<"$BL_OUT"; }
bl_mut_check "pin: the home-path scan also reads --root (an absolute home checkout is refused)" \
  "  a=\"\$(printf '%s\n' \"\$given\" \"\$mode\" \"\$prs\"" "  a=\"\$(printf '%s\n' \"\$root\" \"\$given\" \"\$mode\" \"\$prs\" \"\$owed\" \"\$reason\" \"\$sup\" \"\$date\")\"" \
  bl_sh1 "backlog-stamp: would append to .supervisor/requirements/bl/16-off-enum.md:"
bl_sh2() { bl_run "$1" backlog-stamp bl/16-off-enum abandoned --reason "see /Users/alice/notes" --root "$TH"; printf '%s|%s' "$BL_RC" "$BL_OUT"; }
bl_mut_check "pin: the home-path scan disabled (a home path in --reason is written)" \
  "  a=\"\$(printf '%s\n' \"\$given\" \"\$mode\" \"\$prs\"" "  a=''" bl_sh2 "1|"

# ---- BL10 the readers never write: a full board + every item-state over the tree leaves it byte-unchanged.
BL_B10="$(bl_sum "$T0")"
bl_run "$H" backlog --root "$T0"; bl_run "$H" backlog --json --root "$T0"; bl_run "$H" item-state bl/03-parked --root "$T0"
bl_is "BL10 item-state and backlog wrote nothing under the tree" "$(bl_sum "$T0")" "$BL_B10"
bl_is "BL10 no printed row carries an absolute path" "$(grep -c "$BL" <<<"$BL_DOC")" "0"

# ---- BL11 lanes.tsv gets the same separator scrub as merged.tsv / open.tsv: a lane-status field
# carrying a raw \037 (the prep awk's own field separator) reads as a space, never a field split.
mkdir -p "$BL/fixus/gh"; cp "$BL_FIX/gh/merged.json" "$BL_FIX/gh/open.json" "$BL/fixus/gh/"
jq '(.lanes[] | select(.item | test("bl/10-lane")) | .state) |= "run\u001fning"' "$BL_FIX/lane-status.json" > "$BL/fixus/lane-status.json"
bl_us() { BL_FIXDIR_OVR="$BL/fixus" bl_run "$1" item-state bl/10-lane --root "$T0"; printf '%s' "$BL_OUT"; }
bl_is "BL11 a \\037 in a lane-status field is scrubbed to a space (the lane claim still reads whole)" \
  "$(bl_us "$H")" "in_flight	bl/10-lane	lane L2 (run ning) from lane-status"
bl_mut_check "lanes.tsv scrub removed" '  "$JQ" -r '"'"'def scrub: tostring | gsub(' '  "$JQ" -r '"'"'def scrub: tostring;' bl_us "in_flight	bl/10-lane	lane L2 (run ning) from lane-status"

# ---- BL12 (pa25 AC1) backlog --offline: no gh call and no right-size call in any mode; the document
# is the gh-failure read (github unverified, right-size unknown) with every item in the same state.
# The comparison projection drops only right_size (the failing-gh leg still runs the real right-size).
bl_proj() { jq -c '[.items[] | del(.right_size)], .stale_runs, .totals, .item_count' <<<"$1"; }
BL_GH_FAIL=1 bl_run "$H" backlog --json --root "$T0"; BL_FAILDOC="$BL_OUT"
bl_s12() {
  : > "$BL/gh.log"; : > "$BL/rs.log"
  LOOMWRIGHT_RIGHT_SIZE_BIN="$BL/bin/rsize" bl_run "$1" backlog --json --offline --root "$T0"
  printf '%s %s %s %s %s' "$BL_RC" "$(grep -c . "$BL/gh.log")" "$(grep -c . "$BL/rs.log")" \
    "$(jq -r '"\(.github) \(.right_size) \([.items[] | select(.right_size != "unknown")] | length)"' <<<"$BL_OUT")" \
    "$([ "$(bl_proj "$BL_OUT")" = "$(bl_proj "$BL_FAILDOC")" ] && echo same-as-gh-failure)"
}
bl_is "BL12 --offline: exit 0, zero gh calls, zero right-size calls, github unverified, right_size unknown on the doc and every item, and every item's state/evidence equal the failing-gh read" \
  "$(bl_s12 "$H")" "0 0 0 unverified unknown 0 same-as-gh-failure"
bl_is "BL12 the failing-gh baseline really is the failure path (the comparison is not vacuous)" \
  "$(jq -r '"\(.github) \(.item_count)"' <<<"$BL_FAILDOC")" "unverified 24"
bl_mut_check "pin pa25 AC1: the --offline guard removed from _bl_context (both gh reads run)" \
  '  if [ "$offline" = 1 ]; then rc1=1; rc2=1' '  if false; then :' bl_s12 "0 0 0 unverified unknown 0 same-as-gh-failure"
bl_mut_check "pin pa25 AC1: the --offline guard removed from the right-size job" \
  '  if [ "$offline" = 1 ]; then rsz=unknown' '  if false; then :' bl_s12 "0 0 0 unverified unknown 0 same-as-gh-failure"
# every mode accepts it, with zero gh calls; the table header and --verify-list say unverified
bl_off() { : > "$BL/gh.log"; bl_run "$H" backlog "$@" --offline --root "$T0"; printf '%s:%s' "$BL_RC" "$(grep -c . "$BL/gh.log")"; }
bl_is "BL12 --offline is accepted with --state, --unknown, --verify-list [<item>] and the plain table (exit 0, zero gh calls each)" \
  "$(bl_off --json --state conflict) $(bl_off --unknown) $(bl_off --verify-list) $(bl_off --verify-list bl/14-open) $(bl_off)" "0:0 0:0 0:0 0:0 0:0"
bl_off --state conflict --json >/dev/null
bl_is "BL12 --offline --state keeps whole-tree totals and filters rows" \
  "$(jq -r '"\(.state_filter) \(.totals | add) \([.items[].state] | unique | join(",")) \(.items | length)"' <<<"$BL_OUT")" "conflict 24 conflict $(jq -r '.totals.conflict' <<<"$BL_FAILDOC")"
bl_run "$H" backlog --offline --root "$T0"
bl_is "BL12 the --offline table header reads github: unverified, right-size: unknown" "$(head -n1 <<<"$BL_OUT")" "backlog: 24 items — github: unverified — right-size: unknown"
bl_run "$H" backlog --verify-list bl/14-open --offline --root "$T0"
bl_is "BL12 --verify-list --offline says every candidate is unverified" \
  "$([ "$(grep -c '^  candidate: unverified ' <<<"$BL_OUT")" = "$(grep -c '^verify	' <<<"$BL_OUT")" ] && [ "$(grep -c '^verify	' <<<"$BL_OUT")" -gt 0 ] && echo all-unverified)" "all-unverified"
bl_run "$H" item-state bl/14-open --offline --root "$T0"
bl_is "BL12 item-state takes no --offline flag (usage error, exit 1, nothing on stdout)" "$BL_RC|$BL_OUT" "1|"

# ---- BL13 (dismissed-followups/01 AC1) a follow-up dismissed draft reads `follow_up` with an age. The
# fixture draft has the REAL shape (`## Status: proposed` first, then `- **Decision:** follow-up`); its
# run's ledger holds one follow-up row at 2026-10-20T10:00:00Z. LOOMWRIGHT_FOLLOWUP_NOW (followup.sh's
# clock seam) pins the clock at 2026-10-25T12:00:00Z (epoch 1792929600) ⇒ 5 whole days.
BL_FUN=1792929600
BL_FU="proposed/automate-2026-10-12-100000--17-in-flight-0a1b2c--dismissed-5e6f7a8b"
BL_FUEV="run automate-2026-10-12-100000, PR https://github.com/acme/widgets/pull/117"
bl_fu() { LOOMWRIGHT_FOLLOWUP_NOW="$BL_FUN" bl_run "$1" item-state "$BL_FU" --root "$2"; printf '%s' "$BL_OUT"; }
bl_is "BL13 a real-shape follow-up draft reads follow_up, aged from its ledger row's ts" \
  "$(bl_fu "$H" "$T0")" "follow_up	$BL_FU	follow-up 5d — $BL_FUEV"
bl_is "BL13 the fixture draft really has the real shape (## Status: proposed is its first status line)" \
  "$(grep -m1 '^## Status:' "$T0/.supervisor/requirements/$BL_FU.md")" "## Status: proposed"
bl_fu_state() { bl_fu "$1" "$T0" | cut -f1; }
bl_mut_check "pin AC1: the BL_S=follow_up assignment deleted" '    BL_S=follow_up' __DELETE__ bl_fu_state "follow_up"
# the follow_up test moved below the proposed test (one-line form of the move): a real draft reads proposed
bl_mut_check "pin AC1: follow_up decided AFTER the proposed first-status test" '  elif [ -n "$P_FU" ]; then' \
  '  elif [[ "$fs" =~ $_BL_RE_PROPOSED ]]; then BL_S=proposed; BL_E="$fs"; elif [ -n "$P_FU" ]; then' bl_fu_state "follow_up"
bl_s13k() { bl_run "$1" backlog --json --offline --root "$T0"; jq -r '.totals | keys_unsorted | join(" ")' <<<"$BL_OUT"; }
bl_mut_check "pin AC1: follow_up dropped from _BL_STATES (the totals key order)" \
  '_BL_STATES="done abandoned parked proposed follow_up brief_shipped' \
  '_BL_STATES="done abandoned parked proposed brief_shipped merged_unstamped pr_open in_flight conflict open unknown"' \
  bl_s13k "done abandoned parked proposed follow_up brief_shipped merged_unstamped pr_open in_flight conflict open unknown"
# no ledger ⇒ the draft's mtime, labelled. touch -t is POSIX (TZ=UTC pins its reading): 2026-10-15T00:00Z ⇒ 10d.
T13="$(bl_tree t13)"; BL_FUF="$T13/.supervisor/requirements/$BL_FU.md"
rm -f "$T13/.supervisor/automate/automate-2026-10-12-100000.dismissed-decisions"; TZ=UTC touch -t 202610150000 "$BL_FUF"
bl_is "BL13 no ledger ⇒ aged from the draft's mtime, labelled (mtime)" "$(bl_fu "$H" "$T13")" "follow_up	$BL_FU	follow-up 10d (mtime) — $BL_FUEV"
bl_s13m() { bl_fu "$1" "$T13" | cut -f3; }
bl_mut_check "pin AC1: the (mtime) label dropped" '    t, label = None, " (mtime)"' '    t, label = None, " ()"' bl_s13m "follow-up 10d (mtime) — $BL_FUEV"
# a readable ledger with no row for this draft ⇒ mtime too
printf 'other--dismissed-00000000.md\tfollow-up\t2026-10-01T00:00:00Z\n' > "$T13/.supervisor/automate/automate-2026-10-12-100000.dismissed-decisions"
bl_is "BL13 a readable ledger with no follow-up row for the draft ⇒ mtime" "$(bl_fu "$H" "$T13" | cut -f3)" "follow-up 10d (mtime) — $BL_FUEV"
# an EXISTING but unreadable ledger (a directory: unreadable even to root) ⇒ mtime, and it says so
rm -f "$T13/.supervisor/automate/automate-2026-10-12-100000.dismissed-decisions"; mkdir "$T13/.supervisor/automate/automate-2026-10-12-100000.dismissed-decisions"
bl_is "BL13 an unreadable ledger ⇒ aged from mtime, and the evidence says the ledger was unreadable" \
  "$(bl_fu "$H" "$T13")" "follow_up	$BL_FU	follow-up 10d (mtime — ledger unreadable) — $BL_FUEV"
bl_s13u() { bl_fu "$1" "$T13" | cut -f3; }
bl_mut_check "pin AC1: the unreadable-ledger label dropped" '        label = " (mtime — ledger unreadable)"' '        label = " (mtime — ledger)"' \
  bl_s13u "follow-up 10d (mtime — ledger unreadable) — $BL_FUEV"
# an undecided draft (same shape, Decision undecided) and the hand-written proposals still read proposed;
# a follow-up draft below proposed/ (not directly under it) is no follow-up draft; a done stamp still wins
BL_UND="proposed/automate-2026-10-12-100000--17-in-flight-0a1b2c--dismissed-9c9c9c9c"
sed 's/^- \*\*Decision:\*\* follow-up$/- **Decision:** undecided/' "$T0/.supervisor/requirements/$BL_FU.md" > "$T13/.supervisor/requirements/$BL_UND.md"
mkdir -p "$T13/.supervisor/requirements/proposed/sub"
cp "$T0/.supervisor/requirements/$BL_FU.md" "$T13/.supervisor/requirements/proposed/sub/x--dismissed-1f1f1f1f.md"
BL_DN="proposed/automate-2026-10-12-100000--17-in-flight-0a1b2c--dismissed-d0d0d0d0"
{ cat "$T0/.supervisor/requirements/$BL_FU.md"; printf '\n## Status: done\n'; } > "$T13/.supervisor/requirements/$BL_DN.md"
LOOMWRIGHT_FOLLOWUP_NOW="$BL_FUN" bl_run "$H" backlog --json --offline --root "$T13"
bl_is "BL13 undecided draft, hand-written proposals, a nested draft and a done-stamped follow-up draft read proposed / proposed / proposed / proposed / done" \
  "$(jq -r --arg u "$BL_UND" --arg d "$BL_DN" '[.items[] | select(.item == $u or .item == "proposed/bl-draft" or .item == "bl/04-proposed" or .item == "proposed/sub/x--dismissed-1f1f1f1f" or .item == $d)
      | (if .item == $u then "undecided" elif .item == $d then "done-stamped" else .item end) + "=" + .state] | sort | join(" ")' <<<"$BL_OUT")" \
  "bl/04-proposed=proposed done-stamped=done proposed/bl-draft=proposed proposed/sub/x--dismissed-1f1f1f1f=proposed undecided=proposed"
bl_is "BL13 totals still sum to item_count with follow_up in the set (27 items: the fixture's 24 + 3 drafts)" \
  "$(jq -r '"\(.totals | add) \(.item_count) \(.totals.follow_up) \(.totals.proposed)"' <<<"$BL_OUT")" "27 27 1 4"
LOOMWRIGHT_FOLLOWUP_NOW="$BL_FUN" bl_run "$H" backlog --json --offline --state follow_up --root "$T13"
bl_is "BL13 --state follow_up lists only the follow-up draft, totals whole-tree" \
  "$(jq -r '"\([.items[].item] | join(",")) \(.totals | add) \(.state_filter)"' <<<"$BL_OUT")" "$BL_FU 27 follow_up"
bl_is "BL13 the board never printed an absolute path for a follow-up row" "$(grep -c "$BL" <<<"$BL_OUT")" "0"
# ---- BL14 a merged-PR read of exactly _BL_PR_LIMIT entries may be truncated ⇒ github: unverified
mkdir -p "$BL/fix14" && cp -R "$BL_FIX/." "$BL/fix14/"
jq -n '[range(0; 1000) | {number: (. + 5000), url: ("https://github.com/acme/widgets/pull/" + ((. + 5000) | tostring)), title: "old", headRefName: ("old-" + tostring)}]' > "$BL/fix14/gh/merged.json"
BL_FIXDIR_OVR="$BL/fix14" bl_run "$H" backlog --json --root "$T0"
bl_is "BL14 a merged-PR list as long as the read's --limit ⇒ github unverified (it may be truncated), never verified" "$(jq -r '.github' <<<"$BL_OUT")" "unverified"
jq '.[0:999]' "$BL/fix14/gh/merged.json" > "$BL/fix14/gh/m" && mv "$BL/fix14/gh/m" "$BL/fix14/gh/merged.json"
BL_FIXDIR_OVR="$BL/fix14" bl_run "$H" backlog --json --root "$T0"
bl_is "BL14 one entry under the --limit ⇒ github verified" "$(jq -r '.github' <<<"$BL_OUT")" "verified"
# ---- BL15 a backlog-stamp killed while it holds the item lock removes that lock (its exit trap)
. "$HERE/wait-lib.sh"
# the cp stub parks on a gate file (clock-bounded) instead of a fixed sleep: the lock is held for as
# long as the leg needs, and the gate opens only after the TERM is sent
T15="$(bl_tree t15)"; mkdir -p "$BL/slowbin"; BL_GATE15="$BL/slowbin/gate"; BL_CPPID15="$BL/slowbin/cp.pid"
printf '#!/usr/bin/env bash
echo $$ > %s
end=$(( $(date +%%s) + 30 ))
while [ ! -e %s ] && [ "$(date +%%s)" -lt "$end" ]; do sleep 0.05; done
exec %s "$@"
' "$BL_CPPID15" "$BL_GATE15" "$(command -v cp)" > "$BL/slowbin/cp"; chmod +x "$BL/slowbin/cp"
PATH="$BL/slowbin:$PATH" bash "$H" backlog-stamp bl/14-open abandoned --reason gone --root "$T15" --confirm >/dev/null 2>&1 &
BL_PID=$!; BL_LK15="$T15/.supervisor/requirements/bl/14-open.md.backlog-stamp.lock"
# wait on the cp stub's pid file, not the lock: the lock appears just before the traps are set, and
# the stub starts only after them, so a TERM sent from here always finds the trap in place
wait_for_cmd 10 test -s "$BL_CPPID15"
BL_HELD="$([ -e "$BL_LK15" ] && echo held || echo never)"
# bash runs the TERM trap only once its foreground child returns, so the gate opens after the kill
# and before the wait (the fixed sleep this replaces released the child the same way, by time)
kill -TERM "$BL_PID" 2>/dev/null; : > "$BL_GATE15"; wait "$BL_PID" 2>/dev/null
[ -s "$BL_CPPID15" ] && wait_for_pid_gone "$(cat "$BL_CPPID15")" 35
bl_is "BL15 a TERM while backlog-stamp holds the lock ⇒ the lock is removed (a later stamp is not refused)" \
  "$BL_HELD $([ -e "$BL_LK15" ] && echo left || echo removed)" "held removed"
# ---- BL16 positive control for the calendar check: a leap-year February 29 is stamped
T16="$(bl_tree t16)"
bl_run "$H" backlog-stamp bl/11-conflict kept-open --supersedes automate-2026-09-01-100000 --date 2024-02-29 --root "$T16" --confirm
bl_is "BL16 kept-open --date 2024-02-29 (a leap day) ⇒ stamped" "$BL_RC $(grep -c '^- \*\*Kept open:\*\* 2024-02-29 ' "$T16/.supervisor/requirements/bl/11-conflict.md")" "0 1"
# ---- BL17 a refusal that released the lock never removes a lock another stamp took afterwards:
# cp fails (the write-failed path), and an rm stub plants a foreign lock right after our release —
# the exit trap must leave it alone
T17="$(bl_tree t17)"; mkdir -p "$BL/bin17"; BL_LK17="$T17/.supervisor/requirements/bl/14-open.md.backlog-stamp.lock"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BL/bin17/cp"
printf '#!/usr/bin/env bash
%s "$@"; rc=$?
for a in "$@"; do
  case "$a" in *.backlog-stamp.lock) [ -e %s ] || { echo foreign-holder > "$a"; : > %s; } ;; esac
done
exit $rc
' "$(command -v rm)" "$BL/bin17/planted" "$BL/bin17/planted" > "$BL/bin17/rm"
chmod +x "$BL/bin17/cp" "$BL/bin17/rm"
PATH="$BL/bin17:$PATH" bash "$H" backlog-stamp bl/14-open abandoned --reason gone --root "$T17" --confirm >"$BL/out17" 2>&1; BL_RC17=$?
bl_is "BL17 write failed ⇒ exit 1, the item unchanged, and a lock planted after our release survives our exit" \
  "$BL_RC17 $(grep -c 'write failed' "$BL/out17") $(grep -c 'ABANDONED' "$T17/.supervisor/requirements/bl/14-open.md") $(cat "$BL_LK17" 2>/dev/null || echo removed)" \
  "1 1 0 foreign-holder"
rm -rf "$BL"
