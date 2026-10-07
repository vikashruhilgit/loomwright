#!/usr/bin/env bash
# check-skills-index-sync.sh — SKILLS_INDEX.md ↔ SKILL.md parity gate + index generator (--write).
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
#      Version from column 6 of the index tables (render_index also rewrites
#      Last Updated in column 7) — reordering SKILLS_INDEX columns requires
#      updating index_pairs() and render_index() in the same change.
#   2. Every index row's Directory cell must reference an existing skill dir
#      containing a SKILL.md (no ghost rows).
#   Index follows skill — fix the index row, never a SKILL.md version/lastUpdated.
#   3. GENERATED CELLS (parallel-automate/11): render_index regenerates the index
#      from SKILL.md frontmatter and the gate diffs the committed file against
#      that render — a hand-edited Version or Last Updated cell, a missing row,
#      a ghost row or a stale `**Total: N skills**` line fails, naming the row.
#      The generator OWNS: the row set (one row per skill dir with a SKILL.md,
#      keyed on the Directory cell; ghost and duplicate rows dropped; a skill
#      with no row appended under the LAST table with Skill Name = frontmatter
#      `name`, Agent Consumers `—`, Token Est. `—`), the Version cell
#      (frontmatter `version`), the Last Updated cell (frontmatter
#      `lastUpdated`) and the Total line (derived from the row count). A
#      frontmatter field that is absent leaves that cell as committed. Every
#      other byte — Skill Name, Agent Consumers, Token Est., section headings,
#      footnotes, prose, the footer date — is curated and preserved verbatim.
#      Fix drift with `--write` (generated content: never hand-merge a conflict
#      on the index, re-run `--write`).
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
#   bash scripts/check-skills-index-sync.sh --write      # regenerate every index in place (temp + rename; idempotent)
#   bash scripts/check-skills-index-sync.sh --self-test  # synthetic negative/positive proof
#
# Env overrides (used by --self-test; also handy for fixtures — when either is
# set, the gate and --write act on ONLY that single skills-dir/index pair, no plugin loop):
#   CHECK_SKILLS_DIR    — skills root (default loomwright/skills)
#   CHECK_SKILLS_INDEX  — index file  (default $CHECK_SKILLS_DIR/SKILLS_INDEX.md)

set -uo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

MARKETPLACE_JSON=".claude-plugin/marketplace.json"

# --- helpers -----------------------------------------------------------------

# Print the frontmatter value of key $2 in SKILL.md $1 (empty if none), quotes
# and whitespace stripped. Reads ONLY the first `--- ... ---` block — never
# body prose or changelogs.
frontmatter_field() {
  awk -v k="$2" '
    NR == 1 && !/^---[[:space:]]*$/ { exit }   # frontmatter must open on line 1
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && index($0, k ":") == 1 {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/["'"'"'[:space:]]/, "")
      print
      exit
    }
  ' "$1"
}

# Print the frontmatter `version:` value of a SKILL.md (empty if none).
frontmatter_version() { frontmatter_field "$1" version; }

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

