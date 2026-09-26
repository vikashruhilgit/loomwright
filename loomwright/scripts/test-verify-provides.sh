#!/usr/bin/env bash
# test-verify-provides.sh — static suite for verify-provides.sh (the ONE implementation of the
# `provides:` checks) AND the seam grep-gate over its consumers (agents/execute-manager.md poll-loop
# gate, agents/supervisor.md Single-Agent + Sequential gates, agents/worker.md Step 5.5, the
# RESULT_SCHEMAS.md kind-table copy, the orchestrator.md prose mirror).
#
# Modelled on test-brief-conformance-seam.sh: ok()/no() DEFINED here (test-suite-helpers-defined.sh
# meta-gate), pass/fail counters, "RESULT: N passed, M failed" tail, exit 1 on any failure, paths
# from $BASH_SOURCE, fixtures in `mktemp -d` with the cwd moved ELSEWHERE (proves --root), no
# gh/network/Docker. bash 3.2 / BSD userland safe.
#
# Covers (brief 2026-09-13-manager-reverifies-provides AC5/AC6/AC8/AC9):
#   script  — per-kind present/missing; `provides: []`; the `unverifiable` reasons incl. `bad_args` (dangling /
#             empty --root; exit 0 + stderr reason each; no JSON-less exit 0 in the arg parser
#             outside --kind-table / --help); two-item miss ⇒ outputs_gap exactly "a/b.ts:Sym, c/d.ts"; symbol
#             on an absent file ⇒ missing with a grep check_run (exit 2); --kind-table; JSON validity
#             via `jq -e .`; ERE specials ($ . ( [ and + * ? | { combined) match LITERALLY and a
#             one-char mutation goes `missing`; type-boundary (typeFoo / Shapes do not match);
#             a '/\/\n-sequence name round-trips; the jq-less path (jq off PATH, id containing `"`)
#             prints exit 0 + the literal object with NO subtask_id key; three brief layouts
#             (H3 + fence + `# Subtask N` comment / H2 + `subtask_N:` key / inline `### Subtask N`
#             heading, raw YAML); provides list ends at the next top-level key; --root honoured;
#             `subtask_<non-digit>` keys (`subtask_id:` / `subtask_title:`) and `subtasks:` are never
#             anchors (brief G, + mutation control); a lone `subtask_id:` block on an anchor-less
#             brief anchors as subtask 1, two are ambiguous ⇒ subtask_not_found (H/I); an anchor
#             with no `provides:` key ⇒ no_contracts, not [] (J); a duplicate anchor resolves to
#             the one carrying provides (K); `--parse-only` counts entries without disk checks.
#   seams   — EM §"v12 outputs_verified gate" cites verify-provides.sh + provides_mismatch +
#             "regardless of the worker"; Supervisor Single-Agent step 3 AND Sequential gate cite
#             verify-provides.sh with `--root .` (by anchor, never line number); worker Step 5.5 cites
#             it and covers the field-less `brief_unreadable` / `jq_missing` reasons; EM Step 2b cites
#             `--kind-table` and restates NO table row / GNU-ism, and so does the preloaded
#             skills/async-orchestration/SKILL.md §Pre-Spawn Verification Gate; RESULT_SCHEMAS.md marker block ==
#             `--kind-table` byte-for-byte; orchestrator.md has
#             0 hits of the retired "(worker self-verification, zero tokens)" parenthetical.
#   routing — the EM gate names the two cells that are NOT disk-wins: `status: partial` with an
#             EMPTY outputs_gap (the worker.md Step 1 carve-out — checkpoint, never a pass) and an
#             ABSENT WORKER_RESULT on an unverifiable contract (checkpoint, never "disk verified");
#             both Supervisor gates state the carve-out; all three consumers + the script header pin
#             the subtask_id shape (bare anchor token); worker Step 5.5 passes the worktree path on the
#             Parallel path, not `--root .`; subtask_not_found lists the anchors seen on stderr.
#   (m)     — MUTATION CONTROLS: (1) delete the script-call line(s) from a COPY of execute-manager.md's
#             poll-loop gate; (2) delete the carve-out clause from another COPY; (3) restate a kind-table
#             row carrying GNU `\s`/`\b` inside a COPY of Step 2b (the pointer-vs-copy drift); (4) the same
#             row inside a COPY of the async-orchestration skill's gate section; (5) restore the
#             bare `exit 0` in a COPY of the script's --root branch (the parser-exit guard). Each
#             mutant is gated on non-empty + differs-from-original; the seam assertion against it MUST
#             fail — otherwise the assertion above is vacuous.
#
# EXPLICIT LIMIT: this pins the script's behaviour and the WIRING (the prompts cite it where they say
# they do). It cannot prove an Execute Manager actually runs the Bash call — that is prompt behaviour,
# first observable on the NEXT job after the plugin is reinstalled.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/.." && pwd)"

SCRIPT="$HERE/verify-provides.sh"
EM="$PLUGIN_ROOT/agents/execute-manager.md"
SUP="$PLUGIN_ROOT/agents/supervisor.md"
WORKER="$PLUGIN_ROOT/agents/worker.md"
ORCH="$PLUGIN_ROOT/agents/orchestrator.md"
SCHEMAS="$PLUGIN_ROOT/docs/RESULT_SCHEMAS.md"
ASYNC="$PLUGIN_ROOT/skills/async-orchestration/SKILL.md"
FAILDOC="$PLUGIN_ROOT/docs/FAILURE_ESCALATION.md"
LAUNCHPAD="$PLUGIN_ROOT/agents/launch-pad.md"
REVIEWER="$PLUGIN_ROOT/agents/plan-reviewer.md"
READINESS="$PLUGIN_ROOT/skills/supervisor-readiness/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$SCRIPT" "$EM" "$SUP" "$WORKER" "$ORCH" "$SCHEMAS" "$FAILDOC" "$ASYNC" "$LAUNCHPAD" "$REVIEWER" "$READINESS"; do
  [ -f "$f" ] || no "MISSING surface: $f"
done
if [ "$fail" -ne 0 ]; then
  echo; echo "RESULT: $pass passed, $fail failed"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  no "jq is required to run this suite (the script itself degrades to jq_missing without it)"
  echo; echo "RESULT: $pass passed, $fail failed"; exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/verify-provides.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"
mkdir -p "$ROOT/src" "$ROOT/a" "$ROOT/c" "$TMP/elsewhere" "$TMP/nojq"
cd "$TMP/elsewhere" || exit 1     # cwd is NOT the root — every hit below proves --root

# run <brief> <id> [extra args...] — stdout to $OUT, stderr to $ERR, exit code in $RC
OUT=""; ERR=""; RC=0
run() {
  OUT="$(bash "$SCRIPT" "$@" 2>"$TMP/stderr")"; RC=$?
  ERR="$(cat "$TMP/stderr")"
}
jq_get() { printf '%s' "$OUT" | jq -r "$1"; }
valid_json() { printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; }

