# ---- scrub ----
ALLOW_FILE=""
load_allowlist() {
  ALLOW_FILE="$WORK/allow.lst"
  bash "$HERE/setup-memory.sh" --root "$ROOT" allowlist 2>/dev/null \
    | tr 'A-Z' 'a-z' | awk 'NF && $0 !~ /^#/' > "$ALLOW_FILE" || : > "$ALLOW_FILE"
}

RESERVED_OWNERS=' about apps blog collections contact enterprise events explore features issues login logout marketplace new notifications organizations orgs pricing pulls readme search security settings site sponsors topics trending users '

# scrub_report <path> <rule> <line|-> <with-line:0|1> — ONE hit line: push's `meta_sync: scrub
# <path>: <rule>` (with-line 0, byte-for-byte the pre-existing contract) or the scrub subcommand's
# `meta_sync: scrub-hit <path>:<line>: <rule>` (with-line 1).
scrub_report() {
  if [ "$4" = "1" ]; then echo "meta_sync: scrub-hit $1:$3: $2"; else echo "meta_sync: scrub $1: $2"; fi
}

# EMAIL_FORGE_EXEMPT — the ONE email-rule match that is not a hit: the `git` SSH user at a forge
# host in the scp-style remote form (git@github.com:owner/repo). A whole `grep -o` match must equal
# it exactly — lowercase, the trailing `:` included — so any other user, host, case or shape still
# hits. See the SCRUB header, rule email.
EMAIL_FORGE_EXEMPT='git@(github\.com|gitlab\.com|bitbucket\.org):'

# email_matches <ERE> <file> — every match of the email rule's <ERE> in <file>, one `<line>:<match>`
# per match, MINUS the exact forge SSH-remote exemption above. Exit 0 = at least one real hit, 1 =
# none, >1 = a scan error (the caller reports scan_error(email): fail closed). The -o pass appends an
# optional `:` so the exemption can see the remote's colon; `:` is in neither the local-part nor the
# host class, so this never changes which addresses match. A match starts at the leftmost
# local-part character, so `xgit@github.com:` is one match `xgit@…` and is NOT exempt.
email_matches() {
  local all="$WORK/email.all" rc
  env LC_ALL=C grep -a -i -n -o -E -e "$1:?" "$2" > "$all" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  env LC_ALL=C grep -v -E -e "^[0-9]+:${EMAIL_FORGE_EXEMPT}\$" "$all" 2>/dev/null
}

# first_match_line <i|s|e> <ERE> <file> — the 1-based number of the first line matching <ERE> (i = any
# letter case; e = the email rule: the first line holding a NON-exempt email_matches match), or `-`
# when none can be read back. Only ever called AFTER the decision grep matched, so it never decides
# a hit — it only locates one. -a: a NUL byte would otherwise make grep print "Binary file …
# matches" instead of a numbered line; only the number leaves the pipe.
first_match_line() {
  local n
  if [ "$1" = "e" ]; then
    n="$(email_matches "$2" "$3" | head -n 1 | cut -d: -f1)"
  elif [ "$1" = "i" ]; then
    n="$(env LC_ALL=C grep -a -i -n -m 1 -E -e "$2" "$3" 2>/dev/null | cut -d: -f1)"
  else
    n="$(env LC_ALL=C grep -a -n -m 1 -E -e "$2" "$3" 2>/dev/null | cut -d: -f1)"
  fi
  case "$n" in ''|*[!0-9]*) n="-" ;; esac
  printf '%s' "$n"
}

# scan_file <file> <path> [with-line:0|1] — prints one hit line per hit (scrub_report: push's
# `meta_sync: scrub <path>: <rule>` by default; with-line 1 = the scrub subcommand's `scrub-hit`
# line carrying the first matching line, `-` for whole-file rules); returns 1 when any hit. The
# hit/no-hit DECISION is the same `grep -q` in both modes — with-line only adds the line lookup.
scan_file() {
  local f="$1" p="$2" wl="${3:-0}" hits=0 L='(^|[^A-Za-z0-9_])' rule re rc icase ln
  # rule<TAB>case(i = any letter case, s = exact, e = email: any letter case minus the exact forge
  # SSH-remote exemption, decided by email_matches)<TAB>ERE
  while IFS="$TAB" read -r rule icase re; do
    case "$icase" in
      e) email_matches "$re" "$f" >/dev/null; rc=$? ;;
      i) env LC_ALL=C grep -i -E -q -e "$re" "$f" 2>/dev/null; rc=$? ;;
      *) env LC_ALL=C grep -E -q -e "$re" "$f" 2>/dev/null; rc=$? ;;
    esac
    if [ "$rc" -eq 0 ]; then
      ln="-"; [ "$wl" = "1" ] && ln="$(first_match_line "$icase" "$re" "$f")"
      scrub_report "$p" "$rule" "$ln" "$wl"; hits=1
    elif [ "$rc" -gt 1 ]; then scrub_report "$p" "scan_error($rule)" - "$wl"; hits=1
    fi
  done <<EOF
