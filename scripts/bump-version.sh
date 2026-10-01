#!/usr/bin/env bash
# bump-version.sh — the ONE way to bump the loomwright plugin version (maintainer tooling, not shipped).
#
# WHY: the version lives in exactly three files — loomwright/.claude-plugin/plugin.json (authoritative),
# the loomwright entry of .claude-plugin/marketplace.json, and the top entry of CHANGELOG.md. When every
# feature PR hand-edited all three, two open PRs conflicted and could claim the same number (2026-09-27:
# #284 took v15.107.0 and the next PR had to be renumbered). Now a feature PR carries only a
# changelog.d/<slug>.md fragment (distinct files never conflict), and this script turns the pending
# fragments into one bump. Fragment format and WHO runs this script: changelog.d/README.md.
#
# usage: bash scripts/bump-version.sh [patch|minor|major] [--dry-run]
#   no level argument ⇒ the highest `<!-- bump: X -->` any fragment requests (default patch);
#   an explicit level always wins over the fragments.
#   --dry-run prints the planned version and CHANGELOG entry and writes nothing.
#
# WHAT IT DOES, in this fixed order (any failure ⇒ every file restored byte-identical, exit 1):
#   1. refuse (exit 1, nothing written) when there is no fragment, a fragment is malformed, or the
#      three files disagree on the current version;
#   2. back up the three files and every fragment into a scratch dir under the repo root;
#   3. render all three new files to temp files and self-verify them: plugin.json and marketplace.json
#      each differ by exactly ONE line (the loomwright "version" value — a targeted in-place
#      replacement, never a `jq .` round-trip, which re-encodes the other entries' six-character
#      backslash-u-2014 JSON escapes as raw em-dashes), and the stackpack / mysql-mcp entries stay byte-unchanged;
#   4. rename the temp files over the targets (CHANGELOG.md, plugin.json, marketplace.json);
#   5. delete the folded fragments;
#   6. run the validators (fragments are already gone, so check-doc-currency.sh's
#      bump-without-script guard cannot trip on this bump); a failure restores the three files AND
#      re-creates the fragments.
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
# Exit: 0 bumped (or dry run printed), 1 refused / failed (nothing left changed).
# Portability: bash 3.2 + BSD userland (macOS) and GNU (CI): no sed -i, no mapfile, temp file + mv.
set -uo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

PLUGIN_JSON="loomwright/.claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CHANGELOG="CHANGELOG.md"
FRAG_DIR="changelog.d"
VALIDATORS="${BUMP_VERSION_VALIDATORS:-scripts/validate-version.sh:scripts/check-doc-currency.sh}"
# The CHANGELOG entry shape: `**vX.Y.Z — <headline>:** <body>` (the dash is U+2014).
ENTRY_RE='^\*\*v[0-9]+\.[0-9]+\.[0-9]+ — '

die() { echo "bump-version: $*" >&2; exit 1; }

usage() {
  sed -n '/^# usage:/,/^#   --dry-run/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---- arguments -------------------------------------------------------------------------------
level_arg=""
dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    patch|minor|major)
      [ -z "$level_arg" ] || die "more than one bump level given ($level_arg, $1)"
      level_arg="$1" ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required"
for f in "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$CHANGELOG"; do
  [ -f "$f" ] || die "missing $f (run from a loomwright checkout)"
done

level_rank() { case "$1" in patch) echo 1 ;; minor) echo 2 ;; major) echo 3 ;; *) echo 0 ;; esac; }

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# ---- 1. the three files must agree BEFORE anything is written ---------------------------------
old_ver="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)" || old_ver=""
printf '%s' "$old_ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || die "$PLUGIN_JSON .version is not X.Y.Z (got '$old_ver')"

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

