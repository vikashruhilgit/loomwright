#!/usr/bin/env bash
# stage-golden.sh — the coordinator-model eval's ONE shared scaffold (automate-speed/10).
#
#   bash stage-golden.sh <golden case> [--mutate-expected]
#
# Run by each case's scaffold.sh with the eval sandbox's working directory as cwd (`claude plugin eval
# --scaffold` runs it there, as the operator). Stages ONE golden case of
# loomwright/scripts/fixtures/automate-golden/<case>/ into cwd as a scratch repo, the way
# scripts/test-automate-next-step.sh's new_scratch stages it (git init on `main`, input.md as the run file,
# tree/ with the dot-<name> mapping, gh.stub as the stub table, the sourced setup). The fixtures are READ IN
# PLACE: nothing here, and nothing in the committed eval dir, copies them; the sandbox gets a scratch copy.
#
# Then it lays out the model's world:
#   bin/automate-next-step.sh  the driver as the model calls it: the real driver (a scratch copy of the
#                              plugin under .eval/plugin) with --inline-phases, the fixture's test seams for
#                              that call (`env:` directives, positional, persisting like the test harness's),
#                              the stubbed `gh` and the recorder watcher / notify / run-lock; then the verdict
#   bin/spawn-phase            stands in for running a `spawn`'s work: prints the path of the canned report
#                              the fixture's next `call: --result …` carries (refused when no spawn is pending)
#   bin/ask-owner              stands in for the ask tool: prints the path of the owner's canned answers
#                              (refused — and counted as a WRONG QUESTION — when no `ask` is pending)
#   .eval/entry.txt            the loop's first call, exactly as the fixture's first `call:` line makes it
#   .eval/verdict.txt          rewritten after every call / stand-in: PARITY (the run file, normalised like
#                              leg G — ISO timestamps ⇒ <TS>, the scratch root ⇒ <ROOT> — equals expected.md
#                              byte for byte), SKIPPED (spawn / ask instructions never answered by a later
#                              --result call), WRONG_QUESTIONS (ask-owner with no ask pending), WRONG_SPAWNS,
#                              CALLS, LAST_DO. The case graders read this file.
#
# --mutate-expected (the AC5 mutation control): the staged expectation gets ONE changed `## Progress` line
# (its last), so a correct coordinator run must score PARITY: FAIL.
#
# Supported results directives: env:, call:, expect:, gh:. Anything else (pre:, file:, sidecar:, out:,
# call-bare:, expect-exit:) refuses the case (exit 1) — the eval only stages cases a coordinator can drive from
# one entry call. A case whose expected.md carries a <CASE> / <TMP> token is refused too (only <TS> / <ROOT>
# are normalised here). bash 3.2 + BSD userland + jq.
set -uo pipefail

CASE="${1:-}"; MUT="${2:-}"
[ -n "$CASE" ] || { echo "stage-golden: usage: stage-golden.sh <golden case> [--mutate-expected]" >&2; exit 1; }
case "$MUT" in ""|--mutate-expected) ;; *) echo "stage-golden: unknown option '$MUT'" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "stage-golden: jq not on PATH" >&2; exit 1; }
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$LIB/../../.." && pwd)"
FX="$PLUGIN/scripts/fixtures/automate-golden/$CASE"
for f in input.md expected.md next-step.results source; do
  [ -f "$FX/$f" ] || { echo "stage-golden: $FX/$f missing" >&2; exit 1; }
done
if grep -qE '<CASE>|<TMP>' "$FX/expected.md"; then echo "stage-golden: $CASE's expected.md carries <CASE>/<TMP> — unsupported" >&2; exit 1; fi

W="$(pwd)"; E="$W/.eval"
RUN_ID="$(sed -n 's/^run: *\([^ ]*\).*/\1/p' "$FX/source" | head -n 1)"
[ -n "$RUN_ID" ] || { echo "stage-golden: no run: line in $FX/source" >&2; exit 1; }
ROOT="$W"; AD="$W/.supervisor/automate"; RF="$AD/$RUN_ID.md"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=golden GIT_AUTHOR_EMAIL=golden@example.invalid \
  GIT_COMMITTER_NAME=golden GIT_COMMITTER_EMAIL=golden@example.invalid \
  GIT_AUTHOR_DATE=2026-10-13T12:00:00Z GIT_COMMITTER_DATE=2026-10-13T12:00:00Z

