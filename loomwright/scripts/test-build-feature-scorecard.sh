#!/usr/bin/env bash
# test-build-feature-scorecard.sh — fixture-driven self-tests for build-feature-scorecard.sh, the
# READ-ONLY per-feature scorecard builder. Every fixture (registry, state dir, records, schema doc)
# is built under one `mktemp -d` root, and every builder call passes --state-dir and --registry
# explicitly, so the suite NEVER reads a real .supervisor/. No network, no gh.
# Exit 0 = all pass, 1 = any failure (the BUILDER always exits 0; this self-test fails loudly).
#
# Covers:
#   (1)  every verdict from a fixture registry: keep, keep (critical) on both the never-ran and the
#        costs-without-catching arm, review: costs without catching (AC2), review: never ran,
#        insufficient data (runs < min_sample, caught unknown, ran below min_sample), no record (AC5).
#   (2)  record formats: both SUPERVISOR_RESULT block forms (indented + `## … / - key:` bullets,
#        fenced), text, json (mtime-dated), tsv (an empty TSV is zero rows, not malformed).
#   (3)  unreadable (AC9): a malformed TSV row, a header-less sidecar, a value failing `valid`, an
#        invalid JSON record and a bad registry entry each make ONLY their feature unreadable; exit 0.
#   (4)  cost: token_ledger (agent-suffix match, agent_id de-dupe, proxy vs real), duration, `unknown`
#        with no cost record (never 0), per catch `n/a` at caught 0.
#   (5)  --since: a partial window; later than every record ⇒ every feature with a record is
#        insufficient data and the record-none feature still prints no record (AC6); a bad --since
#        ⇒ status error.
#   (6)  registry missing / invalid JSON / invalid min_sample ⇒ one stderr line, no rows, status
#        error with features [], exit 0 (AC10 script half).
#   (7)  needs-an-emitter + unregistered lists (fixture schema doc via FEATURE_SCORECARD_SCHEMA_DOC).
#   (8)  the shipped registry over a fixture state dir: one row per registry id, in order (AC1).
#   (9)  mutation control (AC12): a copy of the builder whose verdict rule is edited to always
#        `keep` must turn the verdict assertions red — the mutant is gated on non-empty, differs
#        from the original and `bash -n` clean before it is trusted.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="$SCRIPT_DIR/build-feature-scorecard.sh"
REAL_REGISTRY="$SCRIPT_DIR/../docs/feature-scorecard.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "test-build-feature-scorecard: jq absent on this host — builder emits status error; skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# MODE=report → ok/no; MODE=count → count failures into MUT_FAILS (mutation control).
MODE=report; MUT_FAILS=0
check() {   # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then
    [ "$MODE" = report ] && ok "$1"
  else
    if [ "$MODE" = report ]; then no "$1 (got '$2', want '$3')"; else MUT_FAILS=$((MUT_FAILS+1)); fi
  fi
}
field() { printf '%s' "$OUT" | jq -r --arg id "$1" ".features[] | select(.id == \$id) | $2" 2>/dev/null; }

# ---------------------------------------------------------------------------- fixtures
SD="$ROOT/sd"; mkdir -p "$SD/sr" "$SD/small" "$SD/pm" "$SD/pmbad" "$SD/js" "$SD/jsbad" \
  "$SD/srbad" "$SD/srinvalid" "$SD/logs"