email${TAB}e${TAB}[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}
home_path${TAB}i${TAB}(^|[^A-Za-z0-9_-])/(Users|home)/[A-Za-z0-9._-]+/
token_github${TAB}s${TAB}${L}gh[pousr]_[A-Za-z0-9]{36,}
token_github_pat${TAB}s${TAB}${L}github_pat_[A-Za-z0-9_]{22,}
token_sk${TAB}s${TAB}${L}sk-[A-Za-z0-9_-]{20,}
token_slack${TAB}s${TAB}${L}xox[abp]-[A-Za-z0-9-]{10,}
token_aws${TAB}s${TAB}${L}AKIA[0-9A-Z]{16}([^A-Za-z0-9_]|\$)
EOF
  # forge slugs — URL contexts and repo fields only (see header: a bare a/b is not a slug). Both
  # extractions are case-INSENSITIVE (a host or key in any case is the same context) and the output
  # is lowercased BEFORE the sed strip, so the strip patterns only ever see lowercase. The repo key
  # and its value may be bare or wrapped in double, single or back quotes.
  local slugs="$WORK/slugs" s owner bad=0 q="[\"'\`]?"
  {
    env LC_ALL=C grep -ioE '(github\.com|gitlab\.com|bitbucket\.org)[/:](repos/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$f" 2>/dev/null \
      | tr 'A-Z' 'a-z' | sed -E 's#^[^/:]+[/:]##; s#^repos/##'
    env LC_ALL=C grep -ioE "${L}${q}repo${q}[[:space:]]*:[[:space:]]*${q}[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+" "$f" 2>/dev/null \
      | tr 'A-Z' 'a-z' | sed -E "s#^.*repo${q}[[:space:]]*:[[:space:]]*${q}##"
  } | sed -E 's#\.+$##; s#\.git$##' | tr 'A-Z' 'a-z' | env LC_ALL=C sort -u > "$slugs"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    owner="${s%%/*}"
    case "$RESERVED_OWNERS" in *" $owner "*) continue ;; esac
    # an all-dot segment is a placeholder ellipsis (github.com/.../pull), never an owner or repo
    case "$owner" in *[!.]*) : ;; *) continue ;; esac
    case "${s#*/}" in *[!.]*) : ;; *) continue ;; esac
    grep -F -x -q -e "$s" "$ALLOW_FILE" 2>/dev/null || { bad=1; break; }
  done < "$slugs"
  [ "$bad" -eq 1 ] && { scrub_report "$p" forge_slug - "$wl"; hits=1; }
  # project deny patterns — tracked DATA, handed to grep -E, never executed.
  if [ -f "$ROOT/$DENY_CONFIG" ]; then
    local n=0 pat
    while IFS= read -r pat || [ -n "$pat" ]; do
      n=$((n + 1))
      pat="${pat%$'\r'}"
      case "$pat" in ''|'#'*) continue ;; esac
      env LC_ALL=C grep -E -q -e "$pat" "$f" 2>/dev/null; rc=$?
      if [ "$rc" -eq 0 ]; then
        ln="-"; [ "$wl" = "1" ] && ln="$(first_match_line s "$pat" "$f")"
        scrub_report "$p" "deny_pattern:$n" "$ln" "$wl"; hits=1
      elif [ "$rc" -gt 1 ]; then scrub_report "$p" "deny_pattern_invalid:$n" - "$wl"; hits=1
      fi
    done < "$ROOT/$DENY_CONFIG"
  fi
  # ledger: every record's .repo must be allowlisted.
  if [ "$p" = "$LEDGER_PATH" ]; then
    local out
    if ! command -v jq >/dev/null 2>&1; then
      scrub_report "$p" "ledger_unverifiable(jq missing)" - "$wl"; hits=1
    else
      out="$(jq -R -r --arg allow "$(cat "$ALLOW_FILE")" '
              ($allow | split("\n") | map(select(length > 0))) as $a
              | select(test("^\\s*$") | not)
              | (try fromjson catch null) as $o
              | if ($o | type) == "object" and ($o.repo | type) == "string"
                   and (($o.repo | ascii_downcase) as $r | $a | any(.[]; . == $r))
                then empty else "hit" end' "$f" 2>/dev/null)"; rc=$?
      if [ "$rc" -ne 0 ]; then scrub_report "$p" ledger_unverifiable - "$wl"; hits=1
      elif [ -n "$out" ]; then scrub_report "$p" ledger_repo - "$wl"; hits=1
      fi
    fi
  fi
  [ "$hits" -eq 0 ]
}

# scrub_candidates <list: path<TAB>blob> — scans every candidate, prints every hit; 0 = clean.
scrub_candidates() {
  local p s any=0
  load_allowlist
  while IFS="$TAB" read -r p s; do
    [ -n "$p" ] || continue
    g cat-file blob "$s" > "$WORK/scan.blob" 2>/dev/null || { scrub_report "$p" unreadable - 0; any=1; continue; }
    scan_file "$WORK/scan.blob" "$p" || any=1
  done < "$1"
  [ "$any" -eq 0 ]
}