# ---- the scratch repo (new_scratch's shape) -------------------------------------------------------------
mkdir -p "$AD" "$E/env" "$E/canned" "$E/stub" "$W/bin" || exit 1
{ git init -q . && git symbolic-ref HEAD refs/heads/main; } >/dev/null 2>&1 || { echo "stage-golden: git init failed" >&2; exit 1; }
cp "$FX/input.md" "$RF" || exit 1
if [ -d "$FX/tree" ]; then
  T="$E/tree"; mkdir -p "$T" && cp -R "$FX/tree/." "$T/" || exit 1
  find "$T" -depth -name 'dot-?*' | while IFS= read -r p; do
    b="${p##*/}"; t="${p%/*}/.${b#dot-}"; [ ! -e "$t" ] && mv "$p" "$t" || exit 1
  done || { echo "stage-golden: tree staging failed" >&2; exit 1; }
  cp -R "$T/." "$W/" && rm -rf "$T" || exit 1
fi
if [ -f "$FX/setup" ]; then
  ( export ROOT RF RUN_ID; . "$FX/setup" ) >"$E/setup.log" 2>&1 || { echo "stage-golden: setup failed (see .eval/setup.log)" >&2; exit 1; }
fi
if [ -f "$FX/gh.stub" ]; then cp "$FX/gh.stub" "$E/gh.table" || exit 1; else : > "$E/gh.table"; fi
if [ -s "$E/gh.table" ] && [ -n "$(tail -c 1 "$E/gh.table")" ]; then echo >> "$E/gh.table"; fi

# ---- the expectation (mutated for the mutation control) ------------------------------------------------
if [ "$MUT" = --mutate-expected ]; then
  awk '/^## /{ p = ($0 == "## Progress") } { line[NR] = $0; if (p && /^- /) last = NR }
       END { for (i = 1; i <= NR; i++) print (i == last ? line[i] " [mutation-control: this line is deliberately wrong]" : line[i]) }' \
    "$FX/expected.md" > "$E/expected.md" || exit 1
  cmp -s "$FX/expected.md" "$E/expected.md" && { echo "stage-golden: the mutation changed nothing" >&2; exit 1; }
else
  cp "$FX/expected.md" "$E/expected.md" || exit 1
fi
printf '%s\n' "$RUN_ID" > "$E/run_id"

# ---- a scratch copy of the plugin: the driver and every helper it calls (fixtures, tests, docs, evals out) ----
mkdir -p "$E/plugin" && ( cd "$PLUGIN" && tar --exclude ./evals --exclude ./scripts/fixtures --exclude './scripts/test-*' --exclude ./docs --exclude ./sdk-spike -cf - . ) | ( cd "$E/plugin" && tar -xf - ) \
  || { echo "stage-golden: plugin copy failed" >&2; exit 1; }

# ---- the stubbed gh and the recorder (test-automate-next-step.sh's GH_STUB_BODY / REC_BODY) -------------
cat > "$E/stub/gh" <<'EOF'
#!/usr/bin/env bash
all="$*"
if [ -n "${GOLDEN_GH_TABLE:-}" ] && [ -f "$GOLDEN_GH_TABLE" ]; then
  while IFS="	" read -r rc pat out || [ -n "$rc" ]; do
    case "$rc" in ""|"#"*) continue ;; esac
    # shellcheck disable=SC2254
    case "$all" in $pat) [ -n "$out" ] && printf "%s\n" "$out"; exit "$rc" ;; esac
  done < "$GOLDEN_GH_TABLE"
fi
echo "gh-stub: unmatched: $all" >&2
exit 1
EOF
cat > "$E/stub/rec" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$NS_REC_LOG"
exit 0
EOF
chmod +x "$E/stub/gh" "$E/stub/rec"