# sr/: five sidecars dated 2026-10-01..05 in the three block shapes the real store holds.
for n in 1 2 3 4 5; do
  hit=false; [ "$n" = 3 ] && hit=true
  part=""; [ "$n" = 5 ] && part="part: yes"
  f="$SD/sr/automate-2026-10-0${n}-120000.supervisor-result.md"
  case "$n" in
    2)  # bullet form
      {
        echo "## SUPERVISOR_RESULT"
        echo "- schema_version: 1"
        echo "- alpha: {hit: $hit}"
        echo "- alpha_secs: 10"
        echo "- beta: ran"
        echo "- gamma: ran"
        echo "- unk: yes"
        echo "- summary: \"delta_marker: off; eps_marker: off\""
      } > "$f" ;;
    4)  # heading + fenced indented form
      {
        echo "## SUPERVISOR_RESULT"
        echo ""
        echo '```yaml'
        echo "SUPERVISOR_RESULT:"
        echo "  schema_version: 1"
        echo "  alpha:"
        echo "    hit: $hit"
        echo "  alpha_secs: 10"
        echo "  beta: ran"
        echo "  gamma: ran"
        echo "  unk: yes"
        echo "  summary: \"delta_marker: off; eps_marker: off\""
        echo '```'
      } > "$f" ;;
    *)
      {
        echo "SUPERVISOR_RESULT:"
        echo "  schema_version: 1"
        echo "  alpha: {hit: $hit}"
        echo "  alpha_secs: 10"
        echo "  beta: ran"
        echo "  gamma: ran"
        echo "  unk: yes"
        [ -n "$part" ] && echo "  $part"
        echo "  summary: \"delta_marker: off; eps_marker: off\""
      } > "$f" ;;
  esac
done
for n in 1 2; do printf 'SUPERVISOR_RESULT:\n  alpha: {hit: false}\n' > "$SD/small/automate-2026-10-0${n}-120000.supervisor-result.md"; done

# pm/: pin-mutation TSVs (4 columns), one not_held row, plus an empty TSV (zero rows — not malformed).
H1=e8ac1d627f60710fa53f2fc7fd5f986ba4b00504; H2=d3d8da26c714cf8d6f06e79d6ff73eca49450557
printf '%s\theld\t%s\t%s\n' "$H1" "$H2" "$H2" > "$SD/pm/2026-10-01-a.tsv"
printf '%s\theld\t%s\t%s\n%s\tnot_held\t%s\t%s\n' "$H1" "$H2" "$H2" "$H2" "$H1" "$H1" > "$SD/pm/2026-10-02-b.tsv"
printf '%s\theld\t%s\t%s\n' "$H1" "$H2" "$H2" > "$SD/pm/2026-10-03-c.tsv"
: > "$SD/pm/2026-10-04-d.tsv"
# pmbad/: one row with 3 columns.
printf '%s\theld\t%s\t%s\n' "$H1" "$H2" "$H2" > "$SD/pmbad/2026-10-01-a.tsv"
printf '%s\theld\t%s\n' "$H1" "$H2" > "$SD/pmbad/2026-10-02-b.tsv"
printf '%s\theld\t%s\t%s\n' "$H1" "$H2" "$H2" > "$SD/pmbad/2026-10-03-c.tsv"

# js/: JSON records with no date in the name — dated by mtime (touch -t, portable).
for n in 1 2 3; do
  printf '{"fallback_review_ran":"true","x":{"y":%s}}\n' "$n" > "$SD/js/sha$n.next-step.json"
  touch -t "20261001120$n" "$SD/js/sha$n.next-step.json"
done
for n in 1 2 3; do
  printf '{"fallback_review_ran":"true"}\n' > "$SD/jsbad/sha$n.next-step.json"
  touch -t "20261001120$n" "$SD/jsbad/sha$n.next-step.json"
done
printf '{"fallback_review_ran": tru' > "$SD/jsbad/sha2.next-step.json"; touch -t 202610011202 "$SD/jsbad/sha2.next-step.json"

# srbad/: one sidecar with no SUPERVISOR_RESULT block at all. srinvalid/: a value failing `valid`.
for n in 1 2 3; do printf 'SUPERVISOR_RESULT:\n  alpha: {hit: false}\n' > "$SD/srbad/automate-2026-10-0${n}-120000.supervisor-result.md"; done
printf 'just prose, no block\n  alpha: {hit: true}\n' > "$SD/srbad/automate-2026-10-02-120000.supervisor-result.md"
for n in 1 2 3; do printf 'SUPERVISOR_RESULT:\n  alpha: {hit: false}\n' > "$SD/srinvalid/automate-2026-10-0${n}-120000.supervisor-result.md"; done
printf 'SUPERVISOR_RESULT:\n  alpha: {miss: maybe}\n' > "$SD/srinvalid/automate-2026-10-03-120000.supervisor-result.md"

