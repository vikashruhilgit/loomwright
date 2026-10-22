#!/usr/bin/env bash
# bump-version.sh — the ONE way to bump the loomwright plugin version (maintainer tooling, not shipped).
#
# WHY: the version lives in three hand-maintained files — loomwright/.claude-plugin/plugin.json
# (authoritative), the loomwright entry of .claude-plugin/marketplace.json, and the top entry of
# CHANGELOG.md — plus one GENERATED copy, loomwright/capabilities.json's plugin_version, which this
# script regenerates with loomwright/scripts/build-capabilities.sh (the sole writer of the authority
# must also refresh every restated copy, or every release pushes a stale contract). When every
# feature PR hand-edited all three, two open PRs conflicted and could claim the same number (2026-09-27:
# #284 took v15.107.0 and the next PR had to be renumbered). Now a feature PR carries only a
# changelog.d/<slug>.md fragment (distinct files never conflict), and this script turns the pending
# fragments into one bump. Fragment format and WHO runs this script: changelog.d/README.md.
#
# usage: bash scripts/bump-version.sh [patch|minor|major] [--dry-run] [--base <ref>]
#        bash scripts/bump-version.sh --refold [patch|minor|major] [--dry-run] [--base <ref>]
#        bash scripts/bump-version.sh --check [--base <ref>]
#   no level argument ⇒ the highest `<!-- bump: X -->` any fragment requests (default patch);
#   an explicit level always wins over the fragments.
#   --dry-run prints the planned version and CHANGELOG entry and writes nothing.
#   --refold   re-fold ONLY: no-op (exit 0) unless this branch already carries a bump AND a fragment
#              is pending; then it folds every fragment into that ONE bump (see RE-FOLD below).
#   --check    read-only content gate (see CHECK below); exit 0 consistent, 1 violated, 2 cannot check.
#   --base     the ref whose merge base with HEAD is "the base" (default $BUMP_VERSION_BASE, else
#              origin/main). CI passes a dedicated fetched ref.
#
# THE INVARIANT (decision P7 in changelog.d/README.md, #512): what matters is the CONTENT of the
# version files, not the position of the bump commit. At any commit, against the merge base B:
#   either the branch carries NO bump — plugin.json / marketplace.json versions and
#     capabilities.json's plugin_version equal B's, CHANGELOG.md is byte-identical to B's, and every
#     fragment B had is still present (a pending fragment is legal; the next bump folds it);
#   or it carries exactly ONE bump — the version is one patch/minor/major step above B's in all of
#     plugin.json, marketplace.json and capabilities.json, CHANGELOG.md is B's plus exactly the one
#     entry this script renders, that entry is the fold of fragments this branch (or B) carried —
#     every fragment B had among them — and NO fragment is left pending.
# A commit after the bump that touches none of these is legal (the #367 shape: Phase 4.5 heal and
# /review-pr drain commits always land after the bump on a sequential run).
#
# CHECK (--check): verifies the invariant for the WORKING TREE against B. The fold's source
# fragments were deleted by the bump, so it reads every fragment blob from B's tree and from every
# commit in B..HEAD, then searches for the subset (in filename order, at most one blob per name)
# whose fold is the CHANGELOG's new entry. Exit 2 (fail CLOSED) when B is unresolvable or the
# clone is shallow (the blobs may be missing) — CI deepens its checkout and passes --base.
#
# RE-FOLD (--refold, and a plain run on a branch that already carries a bump): a fragment added
# after the bump (a heal or drain fix) used to need the bump commit dropped or reverted by hand —
# a bare re-run double-bumped. Now, when the working-tree version differs from B's and a fragment
# is pending, the script first verifies the existing bump is reproducible (same rules as --check,
# fragments aside), restores the pre-bump state in the working tree (B's CHANGELOG.md, B's version
# on the version lines, the fragments the bump folded — a pending file of the same name wins), then
# runs the ordinary bump over ALL of them in a child run, at the higher of the previous bump's level
# and the fragments' request (an explicit level still wins). Any failure restores every file it
# touched. With B unresolvable a plain run bumps from the working tree as before (with a NOTE) and
# --refold does nothing; the CI --check is the gate.
#
# WHAT IT DOES, in this fixed order (any failure ⇒ every file restored byte-identical, exit 1):
#   1. refuse (exit 1, nothing written) when there is no fragment, a fragment is malformed, the
#      three files disagree on the current version, or only one of capabilities.json / its
#      generator exists;
#   2. back up the target files and every fragment into a scratch dir under the repo root;
#   3. render all three new files to temp files and self-verify them: plugin.json and marketplace.json
#      each differ by exactly ONE line (the loomwright "version" value — a targeted in-place
#      replacement, never a `jq .` round-trip, which re-encodes the other entries' six-character
#      backslash-u-2014 JSON escapes as raw em-dashes), and the stackpack / mysql-mcp entries stay byte-unchanged;
#      capabilities.json (when the tree has one) is regenerated by build-capabilities.sh against a
#      shadow plugin root carrying the NEW plugin.json, and must differ from the committed copy ONLY in
#      plugin_version — a contract that was already stale before the bump is refused, never folded in;
#   4. rename the temp files over the targets (CHANGELOG.md, plugin.json, marketplace.json[, capabilities.json]);
#   5. delete the folded fragments;
#   6. run the validators (fragments are already gone, so check-doc-currency.sh's
#      bump-without-script guard cannot trip on this bump), then `build-capabilities.sh --check`;
#      a failure restores every target file AND re-creates the fragments.
#
# TEST SEAM: BUMP_VERSION_VALIDATORS — a colon-separated list of validator script paths (relative to
# the repo root, each run as `bash <path>` from the repo root). Default:
# scripts/validate-version.sh:scripts/check-doc-currency.sh. scripts/test-bump-version.sh sets it to
# inject a failing validator; nothing else should.
#
# HONEST LIMITS: only the loomwright plugin is versioned (stackpack / mysql-mcp are never touched).
# A crash between two renames is restored by the EXIT trap; a SIGKILL is not trappable — the backups
# are then left in the .bump-version.* scratch dir under the repo root for a manual restore.
#
# CAPABILITIES: loomwright/capabilities.json and loomwright/scripts/build-capabilities.sh must both
# exist or both be absent (absent only in a fixture tree that predates the contract); one without the
# other is refused, so the generated copy can never silently fall out of the bump.
#
# SCAN REMINDER: a minor or major bump (and its --dry-run) prints one advisory line,
# `bump-version: capability baseline last scanned at <X.Y.Z>; run /capability-check`, reading
# plugin_version_at_last_scan live from loomwright/docs/CAPABILITY_BASELINE.json (never a second
# copy). It is fail-SAFE: a missing or invalid baseline prints nothing and never changes the exit
# status. It is printed only after a successful bump's last line or the dry run's entry, never on
# --check or a --refold no-op; in a re-fold the child bump prints it. docs/NATIVE_OVERLAP.md
# records the cadence.
#
# HONEST LIMITS of --check: it verifies the bump-owned bytes only — capabilities.json's other keys
# are build-capabilities.sh --check's job; a fragment folded before it was ever committed has no
# blob to read back (commit the fragment, then bump); B is origin/main as last fetched.
#
# Exit: 0 bumped / re-folded / nothing to re-fold / check consistent (or dry run printed),
#       1 refused / failed (nothing left changed) / check violated, 2 check could not run.
# Portability: bash 3.2 + BSD userland (macOS) and GNU (CI): no sed -i, no mapfile, temp file + mv.
set -uo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

