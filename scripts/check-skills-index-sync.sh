#!/usr/bin/env bash
# check-skills-index-sync.sh — structural SKILLS_INDEX.md ↔ SKILL.md version parity gate.
#
# WHY: per-row skill `version:` cells in SKILLS_INDEX.md are a documented
# doc-currency-gate blind spot (see CLAUDE.md §"Adding or Modifying Agents") —
# rows drift whenever a release touches a skill and only get fixed when a later
# release happens to sweep them (supervisor-readiness drifted 1.1.1 vs 1.1.2;
# automate-loop drifted the same way before v15.2.0 swept it). This gate makes
# the parity mechanical.
#
# WHAT (structural only — never scans changelog prose or example blocks):
#   1. For every {plugin}/skills/*/SKILL.md carrying a `version:` frontmatter
#      field: SKILLS_INDEX.md must have exactly ONE table row whose Directory
#      cell (the backticked `name/` cell — NOT the display name) matches that
#      skill dir, and that row's Version cell must equal the frontmatter value.
#   NOTE: every index row must carry a well-formed X.Y.Z Version cell (no
#      placeholder cells — malformed cells fail loudly). A versionless SKILL.md
#      is skipped by check 1, so its row is validated for shape/existence only.
#   COLUMN ORDER IS LOAD-BEARING: the parser reads Directory from column 3 and
#      Version from column 6 of the index tables — reordering SKILLS_INDEX
#      columns requires updating index_pairs() in the same change.
#   2. Every index row's Directory cell must reference an existing skill dir
#      containing a SKILL.md (no ghost rows).
#   Index follows skill — fix the index row, never a SKILL.md version/lastUpdated.
#
# Rows are keyed on the Directory cell so display-name phrasing ("Supervisor
# Readiness" vs `supervisor-readiness/`) can never false-positive.
#
# MULTI-PLUGIN (v15.6.0): the gate runs once per marketplace plugin whose source
# dir has a skills/ tree (loomwright, stackpack, ...). Plugins that ship no
# skills dir (mysql-mcp) are skipped silently. A skills/ dir WITHOUT a
# SKILLS_INDEX.md fails loudly (run_check's index-not-found branch).
#
# bash-3.2-safe (no mapfile / associative arrays), no network, grep/awk + jq
# (jq only for marketplace.json plugin discovery — already a hard CI dependency).
#
# Usage:
#   bash scripts/check-skills-index-sync.sh              # gate (exit 0 clean, 1 drift)
#   bash scripts/check-skills-index-sync.sh --self-test  # synthetic negative/positive proof
#
# Env overrides (used by --self-test; also handy for fixtures — when either is
# set, the gate checks ONLY that single skills-dir/index pair, no plugin loop):
#   CHECK_SKILLS_DIR    — skills root (default loomwright/skills)
#   CHECK_SKILLS_INDEX  — index file  (default $CHECK_SKILLS_DIR/SKILLS_INDEX.md)

set -uo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

MARKETPLACE_JSON=".claude-plugin/marketplace.json"

# --- helpers -----------------------------------------------------------------

# Print the frontmatter `version:` value of a SKILL.md (empty if none).
# Reads ONLY the first `--- ... ---` block — never body prose or changelogs.
frontmatter_version() {
  awk '
    NR == 1 && !/^---[[:space:]]*$/ { exit }   # frontmatter must open on line 1
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && /^version:/ {
      sub(/^version:[[:space:]]*/, "")
      gsub(/["'"'"'[:space:]]/, "")
      print
      exit
    }
  ' "$1"
}