# ----------------------------------------------------------------------------- fixtures
printf 'export const Sym = 1;\n' > "$ROOT/src/a.ts"
printf 'export interface Shape {}\ntype Alias = number;\nclass Widget {}\nenum Color {}\nconst typeFoo = 1;\ninterface Shapes {}\n' > "$ROOT/src/t.ts"
printf 'x Foo$Bar y\n' > "$ROOT/src/dollar.txt";    printf 'x FooXBar y\n' > "$ROOT/src/dollar_mut.txt"
printf 'x Foo.Bar y\n' > "$ROOT/src/dot.txt";       printf 'x FooXBar y\n' > "$ROOT/src/dot_mut.txt"
printf 'x Foo(Bar y\n' > "$ROOT/src/paren.txt";     printf 'x FooXBar y\n' > "$ROOT/src/paren_mut.txt"
printf 'x Foo[Bar y\n' > "$ROOT/src/bracket.txt";   printf 'x FooXBar y\n' > "$ROOT/src/bracket_mut.txt"
printf 'x a+b*c?d|e{f} y\n' > "$ROOT/src/combo.txt"; printf 'x aXbXcXdXeXfX y\n' > "$ROOT/src/combo_mut.txt"
printf "it's\\\\back\\\\nslash here\n" > "$ROOT/src/inject.txt"     # literal: it's\back\nslash here
printf 'export const Sym = 1;\n' > "$ROOT/a/b.ts"                   # a/b.ts exists but lacks Gone
# c/d.ts deliberately absent

# Brief A — the REAL Launch Pad shape: H3 heading, ```yaml fence, `# Subtask N —` comment anchors,
# trailing `# …` comments on entries, requires/lanes after provides, two subtasks.
cat > "$TMP/briefA.md" <<'EOF'
# Supervisor Job: fixture A

## Environment
- **Project:** /nowhere

## Subtask Structure

| # | Title |
|---|-------|
| 1 | first |
| 12 | twelfth |

### Subtask Contracts

```yaml
# Subtask 1 — first (LAUNCHABLE)
provides:
  - {kind: "file",   path: "src/a.ts"}                                  # exists
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}                     # exists
  - {kind: "type",   path: "src/t.ts", name: "Shape"}                   # interface Shape
  - {kind: "file",   path: "src/nope.ts"}                               # absent
  - {kind: "symbol", path: "src/a.ts", name: "Missing"}                 # absent
  - {kind: "type",   path: "src/t.ts", name: "Foo"}                     # typeFoo must NOT match
requires:
  - {kind: "file", path: "src/req-only.ts"}    # must NOT be counted as a provides entry
lanes:
  - "src/**"
external_requires: []

# Subtask 12 — twelfth (BLOCKED)
provides:
  - {kind: "symbol", path: "a/b.ts", name: "Gone"}
  - {kind: "file",   path: "c/d.ts"}
requires: []
lanes: []
external_requires: []
```

## Configuration
- **Workers:** 2
EOF

# Brief B — H2 heading (skill example shape), lowercase "contracts", `subtask_N:` key anchors,
# fenced, `provides: []` on subtask 2.
cat > "$TMP/briefB.md" <<'EOF'
## Subtask contracts

```yaml
subtask_1:
  provides:
    - {kind: "symbol", path: "src/t.ts", name: "Widget"}
    - {kind: "type",   path: "src/t.ts", name: "Alias"}
  requires: []
subtask_2:
  provides: []
  requires: []
```
EOF

# Brief C — inline layout: `### Subtask N` markdown heading, NO umbrella heading, RAW YAML (no
# fence), a symbol whose path file is absent, followed by an unrelated heading.
cat > "$TMP/briefC.md" <<'EOF'
## Subtask Structure

### Subtask 1 — inline shape
provides:
  - {kind: symbol, path: src/t.ts, name: Color}
  - {kind: "symbol", path: "c/d.ts", name: "Ghost"}
requires: []

### Subtask 2 — sibling
provides:
  - {kind: "file", path: "src/a.ts"}

## Configuration
EOF

# Brief D — ERE specials + injection-safety names
cat > "$TMP/briefD.md" <<'EOF'
### Subtask Contracts

```yaml
# Subtask 1 — specials
provides:
  - {kind: "symbol", path: "src/dollar.txt",      name: "Foo$Bar"}
  - {kind: "symbol", path: "src/dollar_mut.txt",  name: "Foo$Bar"}
  - {kind: "symbol", path: "src/dot.txt",         name: "Foo.Bar"}
  - {kind: "symbol", path: "src/dot_mut.txt",     name: "Foo.Bar"}
  - {kind: "symbol", path: "src/paren.txt",       name: "Foo(Bar"}
  - {kind: "symbol", path: "src/paren_mut.txt",   name: "Foo(Bar"}
  - {kind: "symbol", path: "src/bracket.txt",     name: "Foo[Bar"}
  - {kind: "symbol", path: "src/bracket_mut.txt", name: "Foo[Bar"}
  - {kind: "symbol", path: "src/combo.txt",       name: "a+b*c?d|e{f}"}
  - {kind: "symbol", path: "src/combo_mut.txt",   name: "a+b*c?d|e{f}"}
  - {kind: "symbol", path: "src/inject.txt",      name: "it's\back\nslash"}
requires: []
```
EOF

# Brief E — a `provides:` line with no parsable entries and no `[]`
cat > "$TMP/briefE.md" <<'EOF'
### Subtask Contracts
```yaml
# Subtask 1 — degenerate
provides:
  - not an entry
requires: []
```
EOF

# Brief F — no contract block at all
printf '# Some brief\n\n## Task\nDo the thing.\n' > "$TMP/briefF.md"