# logs/: token_ledger events (one duplicated agent_id, one real-usage agent, one unrelated agent,
# a malformed line, a non-ledger event).
{
  echo '{"event":"token_ledger","agent_type":"loomwright:loomwright:fixture-agent","agent_id":"a1","ts":"2026-10-02T00:00:00Z","proxy":true,"token_proxy_transcript_bytes":100}'
  echo '{"event":"token_ledger","agent_type":"loomwright:loomwright:fixture-agent","agent_id":"a1","ts":"2026-10-02T00:00:00Z","proxy":true,"token_proxy_transcript_bytes":100}'
  echo '{"event":"token_ledger","agent_type":"loomwright:loomwright:fixture-agent","agent_id":"a2","ts":"2026-10-03T00:00:00Z","proxy":true,"token_proxy_transcript_bytes":50}'
  echo '{"event":"token_ledger","agent_type":"loomwright:loomwright:real-agent","agent_id":"r1","ts":"2026-10-03T00:00:00Z","usage":{"input_tokens":10,"output_tokens":5}}'
  echo '{"event":"token_ledger","agent_type":"loomwright:loomwright:other-agent","agent_id":"o1","ts":"2026-10-03T00:00:00Z","proxy":true,"token_proxy_transcript_bytes":9999}'
  echo '{"event":"token_ledger", broken'
  echo '{"event":"session_end","ts":"2026-10-03T00:00:00Z"}'
} > "$SD/logs/s1.jsonl"

SB='"header": "SUPERVISOR_RESULT", "format": "result_block"'
T_REG="$ROOT/registry.json"
cat > "$T_REG" <<EOF
{
  "schema_version": 1,
  "min_sample": 3,
  "not_features": ["skip_me"],
  "features": [
    {"id": "f_keep", "critical": false, "record": {"glob": "sr/*.supervisor-result.md", $SB, "field": "alpha"},
     "ran": {"present": true}, "caught": {"match": "hit: true"}, "cost": {"source": "duration", "field": "alpha_secs"}},
    {"id": "f_cost", "critical": false, "record": {"glob": "sr/*.supervisor-result.md", $SB, "field": "beta"},
     "ran": {"present": true}, "caught": {"match": "found"}, "cost": {"source": "token_ledger", "agent": "fixture-agent"}},
    {"id": "f_crit", "critical": true, "record": {"glob": "sr/*.supervisor-result.md", $SB, "field": "gamma"},
     "ran": {"present": true}, "caught": {"match": "found"}, "cost": {"source": "token_ledger", "agent": "real-agent"}},
    {"id": "f_never", "critical": false, "record": {"glob": "sr/*.supervisor-result.md", "format": "text", "header": "SUPERVISOR_RESULT", "field": "delta_marker"},
     "ran": {"match": "^on"}, "caught": {"match": "x"}, "cost": "none"},
    {"id": "f_crit_never", "critical": true, "record": {"glob": "sr/*.supervisor-result.md", "format": "text", "header": "SUPERVISOR_RESULT", "field": "eps_marker"},
     "ran": {"match": "^on"}, "caught": {"match": "x"}, "cost": "none"},
    {"id": "f_small", "critical": false, "record": {"glob": "small/*.supervisor-result.md", $SB, "field": "alpha"},
     "ran": {"present": true}, "caught": {"match": "hit: true"}, "cost": "none"},
    {"id": "f_unknown", "critical": false, "record": {"glob": "sr/*.supervisor-result.md", $SB, "field": "unk"},
     "ran": {"present": true}, "caught": "unknown", "cost": "none"},
    {"id": "f_partial", "critical": false, "record": {"glob": "sr/*.supervisor-result.md", $SB, "field": "part"},
     "ran": {"present": true}, "caught": {"match": "found"}, "cost": "none"},
    {"id": "f_none", "critical": false, "record": "none", "ran": "unknown", "caught": "unknown", "cost": "none"},
    {"id": "f_tsv", "critical": false, "record": {"glob": "pm/*.tsv", "format": "tsv", "field": "2", "columns": 4, "valid": "^(held|not_held)$"},
     "ran": {"present": true}, "caught": {"match": "^not_held$"}, "cost": "none"},
    {"id": "f_tsv_bad", "critical": false, "record": {"glob": "pmbad/*.tsv", "format": "tsv", "field": "2", "columns": 4, "valid": "^(held|not_held)$"},
     "ran": {"present": true}, "caught": {"match": "^not_held$"}, "cost": "none"},
    {"id": "f_json", "critical": false, "record": {"glob": "js/*.next-step.json", "format": "json", "field": "fallback_review_ran"},
     "ran": {"match": "^true$"}, "caught": "unknown", "cost": "none"},
    {"id": "f_json_nested", "critical": false, "record": {"glob": "js/*.next-step.json", "format": "json", "field": "x.y"},
     "ran": {"present": true}, "caught": {"match": "^2$"}, "cost": "none"},
    {"id": "f_json_bad", "critical": false, "record": {"glob": "jsbad/*.next-step.json", "format": "json", "field": "fallback_review_ran"},
     "ran": {"match": "^true$"}, "caught": "unknown", "cost": "none"},
    {"id": "f_sr_bad", "critical": false, "record": {"glob": "srbad/*.supervisor-result.md", $SB, "field": "alpha"},
     "ran": {"present": true}, "caught": {"match": "hit: true"}, "cost": "none"},
    {"id": "f_sr_invalid", "critical": false, "record": {"glob": "srinvalid/*.supervisor-result.md", $SB, "field": "alpha", "valid": "hit: (true|false)"},
     "ran": {"present": true}, "caught": {"match": "hit: true"}, "cost": "none"},
    {"id": "f_bad_entry", "critical": false, "record": {"glob": "sr/*.md", "format": "yaml", "field": "alpha"},
     "ran": {"present": true}, "caught": {"match": "x"}, "cost": "none"}
  ]
}
EOF

