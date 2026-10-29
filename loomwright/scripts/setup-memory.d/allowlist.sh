# ---- allowlist --------------------------------------------------------------

ALLOWLIST=""
ALLOWLIST_SOURCE="none"

# ORIGIN: ONE READ, ONE NORMALISATION. origin's owner/repo (the layer-4 default) and its HOST (the
# request file's github.com gate) both come from ONE `git remote get-url origin` per resolution
# (resolve_origin) and ONE URL-shape classification (parse_remote_url). They used to be two reads
# through two separate case ladders, so a new URL form taught to one parser could silently disagree
# with the other — the slug saying "acme/widget" while the host said "not github.com", or worse the
# reverse. One ladder makes that disagreement structurally impossible.
ORIGIN_SLUG=""
ORIGIN_HOST=""
PARSED_SLUG=""
PARSED_HOST=""

# parse_remote_url <url> — classify the URL ONCE (filesystem path | scheme | scp | scheme-less) and
# set, in the CURRENT shell, PARSED_HOST (lower-cased, or empty) and PARSED_SLUG (`owner/repo`, or
# empty). Handles `https://[user[:pw]@]host[:port]/…`, `ssh://git@host[:port]/…`, the scp form
# `[user@]host:owner/repo` and a scheme-less `host/owner/repo`; strips a trailing `.git`. The slug is
# empty whenever it cannot decide — NEVER guesses an owner. Pure: no read, no write, no subshell.
parse_remote_url() {
  local url="${1:-}" kind h slug head repo_part rest owner_part
  PARSED_SLUG=""; PARSED_HOST=""
  [ -n "$url" ] || return 0
  # A FILESYSTEM-PATH remote carries no owner (and no host) at all. `origin = /Users/x/myrepo` has
  # the same shape as `host/owner/repo` once you only look at the last two segments, so the naive
  # tail split would return `x/myrepo` — an owner invented from a parent directory name, which is
  # exactly what this parser promises never to do. Decide it is a path and return nothing.
  case "$url" in
    # NOTE the QUOTED tilde: bash tilde-expands `case` PATTERNS, so a bare `~*` would silently
    # become the developer's own home path and stop matching a literal `~/...` remote.
    /*|./*|../*|'~'*|file://*) return 0 ;;
    *://*) kind=scheme; h="${url#*://}"; h="${h%%/*}"; h="${h##*@}"; h="${h%%:*}" ;;
    *:*)   kind=scp;    h="${url%%:*}"; h="${h##*@}" ;;
    *)     kind=plain;  h="${url%%/*}" ;;
  esac
  [ -n "$h" ] && PARSED_HOST="$(printf '%s\n' "$h" | tr 'A-Z' 'a-z')"
  slug="${url%.git}"
  slug="${slug%/}"
  if [ "$kind" = plain ]; then
    # No scheme and no colon: only a HOST-LIKE leading segment can be followed by an owner.
    # `subdir/myrepo` or a bare `myrepo` is a relative path, not `owner/repo`.
    head="${slug%%/*}"
    case "$head" in
      *.*|localhost) : ;;
      *) return 0 ;;
    esac
  fi
  case "$slug" in
    *:*/*)  slug="${slug##*:}" ;;   # git@host:owner/repo  → owner/repo
  esac
  # For URL forms the tail is still host/owner/repo — keep the LAST two segments.
  repo_part="${slug##*/}"
  rest="${slug%/*}"
  owner_part="${rest##*/}"
  [ -n "$repo_part" ] && [ -n "$owner_part" ] || return 0
  case "$owner_part" in *:*) return 0 ;; esac   # no owner segment at all
  PARSED_SLUG="$owner_part/$repo_part"
}