# ============================================================================ SCRIPT
echo "--- script: brief A (H3 + fence + '# Subtask N' comment + trailing comments) ---"
run "$TMP/briefA.md" 1 --root "$ROOT"
[ "$RC" -eq 0 ] && ok "A/1 exits 0" || no "A/1 exit $RC"
valid_json && ok "A/1 stdout is valid JSON (jq -e .)" || no "A/1 stdout not JSON: $OUT"
[ "$(jq_get '.subtask_id')" = "1" ] && ok "A/1 subtask_id echoed" || no "A/1 subtask_id: $(jq_get '.subtask_id')"
[ "$(jq_get '.source')" = "verify-provides.sh" ] && ok "A/1 source field" || no "A/1 source: $(jq_get '.source')"
[ "$(jq_get '.outputs_verified | length')" = "6" ] && ok "A/1 six provides entries (requires entry NOT counted; list ends at next top-level key)" || no "A/1 entry count: $(jq_get '.outputs_verified | length')"
[ "$(jq_get '.outputs_verified[0].status')" = "present" ] && ok "A/1 file present" || no "A/1 file present: $(jq_get '.outputs_verified[0]')"
case "$(jq_get '.outputs_verified[0].check_run')" in "test -f "*"(exit 0)") ok "A/1 file check_run starts with 'test -f' and carries exit code" ;; *) no "A/1 file check_run: $(jq_get '.outputs_verified[0].check_run')" ;; esac
[ "$(jq_get '.outputs_verified[0] | has("name")')" = "false" ] && ok "A/1 file entry omits name" || no "A/1 file entry has name key"
[ "$(jq_get '.outputs_verified[1].status')" = "present" ] && ok "A/1 symbol present" || no "A/1 symbol: $(jq_get '.outputs_verified[1]')"
[ "$(jq_get '.outputs_verified[2].status')" = "present" ] && ok "A/1 type present (interface Shape)" || no "A/1 type: $(jq_get '.outputs_verified[2]')"
[ "$(jq_get '.outputs_verified[3].status')" = "missing" ] && ok "A/1 file missing" || no "A/1 file missing: $(jq_get '.outputs_verified[3]')"
[ "$(jq_get '.outputs_verified[4].status')" = "missing" ] && ok "A/1 symbol missing" || no "A/1 symbol missing: $(jq_get '.outputs_verified[4]')"
[ "$(jq_get '.outputs_verified[5].status')" = "missing" ] && ok "A/1 type boundary: 'typeFoo' does not satisfy type Foo" || no "A/1 type boundary: $(jq_get '.outputs_verified[5]')"
[ "$(jq_get '.outputs_gap')" = "src/nope.ts, src/a.ts:Missing, src/t.ts:Foo" ] && ok "A/1 outputs_gap format + order (path, path:name)" || no "A/1 outputs_gap: $(jq_get '.outputs_gap')"
case "$(jq_get '.outputs_verified[2].check_run')" in *"(type|interface|class|enum)[[:space:]]+Shape([^[:alnum:]_]|\$)"*) ok "A/1 type check_run is the portable ERE (no \\s / \\b)" ;; *) no "A/1 type check_run: $(jq_get '.outputs_verified[2].check_run')" ;; esac

run "$TMP/briefA.md" 12 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "2" ] && ok "A/12 second anchor found (id 1 vs 12 disambiguated)" || no "A/12 entries: $OUT"
[ "$(jq_get '.outputs_gap')" = "a/b.ts:Gone, c/d.ts" ] && ok "A/12 two-item miss ⇒ outputs_gap exactly 'a/b.ts:Gone, c/d.ts'" || no "A/12 outputs_gap: $(jq_get '.outputs_gap')"

run "$TMP/briefA.md" 1
[ "$(jq_get '.outputs_verified[0].status')" = "missing" ] && ok "--root honoured: same brief without --root from a foreign cwd ⇒ missing" || no "--root not honoured: $(jq_get '.outputs_verified[0]')"

run "$TMP/briefA.md" 3 --root "$ROOT"
[ "$RC" -eq 0 ] && [ "$(jq_get '.status')" = "unverifiable" ] && [ "$(jq_get '.reason')" = "subtask_not_found" ] && ok "unknown id ⇒ unverifiable/subtask_not_found, exit 0" || no "subtask_not_found: rc=$RC $OUT"
case "$ERR" in *subtask_not_found*) ok "subtask_not_found reason on stderr" ;; *) no "stderr lacks reason: $ERR" ;; esac
case "$ERR" in *"anchors found: 1, 12"*) ok "subtask_not_found lists the anchors the brief carries (1, 12) — the umbrella headings are not anchors" ;; *) no "subtask_not_found stderr lacks the anchor list: $ERR" ;; esac
run "$TMP/briefA.md" 1-first --root "$ROOT"
[ "$(jq_get '.reason')" = "subtask_not_found" ] && ok "a slug-shaped id (1-first) is NOT the anchor token ⇒ subtask_not_found (the shape the consumers must not pass)" || no "slug id: $OUT"

echo "--- script: brief B (H2 heading, lowercase, subtask_N: keys, provides: []) ---"
run "$TMP/briefB.md" 1 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "2" ] && [ "$(jq_get '.outputs_gap')" = "" ] && ok "B/1 subtask_N: anchor, class + type keywords present, gap empty" || no "B/1: $OUT"
run "$TMP/briefB.md" 2 --root "$ROOT"
valid_json && [ "$(jq_get '.outputs_verified | length')" = "0" ] && [ "$(jq_get '.outputs_gap')" = "" ] && [ "$(jq_get '.status // "none"')" = "none" ] && ok "B/2 provides: [] ⇒ outputs_verified [] + outputs_gap \"\" (not unverifiable)" || no "B/2 provides []: $OUT"

echo "--- script: brief C (inline ### Subtask N heading, raw YAML, no umbrella) ---"
run "$TMP/briefC.md" 1 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "2" ] && ok "C/1 inline heading anchor, unquoted values parsed" || no "C/1: $OUT"
[ "$(jq_get '.outputs_verified[0].status')" = "present" ] && ok "C/1 unquoted symbol Color present (enum)" || no "C/1 Color: $(jq_get '.outputs_verified[0]')"
[ "$(jq_get '.outputs_verified[1].status')" = "missing" ] && ok "C/1 symbol on ABSENT file ⇒ missing" || no "C/1 ghost: $(jq_get '.outputs_verified[1]')"
case "$(jq_get '.outputs_verified[1].check_run')" in "grep -nE -- "*"(exit 2)") ok "C/1 absent-file symbol check_run is a grep with exit 2" ;; *) no "C/1 check_run: $(jq_get '.outputs_verified[1].check_run')" ;; esac
run "$TMP/briefC.md" 2 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "1" ] && [ "$(jq_get '.outputs_gap')" = "" ] && ok "C/2 list ends at the next markdown heading" || no "C/2: $OUT"

echo "--- script: brief D (ERE specials match literally; one-char mutation ⇒ missing) ---"
run "$TMP/briefD.md" 1 --root "$ROOT"
valid_json && ok "D stdout valid JSON with special names" || no "D stdout not JSON: $OUT"
i=0
for label in 'dollar $' 'dot .' 'paren (' 'bracket [' 'combo +*?|{'; do
  [ "$(jq_get ".outputs_verified[$i].status")" = "present" ] && ok "D literal ${label}: present" || no "D literal ${label}: $(jq_get ".outputs_verified[$i]")"
  i=$((i+1))
  [ "$(jq_get ".outputs_verified[$i].status")" = "missing" ] && ok "D mutated ${label}: missing (no wildcard leak)" || no "D mutated ${label}: $(jq_get ".outputs_verified[$i]")"
  i=$((i+1))
done
[ "$(jq_get '.outputs_verified[10].name')" = "it's\\back\\nslash" ] && ok "D injection name (' \\ \\n-sequence) round-trips through jq --arg" || no "D injection name: $(jq_get '.outputs_verified[10].name')"
[ "$(jq_get '.outputs_verified[10].status')" = "present" ] && ok "D injection name matched literally on disk" || no "D injection: $(jq_get '.outputs_verified[10]')"