# ---- the results file ⇒ the entry call, the per-call seams, the canned reports ------------------------
envnow=""; k=0; q=0; entry=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ""|"#"*) continue ;; esac
  rest="${line#*:}"; rest="${rest# }"
  case "$line" in
    "env: "*)
      eval "set -- $rest"
      for w in "$@"; do
        envnow="$(printf '%s\n' "$envnow" | awk -v n="${w%%=*}" -F= 'NF && $1 != n')"
        envnow="$(printf '%s\n%s' "$envnow" "$w" | grep .)"
      done ;;
    "gh: "*) printf '%s\n' "$rest" >> "$E/gh.table" ;;
    "expect: "*) printf '%s\n' "$rest" > "$E/expect.last" ;;
    "call:"*)
      k=$((k + 1)); printf '%s\n' "$envnow" | grep . > "$E/env/$k"; cp "$E/env/$k" "$E/env/last"
      eval "set -- $rest"
      payload=""; flags=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --result) payload="$2"; shift 2 ;;
          *) flags="$flags $(printf '%q' "$1")"; shift ;;
        esac
      done
      if [ "$k" = 1 ]; then
        entry="bash bin/automate-next-step.sh .supervisor/automate/$RUN_ID.md$flags"
        if [ -n "$payload" ]; then printf '%s\n' "$payload" > "$E/canned/entry.json"; entry="$entry --result-file .eval/canned/entry.json"; fi
      else
        [ -z "$flags" ] || { echo "stage-golden: call $k carries flags other than --result ($flags) — unsupported" >&2; exit 1; }
        [ -n "$payload" ] || { echo "stage-golden: call $k carries no --result — unsupported" >&2; exit 1; }
        q=$((q + 1)); printf '%s\n' "$payload" > "$E/canned/q$q.json"
      fi ;;
    *) echo "stage-golden: unsupported directive in $CASE/next-step.results: ${line%%:*}" >&2; exit 1 ;;
  esac
done < "$FX/next-step.results"
[ "$k" -ge 1 ] || { echo "stage-golden: no call: line" >&2; exit 1; }
printf '%s\n' "$entry" > "$E/entry.txt"
printf '0\n' > "$E/canned.next"; : > "$E/calls.log"; : > "$E/standins.log"; printf '0\n' > "$E/calls.n"

# ---- the verdict (rewritten after every call and stand-in) --------------------------------------------
cat > "$E/verdict.sh" <<'EOF'
#!/usr/bin/env bash
# the coordinator-model eval verdict — read by the case graders (regex over .eval/verdict.txt)
E="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; W="$(dirname "$E")"; WP="$(cd "$W" && pwd -P)"
rf="$W/.supervisor/automate/$(cat "$E/run_id").md"
norm() { # leg G's normalisation for these cases: the scratch root ⇒ <ROOT>, ISO timestamps ⇒ <TS>
  local c; c="$(cat "$1"; printf x)"; c="${c%x}"
  c="${c//"$WP"/<ROOT>}"; c="${c//"$W"/<ROOT>}"
  printf '%s' "$c" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<TS>/g'
}
norm "$rf" > "$E/run.norm" 2>/dev/null; norm "$E/expected.md" > "$E/expected.norm"
if cmp -s "$E/run.norm" "$E/expected.norm"; then parity=PASS; else parity=FAIL; fi
# a spawn / ask instruction is answered when a LATER call carried a --result
skipped="$(awk -F'\t' '{ k[NR] = $2; d[NR] = $4 } END { n = 0
  for (i = 1; i <= NR; i++) if (d[i] == "spawn" || d[i] == "ask") { a = 0; for (j = i + 1; j <= NR; j++) if (k[j] == 1) { a = 1; break } if (!a) n++ }
  print n }' "$E/calls.log")"
wq="$(awk -F'\t' '$1 == "ask" && $3 == "WRONG"' "$E/standins.log" | grep -c . | tr -d ' ')"
ws="$(awk -F'\t' '$1 == "spawn" && $3 == "WRONG"' "$E/standins.log" | grep -c . | tr -d ' ')"
calls="$(grep -c . "$E/calls.log" | tr -d ' ')"
last="$(tail -n 1 "$E/calls.log" | cut -f4)"
printf 'PARITY: %s\nSKIPPED: %s\nWRONG_QUESTIONS: %s\nWRONG_SPAWNS: %s\nCALLS: %s\nLAST_DO: %s\n' \
  "$parity" "$skipped" "$wq" "$ws" "$calls" "${last:-none}" > "$E/verdict.txt"
EOF