PLUGIN_JSON="loomwright/.claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CHANGELOG="CHANGELOG.md"
CAPS_JSON="loomwright/capabilities.json"
CAPS_GEN="loomwright/scripts/build-capabilities.sh"
CAP_BASELINE="loomwright/docs/CAPABILITY_BASELINE.json"   # read-only: the scan reminder's source
FRAG_DIR="changelog.d"
VALIDATORS="${BUMP_VERSION_VALIDATORS:-scripts/validate-version.sh:scripts/check-doc-currency.sh}"
# The CHANGELOG entry shape: `**vX.Y.Z — <headline>:** <body>` (the dash is U+2014).
ENTRY_RE='^\*\*v[0-9]+\.[0-9]+\.[0-9]+ — '

die() { echo "bump-version: $*" >&2; exit 1; }

usage() {
  sed -n '/^# usage:/,/CI passes a dedicated fetched ref/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- arguments -------------------------------------------------------------------------------
level_arg=""
dry_run=0
mode="bump"   # bump | refold | check
base_ref="${BUMP_VERSION_BASE:-origin/main}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    patch|minor|major)
      [ -z "$level_arg" ] || die "more than one bump level given ($level_arg, $1)"
      level_arg="$1" ;;
    --dry-run) dry_run=1 ;;
    --check|--refold)
      [ "$mode" = "bump" ] || die "--check and --refold are exclusive"
      mode="${1#--}" ;;
    --base)
      [ "$#" -ge 2 ] && [ -n "$2" ] || die "--base needs a ref"
      base_ref="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done
if [ "$mode" = "check" ] && { [ -n "$level_arg" ] || [ "$dry_run" -eq 1 ]; }; then
  die "--check takes no bump level and no --dry-run (it never writes)"
fi

command -v jq >/dev/null 2>&1 || die "jq is required"
for f in "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$CHANGELOG"; do
  [ -f "$f" ] || die "missing $f (run from a loomwright checkout)"
done

# capabilities.json restates plugin_version: both it and its generator, or neither.
caps=0
if [ -f "$CAPS_JSON" ] && [ -f "$CAPS_GEN" ]; then caps=1
elif [ -f "$CAPS_JSON" ] || [ -f "$CAPS_GEN" ]; then
  die "exactly one of $CAPS_JSON / $CAPS_GEN exists — the generated contract cannot be refreshed by this bump; restore the missing one first"
fi

level_rank() { case "$1" in patch) echo 1 ;; minor) echo 2 ;; major) echo 3 ;; *) echo 0 ;; esac; }

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# ---- render functions (pure: <in> <out>; old/new versions from the globals) --------------------
render_plugin() {
  BUMP_RE="$ver_line_re" awk -v old="\"$old_ver\"" -v new="\"$new_ver\"" '
    BEGIN { re = ENVIRON["BUMP_RE"] }
    !done && $0 ~ re { i = index($0, old); $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); done = 1 }
    { print }' "$1" > "$2"
}

# Targeted in-place replacement of the loomwright entry's version line ONLY. A `jq .` round-trip
# is deliberately NOT used: it re-encodes the stackpack / mysql-mcp descriptions'
# six-character backslash-u-2014 JSON escapes as raw em-dashes.
render_marketplace() {
  BUMP_RE="$ver_line_re" awk -v old="\"$old_ver\"" -v new="\"$new_ver\"" '
    BEGIN { re = ENVIRON["BUMP_RE"] }
    /"name"[[:space:]]*:[[:space:]]*"loomwright"/ { in_lw = 1 }
    in_lw && !done && $0 ~ re { i = index($0, old); $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); done = 1 }
    { print }' "$1" > "$2"
}
# END render_marketplace

render_changelog() {
  BUMP_ENTRY="$entry" BUMP_RE="$ENTRY_RE" awk '
    BEGIN { re = ENVIRON["BUMP_RE"] }
    !done && $0 ~ re { print ENVIRON["BUMP_ENTRY"]; print ""; done = 1 }
    { print }' "$1" > "$2"
}

# render_capabilities <new plugin.json> <out> — regenerate the contract with the REAL generator against
# a shadow plugin root: the new plugin.json in a private .claude-plugin/, every other source the
# generator reads symlinked to the live tree (read-only use), so nothing in the repo is touched.
render_capabilities() {
  local sh="$WORK/caproot" lw="$repo_root/loomwright" d
  mkdir -p "$sh/.claude-plugin" || return 1
  cp "$1" "$sh/.claude-plugin/plugin.json" || return 1
  for d in agents commands skills hooks docs; do
    [ -e "$lw/$d" ] || continue
    ln -s "$lw/$d" "$sh/$d" || return 1
  done
  bash "$CAPS_GEN" --root "$sh" --out "$2" >/dev/null || return 1
  [ -s "$2" ]
}