SCHEMA="$ROOT/supervisor-result.md"
cat > "$SCHEMA" <<'EOF'
## SUPERVISOR_RESULT

```yaml
SUPERVISOR_RESULT:
  schema_version: 1        # integer, required
  alpha: object            # optional — registered as f_keep's field
  skip_me: string          # optional — listed in not_features
  orphan_field: string     # optional — in neither list
  nested_thing:            # optional (fixture)
    inner: string          # optional — nested, never a top-level field
```

```yaml
SUPERVISOR_RESULT:
  later_block: x           # optional — a second yaml block is not the schema
```
EOF
export FEATURE_SCORECARD_SCHEMA_DOC="$SCHEMA"

run() {   # run <builder> [args...] → OUT, ERRF, RC
  _b="$1"; shift
  OUT="$(bash "$_b" --state-dir "$SD" --registry "$T_REG" "$@" 2>"$ROOT/stderr")"; RC=$?
}

# ---------------------------------------------------------------------------- the verdict suite
# Run against the real builder (MODE=report) and the mutant (MODE=count).
verdict_suite() {
  run "$1" --json
  check "(1) exit 0" "$RC" "0"
  check "(1) status ok" "$(printf '%s' "$OUT" | jq -r '.status' 2>/dev/null)" "ok"
  check "(1) keep — caught >= 1" "$(field f_keep .verdict)" "keep"
  check "(1) AC2 ran >= min_sample, caught 0 ⇒ review: costs without catching" "$(field f_cost .verdict)" "review: costs without catching"
  check "(1) AC8 critical feature on the costs-without-catching arm ⇒ keep (critical)" "$(field f_crit .verdict)" "keep (critical)"
  check "(1) ran 0 ⇒ review: never ran" "$(field f_never .verdict)" "review: never ran"
  check "(1) AC8 critical feature on the never-ran arm ⇒ keep (critical)" "$(field f_crit_never .verdict)" "keep (critical)"
  check "(1) runs available < min_sample ⇒ insufficient data" "$(field f_small .verdict)" "insufficient data"
  check "(1) caught unknown ⇒ insufficient data" "$(field f_unknown .verdict)" "insufficient data"
  check "(1) ran below min_sample, caught 0 ⇒ insufficient data" "$(field f_partial .verdict)" "insufficient data"
  check "(1) AC5 record none ⇒ no record" "$(field f_none .verdict)" "no record"
  check "(3) AC9 malformed TSV row ⇒ unreadable" "$(field f_tsv_bad '.verdict | startswith("unreadable: ")')" "true"
  check "(3) AC9 header-less sidecar ⇒ unreadable" "$(field f_sr_bad '.verdict | startswith("unreadable: ")')" "true"
  check "(3) AC9 invalid JSON record ⇒ unreadable" "$(field f_json_bad '.verdict | startswith("unreadable: ")')" "true"
  check "(3) a value failing the registry valid pattern ⇒ unreadable" "$(field f_sr_invalid '.verdict | startswith("unreadable: ")')" "true"
  check "(3) a bad registry entry ⇒ only that feature unreadable" "$(field f_bad_entry '.verdict | startswith("unreadable: registry entry")')" "true"
  check "(3) AC9 only the malformed features are unreadable" \
    "$(printf '%s' "$OUT" | jq -r '[.features[] | select(.verdict | startswith("unreadable: ")) | .id] | sort | join(",")')" \
    "f_bad_entry,f_json_bad,f_sr_bad,f_sr_invalid,f_tsv_bad"
  check "(2) tsv: a not_held row is a catch ⇒ keep" "$(field f_tsv .verdict)" "keep"
  check "(2) json (mtime-dated), caught unknown ⇒ insufficient data" "$(field f_json .verdict)" "insufficient data"
  check "(2) json dotted path x.y read" "$(field f_json_nested .verdict)" "keep"

  run "$1" --json --since 2031-01-01
  check "(5) AC6 --since later than every record: exit 0" "$RC" "0"
  check "(5) AC6 every feature with a record ⇒ insufficient data" \
    "$(printf '%s' "$OUT" | jq -r '[.features[] | select(.id != "f_none" and (.id | startswith("f_bad_entry") | not)) | .verdict] | unique | join(",")')" \
    "insufficient data"
  check "(5) AC6 the record-none feature still prints no record" "$(field f_none .verdict)" "no record"
  check "(5) AC6 runs available 0 in an empty window" "$(field f_cost .runs_available)" "0"
}

