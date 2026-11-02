#!/usr/bin/env bash
# test-automate-helpers-modules.sh — self-tests for the part LOADER of test-automate-helpers.sh (the
# automate-speed/21 split of that suite into test-automate-helpers.d/). The loader's error branches are
# always-on runtime checks; this file exercises their FAILING side, which the suite itself never does
# (dismissed-followups/05, F223). Runs only against a SCRATCH copy of the runner and of
# test-automate-helpers.d/, in mktemp -d dirs, never the real files.
#
# Scratch layout: $T/lw/scripts/ holds a copy of test-automate-helpers.sh and of
# test-automate-helpers.d/, beside a symlink to every other scripts/ entry (so the runner's bundle build
# and its sibling lookups resolve); $T/lw/skills and $T/lw/docs link the real dirs (the runner assembles
# the split automate-loop skill from `$HERE/../skills`). Each run gets TMPDIR=$T/tmp, so the temp dirs a
# loader-aborted run leaves behind are removed with $T.
#
# Covers (each loader branch: non-zero exit AND its own message, naming the planted part):
#   L0 control — the unmodified scratch copy's loader passes: `11-ceiling` runs, exit 0, the
#      parts banner, a 0-failed RESULT line, and none of the four loader messages.
#   L1 a missing part (18-backlog.sh removed)        ⇒ `FAIL: missing test part: test-automate-helpers.d/18-backlog.sh`
#   L2 an unparseable part (11-ceiling.sh broken)     ⇒ `FAIL: test part does not parse (bash -n): test-automate-helpers.d/11-ceiling.sh`
#   L3 a part-source line differing from TAH_PARTS — (a) one line sources another part's file,
#      (b) one source line dropped                    ⇒ `FAIL: part-source lines differ from TAH_PARTS`
#   L4 an unknown part name argument                  ⇒ `FAIL: unknown test part: 99-nosuch`
#   LM gated mutants: each loader message deleted from a copy of the runner ⇒ the same planted run
#      still takes that branch (its replacement text prints) but the matching leg's check rejects it
#      (so every leg above can fail). Every mutant runner is gated on non-empty +
#      differs from the original + `bash -n`; the planted unparseable part is gated on non-empty +
#      differs + FAILING `bash -n` (that is its point).
# Not covered: the runner's other loader messages (prerequisite map, stray part file, tah_sel, the
# sourced-vs-selected backstop) — no finding names them.
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/test-automate-helpers.sh"
PARTS_D="$HERE/test-automate-helpers.d"
MSG_MISSING='FAIL: missing test part:'
MSG_PARSE='FAIL: test part does not parse (bash -n):'
MSG_SOURCE='FAIL: part-source lines differ from TAH_PARTS'
MSG_UNKNOWN='FAIL: unknown test part:'

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/tmp"