# ---- the driver as the model calls it ------------------------------------------------------------------
cat > "$W/bin/automate-next-step.sh" <<'EOF'
#!/usr/bin/env bash
# eval stand-in for loomwright/scripts/automate-next-step.sh — the REAL driver (a scratch copy under
# .eval/plugin), run with --inline-phases and this call's fixture seams; its stdout / stderr / exit code pass
# through unchanged. Every call is logged and the verdict rewritten.
W="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; E="$W/.eval"
k=$(( $(cat "$E/calls.n" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$k" > "$E/calls.n"
envf="$E/env/$k"; [ -f "$envf" ] || envf="$E/env/last"
hasres=0; for a in "$@"; do case "$a" in --result|--result-file) hasres=1 ;; esac; done
(
  cd "$W" || exit 98
  unset LOOMWRIGHT_GH_BIN LOOMWRIGHT_HOLDER_PID NEXT_STEP_FROM NEXT_STEP_UNTIL NEXT_STEP_CLOSEOUT_OUT
  export PATH="$E/stub:$PATH" GOLDEN_GH_TABLE="$E/gh.table" NS_REC_LOG="$E/rec.log"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=golden GIT_AUTHOR_EMAIL=golden@example.invalid \
    GIT_COMMITTER_NAME=golden GIT_COMMITTER_EMAIL=golden@example.invalid
  export NEXT_STEP_WATCH_CMD="$E/stub/rec watch" NEXT_STEP_NOTIFY_CMD="$E/stub/rec notify" \
    NEXT_STEP_LOCK_CMD="$E/stub/rec lock" NEXT_STEP_LOCK_RETRY_SECONDS=0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    n="${l%%=*}"; v="${l#*=}"
    if [ -n "$v" ]; then export "$n=$v"; else unset "$n"; fi
  done < "$envf"
  bash "$E/plugin/scripts/automate-next-step.sh" "$@" --inline-phases
) > "$E/out.$k" 2> "$E/err.$k" < /dev/null
rc=$?
cat "$E/out.$k"; cat "$E/err.$k" >&2
d="$(head -n 1 "$E/out.$k" | jq -r '.do // "none"' 2>/dev/null)"
printf '%s\t%s\t%s\t%s\n' "$k" "$hasres" "$rc" "${d:-none}" >> "$E/calls.log"
bash "$E/verdict.sh"
exit "$rc"
EOF

# ---- the two stand-ins ----------------------------------------------------------------------------------
for kind in spawn ask; do
  if [ "$kind" = spawn ]; then nm=spawn-phase; what="a spawn's work (the canned report the fixture recorded)"; else nm=ask-owner; what="the ask tool (the owner's canned answers)"; fi
  cat > "$W/bin/$nm" <<EOF
#!/usr/bin/env bash
# eval stand-in for $what. Prints the path of the canned --result payload to report with --result-file.
KIND=$kind
EOF
  cat >> "$W/bin/$nm" <<'EOF'
W="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; E="$W/.eval"
last="$(tail -n 1 "$E/calls.log" 2>/dev/null | cut -f4)"; at="$(cat "$E/calls.n")"
if [ "$last" != "$KIND" ]; then
  printf '%s\t%s\tWRONG\n' "$KIND" "${last:-none}" >> "$E/standins.log"; bash "$E/verdict.sh"
  echo "$(basename "$0"): refused — the driver's last instruction is '${last:-none}', not '$KIND'" >&2; exit 1
fi
# the same pending instruction asked twice gets the same payload
if [ -f "$E/canned.at" ] && [ "$(cut -f1 "$E/canned.at")" = "$at" ]; then
  printf '%s\t%s\tOK\n' "$KIND" "$last" >> "$E/standins.log"; bash "$E/verdict.sh"; cut -f2 "$E/canned.at"; exit 0
fi
n=$(( $(cat "$E/canned.next") + 1 )); f=".eval/canned/q$n.json"
[ -f "$W/$f" ] || { printf '%s\t%s\tEMPTY\n' "$KIND" "$last" >> "$E/standins.log"; bash "$E/verdict.sh"; echo "$(basename "$0"): no canned payload left" >&2; exit 1; }
printf '%s\n' "$n" > "$E/canned.next"; printf '%s\t%s\n' "$at" "$f" > "$E/canned.at"
printf '%s\t%s\tOK\n' "$KIND" "$last" >> "$E/standins.log"; bash "$E/verdict.sh"
printf '%s\n' "$f"
EOF
  chmod +x "$W/bin/$nm"
done
chmod +x "$W/bin/automate-next-step.sh" "$E/verdict.sh"
bash "$E/verdict.sh"
exit 0