verdict_suite "$BUILDER"

# ---------------------------------------------------------------------------- record + metric details
run "$BUILDER" --json
check "(2) all three SUPERVISOR_RESULT block forms read (runs available 5)" "$(field f_keep .runs_available)" "5"
check "(2) ran counts every form" "$(field f_cost .ran)" "5"
check "(2) caught counted once (the fenced-form hit is file 3, indented)" "$(field f_keep .caught)" "1"
check "(2) catch rate" "$(field f_keep .catch_rate)" "20%"
check "(2) catch rate n/a when ran 0" "$(field f_never .catch_rate)" "n/a"
check "(2) last fired = newest ran record's date" "$(field f_keep .last_fired)" "2026-10-05T12:00:00Z"
check "(2) last fired null when it never ran" "$(field f_never .last_fired)" "null"
check "(2) empty TSV is zero rows: runs 4, ran 3" "$(field f_tsv '[.runs_available, .ran] | join(",")')" "4,3"
check "(2) json records dated by mtime are in the window" "$(field f_json '[.runs_available, .ran] | join(",")')" "3,3"
check "(3) unreadable reason names the file and the column count" \
  "$(field f_tsv_bad .verdict)" "unreadable: 2026-10-02-b.tsv: line 1: 3 columns, expected 4"
