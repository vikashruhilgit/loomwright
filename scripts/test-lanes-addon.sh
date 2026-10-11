#!/usr/bin/env bash
# test-lanes-addon.sh — the static and engine checks of the optional loomwright-lanes pane
# (parallel-automate/14, decision P9). The add-on may reach Loomwright ONLY through the three core lane
# commands; it must never read a lane's files, launch or resume a lane itself, or be needed by the core.
#
#   1. one door        — exactly two `$.process.run(` calls: `lane()`'s `['bash', s, sub, ...args]`
#                        and `locate()`'s literal `['claude', 'plugin', 'list', '--json']`
#   2. three commands  — the `LaneCommand` union is exactly lane-status | lane-feed | lane-answer, and
#                        every `lane(...)` call names one of them — read from the module flattened to
#                        one line, so a call wrapped across lines (lane-answer's) is seen too; exactly
#                        four call sites, lane-answer among them, and the one beyond the three reads
#                        exactly `'lane-status', ['--keep-awake']` (the owner's Keep-awake button: it
#                        starts the caffeinate lane-status already offers, never a lane)
#   3. no lane files   — no `$.fs`, no `$.process.spawn`, no `bash -c`, no `.supervisor` / inbox /
#                        stream-log path anywhere in the module
#   4. answers say so  — lane-answer is called with `--via lanes-addon`
#   5. P9, statically  — nothing under loomwright/ names the add-on; the marketplace lists it as its
#                        own sibling (`./loomwright-lanes`), never inside loomwright/
#   6. mutation        — a copy of the module that reads a lane's run file, calls lane-launch, or
#                        swaps the multi-line lane-answer call's command for another subcommand, is
#                        refused by checks 1–3 (the checks can fail)
#   7. engine          — `claude plugin validate` and `claude plugin test` on the plugin, where `claude`
#                        is on PATH; otherwise SKIP with the reason (never a silent pass)
#
# The dynamic P9 half — the lane round trip with no add-on loaded — is loomwright/scripts/
# test-automate-lanes.sh, which loads no plugin at all.
# Portability: bash 3.2 safe (macOS) + Linux CI.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="$ROOT/loomwright-lanes"
MOD="$ADDON/hooks/register.tsx"
pass=0; fail=0; skip=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# module_violations <file> — prints one line per broken rule of checks 1–3; nothing when clean.
module_violations() {
  local f="$1" n bad flat subs
  n="$(grep -c '\$\.process\.run(' "$f")"
  [ "$n" = 2 ] || echo "process.run calls: $n (want exactly 2: lane() and locate())"
  grep -q "\$\.process\.run(\['bash', s, sub, \.\.\.args\]" "$f" || echo "lane()'s argv is not ['bash', s, sub, ...args]"
  grep -q "\$\.process\.run(\['claude', 'plugin', 'list', '--json'\]" "$f" || echo "locate()'s argv is not the literal claude plugin list --json"
  grep -q "^type LaneCommand = 'lane-status' | 'lane-feed' | 'lane-answer'$" "$f" || echo "LaneCommand is not exactly lane-status | lane-feed | lane-answer"
  # Flatten first: a call wrapped one argument per line (lane-answer's, in send()) is invisible to a
  # line-at-a-time grep. All whitespace becomes one space, so a call site reads `lane( $, configured, '…'`.
  flat="$(tr '\n\t\r' '   ' < "$f" | tr -s ' ')"
  subs="$(grep -oE "lane\\( ?\\\$, ?configured, ?'[^']*'" <<<"$flat" | sed "s/.*'\([^']*\)'$/\1/")"
  bad="$(grep -vxE 'lane-status|lane-feed|lane-answer' <<<"$subs")"
  [ -z "$bad" ] || echo "lane() called with: $(printf '%s' "$bad" | tr '\n' ' ')"
  [ -n "$subs" ] || echo "no lane() call sites found"
  n="$(grep -c . <<<"$subs")"
  [ "$n" = 4 ] || echo "lane() call sites: $n (want exactly 4: lane-feed, lane-status --json, lane-status --keep-awake, lane-answer)"
  # The second lane-status site may carry only --keep-awake: any other flag set is a new capability.
  n="$(grep -oE "lane\\( ?\\\$, ?configured, ?'lane-status', ?\\[[^]]*\\]" <<<"$flat" | sed "s/.*\\[\\(.*\\)\\]$/\\1/" | sort | tr '\n' '|')"
  [ "$n" = "'--json'|'--keep-awake'|" ] || echo "lane-status call sites carry: $n (want exactly ['--json'] and ['--keep-awake'])"
  grep -qx 'lane-answer' <<<"$subs" || echo "no lane() call site names lane-answer"
  grep -nE '\$\.fs\b|\$\.process\.spawn|'"'"'-c'"'"'|\.supervisor|/inbox/|stream\.log|lane-launch|lane-remove' "$f" | sed 's/^/forbidden: /'
}

echo "1-3. the module reaches Loomwright only through the three lane commands"
if [ ! -f "$MOD" ]; then no "module missing: $MOD"; else
  v="$(module_violations "$MOD")"
  if [ -z "$v" ]; then ok "register.tsx: one door, three commands, no lane files"; else no "register.tsx:"; printf '%s\n' "$v" | sed 's/^/        /'; fi
fi

echo "4. answers are marked as the add-on's"
grep -q "const VIA = 'lanes-addon'" "$MOD" && grep -q "'--via', VIA" "$MOD" \
  && ok "lane-answer gets --via lanes-addon" || no "lane-answer is not called with --via lanes-addon"

echo "5. P9: the core never depends on the add-on"
hits="$(grep -rln 'loomwright-lanes' "$ROOT/loomwright" 2>/dev/null)"
[ -z "$hits" ] && ok "nothing under loomwright/ names loomwright-lanes" || no "loomwright/ names the add-on: $hits"
src="$(jq -r '.plugins[] | select(.name == "loomwright-lanes") | .source' "$ROOT/.claude-plugin/marketplace.json" 2>/dev/null)"
[ "$src" = "./loomwright-lanes" ] && ok "marketplace lists loomwright-lanes as its own sibling" || no "marketplace source for loomwright-lanes is '${src:-absent}'"
[ "$(jq -r .name "$ADDON/.claude-plugin/plugin.json" 2>/dev/null)" = loomwright-lanes ] && ok "plugin.json names loomwright-lanes" || no "plugin.json name is not loomwright-lanes"

echo "6. mutation control: the checks can fail"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed "s|const r = await lane(\$, configured, 'lane-status', \['--json'\])|const r = await lane(\$, configured, 'lane-status', ['--json']); await \$.fs.readFile('/w/L1/.supervisor/automate/r.md')|" "$MOD" > "$T/a.tsx"
grep -q '\$\.fs\.readFile' "$T/a.tsx" && [ -n "$(module_violations "$T/a.tsx")" ] \
  && ok "a module reading a lane's run file is refused" || no "a module reading a lane's run file was NOT refused"
sed "s|lane(\$, configured, 'lane-feed', \[l.path\])|lane(\$, configured, 'lane-launch' as LaneCommand, [l.path])|" "$MOD" > "$T/b.tsx"
grep -q "'lane-launch'" "$T/b.tsx" && [ -n "$(module_violations "$T/b.tsx")" ] \
  && ok "a module calling lane-launch is refused" || no "a module calling lane-launch was NOT refused"
sed "s|lane(\$, configured, 'lane-status', \['--keep-awake'\])|lane(\$, configured, 'lane-status', ['--keep-awake', '--refresh-readiness'])|" "$MOD" > "$T/e.tsx"
grep -q "'--refresh-readiness'" "$T/e.tsx" && [ -n "$(module_violations "$T/e.tsx")" ] \
  && ok "a module whose keep-awake call grows another lane-status flag is refused" \
  || no "a module whose keep-awake call grows another lane-status flag was NOT refused"
sed "s|\$\.process\.run(\['claude', 'plugin', 'list', '--json'\]|\$.process.run(['bash', '-c', 'cat x']|" "$MOD" > "$T/c.tsx"
[ -n "$(module_violations "$T/c.tsx")" ] && ok "a module with a shell probe is refused" || no "a module with a shell probe was NOT refused"
# lane-answer's call is wrapped one argument per line — the only mutating call, and the one a
# line-at-a-time extraction missed. Swap its literal for another automate-lanes.sh subcommand that the
# forbidden-token grep does not name, so only the flattened lane() extraction's checks can catch it.
sed "s|^\( *\)'lane-answer',$|\1'lane-convert-ready',|" "$MOD" > "$T/d.tsx"
grep -q "'lane-convert-ready'" "$T/d.tsx" && [ -n "$(module_violations "$T/d.tsx")" ] \
  && ok "a module whose multi-line lane-answer call names another command is refused" \
  || no "a module whose multi-line lane-answer call names another command was NOT refused"

echo "7. the engine's own checks"
if command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate "$ADDON" 2>&1)" && grep -q 'Validation passed' <<<"$out"; then ok "claude plugin validate"
  else no "claude plugin validate:"; printf '%s\n' "$out" | tail -15 | sed 's/^/        /'; fi
  if out="$(claude plugin test "$ADDON" 2>&1)" && grep -qE '^ *[1-9][0-9]* pass' <<<"$out" && grep -qE '^ *0 fail' <<<"$out"; then
    ok "claude plugin test ($(printf '%s' "$out" | grep -E '^ *[0-9]+ pass' | tr -d ' '))"
  else no "claude plugin test:"; printf '%s\n' "$out" | tail -20 | sed 's/^/        /'; fi
else
  echo "  SKIP: claude CLI not on PATH — plugin validate/test (the fixture render, answer and refusal tests) not run here"
  skip=$((skip+2))
fi

echo "passed: $pass  failed: $fail  skipped: $skip"
[ "$fail" = 0 ]
