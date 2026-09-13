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
#   script  — per-kind present/missing; `provides: []`; the three `unverifiable` reasons (exit 0 +
#             stderr reason each); two-item miss ⇒ outputs_gap exactly "a/b.ts:Sym, c/d.ts"; symbol
#             on an absent file ⇒ missing with a grep check_run (exit 2); --kind-table; JSON validity
#             via `jq -e .`; ERE specials ($ . ( [ and + * ? | { combined) match LITERALLY and a
#             one-char mutation goes `missing`; type-boundary (typeFoo / Shapes do not match);
#             a '/\/\n-sequence name round-trips; the jq-less path (jq off PATH, id containing `"`)
#             prints exit 0 + the literal object with NO subtask_id key; three brief layouts
#             (H3 + fence + `# Subtask N` comment / H2 + `subtask_N:` key / inline `### Subtask N`
#             heading, raw YAML); provides list ends at the next top-level key; --root honoured.
#   seams   — EM §"v12 outputs_verified gate" cites verify-provides.sh + provides_mismatch +
#             "regardless of the worker"; Supervisor Single-Agent step 3 AND Sequential gate cite
#             verify-provides.sh with `--root .` (by anchor, never line number); worker Step 5.5 cites
#             it; RESULT_SCHEMAS.md marker block == `--kind-table` byte-for-byte; orchestrator.md has
#             0 hits of the retired "(worker self-verification, zero tokens)" parenthetical.
#   (m)     — MUTATION CONTROL: delete the script-call line(s) from a COPY of execute-manager.md's
#             poll-loop gate; gate the mutant on non-empty + differs-from-original; the seam assertion
#             against the mutant MUST fail — otherwise the assertion above is vacuous.
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
FAILDOC="$PLUGIN_ROOT/docs/FAILURE_ESCALATION.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$SCRIPT" "$EM" "$SUP" "$WORKER" "$ORCH" "$SCHEMAS" "$FAILDOC"; do
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

echo "--- script: jq-less path (jq off PATH) ---"
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
printf '%s\n' "$KT" | grep -q '^| `file` | `test -f ' && ok "--kind-table file row = test -f" || no "--kind-table file row"
printf '%s\n' "$KT" | grep -q "^| \`symbol\` | \`grep -nE -- '<escaped name>'" && ok "--kind-table symbol row = grep -nE --" || no "--kind-table symbol row"
printf '%s\n' "$KT" | grep -q '(type\\|interface\\|class\\|enum)\[\[:space:\]\]+<escaped name>(\[^\[:alnum:\]_\]\\|\$)' && ok "--kind-table type row = portable ERE (markdown-escaped |)" || no "--kind-table type row"
grep -q '\\s\|\\b' <<<"$KT" && no "--kind-table carries a GNU-ism (\\s or \\b)" || ok "--kind-table has no \\s / \\b"

# ============================================================================ SEAMS
echo "--- seams ---"
# section <file> <from-regex> <to-regex> — lines from the first match of <from> (inclusive) up to the
# next match of <to> (exclusive). Silent; reused on the mutant.
section() { awk -v from="$2" -v to="$3" 'on && $0 ~ to { exit } $0 ~ from { on = 1 } on { print }' "$1"; }

