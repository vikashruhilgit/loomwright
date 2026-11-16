#!/usr/bin/env bash
# run-helpers.sh — SOURCED (never run) by the tests that build frozen run folders by hand
# (test-run.sh, test-replay.sh). Not named test-*, so selvedge/tests/run.sh never runs it.
#
# The caller defines ok / ko / finish and sets TMP (its temp dir, with $TMP/o for logs), APP
# (tests/fixtures/app-server.mjs), CLI (bin/selvedge) and SELVEDGE_LIB (exported).
#
#   rh_start_app               starts the fixture app ($APP serve $TMP/servers.json) in the
#                              background, sets SRV_PID (the caller's cleanup trap kills it) and
#                              exports AURL; reports through the caller's ok / ko / finish (a server
#                              that does not start ends the test file)
#   rh_setup                   writes $TMP/gen.mjs (the plan generator below) and the recording
#                              planner shims: $TMP/planner-shim.sh and $TMP/stubbin/claude append
#                              their arguments to $PLANNER_CALLS / $CLAUDE_CALLS (exported here) and
#                              exit 1, so a run that never calls a model leaves both files absent
#   newrepo <dir>              a temp git repo whose selvedge.json allows only $AURL
#   folder <label> <repo> <spec JSON>
#                              a frozen run folder for the spec; prints its path ("" on failure)
#   STUB_C, stub_spec <n>…     a spec of criteria the stub page passes (every read is
#                              $STUB_PW_TEXT, "stub" by default); $SPEC_EXTRA is appended to the
#                              spec object
#
# The plan generator: node gen.mjs <criteria.json> <spec.json> <run-dir> writes <run-dir>/plan.json
# for spec.criteria[i] = {text, polarity?, assumptions?, steps} or {text, not_planned: {reason, …}}
# (every "$O" in a string becomes the fixture origin; spec.origins overrides the plan's origins),
# and, before the freeze, snapshots.jsonl (spec.plan_time_actions) and planner-usage.json
# (spec.usage).

rh_start_app() {
  local i=0 port
  node "$APP" serve "$TMP/servers.json" >"$TMP/servers.log" 2>&1 &
  SRV_PID=$!
  while [ ! -s "$TMP/servers.json" ] && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
  port="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).app.port))' "$TMP/servers.json" 2>/dev/null)"
  [ -n "$port" ] && ok "setup: fixture app on localhost:$port" || { ko "setup: app-server.mjs did not start: $(cat "$TMP/servers.log")"; finish; }
  export AURL="http://localhost:$port"
}

rh_setup() {
  export PLANNER_CALLS="$TMP/planner-calls.log" CLAUDE_CALLS="$TMP/claude-calls.log"
  printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "$PLANNER_CALLS" > "$TMP/planner-shim.sh"
  mkdir -p "$TMP/stubbin"
  printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "$CLAUDE_CALLS" > "$TMP/stubbin/claude"
  chmod +x "$TMP/stubbin/claude"
  cat > "$TMP/gen.mjs" <<'EOF'
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const { criteriaSha256 } = await import(pathToFileURL(path.join(process.env.SELVEDGE_LIB, 'criteria.mjs')).href);
const [critFile, specFile, dir] = process.argv.slice(2);
const crit = JSON.parse(readFileSync(critFile, 'utf8'));
const spec = JSON.parse(readFileSync(specFile, 'utf8'), (k, v) => (typeof v === 'string' ? v.split('$O').join(process.env.AURL) : v));
const plan = { schema_version: 1, target: 'web', criteria_sha256: criteriaSha256(crit.criteria), origins: spec.origins || [process.env.AURL], steps_by_criterion: {} };
spec.criteria.forEach((c, i) => {
  if (c.not_planned) {
    (plan.not_planned = plan.not_planned || []).push({ id: crit.criteria[i].id, ...c.not_planned });
    return;
  }
  plan.steps_by_criterion[crit.criteria[i].id] = {
    interpretation: `The page shows what criterion ${i + 1} names.`,
    polarity: c.polarity || 'positive',
    unverified_assumptions: c.assumptions || [],
    steps: c.steps,
  };
});
writeFileSync(path.join(dir, 'plan.json'), `${JSON.stringify(plan, null, 2)}\n`);
if (spec.plan_time_actions) writeFileSync(path.join(dir, 'snapshots.jsonl'), `${JSON.stringify({ plan_time_actions: spec.plan_time_actions })}\n`);
if (spec.usage) writeFileSync(path.join(dir, 'planner-usage.json'), `${JSON.stringify(spec.usage)}\n`);
EOF
}

newrepo() { mkdir -p "$1" && git -C "$1" init -q && printf '{"schema_version":1,"origins":["%s"]}\n' "$AURL" > "$1/selvedge.json"; }

folder() {
  local label="$1" repo="$2" dir
  printf '%s\n' "$3" > "$TMP/spec-$label.json"
  node -e 'for (const c of JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).criteria) console.log("- " + c.text)' "$TMP/spec-$label.json" \
    | (cd "$repo" && bash "$CLI" criteria from-text) > "$TMP/crit-$label.json" 2>"$TMP/o/crit-$label.err"
  dir="$(cd "$repo" && bash "$CLI" plan --init "$TMP/crit-$label.json" 2>"$TMP/o/init-$label.err")"
  [ -d "$dir" ] && node "$TMP/gen.mjs" "$TMP/crit-$label.json" "$TMP/spec-$label.json" "$dir" \
    && (cd "$repo" && bash "$CLI" plan --freeze "$dir" >/dev/null 2>"$TMP/o/freeze-$label.err") \
    && printf '%s' "$dir"
}

# shellcheck disable=SC2034  # used by the sourcing test
STUB_C='{"text":"TEXT reads \"stub\"","steps":[{"type":"goto","url":"$O/"},{"type":"read","property":"text","locator":{"testid":"x"}},{"type":"expect","op":"equals","value":"stub"}]}'
stub_spec() { local out="" n; for n in "$@"; do out="$out${out:+,}${STUB_C/TEXT/Criterion $n}"; done; printf '{"criteria":[%s]%s}' "$out" "${SPEC_EXTRA:-}"; }