# Count of differing lines between two files of equal line count (-1 when line counts differ).
changed_lines() {
  local a b
  a="$(wc -l < "$1" | tr -d ' ')"; b="$(wc -l < "$2" | tr -d ' ')"
  [ "$a" = "$b" ] || { echo -1; return; }
  diff "$1" "$2" | grep -c '^<'
}

verify_marketplace_edit() { # <old> <new>
  [ "$(changed_lines "$1" "$2")" = "1" ] || { echo "marketplace.json would change more than the one version line"; return 1; }
  [ "$(jq -r '.plugins[] | select(.name == "loomwright") | .version' "$2" 2>/dev/null)" = "$new_ver" ] \
    || { echo "marketplace.json loomwright version is not $new_ver after the edit"; return 1; }
  [ "$(jq -c '[.plugins[] | select(.name != "loomwright")]' "$1")" = "$(jq -c '[.plugins[] | select(.name != "loomwright")]' "$2" 2>/dev/null)" ] \
    || { echo "marketplace.json non-loomwright entries would change"; return 1; }
  return 0
}

verify_rendered() { # <work dir>
  local w="$1"
  [ "$(changed_lines "$w/bak/plugin.json" "$w/new.plugin.json")" = "1" ] || { echo "plugin.json would change more than one line"; return 1; }
  [ "$(jq -r '.version' "$w/new.plugin.json" 2>/dev/null)" = "$new_ver" ] || { echo "plugin.json version is not $new_ver after the edit"; return 1; }
  verify_marketplace_edit "$w/bak/marketplace.json" "$w/new.marketplace.json" || return 1
  [ "$(grep -m1 -E "$ENTRY_RE" "$w/new.CHANGELOG.md")" = "$entry" ] || { echo "CHANGELOG.md top entry is not the new entry"; return 1; }
  [ "$(( $(wc -l < "$w/new.CHANGELOG.md") - $(wc -l < "$w/bak/CHANGELOG.md") ))" = "2" ] || { echo "CHANGELOG.md would change more than the inserted entry"; return 1; }
  if [ "$caps" -eq 1 ]; then
    [ "$(jq -r '.plugin_version' "$w/new.capabilities.json" 2>/dev/null)" = "$new_ver" ] \
      || { echo "capabilities.json plugin_version is not $new_ver after regeneration"; return 1; }
    [ "$(jq -cS 'del(.plugin_version)' "$w/bak/capabilities.json" 2>/dev/null)" = "$(jq -cS 'del(.plugin_version)' "$w/new.capabilities.json" 2>/dev/null)" ] \
      && [ "$(changed_lines "$w/bak/capabilities.json" "$w/new.capabilities.json")" = "1" ] \
      || { echo "capabilities.json would change more than plugin_version — the committed contract is stale; run bash $CAPS_GEN, commit it, then bump"; return 1; }
  fi
  return 0
}

# ---- fragment parsing and the entry fold (shared by the bump, the re-fold and --check) --------
bump_re='^[[:space:]]*<!--[[:space:]]*bump:[[:space:]]*([A-Za-z]*)[[:space:]]*-->[[:space:]]*$'

# parse_fragment <file> [<label>] — sets PF_LEVEL (empty = patch), PF_HEAD and PF_BODY. A malformed
# fragment returns 1 with PF_ERR set: the bump turns that into a refusal, --check into a finding.
parse_fragment() {
  local f="$1" label="${2:-$1}" line t seen_first=0
  PF_LEVEL=""; PF_HEAD=""; PF_BODY=""; PF_ERR=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    t="$(trim "$line")"
    [ -n "$t" ] || continue
    if [ "$seen_first" -eq 0 ]; then
      seen_first=1
      if [[ "$t" =~ $bump_re ]]; then
        PF_LEVEL="${BASH_REMATCH[1]}"
        [ "$(level_rank "$PF_LEVEL")" -gt 0 ] || { PF_ERR="$label: unknown bump level '$PF_LEVEL' (patch|minor|major)"; return 1; }
        continue
      fi
    fi
    case "$t" in
      '<!--'*bump*) PF_ERR="$label: malformed bump directive '$t' — it must be the first line, exactly '<!-- bump: patch|minor|major -->'"; return 1 ;;
    esac
    if [ -z "$PF_HEAD" ]; then
      PF_HEAD="$(printf '%s' "$t" | sed -e 's/^#*[[:space:]]*//' -e 's/[[:space:]]*:*$//')"
      [ -n "$PF_HEAD" ] || { PF_ERR="$label: empty headline"; return 1; }
    elif [ -z "$PF_BODY" ]; then
      PF_BODY="$t"
    else
      PF_BODY="$PF_BODY $t"
    fi
  done < "$f"
  [ -n "$PF_HEAD" ] || { PF_ERR="$label: fragment has no headline (first line after the optional bump directive)"; return 1; }
  return 0
}

# fold_entry <version> — THE entry shape, for the fragments in FH[] (headlines) / FB[] (bodies), in
# order: `**vX.Y.Z — <h1>; <h2>:** <b1> <b2>`. The bump writes it; --check compares against it.
fold_entry() {
  local v="$1" h="" b="" i
  for ((i = 0; i < ${#FH[@]}; i++)); do
    if [ -z "$h" ]; then h="${FH[$i]}"; else h="$h; ${FH[$i]}"; fi
    if [ -n "${FB[$i]}" ]; then
      if [ -z "$b" ]; then b="${FB[$i]}"; else b="$b ${FB[$i]}"; fi
    fi
  done
  if [ -n "$b" ]; then printf '%s' "**v$v — $h:** $b"; else printf '%s' "**v$v — $h:**"; fi
}

next_version() { # <X.Y.Z> <patch|minor|major>
  local a b c
  IFS=. read -r a b c <<EOF
$1
EOF
  case "$2" in
    major) echo "$((a + 1)).0.0" ;;
    minor) echo "$a.$((b + 1)).0" ;;
    *) echo "$a.$b.$((c + 1))" ;;
  esac
}

step_level() { # <from> <to> — the level that turns <from> into <to>; exit 1 when none does
  local l
  for l in patch minor major; do
    [ "$(next_version "$1" "$l")" = "$2" ] && { echo "$l"; return 0; }
  done
  return 1
}

