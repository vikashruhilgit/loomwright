# ==================================================================================================
# The evidence-file reader of the shared Validation reader (_lanes_validation_rows in readiness.sh): a
# `## Validation` step the PR body leaves NOT-RUN (an unreadable body included) is looked up in the
# committed `docs/evidence/*.md` files of the PR. The PR body is read first and its PASS / FAIL is
# final; this module only ever adds to a NOT-RUN row's evidence text, or replaces that row's status.
# validation-gate and lane-readiness reach it only through that one reader (no second parser).
#
# The declared verdict line — the ONLY thing read from an evidence file:
#   `Verdict: <PASS|FAIL|NOT-RUN> for Validation <n>`   a whole line at column 0, outside any ``` / ~~~
#   fence, trailing whitespace allowed; one line per step, a file may carry several. A `Verdict:` line
#   inside a fence is output, never a declaration; a line that starts `Verdict:` but does not match the
#   form declares nothing. The step and the result are never inferred from headings or from words in
#   the output: a declared PASS whose pasted output says FAIL (a fixture expected to fail) is a PASS.
# Candidates: the `docs/evidence/*.md` files at the PR head (the directory listing at headRefOid) that
#   are ALSO in the PR's changed-file list (`gh pr view --json headRefOid,files`) — an older file the PR
#   does not add or change is never used. Several candidates declaring the same step: the worst declared
#   result wins (FAIL over NOT-RUN over PASS), naming its file. A declared PASS in a file with no fenced
#   output reads NOT-RUN (`declared but no output`).
# Fail CLOSED: no PR, a PR value that is not a https://github.com/<owner>/<repo>/pull/<n> URL, an
#   unreadable changed-file list, directory listing or candidate file, or a candidate name outside
#   [A-Za-z0-9._-] makes EVERY looked-up step NOT-RUN with the reason (an unread file might declare
#   FAIL, so it can never count). HONEST LIMIT: `gh pr view --json files` may cap the changed-file list
#   on a very large PR; a file missed that way leaves its step NOT-RUN, never a false PASS. GitHub
#   Enterprise hosts are not parsed (fail CLOSED).
# gh call shapes (all through the one seam, $LANES_GH, stdin from /dev/null — the caller reads its rows
# from a pipe): `pr view <pr> --json headRefOid,files`; `api repos/<o>/<r>/contents/docs/evidence?ref=<sha>`
# (skipped when the PR changes no docs/evidence/*.md file); `api -H 'Accept: application/vnd.github.raw'
# repos/<o>/<r>/contents/<path>?ref=<sha>` per candidate. Called lazily: a PR whose body evidences every
# step makes none of them. The results are cached in <evdir> (the caller's temp dir), so the calls run
# once per reader run however many steps are looked up.
# Every NOT-RUN text ends in the remedy: add the declared verdict line and the fenced output to the
# step's docs/evidence/ file — never "paste into the PR body". Texts hold no tab, `|` or newline.

_LANES_EV_PASS="declared PASS with fenced output in "   # the PASS text's prefix; validation-gate's `ok` line reads the file after it

# _lanes_ev_set <evdir> <state> <reason> — the cache's verdict line: closed (unreadable) | none (no
# candidate) | ok (declarations parsed into <evdir>/decl).
_lanes_ev_set() { printf '%s\t%s\n' "$2" "$3" > "$1/state" 2>/dev/null; }

