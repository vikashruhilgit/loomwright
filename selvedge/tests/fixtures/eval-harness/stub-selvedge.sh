#!/usr/bin/env bash
# stub-selvedge.sh — a SELVEDGE_EVAL_SELVEDGE_BIN for test-eval-harness.sh (not named test-*, so
# run.sh never runs it). No browser, no model: it imitates the selvedge commands the harness calls.
#
#   plan <criteria.json>             a frozen-looking run folder under .selvedge/runs/, a freeze line
#                                    in .selvedge/runs.jsonl (planner tokens 100 in / 20 out); prints
#                                    the folder; when the workspace sits under
#                                    targets/$STUB_PLAN_FAIL_SLUG*, it freezes nothing, says
#                                    planner_failed on stderr and exits 1 (a plan that did not freeze)
#   run [--replay] [--non-interactive] <dir>
#                                    verdict.json with every criterion STUB_VERDICT (default PASS),
#                                    or BLOCKED budget_exceeded when SELVEDGE_PLANNER_TOKEN_BUDGET is
#                                    set (as lib/runner/run.mjs does for a plan over budget); the
#                                    STUB_FLIP_CALL-th run call (1-based, counted in $STUB_LOG) says
#                                    FAIL instead; a run line in runs.jsonl (duration_ms 1234)
# Every call appends "<command> budget=<set|unset>" to $STUB_LOG/calls.log.
set -uo pipefail
log="${STUB_LOG:?STUB_LOG must be set}"
mkdir -p "$log"
budget='unset'; [ -n "${SELVEDGE_PLANNER_TOKEN_BUDGET+x}" ] && budget='set'
echo "$1 budget=$budget" >>"$log/calls.log"
cmd="$1"; shift
exec node - "$cmd" "$log" "$budget" "$@" <<'JS'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [cmd, log, budget, ...args] = process.argv.slice(2);
const root = process.cwd();
const runs = path.join(root, '.selvedge', 'runs');
const newDir = () => {
  const id = `${new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z')}-${crypto.randomBytes(3).toString('hex')}`;
  const d = path.join(runs, id);
  fs.mkdirSync(d, { recursive: true });
  return { id, d };
};
const line = (o) => fs.appendFileSync(path.join(root, '.selvedge', 'runs.jsonl'), `${JSON.stringify(o)}\n`);
const failSlug = process.env.STUB_PLAN_FAIL_SLUG;
if (cmd === 'plan' && failSlug && root.split(path.sep).includes('targets') && path.basename(path.dirname(root)).startsWith(failSlug)) {
  process.stderr.write('selvedge plan: FAIL planner_failed (stub)\n');
  process.exit(1);
} else if (cmd === 'plan') {
  const { id, d } = newDir();
  fs.copyFileSync(args[0], path.join(d, 'criteria.json'));
  fs.writeFileSync(path.join(d, 'plan.sha256'), `${'0'.repeat(64)}  plan.json\n`);
  line({ event: 'freeze', run_id: id, planner_tokens: { input_tokens: 100, output_tokens: 20 } });
  process.stdout.write(`${d}\n`);
} else if (cmd === 'run') {
  const replay = args.includes('--replay');
  const src = args.filter((a) => !a.startsWith('--')).pop();
  const { id, d } = replay ? newDir() : { id: path.basename(src), d: src };
  if (replay) fs.copyFileSync(path.join(src, 'criteria.json'), path.join(d, 'criteria.json'));
  const counter = path.join(log, 'run-calls');
  const n = (fs.existsSync(counter) ? Number(fs.readFileSync(counter, 'utf8')) : 0) + 1;
  fs.writeFileSync(counter, String(n));
  const crit = JSON.parse(fs.readFileSync(path.join(d, 'criteria.json'), 'utf8')).criteria;
  let v = process.env.STUB_VERDICT || 'PASS';
  let reason = null;
  if (budget === 'set') { v = 'BLOCKED'; reason = 'budget_exceeded'; }
  else if (String(n) === process.env.STUB_FLIP_CALL) v = 'FAIL';
  if (v === 'BLOCKED' || v === 'NOT_VERIFIABLE') reason = reason || 'step_failed';
  const criteria = Object.fromEntries(crit.map((c) => [c.id, { verdict: v, evidence_class: 'structured-read', reason }]));
  fs.writeFileSync(path.join(d, 'verdict.json'), JSON.stringify({ schema_version: 1, criteria }, null, 2));
  line({ event: 'run', run_id: id, duration_ms: 1234, replay_of: replay ? path.basename(src) : null });
  for (const c of crit) process.stdout.write(`${v}${reason ? ` ${reason}` : ''} ${c.id}\n`);
  process.stdout.write(`verdict ${v} ${path.join(d, 'verdict.json')}\n`);
} else {
  process.stderr.write(`stub-selvedge: unknown command ${cmd}\n`);
  process.exit(2);
}
JS