echo "--- script: subtask_<non-digit> keys are never anchors (2026-09-26 subtask_id: regression) ---"
# Brief G — the shape four 2026-09-24..26 briefs carried: `# Subtask 1` comment, THEN a `subtask_id:`
# slug key, then provides. The key used to register as an anchor for subtask "id", ending the block
# before `provides:` ⇒ a vacuous `outputs_verified: []`. Also `subtask_title:` / `subtasks:` keys.
cat > "$TMP/briefG.md" <<'EOF2'
## Subtask Contracts

```yaml
# Subtask 1 — end-to-end (LAUNCHABLE)
subtask_id: thing-01
subtask_title: "the thing"
subtasks: 1
lanes:
  - src/a.ts
requires: []
provides:
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}
  - {kind: "file",   path: "src/nope.ts"}
out_of_lane: []
```
EOF2
run "$TMP/briefG.md" 1 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "2" ] && [ "$(jq_get '.outputs_gap')" = "src/nope.ts" ] && ok "G/1 '# Subtask 1' + subtask_id:/subtask_title:/subtasks: keys ⇒ both provides parsed (not a vacuous [])" || no "G/1: $OUT"
run "$TMP/briefG.md" 2 --root "$ROOT"
case "$ERR" in *"anchors found: 1"$'\n'*|*"anchors found: 1") ok "G/2 anchor list is exactly '1' — no phantom 'id' / 'title' / 's' anchor" ;; *) no "G/2 anchor list: $ERR" ;; esac

# Brief H — NO anchor, exactly ONE `subtask_id:` block (the 2026-09-26 learning-emit brief shape).
cat > "$TMP/briefH.md" <<'EOF2'
## Subtask Structure

| # | Title |
|---|-------|
| 1 | only |

```yaml
subtask_id: only-01
lanes:
  - src/a.ts
requires: []
provides:
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}
out_of_lane: []
```
EOF2
run "$TMP/briefH.md" 1 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "1" ] && [ "$(jq_get '.outputs_verified[0].status')" = "present" ] && ok "H/1 lone subtask_id: block on an anchor-less brief anchors as subtask 1 (legacy fallback)" || no "H/1 fallback: $OUT"
case "$ERR" in *"lone \`subtask_id: only-01\` block anchored as subtask 1"*) ok "H/1 fallback is announced on stderr (never silent)" ;; *) no "H/1 fallback not logged: $ERR" ;; esac
run "$TMP/briefH.md" 2 --root "$ROOT"
[ "$(jq_get '.reason')" = "subtask_not_found" ] && ok "H/2 the fallback serves id 1 only ⇒ id 2 is subtask_not_found" || no "H/2: $OUT"

# Brief I — NO anchor, TWO `subtask_id:` blocks (the verify-spec-replay shape): ambiguous ⇒ fail closed.
cat > "$TMP/briefI.md" <<'EOF2'
```yaml
subtask_id: two-01
provides:
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}
```

```yaml
subtask_id: two-02
provides:
  - {kind: "file", path: "src/a.ts"}
```
EOF2
run "$TMP/briefI.md" 1 --root "$ROOT"
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "subtask_not_found" ] && ok "I/1 two subtask_id: blocks, no anchors ⇒ subtask_not_found (never guess by position)" || no "I/1: rc=$RC $OUT"
case "$ERR" in *"2 \`subtask_id:\` key(s) (two-01, two-02)"*"# Subtask N"*) ok "I/1 stderr names the slug keys and the fix (anchor with # Subtask N)" ;; *) no "I/1 stderr hint: $ERR" ;; esac

# Brief J — an anchor with NO provides: key under it ⇒ no_contracts, never an empty list.
cat > "$TMP/briefJ.md" <<'EOF2'
```yaml
# Subtask 1 — contract-less
requires: []
lanes: []
# Subtask 2 — has one
provides:
  - {kind: "file", path: "src/a.ts"}
```
EOF2
run "$TMP/briefJ.md" 1 --root "$ROOT"
[ "$RC" -eq 0 ] && [ "$(jq_get '.status')" = "unverifiable" ] && [ "$(jq_get '.reason')" = "no_contracts" ] && ok "J/1 anchor without a provides: key ⇒ unverifiable/no_contracts (not outputs_verified [])" || no "J/1: rc=$RC $OUT"
case "$ERR" in *"no provides: key"*) ok "J/1 stderr says the provides: key is absent" ;; *) no "J/1 stderr: $ERR" ;; esac
run "$TMP/briefJ.md" 2 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "1" ] && ok "J/2 sibling with provides still parses" || no "J/2: $OUT"