semver_ok() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# scan_reminder <level> — SCAN REMINDER in the header. Prints nothing below minor, and nothing when
# the baseline is missing, is not JSON, or has no X.Y.Z plugin_version_at_last_scan; never fails.
scan_reminder() {
  local v
  [ "$(level_rank "$1")" -ge 2 ] || return 0
  v="$(jq -r '.plugin_version_at_last_scan // empty' "$CAP_BASELINE" 2>/dev/null)" || return 0
  semver_ok "$v" || return 0
  echo "bump-version: capability baseline last scanned at $v; run /capability-check"
}

# ---- the base and the branch's fragment history (--check and the re-fold) -----------------------
# resolve_base — BASE_SHA = merge-base(HEAD, $base_ref), BASE_VER = its plugin.json version.
resolve_base() {
  BASE_SHA=""; BASE_VER=""; RB_ERR=""
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { RB_ERR="not inside a git work tree"; return 1; }
  git rev-parse --verify -q "${base_ref}^{commit}" >/dev/null 2>&1 \
    || { RB_ERR="the base ref '$base_ref' is not resolvable (fetch it, or pass --base <ref>)"; return 1; }
  BASE_SHA="$(git merge-base HEAD "$base_ref" 2>/dev/null)" || BASE_SHA=""
  [ -n "$BASE_SHA" ] || { RB_ERR="HEAD and '$base_ref' have no merge base (a shallow clone? fetch the history)"; return 1; }
  BASE_VER="$(git show "$BASE_SHA:$PLUGIN_JSON" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)" || BASE_VER=""
  semver_ok "$BASE_VER" || { RB_ERR="the merge base ${BASE_SHA:0:12} has no X.Y.Z $PLUGIN_JSON version"; return 1; }
  return 0
}

# tree_frags <commit> — "<path><TAB><blob>" for every fragment directly under $FRAG_DIR/ in <commit>.
tree_frags() {
  local rec meta path name
  while IFS= read -r -d '' rec; do
    meta="${rec%%$'\t'*}"; path="${rec#*$'\t'}"
    case "$meta" in *" blob "*) ;; *) continue ;; esac
    case "$path" in "$FRAG_DIR"/*.md) ;; *) continue ;; esac
    name="${path#"$FRAG_DIR"/}"
    case "$name" in */*|README.md|.*) continue ;; esac
    printf '%s\t%s\n' "$path" "${meta##* }"
  done < <(git ls-tree -z "$1" -- "$FRAG_DIR/" 2>/dev/null)
}

# collect_pool — POOL_PATH[] / POOL_BLOB[] / POOL_H[] / POOL_B[] / POOL_L[]: every distinct
# well-formed (path, blob) fragment version in the merge base's tree and in every commit of
# B..HEAD, sorted by path (the bump's fold order). BASE_FRAGS = " <path> ..." on the merge base.
# The bump deletes the fragments it folds, so this history is the only place their text survives.
collect_pool() {
  local c path blob i=0
  POOL_PATH=(); POOL_BLOB=(); POOL_H=(); POOL_B=(); POOL_L=(); BASE_FRAGS=" "
  tree_frags "$BASE_SHA" > "$CW/base.frags" || return 1
  while IFS="$(printf '\t')" read -r path blob; do BASE_FRAGS="$BASE_FRAGS$path "; done < "$CW/base.frags"
  cp "$CW/base.frags" "$CW/pool.raw" || return 1
  git rev-list "$BASE_SHA..HEAD" > "$CW/commits" 2>/dev/null || return 1
  while IFS= read -r c; do
    [ -n "$c" ] && tree_frags "$c" >> "$CW/pool.raw"
  done < "$CW/commits"
  sort -u "$CW/pool.raw" > "$CW/pool"
  while IFS="$(printf '\t')" read -r path blob; do
    [ -n "$blob" ] || continue
    git cat-file blob "$blob" > "$CW/blob" 2>/dev/null || continue
    parse_fragment "$CW/blob" "$path@${blob:0:12}" || continue   # the bump never folds a malformed one
    POOL_PATH[$i]="$path"; POOL_BLOB[$i]="$blob"; POOL_H[$i]="$PF_HEAD"; POOL_B[$i]="$PF_BODY"; POOL_L[$i]="${PF_LEVEL:-patch}"
    i=$((i + 1))
  done < "$CW/pool"
  return 0
}

