#!/usr/bin/env bash
# test-adapter.sh — pins selvedge's Claude Code adapter and its release description:
#   agents/verifier.md      tools exactly Bash and Read; integer maxTurns and token_budget, the prompt
#                           (bytes / 4) within token_budget; it forbids editing plan.json after
#                           `plan --freeze` and reading ~/.local/state/selvedge/; its `## Workflow`
#                           prescribes the selvedge commands in the fixed order below, and its
#                           snapshot step names the run folder `plan --init` printed (`--run-dir`).
#   skills/verify/SKILL.md  the same `## Workflow` command order as the verifier.
#   commands/verify.md      a PR number / file / pasted text resolves to `criteria from-pr` / `from-md`
#                           / `from-text`; it spawns the verifier by exactly the subagent_type the AC9
#                           evidence file records; it posts only through `selvedge comment … --pr <n>
#                           --yes`, after an "Ask before posting" step.
#   the description         plugin.json's description is <= 600 characters, carries no v<X>.<Y>.<Z>
#                           token, and equals the `selvedge` entry's in .claude-plugin/marketplace.json
#                           (no repository gate checks selvedge's description).
# Every arm turns red under its row of the brief's pin-mutation table.
#
# Static: reads files only (no browser, no model, no network); a fresh temp HOME. Needs node (>= 18);
# a missing node is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_DIR="$(cd "$PLUGIN_DIR/.." && pwd)"
AGENT="$PLUGIN_DIR/agents/verifier.md"
CMD="$PLUGIN_DIR/commands/verify.md"
SKILL="$PLUGIN_DIR/skills/verify/SKILL.md"
EVID="$PLUGIN_DIR/docs/evidence/verify-adapter-equivalence.md"
PJ="$PLUGIN_DIR/.claude-plugin/plugin.json"
MP="$REPO_DIR/.claude-plugin/marketplace.json"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

command -v node >/dev/null 2>&1 || { echo "  FAIL node is not on PATH (test-adapter.sh needs it)"; echo "test-adapter: 0 passed, 1 failed"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-adapter.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

for f in "$AGENT" "$CMD" "$SKILL" "$EVID" "$PJ" "$MP"; do
  [ -f "$f" ] || { echo "  FAIL missing file: $f"; echo "test-adapter: 0 passed, 1 failed"; exit 1; }
done

# fm <key> <file> — the value of <key> in the file's first `--- … ---` block (empty when absent).
fm() {
  awk -v k="$1" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }
  ' "$2"
}