# Brief K — the same anchor twice: a prose `### Subtask 1` section (no provides) THEN the contract comment.
cat > "$TMP/briefK.md" <<'EOF2'
### Subtask 1 — prose description
Does the thing.

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "src/a.ts", name: "Sym"}
```
EOF2
run "$TMP/briefK.md" 1 --root "$ROOT"
[ "$(jq_get '.outputs_verified | length')" = "1" ] && ok "K/1 duplicate anchor: the occurrence carrying provides: wins over an earlier prose heading" || no "K/1: $OUT"

echo "--- script: --parse-only (Launch Pad's pre-review anchor check; no disk checks) ---"
run "$TMP/briefA.md" 1 --parse-only --root "$TMP/does-not-exist"
valid_json && [ "$(jq_get '.status')" = "parsed" ] && [ "$(jq_get '.provides_count')" = "6" ] && [ "$(jq_get 'has("outputs_verified")')" = "false" ] && ok "--parse-only A/1 ⇒ status parsed, provides_count 6, no disk results (root need not exist)" || no "--parse-only A/1: $OUT"
run "$TMP/briefB.md" 2 --parse-only
[ "$(jq_get '.status')" = "parsed" ] && [ "$(jq_get '.provides_count')" = "0" ] && ok "--parse-only explicit provides: [] ⇒ parsed, provides_count 0" || no "--parse-only B/2: $OUT"
run "$TMP/briefG.md" 1 --parse-only
[ "$(jq_get '.provides_count')" = "2" ] && ok "--parse-only G/1 (subtask_id: under # Subtask 1) ⇒ provides_count 2" || no "--parse-only G/1: $OUT"
run "$TMP/briefI.md" 1 --parse-only
[ "$(jq_get '.reason')" = "subtask_not_found" ] && ok "--parse-only I/1 ⇒ subtask_not_found (the brief a reviewer must bounce)" || no "--parse-only I/1: $OUT"
run "$TMP/briefJ.md" 1 --parse-only
[ "$(jq_get '.reason')" = "no_contracts" ] && ok "--parse-only J/1 ⇒ no_contracts" || no "--parse-only J/1: $OUT"

# MUTATION CONTROL — restore the pre-fix anchor rule (key form `[[:alnum:]]`, no subtask_<non-digit>
# guard) in a COPY of the script; brief G MUST regress to the empty/vacuous result.
MUTA="$TMP/verify-provides-old-anchor.sh"
sed -e '/subtask_\[\^0-9\]\/) return 0$/d' \
    -e 's#subtask\[\[:space:\]_-\]\*\[0-9\]/#subtask[[:space:]_-]*[[:alnum:]]/#' "$SCRIPT" > "$MUTA"
if cmp -s "$MUTA" "$SCRIPT"; then no "old-anchor mutant identical to original — control invalid (anchor_kind shape changed?)"
else
  MOUT="$(bash "$MUTA" "$TMP/briefG.md" 1 --root "$ROOT" 2>/dev/null)"
  if [ "$(printf '%s' "$MOUT" | jq -r '.outputs_verified | length')" = "2" ]; then
    no "MUTATION CONTROL: brief G still parses with the pre-fix anchor rule — the G/1 assertion is vacuous"
  else ok "MUTATION CONTROL: the pre-fix anchor rule makes brief G lose its provides (G/1 is load-bearing)"; fi
fi

echo "--- script: unverifiable reasons + degenerate list ---"
run "$TMP/does-not-exist.md" 1 --root "$ROOT"
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "brief_unreadable" ] && ok "missing brief ⇒ unverifiable/brief_unreadable, exit 0" || no "brief_unreadable: rc=$RC $OUT"
case "$ERR" in *brief_unreadable*) ok "brief_unreadable reason on stderr" ;; *) no "stderr lacks reason: $ERR" ;; esac
run "$TMP/briefF.md" 1 --root "$ROOT"
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "no_contracts" ] && ok "brief without contracts ⇒ unverifiable/no_contracts, exit 0" || no "no_contracts: rc=$RC $OUT"
case "$ERR" in *no_contracts*) ok "no_contracts reason on stderr" ;; *) no "stderr lacks reason: $ERR" ;; esac
run "$TMP/briefE.md" 1 --root "$ROOT"
[ "$RC" -eq 0 ] && [ "$(jq_get '.outputs_verified | length')" = "0" ] && [ "$(jq_get '.outputs_gap')" = "" ] && ok "provides: with no parsable entries ⇒ [] + \"\" (logged)" || no "degenerate provides: $OUT"
[ -n "$ERR" ] && ok "degenerate provides logs to stderr" || no "degenerate provides: silent"
run
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "brief_unreadable" ] && ok "no args ⇒ brief_unreadable, exit 0" || no "no-args: rc=$RC $OUT"

echo "--- script: bad_args (the arg parser's own early exit keeps the contract) ---"
run "$TMP/briefA.md" 1 --root
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && [ "$(jq_get '.reason')" = "bad_args" ] && ok "--root as the last token ⇒ exit 0 + valid JSON + reason bad_args" || no "bad_args (dangling --root): rc=$RC $OUT"
[ "$(jq_get '.subtask_id')" = "1" ] && ok "bad_args carries the already-parsed subtask_id" || no "bad_args subtask_id: $OUT"
case "$ERR" in *bad_args*) ok "bad_args reason on stderr" ;; *) no "stderr lacks reason: $ERR" ;; esac
run --root
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "bad_args" ] && [ "$(jq_get 'has("subtask_id")')" = "false" ] && ok "bare --root ⇒ bad_args with NO subtask_id key (nothing parsed yet)" || no "bad_args (bare --root): rc=$RC $OUT"
run "$TMP/briefA.md" 1 --root ""
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "bad_args" ] && ok "--root '' ⇒ bad_args (never silently rooted at /)" || no "bad_args (empty --root): rc=$RC $OUT"
run "$TMP/briefA.md" 1 --root=
[ "$RC" -eq 0 ] && [ "$(jq_get '.reason')" = "bad_args" ] && ok "--root= ⇒ bad_args" || no "bad_args (--root=): rc=$RC $OUT"
# the CLASS, not one branch: inside the arg-parse loop the only `exit 0`s are the two documented non-JSON modes
parser_exits_ok() {   # exit 0 iff every `exit 0` inside $1's arg-parse loop sits under a --kind-table / --help case label
  awk '/^while \[ \$# -gt 0 \]; do/ { on = 1 } /^done$/ { on = 0 }
       on && /^[[:space:]]*(--kind-table|-h[|]--help)\)/ { allowed = 1 }
       on && /exit 0/ && !allowed { bad = 1 }
       on && /;;[[:space:]]*$/ { allowed = 0 }
       END { exit bad }' "$1"
}
parser_exits_ok "$SCRIPT" && ok "arg parser: no JSON-less exit 0 outside --kind-table / --help" || no "arg parser still has a bare 'exit 0' outside the two documented non-JSON modes"
# mutation control for that guard: re-introduce the original bare exit in the --root branch of a COPY
MUTP="$TMP/verify-provides-bare-exit.sh"
sed 's/^\(      if \[ \$# -lt 2 \]; then \)bad_args=.*$/\1exit 0; fi/' "$SCRIPT" > "$MUTP"
if cmp -s "$MUTP" "$SCRIPT"; then no "bare-exit mutant identical to original — control invalid (--root branch shape changed?)"
elif parser_exits_ok "$MUTP"; then no "MUTATION CONTROL: parser guard still passes with the bare exit 0 restored — guard is vacuous"
else ok "MUTATION CONTROL: restoring the bare 'exit 0' in the --root branch makes the parser guard fail"; fi

echo "--- script: jq-less path (jq off PATH) ---"
NOJQ_OUT="$(PATH="$TMP/nojq" "$BASH" "$SCRIPT" "$TMP/briefA.md" 'ok-1_x' --root 2>/dev/null)"
[ "$NOJQ_OUT" = '{"subtask_id":"ok-1_x","status":"unverifiable","reason":"bad_args","source":"verify-provides.sh"}' ] && ok "jq-less + dangling --root ⇒ templated bad_args object (same shape as jq_missing)" || no "jq-less bad_args: $NOJQ_OUT"
NOJQ_OUT="$(PATH="$TMP/nojq" "$BASH" "$SCRIPT" "$TMP/briefA.md" 'a"b' --root "$ROOT" 2>"$TMP/stderr")"; NOJQ_RC=$?
[ "$NOJQ_RC" -eq 0 ] && ok "jq-less: exit 0" || no "jq-less exit $NOJQ_RC"
[ "$NOJQ_OUT" = '{"status":"unverifiable","reason":"jq_missing","source":"verify-provides.sh"}' ] && ok "jq-less + id containing '\"' ⇒ literal object with NO subtask_id key" || no "jq-less object: $NOJQ_OUT"
printf '%s' "$NOJQ_OUT" | jq -e . >/dev/null 2>&1 && ok "jq-less object is valid JSON" || no "jq-less object not JSON"
case "$(cat "$TMP/stderr")" in *jq_missing*) ok "jq_missing reason on stderr" ;; *) no "jq-less stderr lacks reason" ;; esac
NOJQ_OUT="$(PATH="$TMP/nojq" "$BASH" "$SCRIPT" "$TMP/briefA.md" 'ok-1_x' 2>/dev/null)"
[ "$NOJQ_OUT" = '{"subtask_id":"ok-1_x","status":"unverifiable","reason":"jq_missing","source":"verify-provides.sh"}' ] && ok "jq-less + allowlisted id ⇒ subtask_id carried" || no "jq-less allowlisted: $NOJQ_OUT"

echo "--- script: --kind-table ---"
KT="$(bash "$SCRIPT" --kind-table)"
[ "$(printf '%s\n' "$KT" | wc -l | tr -d ' ')" = "5" ] && ok "--kind-table prints header + separator + 3 rows" || no "--kind-table line count: $(printf '%s\n' "$KT" | wc -l)"
grep -q '^| `file` | `test -f ' < <(printf '%s\n' "$KT") && ok "--kind-table file row = test -f" || no "--kind-table file row"
grep -q "^| \`symbol\` | \`grep -nE -- '<escaped name>'" < <(printf '%s\n' "$KT") && ok "--kind-table symbol row = grep -nE --" || no "--kind-table symbol row"
grep -q '(type\\|interface\\|class\\|enum)\[\[:space:\]\]+<escaped name>(\[^\[:alnum:\]_\]\\|\$)' < <(printf '%s\n' "$KT") && ok "--kind-table type row = portable ERE (markdown-escaped |)" || no "--kind-table type row"
grep -q '\\s\|\\b' <<<"$KT" && no "--kind-table carries a GNU-ism (\\s or \\b)" || ok "--kind-table has no \\s / \\b"