# resolve_origin — read origin's URL exactly ONCE and set ORIGIN_SLUG / ORIGIN_HOST from it, in the
# CURRENT shell. Every resolution calls it afresh (an in-process memo for that resolution only), so
# a later resolution in the same process re-reads rather than trusting an earlier value.
resolve_origin() {
  local url
  url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  parse_remote_url "$url"
  ORIGIN_SLUG="$PARSED_SLUG"
  ORIGIN_HOST="$PARSED_HOST"
}

# remote_slug — print origin's `owner/repo`, or nothing when it cannot decide (the original output
# contract, unchanged: a filesystem-path origin still yields nothing).
remote_slug() {
  resolve_origin
  [ -n "$ORIGIN_SLUG" ] && printf '%s\n' "$ORIGIN_SLUG"
  return 0
}

# THE TRACKED REQUEST FILE. `.supervisor/config.json` is gitignored, so it does not travel: a second
# machine or a scratch clone falls back to the live remote alone, and every pre-rename record then
# reads as foreign (meta-sync.sh's push scrub refuses it). `.agent/meta-allowlist.txt` is TRACKED, so
# it does travel — and that is exactly why it may only REQUEST. The ledger collects records about
# OTHER repos analysed from this checkout, so a list that GRANTED would let whoever controls the
# committed file publish those records. An entry is therefore granted ONLY when GitHub says it is
# the SAME repository as origin: `gh api repos/<slug> --jq .id` equals origin's id (a renamed repo's
# old slug redirects to the same id; any other repository does not).
#
# github.com ORIGINS ONLY. `gh api repos/<slug>` asks github.com unless told otherwise, so for a
# GitLab / Bitbucket / GitHub Enterprise origin it would compare two github.com NAMESAKES of the
# slug — an unrelated repository — and could "prove" sameness that does not exist. So the request
# file is consulted only when origin's HOST is github.com ($ORIGIN_HOST, set by resolve_origin from
# the SAME read and the SAME parse as the slug); any other host grants NOTHING and makes ZERO gh calls. (Not `gh --hostname`: GHE id semantics are
# unverified here, and a guessed grant is the one outcome this layer must never produce.)
#
# BOUNDED. validate-entry.sh resolves this allowlist on every memory/lesson/rule write and
# meta-sync.sh on every push, so a hung `gh` (captive portal, stalled TLS) must not stall them:
# every gh call runs under gh_id_bounded, LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT seconds (default 10):
# on overrun gh AND every process it started (its process group — a child left holding the capture
# pipe included) are killed, and the call is treated as gh failing — nothing granted. After one
# timeout no further gh call is made in that resolution, so a hung gh costs at most two bounds,
# each plus a 1s TERM grace (limit: a descendant that deliberately leaves gh's process group is
# not covered — see gh_id_bounded).
#
# NOT CACHED ACROSS INVOCATIONS — BY DESIGN. Each `setup-memory.sh allowlist` process resolves from
# scratch: origin's URL is read once and origin's id looked up at most once PER RESOLUTION (an
# in-process memo), but nothing survives the process. A cross-invocation cache would have to be a
# FILE, and the WRITE-CONTAINMENT INVARIANT says `allowlist` writes none; an env-provided cache (a
# caller-exported origin id) is refused too, because a stale or forged value could then GRANT — an
# id may only be trusted when this process produced it. The cost is bounded instead: zero gh calls
# with no request file or an own-slug-only one (lazy lookup), at most cap + 1 calls otherwise, each
# within the bound. A caller that resolves many times (validate-entry.sh once per entry, meta-sync.sh
# per push) and wants zero gh calls should set `.supervisor/config.json` `.setup_memory.repo_allowlist`
# — layer 3 then wins and the request file is never read.
#
# CAPPED. The request file is the attacker-controlled input, so the WORK it drives is capped too, not
# just each call: at most META_ALLOWLIST_MAX_ENTRIES well-formed non-own entries are compared per
# resolution (default 20; $LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES overrides it with a positive integer, and
# is clamped to META_ALLOWLIST_MAX_ENTRIES_CEIL), so a resolution makes at most cap + 1 gh calls even
# when gh answers just inside the bound every time. Each entry past the cap is named on stderr
# (`allowlist: ignored <slug> — over the <N>-entry cap`) and never passed to gh. Reading stops after
# META_ALLOWLIST_MAX_LINES lines, named once on stderr, so a huge file cannot drive unbounded
# per-line work either. Granted entries keep their file order.
META_ALLOWLIST_REL=".agent/meta-allowlist.txt"
META_ALLOWLIST_GH_TIMEOUT_DEFAULT=10
META_ALLOWLIST_MAX_ENTRIES_DEFAULT=20
META_ALLOWLIST_MAX_ENTRIES_CEIL=100
META_ALLOWLIST_MAX_LINES=200