# workflow_cmds <file> — for each numbered item of the `## Workflow` section, the first backticked
# `selvedge <command>[ --init|--validate|--freeze]` on its first line (without "selvedge "), one per line.
workflow_cmds() {
  awk '
    /^## / { inwf = ($0 == "## Workflow"); next }
    inwf && /^[0-9]+\. / {
      if (match($0, /`selvedge [a-z]+( --(init|validate|freeze))?/)) {
        s = substr($0, RSTART + 1, RLENGTH - 1); sub(/^selvedge /, "", s); print s
      } else print "(no selvedge command)"
    }
  ' "$1"
}

echo "-- AC8 the verifier's frontmatter"
tools="$(fm tools "$AGENT")"
norm="$(printf '%s\n' "$tools" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort | tr '\n' ' ')"
[ "$norm" = "Bash Read " ] && ok "tools is exactly Bash and Read ('$tools')" || ko "tools is '$tools', not exactly Bash, Read"

mt="$(fm maxTurns "$AGENT")"
case "$mt" in ''|*[!0-9]*|0*) ko "maxTurns is not a positive integer: '$mt'" ;; *) ok "maxTurns is an integer ($mt)" ;; esac

tb="$(fm token_budget "$AGENT")"
bytes="$(wc -c < "$AGENT" | tr -d '[:space:]')"
measured=$((bytes / 4))
case "$tb" in
  ''|*[!0-9]*|0*) ko "token_budget is not a positive integer: '$tb'" ;;
  *) [ "$measured" -le "$tb" ] && ok "the prompt's measured size ($bytes bytes / 4 = $measured) is within token_budget ($tb)" \
       || ko "the prompt measures $measured tokens (bytes / 4), over token_budget $tb" ;;
esac

[ "$(fm model "$AGENT")" = "inherit" ] && ok "model: inherit" || ko "model is '$(fm model "$AGENT")', not inherit"

echo "-- AC8 the verifier's prohibitions"
grep -qF 'plan --freeze' < <(grep -E '[Nn]ever' "$AGENT" | grep -F 'plan.json') \
  && ok "the body forbids editing plan.json after plan --freeze" || ko "no line forbids editing plan.json after plan --freeze"
grep -qF '~/.local/state/selvedge/' < <(grep -E '[Nn]ever' "$AGENT") \
  && ok "the body forbids reading ~/.local/state/selvedge/" || ko "no line forbids reading ~/.local/state/selvedge/"

echo "-- AC8 the same command order in the verifier and the skill"
want="criteria|plan --init|snapshot|plan --validate|plan --freeze|run|verdict"
got_agent="$(workflow_cmds "$AGENT" | paste -sd '|' -)"
got_skill="$(workflow_cmds "$SKILL" | paste -sd '|' -)"
[ "$got_agent" = "$want" ] && ok "verifier.md's Workflow runs: $want" || ko "verifier.md's Workflow runs '$got_agent', want '$want'"
[ "$got_skill" = "$want" ] && ok "SKILL.md's Workflow runs: $want" || ko "SKILL.md's Workflow runs '$got_skill', want '$want'"
{ [ -n "$got_agent" ] && [ "$got_agent" = "$got_skill" ]; } && ok "the verifier and the skill prescribe the same commands in the same order" \
  || ko "the verifier ('$got_agent') and the skill ('$got_skill') differ"
for f in "$AGENT" "$SKILL"; do
  line="$(awk '/^## /{w=($0=="## Workflow");next} w && /^[0-9]+\. `selvedge snapshot /{print; exit}' "$f")"
  grep -qF -- '--run-dir <run-dir>' <<<"$line" \
    && ok "$(basename "$f"): the snapshot step names the run folder (--run-dir <run-dir>)" || ko "$(basename "$f"): the snapshot step has no --run-dir <run-dir>: '$line'"
done

echo "-- AC8 /selvedge:verify resolves the criteria source"
row_pr="$(grep -E '^\|.*PR number' "$CMD" | head -n 1)"
row_md="$(grep -E '^\|.*[Ff]ile' "$CMD" | head -n 1)"
row_tx="$(grep -E '^\|.*pasted text' "$CMD" | head -n 1)"
grep -qF '`selvedge criteria from-pr <n>`' <<<"$row_pr" && ok "a PR number resolves to selvedge criteria from-pr" || ko "PR number row: '$row_pr'"
grep -qF '`selvedge criteria from-md <file>`' <<<"$row_md" && ok "a file resolves to selvedge criteria from-md" || ko "file row: '$row_md'"
grep -qF '`selvedge criteria from-text`' <<<"$row_tx" && ok "pasted text resolves to selvedge criteria from-text" || ko "pasted text row: '$row_tx'"

echo "-- AC8 /selvedge:verify spawns the verifier by the recorded subagent_type"
recorded="$(sed -n 's/^- subagent_type the session used: `\([^`]*\)`.*$/\1/p' "$EVID" | head -n 1)"
named="$(grep -oE 'subagent_type: "[^"]*"' "$CMD" | sed 's/^subagent_type: "//; s/"$//' | sort -u)"
if [ -z "$recorded" ]; then
  ko "the evidence file records no '- subagent_type the session used: \`…\`' line"
elif [ "$named" = "$recorded" ]; then
  ok "commands/verify.md names exactly the recorded subagent_type ($recorded)"
else
  ko "commands/verify.md names '$named', the evidence file records '$recorded'"
fi

echo "-- AC8 /selvedge:verify posts only through selvedge comment --yes, after asking"
ask_ln="$(grep -n 'Ask before posting' "$CMD" | head -n 1 | cut -d: -f1)"
post_ln="$(grep -n '`selvedge comment' "$CMD" | head -n 1 | cut -d: -f1)"
if [ -n "$ask_ln" ] && [ -n "$post_ln" ] && [ "$ask_ln" -lt "$post_ln" ]; then
  ok "an 'Ask before posting' step (line $ask_ln) comes before the first selvedge comment (line $post_ln)"
else
  ko "no 'Ask before posting' step before selvedge comment (ask line '${ask_ln}', comment line '${post_ln}')"
fi
bad="$(grep -F '`selvedge comment' "$CMD" | grep -vF '`selvedge comment <run_dir> --pr <n> --yes`')"
{ [ -n "$post_ln" ] && [ -z "$bad" ]; } && ok "every \`selvedge comment\` the command runs is 'selvedge comment <run_dir> --pr <n> --yes'" || ko "a selvedge comment without --pr <n> --yes: $bad"
grep -qi 'never by default' "$CMD" && grep -q 'posts nothing' "$CMD" \
  && ok "posting is never on by default; any other answer posts nothing" || ko "the command does not say posting is off by default and that a no posts nothing"

echo "-- AC10 the release description"
desc="$(node -e '
const fs = require("fs");
const [pj, mp] = process.argv.slice(1);
const p = JSON.parse(fs.readFileSync(pj, "utf8"));
const m = JSON.parse(fs.readFileSync(mp, "utf8"));
const e = (m.plugins || []).filter((x) => x && x.name === "selvedge");
const d = typeof p.description === "string" ? p.description : "";
console.log([...d].length, /v[0-9]+\.[0-9]+\.[0-9]+/.test(d) ? 1 : 0, e.length, e.length === 1 && e[0].description === d ? 1 : 0);
' "$PJ" "$MP" 2>&1)"
set -- $desc
len="${1:-x}"; vtok="${2:-x}"; entries="${3:-x}"; same="${4:-x}"
case "$len" in ''|*[!0-9]*) ko "cannot read the descriptions: $desc" ;; *)
  { [ "$len" -gt 0 ] && [ "$len" -le 600 ]; } && ok "plugin.json's description is $len characters (<= 600)" || ko "plugin.json's description is $len characters (want 1..600)"
  [ "$vtok" = 0 ] && ok "the description carries no v<X>.<Y>.<Z> token" || ko "the description carries a v<X>.<Y>.<Z> token"
  { [ "$entries" = 1 ] && [ "$same" = 1 ]; } && ok "marketplace.json's selvedge entry has the same description" \
    || ko "marketplace.json: $entries selvedge entr(y|ies), same description: $same"
;; esac

echo "test-adapter: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