# _lanes_ev_parse <file> <path> — one TSV row per declared verdict line: n<TAB>verdict<TAB>path<TAB>fenced
# <TAB>failword (fenced: the file holds a fence; failword: a fenced line shows the word FAIL). A file with
# no declared line prints one row with n `-`, so the caller can name it.
_lanes_ev_parse() {
  awk -v p="$2" '
    { wasin = inf; fl = ($0 ~ /^[ \t]*(```|~~~)/) }
    fl { x = $0; sub(/^[ \t]*/, "", x); c = substr(x, 1, 3); if (!inf) { inf = 1; fc = c; fen = 1 } else if (c == fc) inf = 0; next }
    wasin { if ($0 ~ /(^|[^A-Za-z0-9_])FAIL([^A-Za-z0-9_]|$)/) fw = 1; next }
    /^Verdict: (PASS|FAIL|NOT-RUN) for Validation [0-9]+[ \t\r]*$/ { k++; d[k] = ($5 + 0) "\t" $2 }
    END { if (!k) print "-\t-\t" p "\t" (fen + 0) "\t" (fw + 0)
          for (i = 1; i <= k; i++) print d[i] "\t" p "\t" (fen + 0) "\t" (fw + 0) }' "$1"
}

# _lanes_ev_load <evdir> <pr> — fills the cache once: <evdir>/state, <evdir>/decl. Always returns 0; a
# failure is a `closed` state, never a missing one.
_lanes_ev_load() {
  local d="$1" pr="$2" re slug view sha lst f i=0 sha7
  re='^https://github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/pull/[0-9]+$'
  mkdir -p "$d" 2>/dev/null && : > "$d/decl" 2>/dev/null || return 0
  if [ -z "$pr" ]; then _lanes_ev_set "$d" closed "evidence files unreadable: no PR recorded"; return 0; fi
  if ! [[ $pr =~ $re ]]; then _lanes_ev_set "$d" closed "evidence files unreadable: the PR value is not a https://github.com/<owner>/<repo>/pull/<n> URL"; return 0; fi
  slug="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  view="$("$LANES_GH" pr view "$pr" --json headRefOid,files 2>/dev/null </dev/null)" || view=""
  jq -e 'type == "object" and (.headRefOid | type == "string" and test("^[0-9a-f]{7,40}$")) and (.files | type == "array")' >/dev/null 2>&1 <<<"$view" || { _lanes_ev_set "$d" closed "evidence files unreadable: the PR's changed-file list ($pr)"; return 0; }   # ev-closed: unreadable list
  sha="$(jq -r '.headRefOid // empty' <<<"$view" 2>/dev/null)"; sha7="${sha:0:7}"
  jq -r '.files[]? | .path // empty' <<<"$view" > "$d/changed" 2>/dev/null
  if ! grep -qE '^docs/evidence/[^/]+\.md$' "$d/changed" 2>/dev/null; then
    _lanes_ev_set "$d" none "the PR adds or changes no docs/evidence/*.md file"; return 0
  fi
  lst="$("$LANES_GH" api "repos/$slug/contents/docs/evidence?ref=$sha" 2>/dev/null </dev/null)" || lst=""
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$lst"; then
    _lanes_ev_set "$d" closed "evidence files unreadable: the docs/evidence/ listing at $sha7"; return 0
  fi
  jq -r '.[] | select(.type == "file") | .path // empty' <<<"$lst" 2>/dev/null | grep -E '^docs/evidence/[^/]+\.md$' > "$d/cand"
  grep -Fx -f "$d/changed" "$d/cand" > "$d/cand.f"; mv -f "$d/cand.f" "$d/cand"   # ev-filter: changed-only
  if [ ! -s "$d/cand" ]; then _lanes_ev_set "$d" none "the PR adds or changes no docs/evidence/*.md file at $sha7"; return 0; fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in *[!A-Za-z0-9._/-]*) _lanes_ev_set "$d" closed "evidence files unreadable: a file name outside A-Z a-z 0-9 . _ - in docs/evidence/"; return 0 ;; esac
    i=$((i + 1)); : > "$d/f.$i"
    "$LANES_GH" api -H 'Accept: application/vnd.github.raw' "repos/$slug/contents/$f?ref=$sha" > "$d/f.$i" 2>/dev/null </dev/null || { _lanes_ev_set "$d" closed "evidence files unreadable: $f at $sha7"; return 0; }   # ev-read: content
    _lanes_ev_parse "$d/f.$i" "$f" >> "$d/decl" 2>/dev/null || { _lanes_ev_set "$d" closed "evidence files unreadable: $f could not be parsed"; return 0; }
  done < "$d/cand"
  _lanes_ev_set "$d" ok ""
  return 0
}

# _lanes_ev_step <evdir> <pr> <n> — ONE line `<PASS|FAIL|NOT-RUN><TAB><text>` for Validation step <n>,
# loading the cache on first use. PASS text: `declared PASS with fenced output in <path>`; FAIL / NOT-RUN
# texts name the file (or the reason no file counts), every NOT-RUN one ending in the remedy.
_lanes_ev_step() {
  local d="$1" pr="$2" n="$3" st why fix fscan
  [ -s "$d/state" ] || _lanes_ev_load "$d" "$pr"
  fix=" — add \`Verdict: PASS for Validation $n\` and the fenced output to the step's docs/evidence/ file in this PR"
  IFS="$(printf '\t')" read -r st why < "$d/state" 2>/dev/null || st=""
  case "$st" in
    ok) ;;
    none) printf 'NOT-RUN\t%s%s\n' "$why" "$fix"; return 0 ;;
    closed) printf 'NOT-RUN\t%s%s\n' "$why" "$fix"; return 0 ;;
    *) printf 'NOT-RUN\t%s%s\n' "evidence files unreadable: no scratch dir" "$fix"; return 0 ;;
  esac
  # A declared verdict is the file's statement: the FAIL scan of its output (the PR-body rule) is on by
  # default and switched off here — output words never decide a declared step.
  fscan=1
  fscan=0   # ev-exempt: declared verdict outranks output words
  awk -F'\t' -v n="$n" -v fscan="$fscan" -v pp="$_LANES_EV_PASS" -v fix="$fix" '
    $1 == "-" { nd = nd (nd == "" ? "" : ", ") $3 ": no declared verdict line"; next }
    $1 + 0 != n + 0 { next }
    { if ($2 == "PASS") { if (!$4) { r = 2; t = $3 ": declared but no output" fix }
                          else if (fscan && $5) { r = 3; t = $3 ": fenced output shows FAIL" }
                          else { r = 1; t = pp $3 } }
      else if ($2 == "FAIL") { r = 3; t = $3 ": declared FAIL" }
      else { r = 2; t = $3 ": declared NOT-RUN" fix }
      if (r > w) { w = r; wt = t } }
    END { if (w == 3) print "FAIL\t" wt
          else if (w == 2) print "NOT-RUN\t" wt
          else if (w == 1) print "PASS\t" wt
          else print "NOT-RUN\tno changed docs/evidence/ file declares Validation " n (nd == "" ? "" : " (" nd ")") fix }' "$d/decl"
}
