#!/usr/bin/env bash
# test-build-capabilities.sh — self-tests for build-capabilities.sh, the generator of
# loomwright/capabilities.json (the published capability contract, docs/CAPABILITIES_CONTRACT.md).
#
# Static only: reads the real plugin tree, writes into a mktemp dir, no network, no gh.
#   (D)   determinism: two runs are byte-identical; a fixture copy (different --root) gives the same bytes
#   (C)   the committed capabilities.json is current (--check exits 0 on the real tree)
#   (S)   top-level schema: types + plugin_version == plugin.json .version + host_switch null
#   (N)   one entry per source (agents/*.md, commands/*.md, skills/*/SKILL.md, hooks.json leaves), no
#         duplicate names — expected counts derived from the source dirs NOW, never hard-coded
#   (A)   agents: runtime_agent_type derived + matches the probe fixture; tools = tools - disallowedTools;
#         model verbatim; result_block / result_blocks pins
#   (R)   result_schemas: version pins, a decorated heading's normalised name, exclusions, null versions
#   (H)   hooks: blocking only on the guard leaves; StopFailure writes pinned; no /dev/null or &N target;
#         the four audited scripts non-empty; unknown only where audited unknown
#   (U)   a hook script with no audit entry => writes ["unknown"]
#   (P)   fail-CLOSED hook parser: every script-path spelling, write construct (&>, >|, tee, cp, sed -i,
#         bash -c, rm) and unmodelled command => ["unknown"] or the literal target, never a silent [];
#         blocking is decided by a TRAILING `|| true` only
#   (F)   fail-CLOSED agent / schema parsing: absent tools => null (inherits all), an unparseable tools
#         key, an unindexed *_RESULT emission, or a schema_version in an unparsed form => exit 1
#   (X)   fail-CLOSED: the index naming a different current schema_version than the split file => exit 1
#   (M)   mutation control: delete an agent in a fixture copy => mutant VALID (non-empty, differs) and
#         --check exits 1 with exactly ONE line telling the developer what to run
#   (Z)   usage: an unknown argument => exit 2
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
SUT="$HERE/build-capabilities.sh"
COMMITTED="$PLUGIN/capabilities.json"
[ -f "$SUT" ] || { echo "test-build-capabilities: $SUT not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-build-capabilities: jq required" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-build-capabilities.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }
# q JQ [jq-options...] — evaluate a jq expression against the freshly generated contract.
q() { local e="$1"; shift; jq -r "$@" "$e" "$tmp/a.json"; }

# fixture_copy DIR — the sources the generator reads, copied out of the real plugin tree.
fixture_copy() {
  mkdir -p "$1/docs" "$1/scripts"
  cp -R "$PLUGIN/.claude-plugin" "$PLUGIN/agents" "$PLUGIN/commands" "$PLUGIN/skills" "$PLUGIN/hooks" "$1/"
  cp "$PLUGIN/docs/RESULT_SCHEMAS.md" "$1/docs/"
  cp -R "$PLUGIN/docs/result-schemas" "$1/docs/"
  cp "$COMMITTED" "$1/capabilities.json"
}

# (D)
bash "$SUT" --out "$tmp/a.json"; rc1=$?
bash "$SUT" --out "$tmp/b.json"; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -s "$tmp/a.json" ] && cmp -s "$tmp/a.json" "$tmp/b.json"; then
  ok "(D) two runs on an unchanged tree are byte-identical"
else no "(D) rc=$rc1/$rc2 or outputs differ"; fi
fixture_copy "$tmp/fx"
bash "$SUT" --root "$tmp/fx" --out "$tmp/fx.json"
if cmp -s "$tmp/a.json" "$tmp/fx.json"; then ok "(D) a fixture copy at another --root yields the same bytes (no root-dependent value)"
else no "(D) output depends on --root"; fi
if grep -qF "$PLUGIN" "$tmp/a.json" || grep -qF "$tmp" "$tmp/fx.json"; then no "(D) an absolute path leaked into the output"
else ok "(D) no absolute path in the output"; fi

