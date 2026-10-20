#!/usr/bin/env bash
# selftest.sh — the coordinator-model eval suite checked WITHOUT a model (automate-speed/10).
#
#   bash selftest.sh        one tally `PASS: <n> FAIL: <m>`, exit 1 on any failure
#
# Hermetic: every case is staged by its own scaffold.sh into a `mktemp -d` sandbox (HOME sandboxed, the stub
# gh first on PATH, no network, no `claude`), then driven by a REFERENCE coordinator — the loop the prompt
# describes, done mechanically: run .eval/entry.txt; `spawn` ⇒ bin/spawn-phase, `ask` ⇒ bin/ask-owner, each
# reported with --result-file; stop at park / done / no instruction. It proves the graders can PASS and FAIL:
#   S1  every `ab` case: the reference run scores PARITY: PASS, SKIPPED: 0, WRONG_QUESTIONS: 0 — so a case
#       failing under a model is the model's run, never an unreachable expectation
#   S2  the mutation-control case: the same reference run scores PARITY: FAIL (AC5)
#   S3  grader sensitivity: an ask-owner call with no ask pending ⇒ WRONG_QUESTIONS: 1; stopping at the
#       first spawn / ask without answering it ⇒ SKIPPED: 1; a run file edited by hand ⇒ PARITY: FAIL
#   S4  every case.yaml carries the same prompt and graders (one protocol, five cases)
# Also run as leg E of scripts/test-automate-next-step.sh. bash 3.2 + BSD userland + jq.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(cd "$LIB/.." && pwd)"
pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1"; fail=$((fail + 1)); }
WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# stage <case dir> — a fresh sandbox staged by the case's own scaffold; sets SB
stage() {
  SB="$(mktemp -d "$WORK/sb.XXXXXX")/cwd" && mkdir -p "$SB" "$SB/../home" || return 1
  ( cd "$SB" && HOME="$SB/../home" bash "$1/scaffold.sh" ) > "$SB/../scaffold.log" 2>&1
}
v() { sed -n "s/^$1: //p" "$SB/.eval/verdict.txt"; }   # one verdict field
last_do() { tail -n 1 "$SB/.eval/calls.log" | cut -f4; }
rf() { printf '.supervisor/automate/%s.md' "$(cat "$SB/.eval/run_id")"; }
# reference <stop-at> — the reference coordinator; <stop-at> = spawn|ask stops before answering that do
reference() {
  local stop="${1:-}" n=0 p
  ( cd "$SB" && HOME="$SB/../home" eval "$(cat .eval/entry.txt)" ) >/dev/null 2>&1
  while [ "$n" -lt 20 ]; do
    n=$((n + 1))
    case "$(last_do)" in
      spawn|ask)
        [ "$(last_do)" != "$stop" ] || return 0
        if [ "$(last_do)" = spawn ]; then p="$(cd "$SB" && bash bin/spawn-phase 2>/dev/null)"; else p="$(cd "$SB" && bash bin/ask-owner 2>/dev/null)"; fi
        [ -n "$p" ] || return 1
        ( cd "$SB" && HOME="$SB/../home" bash bin/automate-next-step.sh "$(rf)" --result-file "$p" ) >/dev/null 2>&1 ;;
      *) return 0 ;;
    esac
  done
  return 1
}

echo "== coordinator-model eval selftest ($SUITE)"
first=""
for d in "$SUITE"/[0-9]*/; do
  d="${d%/}"; c="$(basename "$d")"
  [ -f "$d/case.yaml" ] && [ -f "$d/scaffold.sh" ] || { no "$c: case.yaml / scaffold.sh missing"; continue; }
  # S4: the prompt and graders block (everything from `execution:` on, minus the per-case outcome note)
  body="$(awk '/^execution:/{ f = 1 } /^expected_outcome:/{ s = 1; next } s && /^  /{ next } { s = 0 } f' "$d/case.yaml")"
  if [ -z "$first" ]; then first="$body"; elif [ "$body" = "$first" ]; then ok "S4 $c: same prompt + graders as the first case"; else no "S4 $c: prompt / graders differ from the first case"; fi
  if ! stage "$d"; then no "$c: scaffold failed: $(tail -n 3 "$SB/../scaffold.log" | tr '\n' ' ')"; continue; fi
  if ! reference; then no "$c: the reference coordinator did not finish (calls: $(tr '\n' ' ' < "$SB/.eval/calls.log"))"; continue; fi
  if grep -qE '^tags: \[.*mutation-control' "$d/case.yaml"; then
    [ "$(v PARITY)" = FAIL ] && ok "S2 $c: the reference run scores PARITY: FAIL against the mutated expectation" \
      || no "S2 $c: the mutation control scored PARITY: $(v PARITY)"
  else
    [ "$(v PARITY)" = PASS ] && [ "$(v SKIPPED)" = 0 ] && [ "$(v WRONG_QUESTIONS)" = 0 ] \
      && ok "S1 $c: the reference run scores PARITY: PASS, SKIPPED: 0, WRONG_QUESTIONS: 0 ($(v CALLS) call(s), last do $(v LAST_DO))" \
      || no "S1 $c: $(tr '\n' ' ' < "$SB/.eval/verdict.txt") — $(diff "$SB/.eval/expected.norm" "$SB/.eval/run.norm" | head -n 6 | tr '\n' ' ')"
  fi
done

# S3 — grader sensitivity, on the two cases that print a spawn and an ask
if stage "$SUITE/02-ask-interactive-decide-then-park"; then
  ( cd "$SB" && bash bin/ask-owner ) >/dev/null 2>&1   # before any driver call: nothing is pending
  reference
  [ "$(v WRONG_QUESTIONS)" = 1 ] && ok "S3: an ask-owner call with no ask pending ⇒ WRONG_QUESTIONS: 1" || no "S3: wrong question scored $(v WRONG_QUESTIONS)"
fi
if stage "$SUITE/02-ask-interactive-decide-then-park"; then
  reference ask
  [ "$(v SKIPPED)" = 1 ] && [ "$(v PARITY)" = FAIL ] && ok "S3: stopping at the ask without answering ⇒ SKIPPED: 1, PARITY: FAIL" \
    || no "S3: unanswered ask scored SKIPPED: $(v SKIPPED), PARITY: $(v PARITY)"
fi
if stage "$SUITE/01-spawn-run-report"; then
  reference spawn
  [ "$(v SKIPPED)" = 1 ] && ok "S3: stopping at the spawn without answering ⇒ SKIPPED: 1" || no "S3: unanswered spawn scored SKIPPED: $(v SKIPPED)"
fi
if stage "$SUITE/04-done-check-off"; then
  reference && printf -- '- 2026-10-20T00:00:00Z hand-written line\n' >> "$SB/$(rf)" && ( cd "$SB" && bash .eval/verdict.sh )
  [ "$(v PARITY)" = FAIL ] && ok "S3: a run file edited by hand ⇒ PARITY: FAIL" || no "S3: hand edit scored PARITY: $(v PARITY)"
fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
