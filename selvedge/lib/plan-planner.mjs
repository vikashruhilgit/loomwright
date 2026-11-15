// plan-planner.mjs — runs the planner that turns a run folder's testable criteria into plan.json.
//
// Two planners, chosen by the environment (never by a file in the repo):
//
//  - SELVEDGE_PLANNER set: a command run with `/bin/sh -c` at the repo root. It reads
//    $SELVEDGE_CRITERIA (the run folder's planner-input.json), writes the plan to $SELVEDGE_PLAN_OUT,
//    may call `$SELVEDGE_BIN snapshot …` (the run folder is $SELVEDGE_RUN_DIR and the config source
//    $SELVEDGE_BASE — the plan's --base, "" for the working tree — which snapshot reads and holds
//    it to, so each call counts against the folder's snapshot budget and sees the plan's
//    allowlist), and may write
//    {"input_tokens": N, "output_tokens": M} to $SELVEDGE_PLANNER_USAGE. Its stdout and stderr go
//    to selvedge's stderr.
//  - unset (or empty): the built-in default, `claude -p <prompt> --output-format json --model <m>
//    --allowedTools "Bash(<SELVEDGE_BIN> snapshot:*)"`. The prompt is selvedge/prompts/planner.md
//    followed by the planner-input.json text; the model is SELVEDGE_PLANNER_MODEL (default sonnet).
//    The plan is the JSON object in the result's `result` text (a ```json block, or the whole
//    text); selvedge writes it to plan.json and the result's `usage` to planner-usage.json.
//
// A planner that cannot start, exits non-zero (or on a signal), or leaves no plan is planner_failed
// (exit 2). What the plan says is not judged here: plan.mjs runs the plan lint before anything is
// hashed.
//
// Honest limit: `--allowedTools` admits only the snapshot command, but claude still applies the
// user's own settings, so a tool those settings allow is allowed to the planner too.
//
// Node >= 18, standard library only.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS } from './env-config.mjs';
import { RUN_FILES, prettyJson, readPlannerUsage } from './plan-runs.mjs';
import { BASE_ENV } from './snapshot.mjs';

export const PLANNER_ENV = 'SELVEDGE_PLANNER';
export const PLANNER_MODEL_ENV = 'SELVEDGE_PLANNER_MODEL';
export const PLANNER_TOKEN_BUDGET_ENV = 'SELVEDGE_PLANNER_TOKEN_BUDGET';
export const DEFAULT_PLANNER_MODEL = 'sonnet';
export const CLAUDE_BIN = 'claude';

const MAX_OUTPUT = 64 * 1024 * 1024;

function failed(message) {
  return new EnvError(REASONS.planner_failed, message);
}

// The exact --allowedTools rule the default planner gets: the snapshot command and nothing else.
export function snapshotToolRule(selvedgeBin) {
  return `Bash(${selvedgeBin} snapshot:*)`;
}

// claudeArgv({ prompt, model, selvedgeBin }) → the default planner's argv (after `claude`).
// --allowedTools is variadic, so it comes last: nothing after it can be read as another tool.
export function claudeArgv({ prompt, model, selvedgeBin }) {
  return ['-p', prompt, '--output-format', 'json', '--model', model, '--allowedTools', snapshotToolRule(selvedgeBin)];
}

