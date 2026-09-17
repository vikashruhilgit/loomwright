#!/usr/bin/env bash
# test-checkpoint.sh — self-tests for checkpoint.sh, the tiny fail-safe `worker_checkpoint`
# emitter (.supervisor/requirements/orca-derived/03-worker-checkpoints.md). Runs entirely
# under a temp dir (mktemp -d); never touches the real .supervisor/. Exit 0 = all pass,
# 1 = any failure (auto-registered by ci.yml's test-*.sh glob).
#
# Covers:
#   (a) missing ledger-path arg → no-op, exit 0
#   (b) invalid/unwritable ledger path (an existing directory) → no-op, exit 0
#   (c) unwritable ledger path (ancestor path component is a plain file) → no-op, exit 0
#   (d) valid emission for each of the 5 kinds
#   (e) unrecognized kind → no-op
#   (f) paths[] included when given, OMITTED (not an empty array) when not given
#   (g) the exact "positional arg silently omitted" regression (memory
#       `learning-emit-ledger-path-positional`): calling checkpoint.sh WITHOUT the ledger
#       path (kind/text shifted into its slot) must write NOTHING anywhere — not even to
#       a file incidentally named after one of the shifted-in values
#   (h) missing kind / missing text → no-op

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CP="$HERE/checkpoint.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "test-checkpoint: jq absent — checkpoint.sh no-ops on every emission (exit 0). Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ============================================================================
echo "== (a) missing ledger-path arg → no-op, exit 0 =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
( cd "$d" && bash "$CP" )
rcA=$?
[ "$rcA" -eq 0 ] && ok "exits 0 with zero args" || no "expected exit 0, got $rcA"
[ -z "$(find "$d" -type f 2>/dev/null)" ] && ok "no file written anywhere under the cwd" || no "a stray file was written: $(find "$d" -type f)"

# ============================================================================
echo "== (b) invalid ledger path — an EXISTING DIRECTORY — → no-op, exit 0 =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
mkdir -p "$d/ledger-is-a-dir"
bash "$CP" "$d/ledger-is-a-dir" hypothesis_confirmed "reproduced the bug"
rcB=$?
[ "$rcB" -eq 0 ] && ok "exits 0 when ledger path is a directory" || no "expected exit 0, got $rcB"
[ -z "$(find "$d/ledger-is-a-dir" -type f 2>/dev/null)" ] && ok "the directory gained no file inside it" || no "a file appeared inside the directory-as-ledger"

# ============================================================================
echo "== (c) unwritable ledger path — ancestor path component is a plain file — → no-op =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
printf 'im a file, not a dir\n' > "$d/blocker"
bash "$CP" "$d/blocker/sub/ledger.jsonl" blocker "cannot proceed"
rcC=$?
[ "$rcC" -eq 0 ] && ok "exits 0 when an ancestor path component is a plain file" || no "expected exit 0, got $rcC"
[ ! -e "$d/blocker/sub" ] && ok "no sub-path was created under the blocking file" || no "a sub-path was unexpectedly created"

# ============================================================================
echo "== (d) valid emission for each of the 5 kinds =="
kinds="hypothesis_confirmed hypothesis_refuted blocker transition slice_done"
for k in $kinds; do
  d="$(mktemp -d "$ROOT/d.XXXXXX")"
  ledger="$d/session.jsonl"
  bash "$CP" "$ledger" "$k" "did the $k thing"
  rc=$?
  [ "$rc" -eq 0 ] && ok "($k) exits 0" || no "($k) expected exit 0, got $rc"
  [ -f "$ledger" ] && ok "($k) ledger file written" || no "($k) ledger file missing"
  line="$(cat "$ledger" 2>/dev/null)"
  echo "$line" | jq -e --arg k "$k" '.event == "worker_checkpoint" and .kind == $k and (.text | length) > 0' >/dev/null 2>&1 \
    && ok "($k) line has event=worker_checkpoint, kind=$k, non-empty text" \
    || no "($k) malformed/missing line: $line"
  # Exactly one line (append, not overwrite/duplicate).
  [ "$(wc -l < "$ledger" | tr -d ' ')" = "1" ] && ok "($k) exactly one JSONL line" || no "($k) unexpected line count"
done

# ============================================================================
echo "== (e) unrecognized kind → no-op =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
ledger="$d/session.jsonl"
bash "$CP" "$ledger" not_a_real_kind "some text"
rcE=$?
[ "$rcE" -eq 0 ] && ok "exits 0 on an unrecognized kind" || no "expected exit 0, got $rcE"
[ ! -f "$ledger" ] && ok "no ledger file was created for an unrecognized kind" || no "ledger file was created despite an invalid kind: $(cat "$ledger")"

# ============================================================================
echo "== (f) paths[] included when given, OMITTED when not given =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
ledger="$d/session.jsonl"
bash "$CP" "$ledger" slice_done "shipped the thing" "src/a.ts" "src/b.ts"
jq -e '.paths == ["src/a.ts","src/b.ts"]' "$ledger" >/dev/null 2>&1 \
  && ok "paths[] present and correct when given" || no "paths[] missing/incorrect: $(cat "$ledger")"

d2="$(mktemp -d "$ROOT/d.XXXXXX")"
ledger2="$d2/session.jsonl"
bash "$CP" "$ledger2" slice_done "shipped the thing, no paths"
jq -e 'has("paths") | not' "$ledger2" >/dev/null 2>&1 \
  && ok "paths key OMITTED (not an empty array) when no paths were given" \
  || no "paths key present when it should be omitted: $(cat "$ledger2")"

# ============================================================================
echo "== (g) the ledger-path-omitted regression: kind/text shifted in must STILL write nothing =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
( cd "$d" && bash "$CP" hypothesis_confirmed "reproduced the auth failure" )
rcG=$?
[ "$rcG" -eq 0 ] && ok "exits 0 even with the ledger-path arg omitted" || no "expected exit 0, got $rcG"
[ -z "$(find "$d" -type f 2>/dev/null)" ] \
  && ok "NOTHING was written anywhere — no junk file named after the shifted-in kind/text" \
  || no "a stray file was written when the ledger path was omitted: $(find "$d" -type f)"

# ============================================================================
echo "== (h) missing kind / missing text → no-op =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
ledger="$d/session.jsonl"
bash "$CP" "$ledger"
rcH1=$?
[ "$rcH1" -eq 0 ] && ok "exits 0 with only the ledger path given" || no "expected exit 0, got $rcH1"
[ ! -f "$ledger" ] && ok "no ledger file written with kind/text missing" || no "ledger file written despite missing kind/text"

d2="$(mktemp -d "$ROOT/d.XXXXXX")"
ledger2="$d2/session.jsonl"
bash "$CP" "$ledger2" hypothesis_confirmed
rcH2=$?
[ "$rcH2" -eq 0 ] && ok "exits 0 with text missing" || no "expected exit 0, got $rcH2"
[ ! -f "$ledger2" ] && ok "no ledger file written with text missing" || no "ledger file written despite missing text"

# ============================================================================
echo "== (i) cc_session_id is DERIVED from the ledger basename (needed by build-floor.sh) =="
d="$(mktemp -d "$ROOT/d.XXXXXX")"
ledger="$d/sess-abc123.jsonl"
bash "$CP" "$ledger" transition "moving from investigate to fix"
jq -e '.cc_session_id == "sess-abc123"' "$ledger" >/dev/null 2>&1 \
  && ok "cc_session_id derived correctly from the ledger filename" \
  || no "cc_session_id missing/incorrect: $(cat "$ledger")"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