# mk_copy <name> — a fresh scratch tree $T/<name>/lw; prints its scripts/ dir
mk_copy() {
  local s="$T/$1/lw/scripts" e
  mkdir -p "$s" || return 1
  ln -s "$HERE/../skills" "$T/$1/lw/skills" && ln -s "$HERE/../docs" "$T/$1/lw/docs" || return 1
  for e in "$HERE"/*; do
    case "$(basename "$e")" in test-automate-helpers.sh|test-automate-helpers.d) continue ;; esac
    ln -s "$e" "$s/$(basename "$e")" || return 1
  done
  cp "$RUNNER" "$s/test-automate-helpers.sh" && cp -R "$PARTS_D" "$s/test-automate-helpers.d" || return 1
  printf '%s' "$s"
}
# run_copy <scripts-dir> <args…> — sets OUT (stdout+stderr) and RC
run_copy() {
  local s="$1"; shift
  OUT="$(cd "$T/tmp" && env TMPDIR="$T/tmp" "${BASH:-bash}" "$s/test-automate-helpers.sh" "$@" 2>&1)"; RC=$?
}
# gate_runner <scripts-dir> — the copy's runner is non-empty, differs from the real one, and parses
gate_runner() {
  [ -s "$1/test-automate-helpers.sh" ] && ! cmp -s "$RUNNER" "$1/test-automate-helpers.sh" \
    && "${BASH:-bash}" -n "$1/test-automate-helpers.sh" 2>/dev/null
}
# loader_rejects <want-line> — the last run exited non-zero and printed <want-line> (fixed string,
# whole line after the two-space indent)
loader_rejects() { [ "$RC" -ne 0 ] && grep -qxF -- "  $1" <<<"$OUT"; }
# loader_quiet — the last run printed none of the four loader messages
loader_quiet() {
  ! grep -qF -e "$MSG_MISSING" -e "$MSG_PARSE" -e "$MSG_SOURCE" -e "$MSG_UNKNOWN" <<<"$OUT"
}
brief_out() { printf '%s' "$OUT" | tail -n 3 | tr '\n' '|'; }

echo "== L. test-automate-helpers.sh part loader: every error branch exits non-zero with its own message =="

# L0 control — the unmodified copy (byte-identical to the real runner and parts) passes the loader.
C0="$(mk_copy c0)" || C0=""
if [ -n "$C0" ] && cmp -s "$RUNNER" "$C0/test-automate-helpers.sh" && diff -r "$PARTS_D" "$C0/test-automate-helpers.d" >/dev/null 2>&1; then
  run_copy "$C0" 11-ceiling
  if [ "$RC" -eq 0 ] && grep -qxF '== test-automate-helpers: parts 11-ceiling (in this order, prerequisites included) ==' <<<"$OUT" \
     && grep -qE '^RESULT: [1-9][0-9]* passed, 0 failed$' <<<"$OUT" && loader_quiet; then
    ok "L0 control: the unmodified scratch copy's loader passes (11-ceiling runs, exit 0, no loader message)"
  else
    no "L0 control: the unmodified scratch copy failed (rc=$RC): $(brief_out)"
  fi
else
  no "L0 control: could not build an unmodified scratch copy of the runner and its parts"
fi

# L1 — a missing part.
C1="$(mk_copy c1)" || C1=""
L1_WANT="$MSG_MISSING test-automate-helpers.d/18-backlog.sh"
if [ -n "$C1" ] && rm "$C1/test-automate-helpers.d/18-backlog.sh" && [ ! -e "$C1/test-automate-helpers.d/18-backlog.sh" ]; then
  run_copy "$C1"
  if loader_rejects "$L1_WANT"; then
    ok "L1 a missing part ⇒ exit $RC with '$L1_WANT'"
  else
    no "L1 a missing part should exit non-zero with '$L1_WANT' (rc=$RC): $(brief_out)"
  fi
else
  no "L1 could not plant the missing part"
fi

# L2 — an unparseable part (gated: non-empty, differs, and `bash -n` now FAILS on it).
C2="$(mk_copy c2)" || C2=""
L2_WANT="$MSG_PARSE test-automate-helpers.d/11-ceiling.sh"
L2_P="${C2:-/nonexistent}/test-automate-helpers.d/11-ceiling.sh"
if [ -n "$C2" ] && printf '\nif then fi )\n' >> "$L2_P" && [ -s "$L2_P" ] && ! cmp -s "$PARTS_D/11-ceiling.sh" "$L2_P" \
   && ! "${BASH:-bash}" -n "$L2_P" 2>/dev/null; then
  run_copy "$C2"
  if loader_rejects "$L2_WANT"; then
    ok "L2 an unparseable part ⇒ exit $RC with '$L2_WANT'"
  else
    no "L2 an unparseable part should exit non-zero with '$L2_WANT' (rc=$RC): $(brief_out)"
  fi
else
  no "L2 could not plant an unparseable part (empty, unchanged, or still parses)"
fi

# L3 — part-source lines differing from TAH_PARTS: (a) a source line naming another part's file,
# (b) a source line dropped. Each mutant runner is gated.
L3_WANT="$MSG_SOURCE: want one 'tah_run <part> && . \"\$TAH_D/<part>.sh\"' per part, same name twice, in TAH_PARTS order"
C3A="$(mk_copy c3a)" || C3A=""
C3B="$(mk_copy c3b)" || C3B=""
if [ -n "$C3A" ] && [ -n "$C3B" ]; then
  sed 's|^tah_run 12-meta && \. "\$TAH_D/12-meta\.sh"$|tah_run 12-meta \&\& . "$TAH_D/11-ceiling.sh"|' "$RUNNER" > "$C3A/test-automate-helpers.sh"
  grep -v '^tah_run 18-backlog && ' "$RUNNER" > "$C3B/test-automate-helpers.sh"
  for L3_C in "$C3A" "$C3B"; do
    case "$L3_C" in "$C3A") L3_L="(a) one source line sources another part's file" ;; *) L3_L="(b) one source line dropped" ;; esac
    if gate_runner "$L3_C"; then
      run_copy "$L3_C"
      if loader_rejects "$L3_WANT"; then
        ok "L3$L3_L ⇒ exit $RC with '$MSG_SOURCE'"
      else
        no "L3$L3_L should exit non-zero with '$MSG_SOURCE' (rc=$RC): $(brief_out)"
      fi
    else
      no "L3$L3_L mutant runner not gated (empty, identical to the real runner, or fails bash -n)"
    fi
  done
else
  no "L3 could not build the scratch copies"
fi

# L4 — an unknown part name, on the otherwise unmodified copy.
L4_WANT="$MSG_UNKNOWN 99-nosuch (known: $(sed -n 's/^TAH_PARTS="\(.*\)"$/\1/p' "$RUNNER"))"
if [ -n "$C0" ]; then
  run_copy "$C0" 99-nosuch
  if loader_rejects "$L4_WANT"; then
    ok "L4 an unknown part name ⇒ exit $RC with '$MSG_UNKNOWN 99-nosuch (known: …)'"
  else
    no "L4 an unknown part name should exit non-zero with '$MSG_UNKNOWN 99-nosuch' (rc=$RC): $(brief_out)"
  fi
else
  no "L4 no unmodified scratch copy to run"
fi

# LM — gated mutants: one loader message deleted from a copy of the runner ⇒ that leg's check rejects
# the same planted run. lm <label> <copy-name> <message> <plant (eval'd with $S set)> <want-line> [args…]
lm() {
  local label="$1" name="$2" msg="$3" plant="$4" want="$5" S esc; shift 5
  S="$(mk_copy "$name")" || { no "LM $label: could not build the scratch copy"; return; }
  esc="$(printf '%s' "$msg" | sed 's/[][\.*^$|/]/\\&/g')"
  sed "s/$esc/loader-message-removed:/" "$RUNNER" > "$S/test-automate-helpers.sh"
  if ! gate_runner "$S" || grep -qF -- "$msg" "$S/test-automate-helpers.sh"; then
    no "LM $label: mutant runner not gated (empty, identical, fails bash -n, or still carries the message)"; return
  fi
  eval "$plant" || { no "LM $label: could not plant the case"; return; }
  run_copy "$S" "$@"
  if loader_rejects "$want"; then
    no "LM $label: with the message deleted the leg's check still passes — the leg cannot fail"
  elif [ "$RC" -ne 0 ] && grep -qF 'loader-message-removed:' <<<"$OUT"; then
    ok "LM (mutant) $label message deleted ⇒ the run still takes that branch (rc=$RC) but the leg's check rejects it — the leg can fail"
  else
    no "LM $label: the mutant run never reached the mutated branch (rc=$RC): $(brief_out)"
  fi
}
lm "missing-part" m1 "$MSG_MISSING" 'rm "$S/test-automate-helpers.d/18-backlog.sh"' "$L1_WANT"
lm "unparseable-part" m2 "$MSG_PARSE" 'printf "\nif then fi )\n" >> "$S/test-automate-helpers.d/11-ceiling.sh"' "$L2_WANT"
lm "part-source" m3 "$MSG_SOURCE" \
  'grep -v "^tah_run 18-backlog && " "$S/test-automate-helpers.sh" > "$S/r" && ! cmp -s "$S/r" "$S/test-automate-helpers.sh" && mv "$S/r" "$S/test-automate-helpers.sh"' \
  "$L3_WANT"
lm "unknown-part" m4 "$MSG_UNKNOWN" ':' "$L4_WANT" 99-nosuch

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