# (C)
if bash "$SUT" --check 2>"$tmp/c.err"; then ok "(C) committed capabilities.json is current (--check exits 0)"
else no "(C) committed capabilities.json is stale: $(cat "$tmp/c.err")"; fi

# (S)
want_version="$(jq -r .version "$PLUGIN/.claude-plugin/plugin.json")"
if jq -e --arg v "$want_version" '
    (.contract_schema_version | type == "number" and . == floor)
    and .plugin_version == $v and (.plugin_version | type == "string")
    and .host_switch == null
    and ([.agents, .commands, .skills, .result_schemas, .hooks] | all(type == "array"))
    and (.agents | all((.name|type=="string") and (.runtime_agent_type|type=="string")
         and (.model == null or (.model|type=="string")) and (.tools|type=="array")
         and (.result_block == null or (.result_block|type=="string")) and (.result_blocks|type=="array")))
    and (.commands | all((.name|type=="string") and (.description == null or (.description|type=="string"))))
    and (.skills | all(.name|type=="string"))
    and (.result_schemas | all((.name|type=="string") and (.schema_version == null or (.schema_version|type=="number"))))
    and (.hooks | all((.event|type=="string") and (.matcher == null or (.matcher|type=="string"))
         and (.script == null or (.script|type=="string")) and (.scripts|type=="array")
         and (.blocking|type=="boolean") and (.writes|type=="array")))' "$tmp/a.json" >/dev/null; then
  ok "(S) top-level fields and per-entry field types match the documented schema; plugin_version == plugin.json"
else no "(S) schema/type check failed"; fi

# (N) — expected counts derived from the source tree at test time.
n_agents="$(ls "$PLUGIN"/agents/*.md | wc -l | tr -d ' ')"
n_commands="$(ls "$PLUGIN"/commands/*.md | wc -l | tr -d ' ')"
n_skills="$(ls "$PLUGIN"/skills/*/SKILL.md | wc -l | tr -d ' ')"
n_leaves="$(jq '[.hooks[][] | .hooks[]] | length' "$PLUGIN/hooks/hooks.json")"
for pair in "agents:$n_agents" "commands:$n_commands" "skills:$n_skills" "hooks:$n_leaves"; do
  k="${pair%%:*}"; want="${pair#*:}"
  got="$(q ".$k | length")"
  if [ "$want" -gt 0 ] && [ "$got" = "$want" ]; then ok "(N) $k[]: one entry per source ($got)"
  else no "(N) $k[]: got $got entries, sources say $want"; fi
done
for k in agents commands skills result_schemas; do
  d="$(q "[.$k[].name] | (length - (unique | length))")"
  if [ "$d" = 0 ]; then ok "(N) $k[]: no duplicate names"; else no "(N) $k[]: $d duplicate name(s)"; fi
done
want_stems="$(cd "$PLUGIN/commands" && ls *.md | sed 's/\.md$//' | env LC_ALL=C sort)"
if [ "$(q '.commands[].name' | env LC_ALL=C sort)" = "$want_stems" ]; then ok "(N) commands[] names are exactly the command file stems"
else no "(N) commands[] names differ from the command file stems"; fi

# (A)
plugin_name="$(jq -r .name "$PLUGIN/.claude-plugin/plugin.json")"
if [ "$(q '[.agents[] | select(.runtime_agent_type != ($p + ":" + .name))] | length' --arg p "$plugin_name")" = 0 ]; then
  ok "(A) every runtime_agent_type is <plugin.json name>:<frontmatter name>"
else no "(A) runtime_agent_type is not derived as <plugin name>:<frontmatter name>"; fi
observed="$(jq -r .agent_type_observed "$PLUGIN/scripts/fixtures/subagentstop-decision-shape-probe.json")"
if [ -n "$observed" ] && [ "$(q '.agents[] | select(.name == "loomwright:worker") | .runtime_agent_type')" = "$observed" ]; then
  ok "(A) worker runtime_agent_type equals the probe fixture's agent_type_observed ($observed)"