# ============================================================================ SEAMS
echo "--- seams ---"
# section <file> <from-regex> <to-regex> — lines from the first match of <from> (inclusive) up to the
# next match of <to> (exclusive). Silent; reused on the mutant.
section() { awk -v from="$2" -v to="$3" 'on && $0 ~ to { exit } $0 ~ from { on = 1 } on { print }' "$1"; }

em_gate_ok() {   # exit 0 iff the poll-loop gate section of $1 cites the script + decision + phrase
  local s; s="$(section "$1" 'v12 outputs_verified gate' 'Lane-collision gate')"
  [ -n "$s" ] || return 1
  grep -q 'verify-provides\.sh' < <(printf '%s\n' "$s") || return 1
  grep -q 'provides_mismatch' < <(printf '%s\n' "$s") || return 1
  grep -q 'regardless of the worker' < <(printf '%s\n' "$s") || return 1
  return 0
}
em_gate_ok "$EM" && ok "EM §v12 outputs_verified gate cites verify-provides.sh + provides_mismatch + 'regardless of the worker'" || no "EM poll-loop gate seam"
grep -q 'worker_result_absent' < <(section "$EM" 'v12 outputs_verified gate' 'Lane-collision gate') && ok "EM gate handles the dead-worker case (worker_result_absent)" || no "EM gate lacks worker_result_absent"
grep -q 'legacy_brief' < <(section "$EM" 'v12 outputs_verified gate' 'Lane-collision gate') && ok "EM gate carries D1 routing (legacy_brief)" || no "EM gate lacks D1 legacy_brief routing"
em_routes_ok() {   # exit 0 iff the gate section of $1 routes BOTH non-disk-wins cells to a checkpoint
  local s; s="$(section "$1" 'v12 outputs_verified gate' 'Lane-collision gate')"
  [ -n "$s" ] || return 1
  grep -q 'partial with no provides gap' < <(printf '%s\n' "$s") || return 1          # Step 1 carve-out ⇒ checkpoint
  grep -q 'Step 1 carve-out' < <(printf '%s\n' "$s") || return 1
  grep -q 'worker_result_absent and provides unverifiable' < <(printf '%s\n' "$s") || return 1   # ABSENT × unverifiable ⇒ checkpoint
  return 0
}
em_routes_ok "$EM" && ok "EM gate routes 'partial with no provides gap' (Step 1 carve-out) AND ABSENT-on-unverifiable to a checkpoint" || no "EM gate routing seam (carve-out / absent-on-unverifiable)"
grep -q 'disk.source == "verify-provides.sh"' < <(section "$EM" 'v12 outputs_verified gate' 'Lane-collision gate') && ok "EM 'worker_result_absent: disk verified' record is gated on disk.source == verify-provides.sh" || no "EM absent-record not gated on disk.source"
grep -q 'bare token after `Subtask`' < <(section "$EM" 'v12 outputs_verified gate' 'Lane-collision gate') && ok "EM gate pins the subtask_id shape (bare anchor token)" || no "EM gate lacks the subtask_id shape clause"
grep -q 'bare token the brief.s contract anchor names' "$SCRIPT" && ok "script header pins the subtask_id shape (bare anchor token)" || no "script header lacks the subtask_id shape clause"
grep -q '^\*\*Tool call tracking:\*\*.*verify-provides\.sh' "$EM" && ok "EM tool-call tracking notes the +1 Bash per subtask" || no "EM tool-call tracking lacks the verify-provides.sh note"
pointer_section_ok() {   # exit 0 iff section <from>..<to> of $1 cites --kind-table AND restates neither a table row nor a GNU-ism
  local s; s="$(section "$1" "$2" "$3")"
  [ -n "$s" ] || return 1
  grep -q -- '--kind-table' < <(printf '%s\n' "$s") || return 1                # the pointer
  grep -q '\\s\|\\b' < <(printf '%s\n' "$s") && return 1                       # no GNU-only \s / \b (BSD grep false-FAILs)
  grep -q '^| `symbol`\|^| `type`' < <(printf '%s\n' "$s") && return 1         # no second copy of the kind-table rows
  return 0
}
em_step2b_ok()    { pointer_section_ok "$1" 'Step 2b — Pre-Spawn Verification Gate' 'CHECKPOINT format'; }
skill_gate_ok()   { pointer_section_ok "$1" '^## Pre-Spawn Verification Gate' '^## Scope Expansion Adjudication'; }
em_step2b_ok "$EM" && ok "EM Step 2b points at --kind-table and restates NO table row / GNU-ism" || no "EM Step 2b: missing pointer, restated table row, or \\s / \\b GNU-ism"
skill_gate_ok "$ASYNC" && ok "async-orchestration §Pre-Spawn Verification Gate points at --kind-table and restates NO table row / GNU-ism" || no "async-orchestration §Pre-Spawn Verification Gate: missing pointer, restated table row, or \\s / \\b GNU-ism"