// The default planner's prompt: the fixed prompt file, then the planner input.
export function plannerPrompt(promptText, inputText) {
  return `${promptText.replace(/\s+$/, '')}\n\n## Input (planner-input.json)\n\n\`\`\`json\n${inputText.replace(/\s+$/, '')}\n\`\`\`\n`;
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function parseObject(text) {
  try {
    const v = JSON.parse(text);
    return isPlainObject(v) ? v : null;
  } catch {
    return null;
  }
}

// extractPlan(text) → the plan object in a model's result text, or null: the last ```json block
// that parses to an object, else the whole text, else the span from the first `{` to the last `}`.
export function extractPlan(text) {
  if (typeof text !== 'string') return null;
  const blocks = [...text.matchAll(/```(?:json)?[ \t]*\n([\s\S]*?)\n```/g)].map((m) => m[1]);
  for (let i = blocks.length - 1; i >= 0; i -= 1) {
    const v = parseObject(blocks[i]);
    if (v) return v;
  }
  const whole = parseObject(text.trim());
  if (whole) return whole;
  const a = text.indexOf('{');
  const b = text.lastIndexOf('}');
  return a >= 0 && b > a ? parseObject(text.slice(a, b + 1)) : null;
}

// The tokens of a claude --output-format json `usage`: input counts cache reads and writes too
// (every input token the model processed); null when the result carries none.
export function usageTokens(usage) {
  if (!isPlainObject(usage)) return null;
  const n = (k) => (Number.isInteger(usage[k]) && usage[k] >= 0 ? usage[k] : 0);
  if (!Number.isInteger(usage.input_tokens) || !Number.isInteger(usage.output_tokens)) return null;
  return {
    input_tokens: n('input_tokens') + n('cache_creation_input_tokens') + n('cache_read_input_tokens'),
    output_tokens: n('output_tokens'),
  };
}

function exitText(r) {
  return r.signal ? `was killed by ${r.signal}` : `exited ${r.status}`;
}

function runCommandPlanner({ command, root, childEnv, planOut, runDir }) {
  const r = spawnSync('/bin/sh', ['-c', command], { cwd: root, env: childEnv, stdio: ['ignore', 2, 2] });
  if (r.error) throw failed(`${PLANNER_ENV} could not be started with /bin/sh -c: ${r.error.message}`);
  if (r.status !== 0) throw failed(`${PLANNER_ENV} (${command}) ${exitText(r)}; no plan was frozen`);
  if (!existsSync(planOut)) throw failed(`${PLANNER_ENV} (${command}) exited 0 but wrote no plan at ${planOut}`);
  try {
    return readPlannerUsage(runDir);
  } catch (e) {
    throw failed(`${PLANNER_ENV} reported its tokens badly: ${e.message}`);
  }
}

function runClaudePlanner({ root, childEnv, planOut, runDir, promptFile, inputFile, model, selvedgeBin }) {
  const prompt = plannerPrompt(readFileSync(promptFile, 'utf8'), readFileSync(inputFile, 'utf8'));
  const r = spawnSync(CLAUDE_BIN, claudeArgv({ prompt, model, selvedgeBin }), {
    cwd: root,
    env: childEnv,
    stdio: ['ignore', 'pipe', 2],
    encoding: 'utf8',
    maxBuffer: MAX_OUTPUT,
  });
  if (r.error && r.error.code === 'ENOENT') {
    throw failed(`\`${CLAUDE_BIN}\` was not found on PATH; install Claude Code, or set ${PLANNER_ENV} to your own planner command`);
  }
  if (r.error) throw failed(`\`${CLAUDE_BIN}\` could not be run: ${r.error.message}`);
  if (r.status !== 0) throw failed(`\`${CLAUDE_BIN} -p\` ${exitText(r)}`);
  const res = parseObject(String(r.stdout || '').trim());
  if (!res) throw failed(`\`${CLAUDE_BIN} -p --output-format json\` printed no JSON result object`);
  if (res.is_error === true || typeof res.result !== 'string') {
    throw failed(`\`${CLAUDE_BIN} -p\` returned an error result (${res.subtype || 'no subtype'})`);
  }
  const plan = extractPlan(res.result);
  if (!plan) throw failed(`\`${CLAUDE_BIN} -p\`'s result holds no JSON plan object`);
  writeFileSync(planOut, prettyJson(plan));
  const tokens = usageTokens(res.usage);
  if (tokens) writeFileSync(path.join(runDir, RUN_FILES.plannerUsage), prettyJson(tokens));
  return tokens;
}

// runPlanner({ root, runDir, base, env, selvedgeBin, promptFile }) → { planner, tokens }.
// `base` is the plan's --base (undefined: the working tree); the planner's snapshot calls get it.
// The run folder already holds planner-input.json. On success plan.json exists in it; `tokens` is
// what the planner reported ({input_tokens, output_tokens}) or null. Throws planner_failed.
export function runPlanner({ root, runDir, base, env = process.env, selvedgeBin, promptFile }) {
  const inputFile = path.join(runDir, RUN_FILES.plannerInput);
  const planOut = path.join(runDir, RUN_FILES.plan);
  const childEnv = {
    ...env,
    SELVEDGE_RUN_DIR: runDir,
    SELVEDGE_CRITERIA: inputFile,
    SELVEDGE_PLAN_OUT: planOut,
    SELVEDGE_BIN: selvedgeBin,
    SELVEDGE_PLANNER_USAGE: path.join(runDir, RUN_FILES.plannerUsage),
    // The config source the plan is validated against: every snapshot the planner runs reads the
    // same allowlist ("" = the working tree), and a --base naming another is refused.
    [BASE_ENV]: base === undefined || base === null ? '' : base,
  };
  const command = env[PLANNER_ENV];
  if (typeof command === 'string' && command.trim() !== '') {
    return { planner: PLANNER_ENV, tokens: runCommandPlanner({ command, root, childEnv, planOut, runDir }) };
  }
  const model = env[PLANNER_MODEL_ENV] && env[PLANNER_MODEL_ENV].trim() !== '' ? env[PLANNER_MODEL_ENV] : DEFAULT_PLANNER_MODEL;
  return {
    planner: CLAUDE_BIN,
    tokens: runClaudePlanner({ root, childEnv, planOut, runDir, promptFile, inputFile, model, selvedgeBin }),
  };
}