else no "(A) worker runtime_agent_type != probe fixture '$observed'"; fi
# plan-reviewer's disallowedTools names NotebookEdit, which its tools list does not carry.
if [ "$(q '.agents[] | select(.name == "loomwright:plan-reviewer") | .tools | join(",")')" = "Glob,Grep,Read" ]; then
  ok "(A) tools = tools - disallowedTools (a disallowed name absent from tools is ignored)"
else no "(A) plan-reviewer tools = $(q '.agents[] | select(.name == "loomwright:plan-reviewer") | .tools | join(",")')"; fi
if [ "$(q '.agents[] | select(.name == "loomwright:context-keeper") | .model')" = haiku ] \
   && [ "$(q '.agents[] | select(.name == "loomwright:worker") | .model')" = inherit ]; then
  ok "(A) model is the frontmatter value verbatim"
else no "(A) model not verbatim"; fi
for pin in worker:WORKER_RESULT code-reviewer:CODE_REVIEW_RESULT plan-reviewer:PLAN_REVIEW_RESULT \
           launch-pad-runner:LAUNCH_PAD_RESULT supervisor-runner:SUPERVISOR_RESULT \
           execute-manager:EXECUTE_RESULT qa-executor:QA_RESULT; do
  a="loomwright:${pin%%:*}"; want="${pin#*:}"
  got="$(q '.agents[] | select(.name == $a) | .result_block' --arg a "$a")"
  if [ "$got" = "$want" ]; then ok "(A) $a result_block = $want"; else no "(A) $a result_block = $got, want $want"; fi
done
if [ "$(q '.agents[] | select(.name == "loomwright:qa-executor") | .result_blocks | join(",")')" = "QA_RESULT,VERIFY_RESULT" ] \
   && [ "$(q '.agents[] | select(.name == "loomwright:execute-manager") | .result_blocks | join(",")')" = "EXECUTE_CHECKPOINT,EXECUTE_RESULT" ]; then
  ok "(A) multi-block agents list every emitted block in result_blocks[]"
else no "(A) result_blocks for qa-executor / execute-manager wrong"; fi
if [ "$(q '[.agents[] | select((.result_blocks | length) == 0 and .result_block != null)] | length')" = 0 ]; then
  ok "(A) no result_block without a result_blocks[] entry"
else no "(A) result_block set with empty result_blocks[]"; fi

# (R)
for pin in WORKER_RESULT:2 CODE_REVIEW_RESULT:3 REVIEW_HEAL_RESULT:2 LAUNCH_PAD_RESULT:1 session_end:null EVAL_RESULT:1 PRODUCT_CONTEXT:null; do
  n="${pin%%:*}"; want="${pin#*:}"
  got="$(jq -r --arg n "$n" '[.result_schemas[] | select(.name == $n)] | if length == 1 then (.[0].schema_version | tostring) else "absent" end' "$tmp/a.json")"
  if [ "$got" = "$want" ]; then ok "(R) $n schema_version = $want"; else no "(R) $n schema_version = $got, want $want"; fi
done
bad="$(jq -r '[.result_schemas[].name | select(test("^(Schema|Validation|Cited)( |_)?") or test(" "))] | join(",")' "$tmp/a.json")"
if [ -z "$bad" ]; then ok "(R) Schema Versioning / Validation Location / Cited sub-section anchors are not schemas"
else no "(R) non-schema heading(s) listed: $bad"; fi

# (H)
blk="$(q '[.hooks[] | select(.blocking) | .script] | unique | join(",")')"
nblk="$(q '[.hooks[] | select(.blocking)] | length')"
want_nblk="$(jq '[.hooks[][] | .hooks[] | select(.type == "command" and (.command | test("\\|\\|[ \\t]*true[ \\t]*$") | not))] | length' "$PLUGIN/hooks/hooks.json")"
if [ "$blk" = "scripts/guard-test-integrity.sh" ] && [ "$nblk" = "$want_nblk" ] && [ "$nblk" -gt 0 ]; then
  ok "(H) blocking only on command leaves without || true (the guard-test-integrity leaves, $nblk)"