# Emit "<dir>\t<version-cell>" for every data row of the index table.
# A data row is identified structurally: its 2nd column is a backticked
# directory path (`name/`). Header ("Directory") and separator ("-----")
# rows can never match; prose outside tables is never scanned.
index_pairs() {
  awk -F'|' '
    /^\|/ {
      dir = $3
      gsub(/^[ \t]+|[ \t]+$/, "", dir)
      if (dir !~ /^`[A-Za-z0-9._-]+\/`$/) next
      gsub(/[`\/]/, "", dir)
      ver = $6
      gsub(/[ \t]/, "", ver)
      print dir "\t" ver
    }
  ' "$1"
}

# --- the check ---------------------------------------------------------------

run_check() { # $1 = skills dir, $2 = index file
  local SKILLS_DIR="$1" INDEX="$2"
  local fail=0 pairs d skill f v rows n row_ver
  [ -f "$INDEX" ] || { echo "check-skills-index-sync: index not found: $INDEX" >&2; return 1; }
  [ -d "$SKILLS_DIR" ] || { echo "check-skills-index-sync: skills dir not found: $SKILLS_DIR" >&2; return 1; }

  pairs="$(mktemp)"
  index_pairs "$INDEX" > "$pairs"

  if [ ! -s "$pairs" ]; then
    echo "check-skills-index-sync: no data rows parsed from $INDEX — table format changed?" >&2
    rm -f "$pairs"
    return 1
  fi

  # 1) Every versioned skill has exactly one index row with a matching version cell.
  for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    skill="$(basename "$d")"
    f="$d/SKILL.md"
    [ -f "$f" ] || continue
    v="$(frontmatter_version "$f")"
    [ -n "$v" ] || continue   # no version: frontmatter — out of scope
    rows="$(awk -F'\t' -v s="$skill" '$1 == s { print $2 }' "$pairs")"
    if [ -z "$rows" ]; then
      echo "  DRIFT [missing-row] $skill — SKILL.md frontmatter is $v but SKILLS_INDEX.md has no \`$skill/\` row"
      fail=1
      continue
    fi
    n="$(printf '%s\n' "$rows" | grep -c .)"
    if [ "$n" -gt 1 ]; then
      echo "  DRIFT [duplicate-row] $skill — $n index rows for \`$skill/\` (expected exactly 1)"
      fail=1
      continue
    fi
    if [ "$rows" != "$v" ]; then
      echo "  DRIFT [version] $skill — index row says ${rows:-<empty>} but SKILL.md frontmatter is $v"
      fail=1
    fi
  done

  # 2) Every index row references an existing skill dir with a SKILL.md.
  while IFS="$(printf '\t')" read -r skill row_ver; do
    [ -n "$skill" ] || continue
    if [ ! -d "$SKILLS_DIR/$skill" ]; then
      echo "  DRIFT [ghost-row] \`$skill/\` — index row references a nonexistent skill dir"
      fail=1
    elif [ ! -f "$SKILLS_DIR/$skill/SKILL.md" ]; then
      echo "  DRIFT [ghost-row] \`$skill/\` — skill dir exists but has no SKILL.md"
      fail=1
    fi
    if ! printf '%s' "$row_ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "  DRIFT [malformed-cell] \`$skill/\` — version cell \"${row_ver:-<empty>}\" is not X.Y.Z"
      fail=1
    fi
  done < "$pairs"

  rm -f "$pairs"

  if [ "$fail" -ne 0 ]; then
    echo "✗ skills-index drift detected in $INDEX — fix the SKILLS_INDEX.md rows above (index follows skill; never edit a SKILL.md version to make the index fit)."
    return 1
  fi
  echo "✓ skills-index-sync [$SKILLS_DIR]: every versioned SKILL.md has exactly one matching index row; no ghost rows."
  return 0
}

# Gate mode: env override → single check (fixtures / --self-test recursion);
# otherwise loop over every marketplace plugin source that has a skills/ dir.
run_gate() {
  if [ -n "${CHECK_SKILLS_DIR:-}" ] || [ -n "${CHECK_SKILLS_INDEX:-}" ]; then
    local dir="${CHECK_SKILLS_DIR:-loomwright/skills}"
    run_check "$dir" "${CHECK_SKILLS_INDEX:-$dir/SKILLS_INDEX.md}"
    return $?
  fi
  command -v jq >/dev/null 2>&1 || { echo "check-skills-index-sync: jq required for marketplace plugin discovery" >&2; return 1; }
  [ -f "$MARKETPLACE_JSON" ] || { echo "check-skills-index-sync: marketplace manifest not found: $MARKETPLACE_JSON" >&2; return 1; }
  local rc=0 checked=0 src sdir
  while IFS= read -r src; do
    [ -n "$src" ] && [ "$src" != "null" ] || continue
    sdir="${src#./}"; sdir="${sdir%/}/skills"
    [ -d "$sdir" ] || continue   # plugin ships no skills (e.g. mysql-mcp) — out of scope, skip silently
    checked=$((checked + 1))
    run_check "$sdir" "$sdir/SKILLS_INDEX.md" || rc=1
  done < <(jq -r '.plugins[].source' "$MARKETPLACE_JSON")
  if [ "$checked" -eq 0 ]; then
    echo "check-skills-index-sync: no skills-bearing plugin sources found via $MARKETPLACE_JSON — gate matched nothing (anti-drift tripwire)" >&2
    return 1
  fi
  return $rc
}

# --- self-test (synthetic fixture — independent of live repo state) ----------

self_test() {
  local tmp rc pass=0 fail=0
  tmp="$(mktemp -d)"
  # Expand $tmp NOW — a deferred '$tmp' would be unbound at EXIT (local var, set -u).
  trap "rm -rf '$tmp'" EXIT

  mkdir -p "$tmp/skills/alpha" "$tmp/skills/beta"
  printf -- '---\nname: alpha\nversion: 1.0.0\n---\n# Alpha\n' > "$tmp/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\nversion: "2.1.0"\n---\n# Beta\n' > "$tmp/skills/beta/SKILL.md"

  cat > "$tmp/index.md" <<'EOF'
# Fixture Index

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Alpha | `alpha/` | — | ~100 | 1.0.0 | 2026-01 |
| Beta | `beta/` | — | ~100 | 2.1.0 | 2026-01 |
EOF

  assert() { # <label> <expected_rc> <actual_rc> <output> [<must-contain>]
    local label="$1" want="$2" got="$3" out="$4" needle="${5:-}"
    if [ "$got" -ne "$want" ]; then
      echo "SELF-TEST FAIL [$label] expected exit $want, got $got"; echo "$out" | sed 's/^/    /'
      fail=$((fail + 1)); return
    fi
    if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF "$needle"; then
      echo "SELF-TEST FAIL [$label] output missing \"$needle\""; echo "$out" | sed 's/^/    /'
      fail=$((fail + 1)); return
    fi
    echo "SELF-TEST PASS [$label]"
    pass=$((pass + 1))
  }

  local out

  # (a) aligned fixture → exit 0
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index.md" bash "$0" 2>&1)"; rc=$?
  assert "aligned-passes" 0 "$rc" "$out"

  # (b) corrupted version cell → exit 1, names the skill (the negative-test proof)
  sed 's/| 2\.1\.0 |/| 9.9.9 |/' "$tmp/index.md" > "$tmp/index-bad-version.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-bad-version.md" bash "$0" 2>&1)"; rc=$?
  assert "wrong-version-fails" 1 "$rc" "$out" "DRIFT [version] beta"

  # (a2) versionless skill: skipped by check 1, row validated for shape only → exit 0
  mkdir -p "$tmp/skills/nover"
  printf -- '# NoVer skill, no frontmatter\n' > "$tmp/skills/nover/SKILL.md"
  { cat "$tmp/index.md"; printf '| NoVer | `nover/` | — | ~100 | 1.0.0 | 2026-01 |\n'; } > "$tmp/index-nover.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-nover.md" bash "$0" 2>&1)"; rc=$?
  assert "versionless-skill-skipped" 0 "$rc" "$out"
  rm -rf "$tmp/skills/nover"

  # (a3) table format changed (zero data rows parsed) → exit 1 tripwire
  printf '# Fixture Index\n\nNo table here anymore.\n' > "$tmp/index-notable.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-notable.md" bash "$0" 2>&1)"; rc=$?
  assert "no-rows-tripwire-fails" 1 "$rc" "$out"

  # (b2) malformed version cell (non-X.Y.Z) → exit 1 via the malformed-cell branch
  sed 's/| 2\.1\.0 |/| TBD |/' "$tmp/index.md" > "$tmp/index-malformed.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-malformed.md" bash "$0" 2>&1)"; rc=$?
  assert "malformed-cell-fails" 1 "$rc" "$out" "DRIFT [malformed-cell] \`beta/\`"

  # (c2) ghost row (dir exists, no SKILL.md) → exit 1 via the second ghost sub-branch
  mkdir -p "$tmp/skills/empty"
  { cat "$tmp/index.md"; printf '| Empty | `empty/` | — | ~100 | 1.0.0 | 2026-01 |\n'; } > "$tmp/index-noskillmd.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-noskillmd.md" bash "$0" 2>&1)"; rc=$?
  assert "ghost-row-no-skillmd-fails" 1 "$rc" "$out" "skill dir exists but has no SKILL.md"
  rm -rf "$tmp/skills/empty"

  # (c) ghost row (nonexistent dir) → exit 1
  { cat "$tmp/index.md"; printf '| Gamma | `gamma/` | — | ~100 | 1.0.0 | 2026-01 |\n'; } > "$tmp/index-ghost.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-ghost.md" bash "$0" 2>&1)"; rc=$?
  assert "ghost-row-fails" 1 "$rc" "$out" "DRIFT [ghost-row] \`gamma/\`"

  # (d) missing row for a versioned skill → exit 1
  grep -v '`beta/`' "$tmp/index.md" > "$tmp/index-missing.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-missing.md" bash "$0" 2>&1)"; rc=$?
  assert "missing-row-fails" 1 "$rc" "$out" "DRIFT [missing-row] beta"

  # (e) duplicate rows for one dir → exit 1
  { cat "$tmp/index.md"; printf '| Beta again | `beta/` | — | ~100 | 2.1.0 | 2026-01 |\n'; } > "$tmp/index-dup.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-dup.md" bash "$0" 2>&1)"; rc=$?
  assert "duplicate-row-fails" 1 "$rc" "$out" "DRIFT [duplicate-row] beta"

  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# --- entrypoint --------------------------------------------------------------

case "${1:-}" in
  --self-test) self_test ;;
  "")          run_gate ;;
  *)           echo "usage: $0 [--self-test]" >&2; exit 2 ;;
esac