check "(3) header-less sidecar reason" "$(field f_sr_bad .verdict)" \
  "unreadable: automate-2026-10-02-120000.supervisor-result.md: no SUPERVISOR_RESULT: block"
check "(3) unreadable features carry null counts, never 0" "$(field f_tsv_bad '[.runs_available, .ran, .caught] | map(tostring) | join(",")')" "null,null,null"
check "(4) token_ledger cost: agent-suffix match, agent_id de-duped (100 + 50)" "$(field f_cost .cost_total)" "proxy:150B"
check "(4) cost per catch n/a when caught 0" "$(field f_cost .cost_per_catch)" "n/a"
check "(4) real usage summed (10 + 5)" "$(field f_crit .cost_total)" "real:15t"
check "(4) duration cost summed over the window (5 × 10)" "$(field f_keep .cost_total)" "50s"
check "(4) duration cost per catch" "$(field f_keep .cost_per_catch)" "50s"
check "(4) no cost record ⇒ unknown, never 0" "$(field f_tsv .cost_total)" "unknown"
check "(4) record paths name the record glob and the ledger" \
  "$(field f_cost '.record_paths | join(" ")')" "$SD/sr/*.supervisor-result.md $SD/logs/*.jsonl"
check "(5) contract keys" "$(printf '%s' "$OUT" | jq -r '[.schema_version, .status, .error, .since] | map(tostring) | join(",")')" "1,ok,null,null"
check "(5) feature keys exactly the --json contract" \
  "$(printf '%s' "$OUT" | jq -r '.features[0] | keys_unsorted | join(",")')" \
  "id,critical,record_paths,runs_available,ran,caught,catch_rate,cost_total,cost_per_catch,last_fired,verdict"
check "(5) AC5 record-none counts are null, never 0" \
  "$(field f_none '[.runs_available, .ran, .caught, .catch_rate, .cost_total, .last_fired] | map(tostring) | unique | join(",")')" "null"
check "(7) needs an emitter lists every record-none id" "$(printf '%s' "$OUT" | jq -r '.needs_emitter | join(",")')" "f_none"
check "(7) unregistered = schema optional fields − record fields − not_features (first yaml block, top-level keys)" \
  "$(printf '%s' "$OUT" | jq -r '.unregistered | join(",")')" "nested_thing,orphan_field"

run "$BUILDER" --json --since 2026-10-04
check "(5) partial window: --since echoed" "$(printf '%s' "$OUT" | jq -r '.since')" "2026-10-04"
check "(5) partial window: 2 sidecars in window" "$(field f_keep .runs_available)" "2"
check "(5) partial window: the out-of-window catch is not counted ⇒ insufficient data" "$(field f_keep .verdict)" "insufficient data"
check "(5) partial window: ledger events before --since are left out" "$(field f_cost .cost_total)" "unknown"

run "$BUILDER" --json --since 2026-10-03T00:00:00Z
check "(5) ISO --since accepted (3 sidecars from 10-03)" "$(field f_cost .runs_available)" "3"

run "$BUILDER" --json --since not-a-date-or-sha
check "(5) bad --since ⇒ status error, exit 0" "$(printf '%s' "$OUT" | jq -r '.status'),$RC" "error,0"
check "(5) bad --since ⇒ no features" "$(printf '%s' "$OUT" | jq -r '.features | length')" "0"
OUT="$(bash "$BUILDER" --state-dir "$SD" --registry "$T_REG" --since --json 2>/dev/null)"
check "(5) --since followed by a flag is a missing value, never the window" "$(printf '%s' "$OUT" | jq -r '.status')" "error"

# --since <commit>: a fixture git repo whose only commit is dated after every record.
GR="$ROOT/gitrepo"; mkdir -p "$GR"
if git -C "$GR" init -q 2>/dev/null; then
  cp -R "$SD" "$GR/.supervisor"
  ( cd "$GR" && echo x > f && git add f && GIT_COMMITTER_DATE="2030-06-01T00:00:00Z" GIT_AUTHOR_DATE="2030-06-01T00:00:00Z" \
      git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --no-verify -m c ) >/dev/null 2>&1
  OUT="$(bash "$BUILDER" --state-dir "$GR/.supervisor" --registry "$T_REG" --json --since HEAD 2>/dev/null)"
  check "(5) --since <commit> resolves against the state dir's repo" "$(field f_keep .verdict),$(field f_keep .runs_available)" "insufficient data,0"