# search_fold <entry> <version> <required " p1 p2 "> — find a subset of the pool, at most one blob
# per path, in path order, whose fold_entry is exactly <entry>; every <required> path must be in
# it. Sets FOLD_IDX[] (pool indices). Exit 0 found, 1 none, 2 too many combinations to search.
FOLD_SEARCH_CAP=4096
search_fold() {
  local target="$1" v="$2" req="$3" i j n x d total=1 np=0 found_any
  local -a UP US UN UR pick
  for ((i = 0; i < ${#POOL_PATH[@]}; i++)); do
    if [ "$np" -gt 0 ] && [ "${UP[$((np - 1))]}" = "${POOL_PATH[$i]}" ]; then
      UN[$((np - 1))]=$(( ${UN[$((np - 1))]} + 1 ))
    else
      UP[$np]="${POOL_PATH[$i]}"; US[$np]="$i"; UN[$np]=1; np=$((np + 1))
    fi
  done
  for ((j = 0; j < np; j++)); do
    case "$req" in *" ${UP[$j]} "*) UR[$j]="${UN[$j]}" ;; *) UR[$j]=$(( ${UN[$j]} + 1 )) ;; esac
    total=$(( total * ${UR[$j]} ))
    [ "$total" -le "$FOLD_SEARCH_CAP" ] || return 2
  done
  for p in $req; do   # a required path with no well-formed version can never be in the fold
    case " ${UP[*]:-} " in *" $p "*) ;; *) return 1 ;; esac
  done
  [ "$np" -gt 0 ] || return 1
  for ((n = 0; n < total; n++)); do
    x="$n"; FH=(); FB=(); pick=(); found_any=0
    for ((j = 0; j < np; j++)); do
      d=$(( x % ${UR[$j]} )); x=$(( x / ${UR[$j]} ))
      if [ "${UR[$j]}" = "${UN[$j]}" ]; then i=$(( ${US[$j]} + d ))      # required: always one version
      elif [ "$d" -eq 0 ]; then continue
      else i=$(( ${US[$j]} + d - 1 )); fi
      FH[${#FH[@]}]="${POOL_H[$i]}"; FB[${#FB[@]}]="${POOL_B[$i]}"; pick[${#pick[@]}]="$i"; found_any=1
    done
    [ "$found_any" -eq 1 ] || continue
    if [ "$(fold_entry "$v")" = "$target" ]; then FOLD_IDX=("${pick[@]}"); return 0; fi
  done
  return 1
}

chk() { CHK[${#CHK[@]}]="$1"; }

# read_wt — the working tree's version-bearing values.
read_wt() {
  W_VER="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)" || W_VER=""
  W_MKT="$(jq -r '[.plugins[]? | select(.name == "loomwright") | .version] | if length == 1 then .[0] else "(\(length) loomwright entries)" end' "$MARKETPLACE_JSON" 2>/dev/null)" || W_MKT="(unreadable)"
  W_CAPS_PRESENT=0; W_CAPS=""
  if [ -f "$CAPS_JSON" ]; then
    W_CAPS_PRESENT=1; W_CAPS="$(jq -r '.plugin_version // empty' "$CAPS_JSON" 2>/dev/null)" || W_CAPS=""
  fi
}

is_pending() { # <path>
  local f
  for f in ${frags[@]+"${frags[@]}"}; do [ "$f" = "$1" ] && return 0; done
  return 1
}

# verify_bump_content <ignore_pending 0|1> — the bumped-state rules of THE INVARIANT (header).
# Appends each violation to CHK[]; on success FOLD_IDX[] names the folded pool entries and
# PREV_LEVEL the bump's level. Needs resolve_base, read_wt and CW.
verify_bump_content() {
  local ignore_pending="$1" top req p rc
  FOLD_IDX=()
  PREV_LEVEL="$(step_level "$BASE_VER" "$W_VER")" || PREV_LEVEL=""
  [ -n "$PREV_LEVEL" ] || chk "$PLUGIN_JSON version $W_VER is not one patch/minor/major step above the merge base's $BASE_VER — a hand edit, or a bump left stale after main moved (bring main in, then re-run bash scripts/bump-version.sh)"
  [ "$W_MKT" = "$W_VER" ] || chk "$MARKETPLACE_JSON loomwright version $W_MKT differs from $PLUGIN_JSON's $W_VER — a hand edit"
  if [ "$W_CAPS_PRESENT" -eq 1 ] && [ "$W_CAPS" != "$W_VER" ]; then
    chk "$CAPS_JSON plugin_version ${W_CAPS:-<none>} differs from $PLUGIN_JSON's $W_VER — the generated copy drifted (only bash scripts/bump-version.sh writes it)"
  fi
  if [ "$ignore_pending" -eq 0 ] && [ "${#frags[@]}" -gt 0 ]; then
    chk "fragment(s) pending after this branch's bump $BASE_VER -> $W_VER: ${frags[*]} — re-run bash scripts/bump-version.sh (it re-folds them into the ONE bump)"
  fi
  top="$(grep -m1 -E "$ENTRY_RE" "$CHANGELOG")"
  case "$top" in
    "**v$W_VER — "*) ;;
    *) chk "$CHANGELOG's newest entry is not v$W_VER (it is '$(printf '%s' "$top" | cut -c1-60)') — a hand edit"; return 0 ;;
  esac
  git show "$BASE_SHA:$CHANGELOG" > "$CW/base.cl" 2>/dev/null || { chk "cannot read $CHANGELOG at the merge base ${BASE_SHA:0:12}"; return 0; }
  entry="$top"; render_changelog "$CW/base.cl" "$CW/exp.cl"
  cmp -s "$CW/exp.cl" "$CHANGELOG" \
    || chk "$CHANGELOG is not the merge base's plus exactly the one new entry — a hand edit (changelog text belongs in a $FRAG_DIR/ fragment; only the bump writes $CHANGELOG)"
  collect_pool || { chk "cannot read the fragment history between ${BASE_SHA:0:12} and HEAD"; return 0; }
  req=" "
  for p in $BASE_FRAGS; do is_pending "$p" || req="$req$p "; done
  search_fold "$top" "$W_VER" "$req"; rc=$?
  case "$rc" in
    0) ;;
    2) chk "too many fragment versions on this branch to search (over $FOLD_SEARCH_CAP combinations) — cannot prove the entry is a fold" ;;
    *) chk "the v$W_VER entry is not the fold of any set of fragments this branch carried (every fragment the merge base had among them) — a hand-edited entry, or a fragment edited after its fold; put the text in a $FRAG_DIR/ fragment and re-run bash scripts/bump-version.sh" ;;
  esac
  return 0
}

fold_names() { local i s=""; for i in ${FOLD_IDX[@]+"${FOLD_IDX[@]}"}; do s="$s ${POOL_PATH[$i]#"$FRAG_DIR"/}"; done; printf '%s' "${s# }"; }