else no "(H) blocking=[$blk] n=$nblk want=$want_nblk"; fi
el_writes="$(q '[.hooks[] | select(.scripts == ["scripts/emit-lifecycle.sh"] and .event == "PostToolUse")][0].writes')"
sf_want="$(jq -c --argjson el "$el_writes" -n '($el + [".supervisor/logs/failures.log"]) | unique')"
sf_got="$(q '[.hooks[] | select(.event == "StopFailure")] | if length == 1 then .[0].writes else "count" end' | jq -c .)"
if [ "$sf_got" = "$sf_want" ] && [ "$(jq 'length' <<<"$el_writes")" -gt 0 ]; then
  ok "(H) StopFailure writes = .supervisor/logs/failures.log ∪ emit-lifecycle.sh's audited writes"
else no "(H) StopFailure writes=$sf_got want=$sf_want"; fi
if [ "$(q '[.hooks[].writes[] | select(test("/dev/null") or startswith("&"))] | length')" = 0 ]; then
  ok "(H) no hooks[] entry lists /dev/null or an &N target"
else no "(H) a /dev/null or fd target leaked into writes[]"; fi
for s in set-otel-resource-attrs.sh emit-lifecycle.sh emit-token-ledger.sh stamp-requirement-status.sh; do
  r="$(jq -r --arg s "scripts/$s" '[.hooks[] | select(.scripts | index($s))] | if length == 0 then "absent" else (map(.writes | (length > 0 and (index("unknown") | not))) | all | tostring) end' "$tmp/a.json")"
  if [ "$r" = true ]; then ok "(H) every leaf running $s has a non-empty, audited writes[]"
  else no "(H) $s: $r"; fi
done
unk="$(q '[.hooks[] | select(.writes == ["unknown"]) | .scripts[]] | unique | join(",")')"
if [ "$unk" = "scripts/hook-dispatch-on-pr-create.sh" ]; then
  ok "(H) every hook script has an audit entry (the only unknown is the audited-unknown detached dispatcher)"
else no "(H) unknown writes on: $unk"; fi
if [ "$(q '[.hooks[] | select(.type == "prompt") | select(.script != null or .scripts != [] or .writes != [])] | length')" = 0 ]; then
  ok "(H) a prompt leaf has script null, scripts [], writes []"
else no "(H) prompt leaf shape wrong"; fi

# (U) — an unaudited script.
fixture_copy "$tmp/fu"
jq '.hooks.SessionStart += [{"hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/never-audited.sh\" || true"}]}]' \
  "$PLUGIN/hooks/hooks.json" > "$tmp/fu/hooks/hooks.json"
bash "$SUT" --root "$tmp/fu" --out "$tmp/fu.json"
if [ "$(jq -c '[.hooks[] | select(.script == "scripts/never-audited.sh") | .writes]' "$tmp/fu.json")" = '[["unknown"]]' ]; then
  ok "(U) a script with no audit entry gets writes [\"unknown\"], never a silent []"
else no "(U) unaudited script writes = $(jq -c '[.hooks[] | select(.script == "scripts/never-audited.sh") | .writes]' "$tmp/fu.json")"; fi

# (P) — the hook parser fails closed. One single-leaf hooks.json per case, built inside $tmp only.
fixture_copy "$tmp/fp"
# leaf CMD -> the generated entry as [script, writes, blocking] (or "rc=N" when the generator failed)
# Commands spell the install-root variable as @R@; leaf() substitutes the real name (named once here).
leaf() {
  local c="${1//@R@/CLAUDE_PLUGIN_ROOT}"
  jq --arg c "$c" '.hooks = {"SessionStart": [{"hooks": [{"type": "command", "command": $c}]}]}' \
    "$PLUGIN/hooks/hooks.json" > "$tmp/fp/hooks/hooks.json"
  bash "$SUT" --root "$tmp/fp" --out "$tmp/fp.json" 2>/dev/null || { echo "rc=$?"; return; }
  jq -c '.hooks[0] | [.script, .writes, .blocking]' "$tmp/fp.json"
}
pcase() { # pcase <label> <command> <expected [script, writes, blocking]>
  local got; got="$(leaf "$2")"
  if [ "$got" = "$3" ]; then ok "(P) $1"; else no "(P) $1: got $got want $3"; fi
}
pcase 'quoted-root spelling "${ROOT}"/scripts/x of an unaudited script => unknown' \
  'bash "${@R@}"/scripts/never-audited.sh || true' '["scripts/never-audited.sh",["unknown"],false]'