fi

# ---------------------------------------------------------------------------- table mode
run "$BUILDER"
check "(1) table: exit 0" "$RC" "0"
if grep -q '^| feature | critical | runs available | ran | caught | catch rate | cost total | cost per catch | last fired | verdict |$' <<<"$OUT"; then
  ok "(1) table header row"
else no "(1) table header row missing"; fi
none_row="$(printf '%s\n' "$OUT" | grep '^| f_none |')"
case "$none_row" in
  *"| no record |") ok "(1) AC5 table: record-none row ends in no record" ;;
  *) no "(1) AC5 table: record-none row: $none_row" ;;
esac
case "$none_row" in
  *"| 0 |"*) no "(1) AC5 table: record-none row prints a 0" ;;
  *) ok "(1) AC5 table: record-none row prints no 0" ;;
esac
if grep -qx -- '- f_none' < <(sed -n '/^## Needs an emitter/,/^$/p' <<<"$OUT"); then
  ok "(1) AC5 table: f_none listed under Needs an emitter"
else no "(1) AC5 table: f_none not under Needs an emitter"; fi
if grep -qx -- '- orphan_field' < <(sed -n '/^## Unregistered/,$p' <<<"$OUT"); then
  ok "(7) table: orphan_field listed under Unregistered"
else no "(7) table: Unregistered list missing orphan_field"; fi
if grep -q '^| f_tsv_bad | no | - | - | - | - | - | - | - | unreadable: ' <<<"$OUT"; then
  ok "(3) table: unreadable row renders dashes, not numbers"
else no "(3) table: unreadable row shape"; fi

# ---------------------------------------------------------------------------- AC10: registry errors
OUT="$(bash "$BUILDER" --state-dir "$SD" --registry "$ROOT/missing.json" 2>"$ROOT/stderr")"; RC=$?
check "(6) missing registry: exit 0" "$RC" "0"
check "(6) missing registry: no rows on stdout" "$OUT" ""
check "(6) missing registry: exactly one stderr line" "$(wc -l < "$ROOT/stderr" | tr -d ' ')" "1"
OUT="$(bash "$BUILDER" --state-dir "$SD" --registry "$ROOT/missing.json" --json 2>/dev/null)"; RC=$?
check "(6) missing registry --json: status error, features [], exit 0" \
  "$(printf '%s' "$OUT" | jq -r '[.status, (.features | length), (.error | type)] | map(tostring) | join(",")'),$RC" "error,0,string,0"
printf '{"schema_version": 1, "min_sample": 3, "features": [' > "$ROOT/broken.json"
OUT="$(bash "$BUILDER" --state-dir "$SD" --registry "$ROOT/broken.json" --json 2>"$ROOT/stderr")"; RC=$?
check "(6) invalid-JSON registry: status error, no features, exit 0" \
  "$(printf '%s' "$OUT" | jq -r '[.status, (.features | length), (.needs_emitter | length)] | map(tostring) | join(",")'),$RC" "error,0,0,0"
check "(6) invalid-JSON registry: one stderr line" "$(wc -l < "$ROOT/stderr" | tr -d ' ')" "1"
jq '.min_sample = 0' "$T_REG" > "$ROOT/zero.json"
OUT="$(bash "$BUILDER" --state-dir "$SD" --registry "$ROOT/zero.json" --json 2>/dev/null)"
check "(6) min_sample 0 ⇒ registry invalid" "$(printf '%s' "$OUT" | jq -r '.status')" "error"
OUT="$(bash "$BUILDER" --state-dir "$ROOT/no-such-dir" --registry "$T_REG" --json 2>/dev/null)"; RC=$?
check "(6) nonexistent state dir: status ok, exit 0" "$(printf '%s' "$OUT" | jq -r '.status'),$RC" "ok,0"
check "(6) nonexistent state dir: every record feature insufficient data, runs 0" \
  "$(printf '%s' "$OUT" | jq -r '[.features[] | select(.id != "f_none" and .id != "f_bad_entry") | "\(.verdict)/\(.runs_available)"] | unique | join(",")')" \
  "insufficient data/0"