# ---- --check: the content gate (read-only) -------------------------------------------------------
run_check() {
  local f p state
  CHK=()
  resolve_base || { echo "bump-version: check CANNOT RUN — $RB_ERR"; exit 2; }
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    echo "bump-version: check CANNOT RUN — this clone is shallow, so the folded fragments' history may be missing (git fetch --unshallow first)"
    exit 2
  fi
  CW="$(mktemp -d "${TMPDIR:-/tmp}/bump-version-check.XXXXXX")" || { echo "bump-version: check CANNOT RUN — no scratch dir"; exit 2; }
  trap 'rm -rf "$CW"' EXIT
  read_wt
  for f in ${frags[@]+"${frags[@]}"}; do
    parse_fragment "$f" || chk "pending fragment is malformed, so the next bump would refuse it: $PF_ERR"
  done
  if [ "$W_VER" = "$BASE_VER" ]; then
    [ "$W_MKT" = "$BASE_VER" ] || chk "$MARKETPLACE_JSON loomwright version $W_MKT differs from the merge base's $BASE_VER while $PLUGIN_JSON did not change — a hand edit"
    if [ "$W_CAPS_PRESENT" -eq 1 ] && [ "$W_CAPS" != "$BASE_VER" ]; then
      chk "$CAPS_JSON plugin_version ${W_CAPS:-<none>} differs from $PLUGIN_JSON's $BASE_VER — the generated copy drifted"
    fi
    if git show "$BASE_SHA:$CHANGELOG" > "$CW/base.cl" 2>/dev/null; then
      cmp -s "$CW/base.cl" "$CHANGELOG" \
        || chk "$CHANGELOG differs from the merge base's but the version did not change — a hand edit (changelog text belongs in a $FRAG_DIR/ fragment; the bump writes $CHANGELOG)"
    else
      chk "cannot read $CHANGELOG at the merge base ${BASE_SHA:0:12}"
    fi
    tree_frags "$BASE_SHA" > "$CW/base.frags"
    while IFS="$(printf '\t')" read -r p _; do
      [ -f "$p" ] || chk "$p (on the merge base) was deleted without a bump — that loses its changelog entry; restore it with git checkout ${BASE_SHA:0:12} -- $p"
    done < "$CW/base.frags"
    state="not bumped (version $BASE_VER, the merge base's); ${#frags[@]} fragment(s) pending — legal, the next bump folds them"
  else
    verify_bump_content 0
    state="bumped $BASE_VER -> $W_VER (${PREV_LEVEL:-?}); the entry is the fold of: $(fold_names)"
  fi
  if [ "${#CHK[@]}" -eq 0 ]; then
    echo "bump-version: check OK — $state (base $base_ref, merge base ${BASE_SHA:0:12})"
    exit 0
  fi
  echo "bump-version: check FAILED — the version files are not what bump-version.sh produces from the merge base ${BASE_SHA:0:12} ($base_ref) plus this branch's fragments:"
  for p in "${CHK[@]}"; do echo "  - $p"; done
  echo "  (the invariant: changelog.d/README.md, decision P7)"
  exit 1
}