# render_index <skills dir> <index file> — print the regenerated index on stdout
# (check 3 in the header: generator-owned row set / Version / Last Updated /
# Total; every curated byte preserved). Exit non-zero, printing nothing usable,
# when the index has no data row to anchor on (table format changed?) — the
# caller must never install a failed render.
render_index() { # $1 = skills dir, $2 = index file
  local SKILLS_DIR="$1" INDEX="$2" map d skill rc
  map="$(mktemp)" || return 1
  # One "<dir>\t<version>\t<lastUpdated>\t<name>" line per skill dir with a
  # SKILL.md, in glob (sorted) order — the order new rows are appended in.
  for d in "$SKILLS_DIR"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    skill="$(basename "$d")"
    printf '%s\t%s\t%s\t%s\n' "$skill" \
      "$(frontmatter_field "$d/SKILL.md" version)" \
      "$(frontmatter_field "$d/SKILL.md" lastUpdated)" \
      "$(frontmatter_field "$d/SKILL.md" name)" >> "$map"
  done
  # The map is read with getline (not as a first input file) so an EMPTY map can
  # never make the index itself be consumed as map lines.
  awk -F'|' -v OFS='|' -v mapfile="$map" '
    BEGIN {
      while ((getline line < mapfile) > 0) {
        split(line, a, "\t"); d = a[1]
        known[d] = 1; ver[d] = a[2]; lu[d] = a[3]; nm[d] = (a[4] == "" ? d : a[4])
        order[++nk] = d
      }
      close(mapfile)
    }
    /^\|/ && NF >= 8 {
      dir = $3
      gsub(/^[ \t]+|[ \t]+$/, "", dir)
      if (dir ~ /^`[A-Za-z0-9._-]+\/`$/) {
        gsub(/[`\/]/, "", dir)
        if (!(dir in known)) next     # ghost row: the generator owns the row set
        if (dir in seen) next         # duplicate row: first one wins
        seen[dir] = 1
        if (ver[dir] != "") $6 = " " ver[dir] " "
        if (lu[dir] != "")  $7 = " " lu[dir] " "
        out[++no] = $0; last = no; rows++
        next
      }
    }
    /^\*\*Total: [0-9]+ skills\*\*[ \t]*$/ { out[++no] = "\001TOTAL"; next }
    { out[++no] = $0 }
    END {
      if (last == 0) exit 3          # no data row to anchor on
      for (i = 1; i <= nk; i++) {
        d = order[i]
        if (d in seen) continue
        add[++na] = "| " nm[d] " | `" d "/` | — | — | " (ver[d] == "" ? "—" : ver[d]) " | " (lu[d] == "" ? "—" : lu[d]) " |"
        rows++
      }
      for (i = 1; i <= no; i++) {
        if (out[i] == "\001TOTAL") print "**Total: " rows " skills**"
        else print out[i]
        if (i == last) for (j = 1; j <= na; j++) print add[j]
      }
    }
  ' "$INDEX"
  rc=$?
  rm -f "$map"
  return $rc
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

  # 3) The committed index equals its frontmatter render (generated cells only).
  local rendered
  rendered="$(mktemp)"
  if ! render_index "$SKILLS_DIR" "$INDEX" > "$rendered"; then
    echo "  DRIFT [render-failed] $INDEX — render_index found no data row to regenerate"
    fail=1
  elif ! cmp -s "$INDEX" "$rendered"; then
    # Name every row (and the Total line) whose generated content differs, then
    # show the diff itself as the failure message.
    diff "$INDEX" "$rendered" | awk -F'|' '
      /^[<>] \|/ {
        d = $3; gsub(/^[ \t]+|[ \t]+$/, "", d)
        if (d ~ /^`[A-Za-z0-9._-]+\/`$/ && !(d in s)) { s[d] = 1; print "  DRIFT [generated-row] " d " — Version / Last Updated / row set differs from SKILL.md frontmatter" }
        next
      }
      /^[<>] \*\*Total: / && !t { t = 1; print "  DRIFT [generated-total] the **Total: N skills** line differs from the row count" }
    '
    echo "  DRIFT [generated] $INDEX differs from its frontmatter render (fix: bash scripts/check-skills-index-sync.sh --write):"
    diff -u -L "$INDEX (committed)" -L "$INDEX (generated)" "$INDEX" "$rendered" | sed 's/^/    /'
    fail=1
  fi
  rm -f "$rendered"

  if [ "$fail" -ne 0 ]; then
    echo "✗ skills-index drift detected in $INDEX — regenerate it with \`bash scripts/check-skills-index-sync.sh --write\` (index follows skill; never edit a SKILL.md version to make the index fit)."
    return 1
  fi
  echo "✓ skills-index-sync [$SKILLS_DIR]: every versioned SKILL.md has exactly one matching index row; no ghost rows; index equals its frontmatter render."
  return 0
}

# --write for one pair: render into a temp file beside the index (mode copied
# from the index), then rename over it. A failed or empty render never touches
# the index; an unchanged render leaves the file (and its mtime) alone.
write_one() { # $1 = skills dir, $2 = index file
  local SKILLS_DIR="$1" INDEX="$2" tmp
  [ -f "$INDEX" ] || { echo "check-skills-index-sync: index not found: $INDEX" >&2; return 1; }
  [ -d "$SKILLS_DIR" ] || { echo "check-skills-index-sync: skills dir not found: $SKILLS_DIR" >&2; return 1; }
  tmp="$(mktemp "$INDEX.XXXXXX")" || { echo "check-skills-index-sync: cannot create temp file beside $INDEX" >&2; return 1; }
  cp -p "$INDEX" "$tmp" 2>/dev/null || :
  if ! render_index "$SKILLS_DIR" "$INDEX" > "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "check-skills-index-sync: render failed for $INDEX (no data row to regenerate?) — index left unchanged" >&2
    return 1
  fi
  if cmp -s "$INDEX" "$tmp"; then
    rm -f "$tmp"
    echo "= $INDEX unchanged (already equals its frontmatter render)"
    return 0
  fi
  mv -f "$tmp" "$INDEX" || { rm -f "$tmp"; echo "check-skills-index-sync: cannot install $INDEX" >&2; return 1; }
  echo "✓ wrote $INDEX (regenerated from $SKILLS_DIR/*/SKILL.md frontmatter)"
  return 0
}

# Run <fn> <skills dir> <index> for each pair: env override → that single pair
# (fixtures / --self-test recursion); otherwise every marketplace plugin source
# that has a skills/ dir. Gate mode uses run_check, --write uses write_one.
for_each_pair() { # $1 = per-pair function
  local fn="$1"
  if [ -n "${CHECK_SKILLS_DIR:-}" ] || [ -n "${CHECK_SKILLS_INDEX:-}" ]; then
    local dir="${CHECK_SKILLS_DIR:-loomwright/skills}"
    "$fn" "$dir" "${CHECK_SKILLS_INDEX:-$dir/SKILLS_INDEX.md}"
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
    "$fn" "$sdir" "$sdir/SKILLS_INDEX.md" || rc=1
  done < <(jq -r '.plugins[].source' "$MARKETPLACE_JSON")
  if [ "$checked" -eq 0 ]; then
    echo "check-skills-index-sync: no skills-bearing plugin sources found via $MARKETPLACE_JSON — gate matched nothing (anti-drift tripwire)" >&2
    return 1
  fi
  return $rc
}

run_gate()  { for_each_pair run_check; }
run_write() { for_each_pair write_one; }

# --- self-test (synthetic fixture — independent of live repo state) ----------

self_test() {
  local tmp rc pass=0 fail=0
  tmp="$(mktemp -d)"
  # Expand $tmp NOW — a deferred '$tmp' would be unbound at EXIT (local var, set -u).
  trap "rm -rf '$tmp'" EXIT

  mkdir -p "$tmp/skills/alpha" "$tmp/skills/beta"
  printf -- '---\nname: alpha\nversion: 1.0.0\nlastUpdated: "2026-01"\n---\n# Alpha\n' > "$tmp/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\nversion: "2.1.0"\nlastUpdated: 2026-01\n---\n# Beta\n' > "$tmp/skills/beta/SKILL.md"

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

  # --- generated cells (check 3) + --write (parallel-automate/11) ------------

  # (f) hand-edited Last Updated cell (Version still right) → exit 1 naming the row
  sed '/`beta\/`/s/| 2026-01 |$/| 2025-12 |/' "$tmp/index.md" > "$tmp/index-bad-lu.md"
  if cmp -s "$tmp/index.md" "$tmp/index-bad-lu.md"; then
    echo "SELF-TEST FAIL [wrong-last-updated-fails] fixture mutation did not apply"; fail=$((fail + 1))
  else
    out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-bad-lu.md" bash "$0" 2>&1)"; rc=$?
    assert "wrong-last-updated-fails" 1 "$rc" "$out" 'DRIFT [generated-row] `beta/`'
  fi

  # (g) hand-edited Version cell is also named by the render diff
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-bad-version.md" bash "$0" 2>&1)"; rc=$?
  assert "wrong-version-named-by-render" 1 "$rc" "$out" 'DRIFT [generated-row] `beta/`'

  # (h) missing row is named by the render diff too (the row it would append)
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-missing.md" bash "$0" 2>&1)"; rc=$?
  assert "missing-row-named-by-render" 1 "$rc" "$out" 'DRIFT [generated-row] `beta/`'

  # (i) Total line: right count passes, wrong count fails
  { cat "$tmp/index.md"; printf '\n**Total: 2 skills**\n'; } > "$tmp/index-total.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-total.md" bash "$0" 2>&1)"; rc=$?
  assert "total-line-aligned-passes" 0 "$rc" "$out"
  sed 's/^\*\*Total: 2 skills\*\*$/**Total: 3 skills**/' "$tmp/index-total.md" > "$tmp/index-total-bad.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-total-bad.md" bash "$0" 2>&1)"; rc=$?
  assert "total-line-wrong-fails" 1 "$rc" "$out" "DRIFT [generated-total]"

  # (j) --write on a drifted multi-table index: Version / Last Updated regenerated,
  #     ghost + duplicate rows dropped, missing rows appended under the LAST table
  #     (Skill Name = frontmatter name, curated cells `—`), Total recounted; every
  #     curated cell, heading, footnote and prose line preserved byte-for-byte.
  mkdir -p "$tmp/w/skills/alpha" "$tmp/w/skills/beta" "$tmp/w/skills/gamma" "$tmp/w/skills/delta"
  cp "$tmp/skills/alpha/SKILL.md" "$tmp/w/skills/alpha/SKILL.md"
  cp "$tmp/skills/beta/SKILL.md" "$tmp/w/skills/beta/SKILL.md"
  printf -- '---\nname: gamma-skill\nversion: "3.0.0"\nlastUpdated: "2026-02"\n---\n# Gamma\n' > "$tmp/w/skills/gamma/SKILL.md"
  printf -- '# Delta, versionless — its committed cells are kept\n' > "$tmp/w/skills/delta/SKILL.md"
  cat > "$tmp/w/index.md" <<'EOF'
# Fixture Index 2

Intro prose stays.

## Section A

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Alpha Display | `alpha/` | Custom Consumer (preload) | ~123 [^fn] | 0.0.1 | 2025-12 |
| Ghost | `ghost/` | — | ~100 | 1.0.0 | 2026-01 |
| Alpha Dup | `alpha/` | — | ~100 | 1.0.0 | 2026-01 |

[^fn]: footnote prose stays.

## Section B

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Delta | `delta/` | — | ~100 | 1.0.0 | 2026-01 |

---

**Total: 9 skills**

_Last updated: 2020-01-01_
EOF
  cat > "$tmp/w/expected.md" <<'EOF'
# Fixture Index 2

Intro prose stays.

## Section A

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Alpha Display | `alpha/` | Custom Consumer (preload) | ~123 [^fn] | 1.0.0 | 2026-01 |

[^fn]: footnote prose stays.

## Section B

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Delta | `delta/` | — | ~100 | 1.0.0 | 2026-01 |
| beta | `beta/` | — | — | 2.1.0 | 2026-01 |
| gamma-skill | `gamma/` | — | — | 3.0.0 | 2026-02 |

---

**Total: 4 skills**

_Last updated: 2020-01-01_
EOF
  out="$(CHECK_SKILLS_DIR="$tmp/w/skills" CHECK_SKILLS_INDEX="$tmp/w/index.md" bash "$0" 2>&1)"; rc=$?
  assert "drifted-multi-table-fails-before-write" 1 "$rc" "$out" 'DRIFT [generated-row] `gamma/`'
  out="$(CHECK_SKILLS_DIR="$tmp/w/skills" CHECK_SKILLS_INDEX="$tmp/w/index.md" bash "$0" --write 2>&1)"; rc=$?
  assert "write-exits-0" 0 "$rc" "$out" "wrote $tmp/w/index.md"
  if cmp -s "$tmp/w/index.md" "$tmp/w/expected.md"; then
    echo "SELF-TEST PASS [write-regenerates-generated-cells-preserves-curated]"; pass=$((pass + 1))
  else
    echo "SELF-TEST FAIL [write-regenerates-generated-cells-preserves-curated]"
    diff "$tmp/w/expected.md" "$tmp/w/index.md" | sed 's/^/    /'; fail=$((fail + 1))
  fi
  out="$(CHECK_SKILLS_DIR="$tmp/w/skills" CHECK_SKILLS_INDEX="$tmp/w/index.md" bash "$0" 2>&1)"; rc=$?
  assert "gate-passes-after-write" 0 "$rc" "$out"

  # (k) a second --write is a byte-for-byte no-op
  cp "$tmp/w/index.md" "$tmp/w/after-first.md"
  out="$(CHECK_SKILLS_DIR="$tmp/w/skills" CHECK_SKILLS_INDEX="$tmp/w/index.md" bash "$0" --write 2>&1)"; rc=$?
  assert "second-write-reports-unchanged" 0 "$rc" "$out" "unchanged"
  if cmp -s "$tmp/w/index.md" "$tmp/w/after-first.md"; then
    echo "SELF-TEST PASS [write-idempotent]"; pass=$((pass + 1))
  else
    echo "SELF-TEST FAIL [write-idempotent] second --write changed the file"; fail=$((fail + 1))
  fi

  # (l) a render with no data row to anchor on never touches the index
  cp "$tmp/index-notable.md" "$tmp/notable-before.md"
  out="$(CHECK_SKILLS_DIR="$tmp/skills" CHECK_SKILLS_INDEX="$tmp/index-notable.md" bash "$0" --write 2>&1)"; rc=$?
  assert "write-render-failure-exits-1" 1 "$rc" "$out" "index left unchanged"
  if cmp -s "$tmp/index-notable.md" "$tmp/notable-before.md" && [ -z "$(find "$tmp" -maxdepth 1 -name 'index-notable.md.*')" ]; then
    echo "SELF-TEST PASS [write-render-failure-leaves-index-and-no-temp]"; pass=$((pass + 1))
  else
    echo "SELF-TEST FAIL [write-render-failure-leaves-index-and-no-temp]"; fail=$((fail + 1))
  fi

  echo "self-test: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# --- entrypoint --------------------------------------------------------------

case "${1:-}" in
  --self-test) self_test ;;
  --write)     run_write ;;
  "")          run_gate ;;
  *)           echo "usage: $0 [--write | --self-test]" >&2; exit 2 ;;
esac