em_gate_ok() {   # exit 0 iff the poll-loop gate section of $1 cites the script + decision + phrase
  local s; s="$(section "$1" 'v12 outputs_verified gate' 'Lane-collision gate')"
  [ -n "$s" ] || return 1
  printf '%s\n' "$s" | grep -q 'verify-provides\.sh' || return 1
  printf '%s\n' "$s" | grep -q 'provides_mismatch' || return 1
  printf '%s\n' "$s" | grep -q 'regardless of the worker' || return 1
  return 0
}
em_gate_ok "$EM" && ok "EM §v12 outputs_verified gate cites verify-provides.sh + provides_mismatch + 'regardless of the worker'" || no "EM poll-loop gate seam"
section "$EM" 'v12 outputs_verified gate' 'Lane-collision gate' | grep -q 'worker_result_absent' && ok "EM gate handles the dead-worker case (worker_result_absent)" || no "EM gate lacks worker_result_absent"
section "$EM" 'v12 outputs_verified gate' 'Lane-collision gate' | grep -q 'legacy_brief' && ok "EM gate carries D1 routing (legacy_brief)" || no "EM gate lacks D1 legacy_brief routing"
grep -q '^\*\*Tool call tracking:\*\*.*verify-provides\.sh' "$EM" && ok "EM tool-call tracking notes the +1 Bash per subtask" || no "EM tool-call tracking lacks the verify-provides.sh note"
section "$EM" 'Step 2b — Pre-Spawn Verification Gate' 'CHECKPOINT format' | grep -q 'kind-table' && ok "EM Step 2b points at --kind-table" || no "EM Step 2b lacks the kind-table pointer"

sup_single="$(section "$SUP" '#### Single-Agent Path' '#### Sequential Path')"
printf '%s\n' "$sup_single" | grep -q 'verify-provides\.sh.*--root \.' && ok "Supervisor Single-Agent step 3 cites verify-provides.sh with --root ." || no "Supervisor Single-Agent gate seam"
sup_seq="$(section "$SUP" '#### Sequential Path' '#### Parallel Path')"
printf '%s\n' "$sup_seq" | grep -q 'verify-provides\.sh.*--root \.' && ok "Supervisor Sequential gate cites verify-provides.sh with --root ." || no "Supervisor Sequential gate seam"
printf '%s\n' "$sup_single" | grep -q 'pre-spawn' && no "Supervisor step 3 still calls the poll-loop gate 'pre-spawn'" || ok "Supervisor step 3 no longer mislabels the poll-loop gate as pre-spawn"

section "$WORKER" 'verify own `provides:`' 'Step 5.65' | grep -q 'verify-provides\.sh' && ok "worker Step 5.5 cites verify-provides.sh" || no "worker Step 5.5 seam"
grep -q 'present' "$WORKER" && grep -q 'missing' "$WORKER" && ok "worker.md keeps the present/missing enum tokens (check-contract-parity.sh)" || no "worker.md lost present/missing"

DOC_KT="$(awk '/<!-- kind-table:begin -->/ { on = 1; next } /<!-- kind-table:end -->/ { on = 0 } on { print }' "$SCHEMAS")"
[ -n "$DOC_KT" ] && ok "RESULT_SCHEMAS.md has the kind-table marker block" || no "RESULT_SCHEMAS.md marker block missing/empty"
[ "$DOC_KT" = "$KT" ] && ok "RESULT_SCHEMAS.md kind-table == --kind-table byte-for-byte" || no "RESULT_SCHEMAS.md kind-table drifted from --kind-table"
grep -q 'provides_mismatch' "$SCHEMAS" && ok "RESULT_SCHEMAS.md names provides_mismatch" || no "RESULT_SCHEMAS.md lacks provides_mismatch"

[ "$(grep -c 'worker self-verification, zero tokens)' "$ORCH")" = "0" ] && ok "orchestrator.md: retired '(worker self-verification, zero tokens)' is 0-hit" || no "orchestrator.md still carries the retired parenthetical"
[ "$(grep -c 'cross-checked on disk by the consumer via `verify-provides.sh`' "$ORCH")" = "2" ] && ok "orchestrator.md: both mirrors carry the cross-checked-on-disk phrasing" || no "orchestrator.md mirror count: $(grep -c 'cross-checked on disk' "$ORCH")"
grep -q 'verify-provides\.sh' "$FAILDOC" && ok "FAILURE_ESCALATION.md trigger names verify-provides.sh" || no "FAILURE_ESCALATION.md lacks verify-provides.sh"

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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