sup_single="$(section "$SUP" '#### Single-Agent Path' '#### Sequential Path')"
grep -q 'verify-provides\.sh.*--root \.' < <(printf '%s\n' "$sup_single") && ok "Supervisor Single-Agent step 3 cites verify-provides.sh with --root ." || no "Supervisor Single-Agent gate seam"
sup_seq="$(section "$SUP" '#### Sequential Path' '#### Parallel Path')"
grep -q 'verify-provides\.sh.*--root \.' < <(printf '%s\n' "$sup_seq") && ok "Supervisor Sequential gate cites verify-provides.sh with --root ." || no "Supervisor Sequential gate seam"
grep -q 'pre-spawn' < <(printf '%s\n' "$sup_single") && no "Supervisor step 3 still calls the poll-loop gate 'pre-spawn'" || ok "Supervisor step 3 no longer mislabels the poll-loop gate as pre-spawn"
grep -q 'Step 1 carve-out' < <(printf '%s\n' "$sup_single") && ok "Supervisor Single-Agent step 3 states the partial-with-empty-gap carve-out (retry/pause, not pass)" || no "Supervisor Single-Agent step 3 lacks the Step 1 carve-out clause"
grep -q 'Step 1 carve-out' < <(printf '%s\n' "$sup_seq") && ok "Supervisor Sequential gate states the Step 1 carve-out" || no "Supervisor Sequential gate lacks the Step 1 carve-out clause"
grep -q 'bare token after `Subtask`' < <(printf '%s\n' "$sup_single") && ok "Supervisor step 3 pins the subtask_id shape (bare anchor token)" || no "Supervisor step 3 lacks the subtask_id shape clause"
grep -q 'never a pass' < <(printf '%s\n' "$sup_single") && ok "Supervisor step 3: absent WORKER_RESULT on an unverifiable contract is a pause, never a pass" || no "Supervisor step 3 lacks the absent-on-unverifiable clause"

grep -q 'verify-provides\.sh' < <(section "$WORKER" 'verify own `provides:`' 'Step 5.65') && ok "worker Step 5.5 cites verify-provides.sh" || no "worker Step 5.5 seam"
w55="$(section "$WORKER" 'verify own `provides:`' 'Step 5.65')"
grep -q 'verify-provides\.sh.*--root \.' < <(printf '%s\n' "$w55") && no "worker Step 5.5 hard-codes --root . (wrong tree on the Parallel path: Bash cwd is the main checkout)" || ok "worker Step 5.5 does not hard-code --root ."
grep -qi 'worktree.*ABSOLUTE path on the Parallel path' < <(printf '%s\n' "$w55") && ok "worker Step 5.5 passes the worktree's absolute path on the Parallel path" || no "worker Step 5.5 lacks the Parallel-path worktree --root clause"
grep -q 'present' "$WORKER" && grep -q 'missing' "$WORKER" && ok "worker.md keeps the present/missing enum tokens (check-contract-parity.sh)" || no "worker.md lost present/missing"
grep -q 'brief_unreadable.*jq_missing' < <(printf '%s\n' "$w55") && grep -q 'name the reason in `summary`' < <(printf '%s\n' "$w55") && ok "worker Step 5.5 covers the field-less unverifiable reasons (brief_unreadable / jq_missing: empty fields, reason in summary)" || no "worker Step 5.5 lacks the brief_unreadable / jq_missing clause"
grep -q 'subtask_not_found.*name it in `summary`' < <(printf '%s\n' "$w55") && ok "worker Step 5.5 distinguishes subtask_not_found (contracts present, anchor absent — named in summary) from no_contracts" || no "worker Step 5.5 conflates subtask_not_found with no_contracts"

DOC_KT="$(awk '/<!-- kind-table:begin -->/ { on = 1; next } /<!-- kind-table:end -->/ { on = 0 } on { print }' "$SCHEMAS")"
[ -n "$DOC_KT" ] && ok "RESULT_SCHEMAS.md has the kind-table marker block" || no "RESULT_SCHEMAS.md marker block missing/empty"
[ "$DOC_KT" = "$KT" ] && ok "RESULT_SCHEMAS.md kind-table == --kind-table byte-for-byte" || no "RESULT_SCHEMAS.md kind-table drifted from --kind-table"
grep -q 'provides_mismatch' "$SCHEMAS" && ok "RESULT_SCHEMAS.md names provides_mismatch" || no "RESULT_SCHEMAS.md lacks provides_mismatch"

[ "$(grep -c 'worker self-verification, zero tokens)' "$ORCH")" = "0" ] && ok "orchestrator.md: retired '(worker self-verification, zero tokens)' is 0-hit" || no "orchestrator.md still carries the retired parenthetical"
[ "$(grep -c 'cross-checked on disk by the consumer via `verify-provides.sh`' "$ORCH")" = "2" ] && ok "orchestrator.md: both mirrors carry the cross-checked-on-disk phrasing" || no "orchestrator.md mirror count: $(grep -c 'cross-checked on disk' "$ORCH")"
grep -q 'verify-provides\.sh' "$FAILDOC" && ok "FAILURE_ESCALATION.md trigger names verify-provides.sh" || no "FAILURE_ESCALATION.md lacks verify-provides.sh"

# Anchor guarantee (2026-09-26): the gate can only verify what it can parse, and Plan Reviewer has no
# Bash — so Launch Pad runs --parse-only per id before every review spawn and hands the reviewer the
# lines; Criterion 12 blocks an unparseable anchor; both templates name the required anchor.
lp_1b="$(section "$LAUNCHPAD" '^1b[.] [*][*]Gate-parse check' '^2[.] Spawn Plan Reviewer')"
grep -q 'verify-provides\.sh.*--parse-only' < <(printf '%s\n' "$lp_1b") && ok "Launch Pad Phase 5.5 action 1b runs verify-provides.sh --parse-only per subtask id" || no "Launch Pad lacks the --parse-only pre-review check"
grep -q -- '--- GATE PARSE ---' "$LAUNCHPAD" && ok "Launch Pad spawn contract carries the GATE PARSE block" || no "Launch Pad spawn contract lacks GATE PARSE"
c12="$(section "$REVIEWER" '^### 12[.] Inter-Subtask Output Contracts' '^### 13[.]')"
grep -q 'Gate-parseable anchor' < <(printf '%s\n' "$c12") && grep -q 'GATE PARSE' < <(printf '%s\n' "$c12") && grep -q 'subtask_id: foo-01' < <(printf '%s\n' "$c12") && ok "Criterion 12 requires a gate-parseable anchor, rejects slug keys, and consumes GATE PARSE" || no "Criterion 12 anchor clause missing"
grep -q 'no gate-parseable `Subtask N` anchor' < <(printf '%s\n' "$c12") && ok "Criterion 12 lists the unparseable anchor as BLOCKING" || no "Criterion 12 severity list lacks the anchor case"
grep -q 'NOT an anchor' "$READINESS" && grep -q -- '--parse-only' "$READINESS" && ok "supervisor-readiness authoring rules name the required anchor" || no "supervisor-readiness lacks the anchor rule"
# every contract example in the two templates is itself gate-parseable (a template that violates the rule teaches it)
tpl_counts() {   # prints "<fenced yaml blocks with provides:> <of those lacking a Subtask N anchor>" for $1
  awk '/^```yaml$/ { on = 1; blk = ""; next } on && /^```$/ { on = 0; if (blk ~ /(^|\n)[[:space:]]*provides:/) print blk "\n---BLOCK---"; next } on { blk = blk $0 "\n" }' "$1" |
    awk -v RS='---BLOCK---\n' 'NF { n++; if ($0 !~ /(^|\n)[[:space:]]*(#+[[:space:]]*[Ss]ubtask[[:space:]]+[0-9]|subtask_[0-9])/) bad++ } END { print n+0, bad+0 }'
}
for tpl in "$LAUNCHPAD" "$READINESS"; do
  read -r nblk bad < <(tpl_counts "$tpl")
  [ "$nblk" -gt 0 ] && [ "$bad" -eq 0 ] && ok "$(basename "$(dirname "$tpl")")/$(basename "$tpl"): all $nblk fenced contract examples carry a Subtask N anchor" || no "$(basename "$tpl"): $bad of $nblk fenced contract examples lack a Subtask N anchor"