pcase 'brace-less $ROOT/scripts/x spelling of an unaudited script => unknown' \
  'bash "$@R@/scripts/never-audited.sh" || true' '["scripts/never-audited.sh",["unknown"],false]'
pcase 'quoted-root spelling of an AUDITED script resolves to its audit entry (not unknown)' \
  'bash "${@R@}"/scripts/stamp-requirement-status.sh || true' '["scripts/stamp-requirement-status.sh",[".supervisor/requirements/<requirement>.md"],false]'
pcase 'a root mention that is not a parsed script path => unknown' \
  'bash "${@R@}/scripts/send-webhook.sh" || true; cd "${@R@}" || true' '["scripts/send-webhook.sh",["unknown"],false]'
pcase '&> <literal> is a write of that path (never [])' \
  'echo x &> .supervisor/logs/x.log || true' '[null,[".supervisor/logs/x.log"],false]'
pcase '>| <literal> is a write of that path (never [])' \
  'echo x >| .supervisor/logs/y.log || true' '[null,[".supervisor/logs/y.log"],false]'
pcase 'tee => unknown' 'echo x | tee -a .supervisor/logs/x.log || true' '[null,["unknown"],false]'
pcase 'cp => unknown' 'cp a .supervisor/b || true' '[null,["unknown"],false]'
pcase 'sed -i => unknown' 'sed -i s/a/b/ f || true' '[null,["unknown"],false]'
pcase 'bash -c <inline code> => unknown' 'bash -c "echo hi > z" || true' '[null,["unknown"],false]'
pcase 'rm after an audited script => unknown (unknown wins)' \
  'bash "${@R@}/scripts/send-webhook.sh" || true; rm -f x || true' '["scripts/send-webhook.sh",["unknown"],false]'
pcase 'a redirect to a non-literal target => unknown' 'echo x > "$F" || true' '[null,["unknown"],false]'
pcase 'a <> read-write open => unknown' 'exec 3<>f || true' '[null,["unknown"],false]'
pcase 'fd duplication and /dev/null stay non-writes (control: the parser is not unknown-on-everything)' \
  'X=1 bash "${@R@}/scripts/send-webhook.sh" >/dev/null 2>&1 || true' '["scripts/send-webhook.sh",[],false]'
pcase 'a non-trailing `|| true` does not make the leaf fail-safe (blocking)' \
  'bash "${@R@}/scripts/send-webhook.sh" || true; bash "${@R@}/scripts/guard-test-integrity.sh"' '["scripts/send-webhook.sh",[],true]'

# (F) — agent / schema parsing fails closed, or publishes null — never a silent empty answer.
fixture_copy "$tmp/ff"
awk '!/^tools:/' "$PLUGIN/agents/worker.md" > "$tmp/ff/agents/worker.md"
bash "$SUT" --root "$tmp/ff" --out "$tmp/ff.json"
if ! grep -q '^tools:' "$tmp/ff/agents/worker.md" \
   && [ "$(jq -c '.agents[] | select(.name == "loomwright:worker") | .tools' "$tmp/ff.json")" = null ]; then
  ok "(F) an agent with no tools key publishes tools: null (inherits every tool), never []"