# allowlist_gh_limit — the per-call gh bound in whole seconds: $LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT when
# it is a positive integer (no leading zero), else the default.
allowlist_gh_limit() {
  local lim="${LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT:-}"
  case "$lim" in ''|*[!0-9]*|0*) lim="$META_ALLOWLIST_GH_TIMEOUT_DEFAULT" ;; esac
  printf '%s\n' "$lim"
}

# allowlist_max_entries — the per-resolution comparison cap: $LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES when
# it is a positive integer (no leading zero), clamped to META_ALLOWLIST_MAX_ENTRIES_CEIL; else the
# default. (Length-checked before the arithmetic so a 30-digit value cannot overflow the compare.)
allowlist_max_entries() {
  local cap="${LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES:-}"
  case "$cap" in ''|*[!0-9]*|0*) cap="$META_ALLOWLIST_MAX_ENTRIES_DEFAULT" ;; esac
  if [ "${#cap}" -gt 3 ] || [ "$cap" -gt "$META_ALLOWLIST_MAX_ENTRIES_CEIL" ]; then
    cap="$META_ALLOWLIST_MAX_ENTRIES_CEIL"
  fi
  printf '%s\n' "$cap"
}

# gh_id_bounded <owner/repo> — print `gh api repos/<slug> --jq .id` within the bound. Exit 0 on a
# completed, successful gh; 1 when gh failed; 124 when the bound expired. bash 3.2 / BSD has no
# `timeout`, and this runner is FILE-FREE (the WRITE-CONTAINMENT INVARIANT says `allowlist` writes
# nothing): inside the command substitution gh runs in the background with the substitution pipe as
# its stdout, and gh reads </dev/null so it can never consume the caller's stdin.
#
# WHAT IS BOUNDED IS THE PIPE, NOT gh's PID. Anything gh forks inherits that stdout, and the
# substitution waits for EOF on it, so a child left behind — one that ignores TERM after gh died, or
# one gh exited 0 without waiting for — would hold the call open after gh itself is gone. So gh is
# started under `set -m`, which makes it the leader of a NEW PROCESS GROUP that every descendant
# joins (and stays in after gh exits and it is re-parented). A watchdog subshell — its own
# stdin/stdout/stderr on /dev/null, so it never holds the pipe — polls that GROUP, not gh, every
# 0.1s: it exits 0 as soon as the group is empty (gh and everything it started have finished), and
# at the bound it sends TERM to the whole group, waits up to 1s, sends KILL to the whole group and
# exits 124. A group whose leader exited 0 but whose child still runs at the bound is therefore a
# timeout too (its partial output is never printed). Signals go only to `-<gh's pid>`, the group gh
# leads, never to a pid found by a pattern. So a hung call costs at most the bound plus the 1s TERM
# grace. HONEST LIMIT: a descendant that leaves the group on purpose (setsid / setpgid — a daemon)
# is outside it and NOT bounded; gh does not do that. If the group did not form (gh alive, group
# absent), gh is killed and the call fails closed rather than running unbounded. The substitution
# reaps gh, then the watchdog, and its stderr is discarded so no "Terminated" job notice escapes.
gh_id_bounded() {
  local slug="$1" lim max out rc
  lim="$(allowlist_gh_limit)"
  max=$((lim * 10))
  out="$(
    {
      set -m
      gh api "repos/$slug" --jq .id </dev/null 2>/dev/null &
      gpid=$!
      set +m
      if ! kill -0 -- "-$gpid" 2>/dev/null && kill -0 "$gpid" 2>/dev/null; then
        kill -KILL "$gpid" 2>/dev/null
        wait "$gpid"
        exit 1
      fi
      (
        ticks=0
        while kill -0 -- "-$gpid" 2>/dev/null; do
          if [ "$ticks" -ge "$max" ]; then
            kill -TERM -- "-$gpid" 2>/dev/null
            ticks=0
            while kill -0 -- "-$gpid" 2>/dev/null && [ "$ticks" -lt 10 ]; do sleep 0.1; ticks=$((ticks + 1)); done
            kill -KILL -- "-$gpid" 2>/dev/null
            exit 124
          fi
          sleep 0.1
          ticks=$((ticks + 1))
        done
        exit 0
      ) </dev/null >/dev/null 2>&1 &
      wpid=$!
      wait "$gpid"; grc=$?
      wait "$wpid"; wrc=$?
      [ "$wrc" -eq 124 ] && exit 124
      [ "$grc" -eq 0 ] && exit 0
      exit 1
    } 2>/dev/null
  )"; rc=$?
  [ "$rc" -eq 124 ] && return 124
  [ "$rc" -eq 0 ] || return 1
  printf '%s\n' "$out"
  return 0
}