# ---- fragments ---------------------------------------------------------------------------------
frags=()
if [ -d "$FRAG_DIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && frags+=("$f")
  done < <(find "$FRAG_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name '.*' | sort)
fi

[ "$mode" = "check" ] && run_check

# ---- 1. the three files must agree BEFORE anything is written ---------------------------------
old_ver="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)" || old_ver=""
semver_ok "$old_ver" || die "$PLUGIN_JSON .version is not X.Y.Z (got '$old_ver')"

lw_entries="$(jq '[.plugins[]? | select(.name == "loomwright")] | length' "$MARKETPLACE_JSON" 2>/dev/null)" \
  || die "$MARKETPLACE_JSON is not valid JSON"
[ "$lw_entries" = "1" ] || die "$MARKETPLACE_JSON must list exactly one loomwright plugin (found $lw_entries)"
mkt_ver="$(jq -r '.plugins[] | select(.name == "loomwright") | .version' "$MARKETPLACE_JSON")"

cl_ver="$(grep -m1 -E "$ENTRY_RE" "$CHANGELOG" | sed -E 's/^\*\*v([0-9]+\.[0-9]+\.[0-9]+) .*/\1/')"
[ -n "$cl_ver" ] || die "$CHANGELOG has no '**vX.Y.Z — ' entry to insert above"

if [ "$old_ver" != "$mkt_ver" ] || [ "$old_ver" != "$cl_ver" ]; then
  die "the three version files disagree — refusing to bump (plugin.json=$old_ver marketplace.json=$mkt_ver CHANGELOG.md=$cl_ver); reconcile them first"
fi

# The targeted edits below need exactly one replaceable version line per manifest.
ver_line_re="^[[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"${old_ver//./\\.}\",?[[:space:]]*$"
n="$(grep -cE "$ver_line_re" "$PLUGIN_JSON")"
[ "$n" = "1" ] || die "$PLUGIN_JSON must carry exactly one '\"version\": \"$old_ver\"' line (found $n)"

# ---- pending fragments: parse (a malformed one refuses the bump) -------------------------------
want_rank=0
FH=(); FB=()
for f in ${frags[@]+"${frags[@]}"}; do
  parse_fragment "$f" || die "$PF_ERR"
  r="$(level_rank "${PF_LEVEL:-patch}")"
  [ "$r" -gt "$want_rank" ] && want_rank="$r"
  FH[${#FH[@]}]="$PF_HEAD"; FB[${#FB[@]}]="$PF_BODY"
done

# ---- re-fold: this branch already carries a bump (RE-FOLD in the header) -------------------------
# set_caps_version <in> <out> <from> <to> — targeted edit of capabilities.json's plugin_version line.
set_caps_version() {
  awk -v old="\"$3\"" -v new="\"$4\"" '
    !done && /^[[:space:]]*"plugin_version"[[:space:]]*:/ { i = index($0, old); if (i) { $0 = substr($0, 1, i - 1) new substr($0, i + length(old)); done = 1 } }
    { print }' "$1" > "$2"
}

do_refold() {
  local i p name lvl eff_rank=0 rc names="" t
  CHK=()
  CW="$(mktemp -d "$repo_root/.bump-version.XXXXXX")" || die "cannot create a scratch dir under $repo_root"
  RF_PHASE="prepare"; RF_MADE=()
  trap 'refold_cleanup' EXIT
  trap 'exit 1' INT TERM HUP
  read_wt
  verify_bump_content 1
  if [ "${#CHK[@]}" -gt 0 ]; then
    echo "bump-version: refusing to re-fold — this branch's bump $BASE_VER -> $old_ver is not reproducible from its fragments (merge base ${BASE_SHA:0:12}, $base_ref):" >&2
    for p in "${CHK[@]}"; do echo "  - $p" >&2; done
    echo "  fix: revert this branch's bump commit(s) (that brings back the fragments they folded), then re-run bash scripts/bump-version.sh" >&2
    exit 1
  fi
  # The fold set: every pending fragment plus every fragment the existing bump folded (a pending
  # file of the same name wins — its newer text is the one to publish).
  eff_rank="$want_rank"
  for i in "${FOLD_IDX[@]}"; do
    p="${POOL_PATH[$i]}"
    is_pending "$p" && continue
    t="$(level_rank "${POOL_L[$i]}")"; [ "$t" -gt "$eff_rank" ] && eff_rank="$t"
    names="$names ${p#"$FRAG_DIR"/}"
  done
  if [ -n "$level_arg" ]; then lvl="$level_arg"
  elif [ "$(level_rank "$PREV_LEVEL")" -gt "$eff_rank" ]; then lvl="$PREV_LEVEL"   # keep an explicit level the first bump was given
  else lvl=""; fi
  if [ "$dry_run" -eq 1 ]; then
    echo "bump-version: DRY RUN — nothing written"
    echo "  re-fold:   this branch already carries the bump $BASE_VER -> $old_ver (merge base ${BASE_SHA:0:12})"
    echo "  restores:  ${names# }${names:+ }(folded by that bump) and re-folds them with: ${frags[*]}"
    echo "  level:     ${lvl:-from the fragments}"
    exit 0
  fi
  for t in "$CHANGELOG" "$PLUGIN_JSON" "$MARKETPLACE_JSON"; do cp -p "$t" "$CW/bak.$(basename "$t")" || die "cannot back up $t"; done
  [ -f "$CAPS_JSON" ] && { cp -p "$CAPS_JSON" "$CW/bak.capabilities.json" || die "cannot back up $CAPS_JSON"; }
  mkdir -p "$CW/frag" || die "cannot back up the pending fragments"
  for f in ${frags[@]+"${frags[@]}"}; do cp -p "$f" "$CW/frag/$(basename "$f")" || die "cannot back up $f"; done
  # Render the pre-bump state: the merge base's CHANGELOG, the base version on each version line.
  new_ver="$BASE_VER"
  render_plugin "$CW/bak.plugin.json" "$CW/pre.plugin.json" && render_marketplace "$CW/bak.marketplace.json" "$CW/pre.marketplace.json" \
    || die "cannot render the pre-bump manifests"
  [ "$(jq -r .version "$CW/pre.plugin.json" 2>/dev/null)" = "$BASE_VER" ] \
    && [ "$(jq -r '.plugins[] | select(.name == "loomwright") | .version' "$CW/pre.marketplace.json" 2>/dev/null)" = "$BASE_VER" ] \
    || die "cannot reset the manifests' version lines to $BASE_VER (nothing written)"
  if [ -f "$CAPS_JSON" ]; then
    set_caps_version "$CW/bak.capabilities.json" "$CW/pre.capabilities.json" "$old_ver" "$BASE_VER"
    [ "$(jq -r .plugin_version "$CW/pre.capabilities.json" 2>/dev/null)" = "$BASE_VER" ] || die "cannot reset $CAPS_JSON plugin_version to $BASE_VER (nothing written)"
  fi
  RF_PHASE="mutate"
  cat "$CW/base.cl" > "$CHANGELOG" && cat "$CW/pre.plugin.json" > "$PLUGIN_JSON" && cat "$CW/pre.marketplace.json" > "$MARKETPLACE_JSON" \
    || refold_abort "cannot write the pre-bump version files"
  if [ -f "$CAPS_JSON" ]; then cat "$CW/pre.capabilities.json" > "$CAPS_JSON" || refold_abort "cannot write the pre-bump $CAPS_JSON"; fi
  for i in "${FOLD_IDX[@]}"; do
    p="${POOL_PATH[$i]}"
    [ -e "$p" ] && continue
    git cat-file blob "${POOL_BLOB[$i]}" > "$p" 2>/dev/null || refold_abort "cannot restore the folded fragment $p"
    RF_MADE[${#RF_MADE[@]}]="$p"
  done
  echo "bump-version: re-fold — reset to the merge base's $BASE_VER, restored${names:- nothing}; folding them with ${frags[*]}"
  bash "$repo_root/scripts/bump-version.sh" --base "$base_ref" ${lvl:+"$lvl"}; rc=$?
  [ "$rc" -eq 0 ] || refold_abort "the bump over the restored fragments failed (exit $rc)"
  RF_PHASE="done"
  t="$CHANGELOG $PLUGIN_JSON $MARKETPLACE_JSON"; [ -f "$CAPS_JSON" ] && t="$t $CAPS_JSON"
  [ "${#frags[@]}" -gt 0 ] && t="$t ${frags[*]}"
  echo "bump-version: re-folded this branch's bump — next: commit the result; bash scripts/bump-version.sh --check verifies it"
  echo "bump-version: refold-touched: $t"   # machine line: the paths a caller commits (release-refold.sh)
  exit 0
}

refold_restore() {
  local t f
  cat "$CW/bak.CHANGELOG.md" > "$CHANGELOG"; cat "$CW/bak.plugin.json" > "$PLUGIN_JSON"; cat "$CW/bak.marketplace.json" > "$MARKETPLACE_JSON"
  [ -f "$CW/bak.capabilities.json" ] && cat "$CW/bak.capabilities.json" > "$CAPS_JSON"
  for t in ${RF_MADE[@]+"${RF_MADE[@]}"}; do rm -f "$t"; done
  for f in ${frags[@]+"${frags[@]}"}; do cmp -s "$CW/frag/$(basename "$f")" "$f" 2>/dev/null || cp -p "$CW/frag/$(basename "$f")" "$f"; done
}
refold_abort() { echo "bump-version: $* — restoring every file" >&2; refold_restore; RF_PHASE="done"; exit 1; }
refold_cleanup() { [ "${RF_PHASE:-}" = "mutate" ] && refold_restore; rm -rf "$CW"; }

if resolve_base; then
  if [ "$old_ver" != "$BASE_VER" ]; then
    [ "${#frags[@]}" -gt 0 ] && do_refold
    [ "$mode" = "refold" ] && { echo "bump-version: --refold: nothing to re-fold — this branch's bump $BASE_VER -> $old_ver already folds every fragment"; exit 0; }
    die "no changelog fragment in $FRAG_DIR/ — this branch's bump $BASE_VER -> $old_ver already folds every fragment; nothing to bump"
  fi
  if [ "$mode" = "refold" ]; then
    echo "bump-version: --refold: nothing to re-fold — this branch carries no bump (${#frags[@]} fragment(s) stay pending; legal, the next bump folds them)"
    exit 0
  fi
else
  if [ "$mode" = "refold" ]; then
    echo "bump-version: --refold: nothing re-folded — cannot tell whether this branch carries a bump ($RB_ERR); the CI content check (--check) is the gate"
    exit 0
  fi
  echo "bump-version: NOTE — cannot tell whether this branch already carries a bump ($RB_ERR); bumping from the working tree's version $old_ver" >&2
fi

[ "${#frags[@]}" -gt 0 ] || die "no changelog fragment in $FRAG_DIR/ (write $FRAG_DIR/<slug>.md first — format in $FRAG_DIR/README.md); nothing to bump"

if [ -n "$level_arg" ]; then
  level="$level_arg"; level_src="argument"
else
  case "$want_rank" in 3) level=major ;; 2) level=minor ;; *) level=patch ;; esac
  level_src="highest fragment request"
fi

new_ver="$(next_version "$old_ver" "$level")"
entry="$(fold_entry "$new_ver")"

if [ "$dry_run" -eq 1 ]; then
  echo "bump-version: DRY RUN — nothing written"
  echo "  version:   $old_ver -> $new_ver ($level, from $level_src)"
  echo "  fragments: ${frags[*]}"
  [ "$caps" -eq 1 ] && echo "  also regenerates: $CAPS_JSON (plugin_version only)"
  echo "  CHANGELOG entry:"
  printf '%s\n' "$entry"
  scan_reminder "$level"
  exit 0
fi

# ---- 2..6: back up, render, rename, delete, validate — restore on any failure -----------------
WORK="$(mktemp -d "$repo_root/.bump-version.XXXXXX")" || die "cannot create a scratch dir under $repo_root"
TARGETS="$CHANGELOG $PLUGIN_JSON $MARKETPLACE_JSON"   # rename order
[ "$caps" -eq 1 ] && TARGETS="$TARGETS $CAPS_JSON"
phase="prepare"          # prepare -> mutate -> done
restore_failed=0

restore_all() {
  local t b f
  for t in $TARGETS; do
    b="$WORK/bak/$(basename "$t")"
    cmp -s "$b" "$t" 2>/dev/null && continue
    cp -p "$b" "$t" 2>/dev/null && cmp -s "$b" "$t" || { echo "bump-version: RESTORE FAILED for $t — backup kept at $b" >&2; restore_failed=1; }
  done
  for f in "${frags[@]}"; do
    b="$WORK/bak/frag/$(basename "$f")"
    cmp -s "$b" "$f" 2>/dev/null && continue
    cp -p "$b" "$f" 2>/dev/null && cmp -s "$b" "$f" || { echo "bump-version: RESTORE FAILED for $f — backup kept at $b" >&2; restore_failed=1; }
  done
}

cleanup() {
  if [ "$phase" = "mutate" ]; then restore_all; fi
  if [ "$restore_failed" -eq 0 ]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

abort() {
  echo "bump-version: $* — restoring every file" >&2
  restore_all
  phase="done"
  if [ "$restore_failed" -eq 0 ]; then
    echo "bump-version: restored $(echo $TARGETS | sed 's/ /, /g') and ${#frags[@]} fragment(s) byte-identical; nothing changed" >&2
  fi
  exit 1
}

mkdir -p "$WORK/bak/frag" || die "cannot create backup dir"
for t in $TARGETS; do cp -p "$t" "$WORK/bak/$(basename "$t")" || die "cannot back up $t"; done
for f in "${frags[@]}"; do cp -p "$f" "$WORK/bak/frag/$(basename "$f")" || die "cannot back up $f"; done

render_plugin "$WORK/bak/plugin.json" "$WORK/new.plugin.json" || die "cannot render plugin.json"
render_marketplace "$WORK/bak/marketplace.json" "$WORK/new.marketplace.json" || die "cannot render marketplace.json"
render_changelog "$WORK/bak/CHANGELOG.md" "$WORK/new.CHANGELOG.md" || die "cannot render CHANGELOG.md"
if [ "$caps" -eq 1 ]; then
  render_capabilities "$WORK/new.plugin.json" "$WORK/new.capabilities.json" || die "cannot regenerate $CAPS_JSON with $CAPS_GEN (nothing written)"
fi
why="$(verify_rendered "$WORK")" || die "refusing: $why (nothing written)"

# Stage each new file as a mode-preserving copy of its target, so the rename keeps the file mode.
for t in $TARGETS; do
  s="$WORK/stage.$(basename "$t")"
  cp -p "$t" "$s" && cat "$WORK/new.$(basename "$t")" > "$s" || die "cannot stage $t (nothing written)"
done

phase="mutate"
for t in $TARGETS; do
  mv -f "$WORK/stage.$(basename "$t")" "$t" 2>/dev/null || abort "cannot rename the new $t into place"
done
for f in "${frags[@]}"; do
  rm -f "$f" 2>/dev/null && [ ! -e "$f" ] || abort "cannot delete folded fragment $f"
done

OLDIFS="$IFS"; IFS=:
set -f
validators=($VALIDATORS)
set +f
IFS="$OLDIFS"
[ "${#validators[@]}" -gt 0 ] || abort "BUMP_VERSION_VALIDATORS names no validator"
for v in "${validators[@]}"; do
  [ -n "$v" ] || continue
  echo "bump-version: running $v"
  bash "$v" || abort "validator $v failed after the bump"
done
if [ "$caps" -eq 1 ]; then
  echo "bump-version: running $CAPS_GEN --check"
  bash "$CAPS_GEN" --check || abort "$CAPS_GEN --check failed after the bump"
fi

phase="done"
echo "bump-version: bumped $old_ver -> $new_ver ($level, from $level_src); folded ${#frags[@]} fragment(s): ${frags[*]}"
caps_note=""; [ "$caps" -eq 1 ] && caps_note=", capabilities.json"
echo "bump-version: next: review 'git diff', then commit (plugin.json, marketplace.json, CHANGELOG.md${caps_note}, removed fragments); later commits may follow it — bash scripts/bump-version.sh --check verifies the content, and a fragment added later is folded by re-running this script"
scan_reminder "$level"
exit 0