done
MUTT="$TMP/launch-pad-no-anchor.md"
sed '/^# Subtask 2 — JWT guard (BLOCKED by #1)$/d' "$LAUNCHPAD" > "$MUTT"
if cmp -s "$MUTT" "$LAUNCHPAD"; then no "template mutant identical to original — control invalid (example anchor line changed?)"
else
  read -r nblk bad < <(tpl_counts "$MUTT")
  [ "$bad" -eq 1 ] && ok "MUTATION CONTROL: dropping the example block's '# Subtask 2' anchor makes the template check fail" || no "MUTATION CONTROL: template check still passes with the example anchor removed — vacuous"
fi

echo "--- mutation control ---"
MUT="$TMP/em-mutant.md"
awk '/v12 outputs_verified gate/ { on = 1 } /Lane-collision gate/ { on = 0 } on && /verify-provides\.sh/ { next } { print }' "$EM" > "$MUT"
if [ ! -s "$MUT" ]; then
  no "mutant is empty — control invalid"
elif cmp -s "$MUT" "$EM"; then
  no "mutant identical to original — control invalid (no script-call line inside the gate section?)"
else
  ok "mutant is non-empty and differs from the original"
  if em_gate_ok "$MUT"; then
    no "MUTATION CONTROL: EM seam assertion still passes with the script call deleted — assertion is vacuous"
  else
    ok "MUTATION CONTROL: deleting the script call from the poll-loop gate makes the seam assertion fail"
  fi
fi
MUT2="$TMP/em-mutant-carveout.md"
awk '/v12 outputs_verified gate/ { on = 1 } /Lane-collision gate/ { on = 0 } on && /carve-out/ { next } { print }' "$EM" > "$MUT2"
if [ ! -s "$MUT2" ]; then
  no "carve-out mutant is empty — control invalid"
elif cmp -s "$MUT2" "$EM"; then
  no "carve-out mutant identical to original — control invalid (no carve-out line inside the gate section?)"
else
  ok "carve-out mutant is non-empty and differs from the original"
  if em_routes_ok "$MUT2"; then
    no "MUTATION CONTROL: EM routing assertion still passes with the carve-out clause deleted — assertion is vacuous"
  else
    ok "MUTATION CONTROL: deleting the carve-out clause from the poll-loop gate makes the routing assertion fail"
  fi
  em_gate_ok "$MUT2" && ok "carve-out mutant still passes the script-call seam (the two controls test different clauses)" || no "carve-out mutant broke the script-call seam — controls are not independent"
fi
# (3) restate ONE kind-table row (carrying the retired GNU \s/\b) inside a COPY of Step 2b — the drift the
# pointer replaced; the Step 2b assertion MUST fail on it while the two poll-loop-gate seams still pass.
MUT3="$TMP/em-mutant-step2b.md"
ROW='| `type` | `grep -nE '"'"'(type\|interface\|class\|enum)\s+<escaped name>\b'"'"' <worktree>/<path>` | any match (exit 0) |'
ROW="$ROW" awk '/Step 2b — Pre-Spawn Verification Gate/ { on = 1 } /CHECKPOINT format/ { on = 0 } on && /Record each check result/ { print ENVIRON["ROW"] } { print }' "$EM" > "$MUT3"
if [ ! -s "$MUT3" ]; then
  no "Step 2b mutant is empty — control invalid"
elif cmp -s "$MUT3" "$EM"; then
  no "Step 2b mutant identical to original — control invalid (no 'Record each check result' line inside Step 2b?)"
else
  ok "Step 2b mutant is non-empty and differs from the original"
  if em_step2b_ok "$MUT3"; then
    no "MUTATION CONTROL: EM Step 2b assertion still passes with a GNU-ism table row restated — assertion is vacuous"
  else
    ok "MUTATION CONTROL: restating a kind-table row (with \\s / \\b) inside Step 2b makes the Step 2b assertion fail"
  fi
  em_gate_ok "$MUT3" && em_routes_ok "$MUT3" && ok "Step 2b mutant still passes both poll-loop-gate seams (the three controls test different sections)" || no "Step 2b mutant broke a poll-loop-gate seam — controls are not independent"
fi
# (4) the same restated row inside a COPY of the preloaded skill's §Pre-Spawn Verification Gate (the third
# copy of the table that drifted); its assertion MUST fail while the EM Step 2b assertion (a different file) still passes.
MUT4="$TMP/async-mutant-gate.md"
ROW="$ROW" awk '/^## Pre-Spawn Verification Gate/ { on = 1 } /^## Scope Expansion Adjudication/ { on = 0 } on && /^\*\*Pass criterion:\*\*/ { print ENVIRON["ROW"] } { print }' "$ASYNC" > "$MUT4"
if [ ! -s "$MUT4" ]; then
  no "skill-gate mutant is empty — control invalid"
elif cmp -s "$MUT4" "$ASYNC"; then
  no "skill-gate mutant identical to original — control invalid (no 'Pass criterion' line inside the section?)"
else
  ok "skill-gate mutant is non-empty and differs from the original"
  if skill_gate_ok "$MUT4"; then
    no "MUTATION CONTROL: async-orchestration gate assertion still passes with a GNU-ism table row restated — assertion is vacuous"
  else
    ok "MUTATION CONTROL: restating a kind-table row (with \\s / \\b) inside the skill's gate section makes its assertion fail"
  fi
  grep -q -- '--kind-table' < <(section "$MUT4" '^## Pre-Spawn Verification Gate' '^## Scope Expansion Adjudication') && ok "skill-gate mutant still carries the --kind-table pointer (it fails on the restated row, not on a broken section extraction)" || no "skill-gate mutant lost the pointer — the control is failing for the wrong reason"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