# meta_allowlist_grants <origin-slug> — print, one per line, the request-file entries that are
# GRANTED; name every skipped entry (and why) on STDERR, never stdout. FAILS CLOSED: no `gh`, a
# failing or timed-out `gh`, a non-numeric answer, an origin with no parseable owner/repo, or an
# origin whose host is not github.com grants NOTHING.
#   · an ABSENT request file is silent; one that EXISTS but is not a readable regular file (mode
#     000, a directory, a symlink to one) is named once on stderr and grants nothing;
#   · origin's host is read from $ORIGIN_HOST (resolve_origin, run by load_allowlist before this) —
#     never a second `git remote get-url`; unset, it fails closed as "not on github.com";
#   · `#` comments and blank lines are skipped;
#   · origin's own slug (case-insensitive) is already granted by the remote default — no gh call;
#   · an entry that is not owner/repo-shaped (`[A-Za-z0-9._-]+/[A-Za-z0-9._-]+`, neither half `.`
#     or `..`) is never passed to gh;
#   · origin's id is looked up LAZILY, at most once per call, and only when a well-formed non-own
#     entry needs comparing — so no request file, or one holding only origin's own slug, makes ZERO
#     gh calls (the GitHub-shaped test fixtures stay hermetic);
#   · at most allowlist_max_entries non-own entries are COMPARED (each one gh call) — every later
#     one is named `over the <N>-entry cap` and never passed to gh — and reading stops after
#     META_ALLOWLIST_MAX_LINES lines (see CAPPED above).
# gh reads </dev/null: it must never consume the request file this loop is reading from stdin.
meta_allowlist_grants() {
  local own="${1:-}" f="$repo/$META_ALLOWLIST_REL" line e le own_l origin_id="" origin_state="" id rc
  local lim cap compared=0 nlines=0
  if [ -e "$f" ] && ! { [ -f "$f" ] && [ -r "$f" ]; }; then
    echo "allowlist: ignored $META_ALLOWLIST_REL — not readable (not a readable regular file), so no request entry is granted" >&2
  fi
  [ -f "$f" ] && [ -r "$f" ] || return 0
  lim="$(allowlist_gh_limit)"
  cap="$(allowlist_max_entries)"
  own_l="$(printf '%s' "$own" | tr 'A-Z' 'a-z')"
  while IFS= read -r line || [ -n "$line" ]; do
    nlines=$((nlines + 1))
    if [ "$nlines" -gt "$META_ALLOWLIST_MAX_LINES" ]; then
      echo "allowlist: stopped reading $META_ALLOWLIST_REL after $META_ALLOWLIST_MAX_LINES lines — over the line cap; later entries are ignored" >&2
      break
    fi
    e="$(printf '%s' "$line" | awk '{ sub(/^[ \t]+/, ""); sub(/[ \t\r]+$/, ""); print }')"
    case "$e" in ''|'#'*) continue ;; esac
    le="$(printf '%s' "$e" | tr 'A-Z' 'a-z')"
    if [ -n "$own_l" ] && [ "$le" = "$own_l" ]; then
      echo "allowlist: granted $e — current remote (no gh call)" >&2
      continue
    fi
    if ! printf '%s\n' "$e" | env LC_ALL=C grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
      echo "allowlist: ignored $e — not an owner/repo slug (never passed to gh)" >&2
      continue
    fi
    case "/$e/" in */./*|*/../*)
      echo "allowlist: ignored $e — not an owner/repo slug (never passed to gh)" >&2
      continue ;;
    esac
    if [ -z "$origin_state" ]; then
      if [ -z "$own" ]; then
        origin_state="origin has no owner/repo slug (a filesystem-path or unparseable remote), so nothing can be compared"
      elif [ "$ORIGIN_HOST" != "github.com" ]; then
        origin_state="origin is not on github.com, so the request cannot be checked (gh would compare a github.com namesake)"
      elif ! command -v gh >/dev/null 2>&1; then
        origin_state="gh is not installed, so the request cannot be checked (request-file entries need gh)"
      else
        origin_id="$(gh_id_bounded "$own")"; rc=$?
        [ "$rc" -eq 0 ] || origin_id=""
        if [ "$rc" -eq 124 ]; then
          origin_state="gh timed out after ${lim}s resolving origin $own, so the request cannot be checked"
        else
          case "$origin_id" in
            ''|*[!0-9]*) origin_id=""; origin_state="gh could not resolve origin $own (unauthenticated, offline or failing), so the request cannot be checked" ;;
            *) origin_state="ok" ;;
          esac
        fi
      fi
    fi
    if [ "$origin_state" != "ok" ]; then
      echo "allowlist: ignored $e — $origin_state" >&2
      continue
    fi
    if [ "$compared" -ge "$cap" ]; then
      echo "allowlist: ignored $e — over the ${cap}-entry cap (never passed to gh)" >&2
      continue
    fi
    compared=$((compared + 1))
    id="$(gh_id_bounded "$e")"; rc=$?
    [ "$rc" -eq 0 ] || id=""
    if [ "$rc" -eq 124 ]; then
      # One overrun means gh is unreachable for this resolution: stop asking, so the total stays bounded.
      origin_state="gh timed out after ${lim}s, so the request cannot be checked"
      echo "allowlist: ignored $e — $origin_state" >&2
      continue
    fi
    case "$id" in
      ''|*[!0-9]*)
        echo "allowlist: ignored $e — gh could not resolve it, so it cannot be shown to be this repository" >&2
        continue ;;
    esac
    if [ "$id" = "$origin_id" ]; then
      echo "allowlist: granted $e — same repository as origin $own (id $id)" >&2
      printf '%s\n' "$e"
    else
      echo "allowlist: ignored $e — not this repository" >&2
    fi
  done < "$f"
  return 0
}

# load_allowlist — resolve the allowlist INTO THE GLOBALS $ALLOWLIST (newline-separated entries)
# and $ALLOWLIST_SOURCE (a human-readable provenance label). It must run in the CURRENT shell:
# a command substitution would evaluate it in a SUBSHELL and the source label would never reach
# the caller (the entries would look right while the reported provenance stayed stale).
#
# Precedence (first non-empty wins):
#   1. --allow flags (repeatable)
#   2. $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST (newline-, comma- or colon-separated)
#   3. .supervisor/config.json  .setup_memory.repo_allowlist[]   (a JSON ARRAY — the stored shape)
#   4. default: the CURRENT git remote's owner/repo (fresh-install default; never a hardcoded owner)
#      PLUS the GRANTED entries of the tracked request file `.agent/meta-allowlist.txt`
#      (see meta_allowlist_grants — a listed slug is only a REQUEST)
#
# It is a LIST at every layer. A repo RENAME is the documented reason: records written before the
# rename carry the old slug, and a live-remote-keyed filter would silently drop them. This is also
# why layer 4 is only a DEFAULT — `apply` snapshots it into config, and every later read comes from
# config, so renaming the remote afterwards does not retroactively change what the filter retains.
#
# Layers 1–3 win exactly as before: when any of them is non-empty the request file is NOT read and
# `gh` is never called. Every request-file status line goes to STDERR — meta-sync.sh's scrub and
# validate-entry.sh read this subcommand's STDOUT as the list, so a status line on stdout would
# become an allowlist entry.
load_allowlist() {
  local out="" own granted
  ALLOWLIST_SOURCE="none"
  if [ -n "$ALLOW_FLAGS" ]; then
    out="$ALLOW_FLAGS"
    ALLOWLIST_SOURCE="--allow flags"
  fi
  if [ -z "$out" ] && [ -n "${LOOMWRIGHT_MEMORY_REPO_ALLOWLIST:-}" ]; then
    out="$(printf '%s' "$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST" | tr ',:' '\n\n')"
    ALLOWLIST_SOURCE="env LOOMWRIGHT_MEMORY_REPO_ALLOWLIST"
  fi
  if [ -z "$out" ] && command -v jq >/dev/null 2>&1 && [ -f "$CFG" ]; then
    local kind
    kind="$(jq -r '.setup_memory.repo_allowlist | type' "$CFG" 2>/dev/null || true)"
    if [ "$kind" = "array" ]; then
      out="$(jq -r '(.setup_memory.repo_allowlist // [])[] | select(type == "string")' "$CFG" 2>/dev/null || true)"
      ALLOWLIST_SOURCE="config .setup_memory.repo_allowlist"
    elif [ "$kind" = "string" ]; then
      # Tolerated on READ so a hand-edit is not silently dropped, but it IS a misconfiguration:
      # the stored shape is an ARRAY precisely so a renamed repo can list both slugs.
      echo "setup-memory: WARNING — .setup_memory.repo_allowlist is a STRING in $CFG; it MUST be a JSON array (a renamed repo needs both slugs). Coercing to a single-entry list." >&2
      out="$(jq -r '.setup_memory.repo_allowlist' "$CFG" 2>/dev/null || true)"
      ALLOWLIST_SOURCE="config .setup_memory.repo_allowlist (string — coerced, fix it)"
    fi
  fi
  if [ -z "$out" ]; then
    resolve_origin   # ONE origin read for this resolution: the slug here AND the host gate inside
    own="$ORIGIN_SLUG"
    granted="$(meta_allowlist_grants "$own")"
    out="$own"
    if [ -n "$own" ]; then
      ALLOWLIST_SOURCE="default (current git remote)"
      if [ -n "$granted" ]; then
        out="${own}
${granted}"
        ALLOWLIST_SOURCE="default (current git remote) + request file $META_ALLOWLIST_REL (granted entries)"
      fi
    else
      ALLOWLIST_SOURCE="unset (no git remote to default from)"
    fi
  fi
  # Trim, drop blanks, de-duplicate while preserving order.
  ALLOWLIST="$(printf '%s\n' "$out" | awk 'NF { sub(/^[ \t]+/,""); sub(/[ \t\r]+$/,""); if ($0 != "" && !seen[$0]++) print }')"
}

# resolve_allowlist — print the resolved repo allowlist, ONE ENTRY PER LINE (empty output when
# nothing resolves). This is the reusable predicate half of the pair: safe to call from a command
# substitution. Use load_allowlist directly when you also need $ALLOWLIST_SOURCE.
resolve_allowlist() {
  load_allowlist
  [ -n "$ALLOWLIST" ] && printf '%s\n' "$ALLOWLIST"
  return 0
}

# Seed the allowlist into .supervisor/config.json as a JSON ARRAY. Backup-first, parse-gated,
# atomic, and idempotent: an existing non-empty array is NEVER overwritten (a renamed repo's
# hand-added second slug must survive re-apply).
seed_allowlist() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  allowlist: SKIPPED — jq not available (config unchanged)."
    return 0
  fi
  # Containment: lazy-load the library from the entry script's directory; fail CLOSED.  # cpl-guard
  { . "$(dirname "$0")/contained-path-lib.sh" 2>/dev/null || { CPL_REASON=containment_unavailable; false; }; } && cpl_check_write allowlist "$CFG" "$repo" >/dev/null || { echo "  allowlist: SKIPPED — ${CPL_REASON:-containment_unavailable}: $CFG resolves outside $repo or cannot be checked; nothing was written (unchanged)."; return 0; }  # cpl-guard
  local existing_kind existing_len entries json
  if [ -f "$CFG" ]; then
    if ! jq empty "$CFG" >/dev/null 2>&1; then
      echo "  allowlist: SKIPPED — $CFG exists but is not valid JSON; fix it by hand (nothing was written)."
      return 0
    fi
    existing_kind="$(jq -r '.setup_memory.repo_allowlist | type' "$CFG" 2>/dev/null || echo null)"
    existing_len="$(jq -r '(.setup_memory.repo_allowlist // []) | if type == "array" then length else 0 end' "$CFG" 2>/dev/null || echo 0)"
    if [ "$existing_kind" = "array" ] && [ "${existing_len:-0}" -gt 0 ]; then
      echo "  allowlist: already configured ($existing_len entr$([ "$existing_len" = "1" ] && echo y || echo ies)) — left untouched."
      return 0
    fi
  fi
  entries="$(resolve_allowlist)"
  if [ -z "$entries" ]; then
    echo "  allowlist: SKIPPED — no git remote to default from and nothing configured; seed it by hand:"
    echo "             jq '.setup_memory.repo_allowlist = [\"owner/repo\"]' $CFG"
    return 0
  fi
  json="$(printf '%s\n' "$entries" | jq -R . | jq -s .)" || return 0
  mkdir -p "$(dirname "$CFG")" 2>/dev/null
  local tmp="$CFG.tmp.$$"
  if [ -f "$CFG" ]; then
    # Backup-first here too, and fail CLOSED when no free backup name exists — an unbacked-up
    # rewrite of a user's config is exactly what the backup-first contract forbids.
    local cfg_backup
    cfg_backup="$(unique_backup_path "$CFG")"
    if [ -z "$cfg_backup" ] || ! cp "$CFG" "$cfg_backup" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      echo "  allowlist: SKIPPED — could not write a backup of $CFG; refusing to rewrite it unbacked-up (unchanged)."
      return 0
    fi
    jq --argjson a "$json" '.setup_memory = ((.setup_memory // {}) | .repo_allowlist = $a)' "$CFG" > "$tmp" 2>/dev/null \
      && mv "$tmp" "$CFG" 2>/dev/null \
      || { rm -f "$tmp" 2>/dev/null; echo "  allowlist: SKIPPED — could not merge into $CFG (unchanged)."; return 0; }
  else
    jq -n --argjson a "$json" '{setup_memory: {repo_allowlist: $a}}' > "$tmp" 2>/dev/null \
      && mv "$tmp" "$CFG" 2>/dev/null \
      || { rm -f "$tmp" 2>/dev/null; echo "  allowlist: SKIPPED — could not create $CFG (unchanged)."; return 0; }
  fi
  echo "  allowlist: seeded as a JSON array → $(printf '%s' "$entries" | tr '\n' ' ')"
  echo "             (a repo RENAME needs the OLD slug added by hand — the list shape exists for exactly that.)"
}

# LEDGER_RETAIN_JQ — the RETAIN half of the allowlist predicate, hoisted so it exists ONCE.
# filter_ledger_by_allowlist runs two passes (whole-file, then per-line on a malformed file) and
# both need the same program; written inline twice they can drift apart under a later edit while
# still looking right at each site. Mirrors LEDGER_GATE_JQ below, which is the SELECT-FOREIGN half
# (the logical inverse) and was already hoisted for exactly this reason — the file had learned the
# lesson for the gate but not for the filter.
LEDGER_RETAIN_JQ='select(((.repo // "") | tostring) as $r | ($allow | index($r)) != null)'

# filter_ledger_by_allowlist <ledger-path> [allow-entry ...]
#
# Prints, one per line, the JSONL records whose `.repo` is in the allowlist. Records with a
# missing/null/empty `.repo` are EXCLUDED — an unattributable record cannot be shown to belong to
# this repo, and the cost of wrongly publishing another repo's record is higher than dropping one.
# An EMPTY allowlist retains NOTHING (never "everything") for the same reason.
# Unparseable lines are skipped with a stderr note; a corrupt line never aborts the filter.
filter_ledger_by_allowlist() {
  local ledger="$1"; shift
  if ! command -v jq >/dev/null 2>&1; then
    echo "setup-memory: jq required for filter-ledger — skipping (nothing printed)." >&2
    return 0
  fi
  if [ ! -f "$ledger" ]; then
    echo "setup-memory: ledger not found at $ledger — skipping (nothing printed)." >&2
    return 0
  fi
  local allow_json
  if [ "$#" -eq 0 ]; then
    allow_json='[]'
    echo "setup-memory: WARNING — empty allowlist; NO records are retained (fail-closed by design)." >&2
  else
    allow_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)" || return 0
  fi
  # Whole-file pass first (fast). If any line is malformed, jq aborts → fall back to a per-line
  # pass that skips only the bad lines.
  #
  # The status is captured from the ASSIGNMENT, not from an `if jq …; then` — after a failed
  # `if cmd; then …; fi` bash reports the exit status of the IF STATEMENT (0), not of `cmd`, so
  # reading `$?` there would always look successful and the fallback would be dead code.
  # No `-e`: without it jq exits 0 on a clean run that simply retained nothing.
  local out rc
  out="$(jq -c --argjson allow "$allow_json" \
          "$LEDGER_RETAIN_JQ" \
          "$ledger" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
  fi
  local line n=0
  # `|| [ -n "$line" ]` — see _evaluate_ledger_gate: a bare `while read` never runs its body for an
  # unterminated final line. Here the direction was already fail-SAFE (the dropped record simply
  # never reaches the filtered output, and this filter's whole job is to DROP what cannot be shown
  # to be allowlisted), so this is a correctness fix, not a posture change: a truncated record is
  # still never RETAINED — it is now merely counted and reported as unparseable like any other.
  # The reachable case runs the OTHER way, and is the real cost: when the unterminated final line is
  # a VALID, ALLOWLISTED record, the guard RETAINS a record the pre-fix loop silently DROPPED from
  # `filter-ledger > tmp && mv tmp ledger` — the documented remedy — i.e. real data loss.
  # Pinned by test-setup-memory.sh group (d10).
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -n "$line" ] || continue
    printf '%s' "$line" | jq -c --argjson allow "$allow_json" \
      "$LEDGER_RETAIN_JQ" 2>/dev/null \
      || echo "setup-memory: skipping unparseable ledger line $n" >&2
  done < "$ledger"
}