else no "(F) tools-absent agent: $(jq -c '.agents[] | select(.name == "loomwright:worker") | .tools' "$tmp/ff.json")"; fi
fcase() { # fcase <label> <stderr substring> — the current $tmp/ff fixture must make the generator exit 1
  bash "$SUT" --root "$tmp/ff" --out "$tmp/ff.json" 2>"$tmp/ff.err"; local rc=$?
  if [ "$rc" -eq 1 ] && grep -qF "$2" "$tmp/ff.err"; then ok "(F) $1"; else no "(F) $1: rc=$rc err=$(cat "$tmp/ff.err")"; fi
}
awk '!/^tools:/ { print; next } { print "tools:"; print "  - Read"; print "  - Bash" }' "$PLUGIN/agents/worker.md" > "$tmp/ff/agents/worker.md"
fcase "a tools key in block-list form (unparsed) exits 1 instead of publishing []" "has a 'tools:' key the generator cannot parse"
cp "$PLUGIN/agents/worker.md" "$tmp/ff/agents/worker.md"
printf '\nNEVER_INDEXED_RESULT:\n' >> "$tmp/ff/agents/worker.md"
fcase "an emitted *_RESULT block the index does not know exits 1 instead of being dropped" "NEVER_INDEXED_RESULT"
cp "$PLUGIN/agents/worker.md" "$tmp/ff/agents/worker.md"
# product-context.md is indexed and records no schema_version (pinned null in (R) above).
sf="product-context.md"
if [ -f "$tmp/ff/docs/result-schemas/$sf" ] && ! grep -q 'schema_version' "$tmp/ff/docs/result-schemas/$sf"; then
  printf '\nschema_version = 4\n' >> "$tmp/ff/docs/result-schemas/$sf"
  fcase "a schema_version in an unparsed form exits 1 instead of publishing null" "does not parse"
else no "(F) $sf missing or already records schema_version — the control would prove nothing"; fi

# (X) — fail-CLOSED index cross-check.
fixture_copy "$tmp/fx2"
sed 's/WORKER_RESULT at `schema_version: 2`/WORKER_RESULT at `schema_version: 3`/' "$PLUGIN/docs/RESULT_SCHEMAS.md" > "$tmp/fx2/docs/RESULT_SCHEMAS.md"
if cmp -s "$PLUGIN/docs/RESULT_SCHEMAS.md" "$tmp/fx2/docs/RESULT_SCHEMAS.md"; then no "(X) mutant invalid: the sed changed nothing"
else
  bash "$SUT" --root "$tmp/fx2" --out "$tmp/fx2.json" 2>"$tmp/x.err"; rc=$?
  if [ "$rc" -eq 1 ] && grep -q WORKER_RESULT "$tmp/x.err"; then ok "(X) index/split-file version disagreement fails closed, naming the schema"
  else no "(X) rc=$rc err=$(cat "$tmp/x.err")"; fi
fi

# (M) — mutation control for the staleness gate.
fixture_copy "$tmp/fm"
if bash "$SUT" --root "$tmp/fm" --check 2>/dev/null; then ok "(M) baseline: an unmutated fixture copy passes --check"
else no "(M) baseline fixture already fails --check — the control would prove nothing"; fi
rm -f "$tmp/fm/agents/worker.md"
bash "$SUT" --root "$tmp/fm" --out "$tmp/mutant.json"
if [ -s "$tmp/mutant.json" ] && ! cmp -s "$tmp/mutant.json" "$COMMITTED" \
   && [ "$(jq '.agents | length' "$tmp/mutant.json")" = "$((n_agents - 1))" ]; then
  ok "(M) mutant is VALID: non-empty, differs from the committed contract, one agent fewer"
  bash "$SUT" --root "$tmp/fm" --check 2>"$tmp/m.err" >/dev/null; rc=$?
  lines="$(wc -l < "$tmp/m.err" | tr -d ' ')"
  if [ "$rc" -ne 0 ] && [ "$lines" = 1 ] && grep -qF 'run: bash loomwright/scripts/build-capabilities.sh and commit' "$tmp/m.err"; then
    ok "(M) deleting an agent makes --check exit non-zero with ONE line naming the fix"
  else no "(M) rc=$rc lines=$lines err=$(cat "$tmp/m.err")"; fi
else no "(M) mutant invalid — the staleness assertion would not be trustworthy"; fi

# (Z)
bash "$SUT" --bogus >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "(Z) unknown argument: exit 2"; else no "(Z) rc=$rc"; fi

echo
echo "test-build-capabilities: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