# ---- fragments ---------------------------------------------------------------------------------
frags=()
if [ -d "$FRAG_DIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && frags+=("$f")
  done < <(find "$FRAG_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name '.*' | sort)
fi
[ "${#frags[@]}" -gt 0 ] || die "no changelog fragment in $FRAG_DIR/ (write $FRAG_DIR/<slug>.md first — format in $FRAG_DIR/README.md); nothing to bump"

bump_re='^[[:space:]]*<!--[[:space:]]*bump:[[:space:]]*([A-Za-z]*)[[:space:]]*-->[[:space:]]*$'
want_rank=0
heads=""
bodies=""
for f in "${frags[@]}"; do
  fr_level=""; fr_head=""; fr_body=""; seen_first=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    t="$(trim "$line")"
    [ -n "$t" ] || continue
    if [ "$seen_first" -eq 0 ]; then
      seen_first=1
      if [[ "$t" =~ $bump_re ]]; then
        fr_level="${BASH_REMATCH[1]}"
        [ "$(level_rank "$fr_level")" -gt 0 ] || die "$f: unknown bump level '$fr_level' (patch|minor|major)"
        continue
      fi
    fi
    case "$t" in
      '<!--'*bump*) die "$f: malformed bump directive '$t' — it must be the first line, exactly '<!-- bump: patch|minor|major -->'" ;;
    esac
    if [ -z "$fr_head" ]; then
      fr_head="$(printf '%s' "$t" | sed -e 's/^#*[[:space:]]*//' -e 's/[[:space:]]*:*$//')"
      [ -n "$fr_head" ] || die "$f: empty headline"
    elif [ -z "$fr_body" ]; then
      fr_body="$t"
    else
      fr_body="$fr_body $t"
    fi
  done < "$f"
  [ -n "$fr_head" ] || die "$f: fragment has no headline (first line after the optional bump directive)"
  r="$(level_rank "${fr_level:-patch}")"
  [ "$r" -gt "$want_rank" ] && want_rank="$r"
  if [ -z "$heads" ]; then heads="$fr_head"; else heads="$heads; $fr_head"; fi
  if [ -n "$fr_body" ]; then
    if [ -z "$bodies" ]; then bodies="$fr_body"; else bodies="$bodies $fr_body"; fi
  fi
done

if [ -n "$level_arg" ]; then
  level="$level_arg"; level_src="argument"
else
  case "$want_rank" in 3) level=major ;; 2) level=minor ;; *) level=patch ;; esac
  level_src="highest fragment request"
fi

IFS=. read -r v_major v_minor v_patch <<EOF
$old_ver
EOF
case "$level" in
  major) new_ver="$((v_major + 1)).0.0" ;;
  minor) new_ver="${v_major}.$((v_minor + 1)).0" ;;
  patch) new_ver="${v_major}.${v_minor}.$((v_patch + 1))" ;;
esac

entry="**v${new_ver} — ${heads}:**"
[ -n "$bodies" ] && entry="$entry $bodies"

if [ "$dry_run" -eq 1 ]; then
  echo "bump-version: DRY RUN — nothing written"
  echo "  version:   $old_ver -> $new_ver ($level, from $level_src)"
  echo "  fragments: ${frags[*]}"
  echo "  CHANGELOG entry:"
  printf '%s\n' "$entry"
  exit 0
fi

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
  return 0
}

# ---- 2..6: back up, render, rename, delete, validate — restore on any failure -----------------
WORK="$(mktemp -d "$repo_root/.bump-version.XXXXXX")" || die "cannot create a scratch dir under $repo_root"
TARGETS="$CHANGELOG $PLUGIN_JSON $MARKETPLACE_JSON"   # rename order
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
    echo "bump-version: restored $PLUGIN_JSON, $MARKETPLACE_JSON, $CHANGELOG and ${#frags[@]} fragment(s) byte-identical; nothing changed" >&2
  fi
  exit 1
}

mkdir -p "$WORK/bak/frag" || die "cannot create backup dir"
for t in $TARGETS; do cp -p "$t" "$WORK/bak/$(basename "$t")" || die "cannot back up $t"; done
for f in "${frags[@]}"; do cp -p "$f" "$WORK/bak/frag/$(basename "$f")" || die "cannot back up $f"; done

render_plugin "$WORK/bak/plugin.json" "$WORK/new.plugin.json" || die "cannot render plugin.json"
render_marketplace "$WORK/bak/marketplace.json" "$WORK/new.marketplace.json" || die "cannot render marketplace.json"
render_changelog "$WORK/bak/CHANGELOG.md" "$WORK/new.CHANGELOG.md" || die "cannot render CHANGELOG.md"
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

phase="done"
echo "bump-version: bumped $old_ver -> $new_ver ($level, from $level_src); folded ${#frags[@]} fragment(s): ${frags[*]}"
echo "bump-version: next: review 'git diff', then commit (plugin.json, marketplace.json, CHANGELOG.md, removed fragments) as the PR's LAST commit"
exit 0