# ---------------------------------------------------------------------------- AC1: shipped registry
RSD="$ROOT/real-sd"; mkdir -p "$RSD/automate" "$RSD/review-heal" "$RSD/pin-mutations" "$RSD/logs"
for n in 1 2 3 4 5 6; do
  {
    echo "SUPERVISOR_RESULT:"
    echo "  schema_version: 1"
    echo "  rubric_score: \"5/6\""
    echo "  risk_classification: {high_risk: true, reasons: []}"
    echo "  summary: \"red_team_advisory: disabled\""
  } > "$RSD/automate/automate-2026-10-0${n}-120000.supervisor-result.md"
done
OUT="$(FEATURE_SCORECARD_SCHEMA_DOC= bash "$BUILDER" --state-dir "$RSD" --registry "$REAL_REGISTRY" --json 2>/dev/null)"; RC=$?
check "(8) shipped registry: status ok, exit 0" "$(printf '%s' "$OUT" | jq -r '.status'),$RC" "ok,0"
check "(8) AC1 one row per registry id, in registry order" \
  "$(printf '%s' "$OUT" | jq -r '[.features[].id] | join(",")')" "$(jq -r '[.features[].id] | join(",")' "$REAL_REGISTRY")"
check "(8) AC1 every row has a verdict" "$(printf '%s' "$OUT" | jq -r '[.features[] | select((.verdict // "") == "")] | length')" "0"
check "(8) shipped registry: every record:none id is in needs_emitter" \
  "$(printf '%s' "$OUT" | jq -r '.needs_emitter | join(",")')" "$(jq -r '[.features[] | select(.record == "none") | .id] | join(",")' "$REAL_REGISTRY")"
check "(8) shipped registry names at least one record:none feature" \
  "$(jq -r '[.features[] | select(.record == "none")] | length > 0' "$REAL_REGISTRY")" "true"
check "(8) shipped registry: rubric 5/6 is a catch ⇒ keep" "$(field rubric_score .verdict)" "keep"
check "(8) shipped registry: unregistered is an array (drift report, not a gate)" "$(printf '%s' "$OUT" | jq -r '.unregistered | type')" "array"
check "(8) shipped registry: min_sample is a positive integer" "$(jq -r '.min_sample | (type == "number" and . >= 1 and . == floor)' "$REAL_REGISTRY")" "true"

# ---------------------------------------------------------------------------- (9) mutation control
MUT="$ROOT/mutant/build-feature-scorecard.sh"; mkdir -p "$ROOT/mutant"
awk -v a='VERDICT="$v"' -v b='VERDICT="keep"' '
  { i = index($0, a); if (i > 0) { $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); n++ } print }
  END { if (n != 1) exit 3 }' "$BUILDER" > "$MUT"; awk_rc=$?
if [ "$awk_rc" -ne 0 ] || [ ! -s "$MUT" ] || cmp -s "$BUILDER" "$MUT" || ! bash -n "$MUT" 2>/dev/null; then
  no "(9) mutant invalid (rc=$awk_rc, empty, identical or bash -n failed) — the mutation control cannot be trusted"
else
  ok "(9) mutant built: one occurrence replaced, differs, bash -n clean"
  MODE=count; MUT_FAILS=0
  verdict_suite "$MUT"
  MODE=report
  if [ "$MUT_FAILS" -gt 0 ]; then
    ok "(9) AC12 verdict rule edited to always keep turns the suite red ($MUT_FAILS assertions failed)"
  else
    no "(9) AC12 always-keep mutant passed every verdict assertion — the suite does not pin the verdict rule"
  fi
fi

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
