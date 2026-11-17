// runner/run.mjs — `selvedge run [--trace] [--non-interactive] <run-dir>` and `selvedge run --replay
// <frozen-run-dir> [--trace] [--non-interactive]`, run by selvedge/bin/selvedge.
//
// Executes a frozen run folder's plan.json through the guarded browser. No model is called: every
// step is a typed plan step (runner/steps.mjs), every evidence line is written by this runner
// (runner/evidence.mjs), and the verdict is derived from those lines by deriveVerdict
// (lib/verdict.mjs), which reads them back from disk.
//
// Refused before anything is written or launched, in this order (each exit 2, the reason on stderr):
//   usage           not one <run-dir>, a bad SELVEDGE_ENTRY / SELVEDGE_RUN_BUDGET_MS /
//                   SELVEDGE_STEP_TIMEOUT_MS / SELVEDGE_PLANNER_TOKEN_BUDGET value
//   not_frozen      the folder holds no plan.sha256 (or no freeze.json)
//   already_run     the folder already holds evidence.jsonl, or run.claim (one run per folder)
//   plan_modified   the sha256 of plan.json's bytes is not the one plan.sha256 records, or not the
//                   one the folder's own `event: "freeze"` line in runs.jsonl records (a plan.json
//                   and plan.sha256 edited together are still plan_modified; so is a folder with no
//                   freeze line)
//   a config reason selvedge.json (of the repo that holds the run folder) does not load, or its
//                   auth.signed_in_check is not one plan-step locator form (a CSS or XPath locator
//                   is config_schema_violation: validateSignedInCheck, auth-state.mjs)
// Then the run claims the folder: run.claim is created exclusively before any hook runs or anything
// launches, so of two runs started together on one folder exactly one goes on and the other is
// already_run before it runs a hook. The claim is removed when the run ends, however it ends; a run
// killed outright leaves it behind, and the folder then reads as already_run until it is removed.
// Then, each making every criterion BLOCKED (evidence and verdict.json are written; nothing
// launches):
//   budget_exceeded        freeze.json's planner tokens (input + output) exceed
//                          SELVEDGE_PLANNER_TOKEN_BUDGET (only when both are known)
//   env_hooks_unapproved   a reset / seed hook in selvedge.json is not approved (`selvedge env
//                          hook` exits 2; its own reason is taken when it names another)
// The approved hooks run after the claim and before the first browser launch, reset then seed, each
// through this CLI's own `selvedge env hook <name>` (so the approval and remote-origin checks stay
// env.mjs's). A hook that runs and fails is an operation failure: exit 1 and no evidence is written
// (the claim is removed), so the folder can be run again once the hook is fixed. With a hook run,
// data_state is managed; with none, unmanaged and plan_time_actions is freeze.json's (what the
// planner's snapshots did to the app).
// The sign-in check (only when selvedge.json has `auth.signed_in_check` and the plan has a planned
// criterion; with no `auth` key nothing here changes): after the hooks, before the per-criterion
// checks, Playwright is resolved (once; the criteria reuse it) and runner/auth-check.mjs checks the
// login wall ONCE in a guarded context with the stored session (auth-state.mjs, when its file
// exists). A failed check makes every criterion BLOCKED needs_auth at once when nobody can sign in
// (stdin not a terminal, or --non-interactive);
// on a terminal it asks for one sign-in (`selvedge auth setup --headed`), reads one line and checks
// once more. No retry loop, and run never runs the auth_setup hook itself. With `auth` set, every
// criterion context starts from the stored session when it exists, and every value of an `auth.env`
// variable joins the redaction list, written back as {{NAME}}. With `auth` but no signed_in_check, a
// stored session file Playwright would not load (auth-state.mjs stateFileProblem) makes every
// criterion BLOCKED needs_auth before any browser opens.
// Per criterion, before launch: a goto origin selvedge.json no longer allows is BLOCKED
// host_not_allowed; an unset {{NAME}} is BLOCKED placeholder_unset; Playwright that does not resolve
// makes every criterion still to run BLOCKED playwright_unavailable.
//
// Every criterion runs in its own fresh guarded context (runner/execute.mjs). SELVEDGE_RUN_BUDGET_MS
// (default 600000) is checked before each criterion starts: once the run has spent it, every
// criterion not yet started is BLOCKED budget_exceeded and gets no browser. SELVEDGE_STEP_TIMEOUT_MS
// (default STEP_TIMEOUT_MS, 5000) bounds each action. A criterion under plan.json's not_planned is
// written as criterion_end not_planned with the plan's reason.
//
// After the run: verdict.json (deriveVerdict) and exactly ONE `event: "run"` line appended to
// <repo root>/.selvedge/runs.jsonl:
//   {event, ts, run_id, entry, counts, verdict, planner_tokens, duration_ms, plan_sha256,
//    criteria_sha256, plan_revision, replay_of}
// entry is SELVEDGE_ENTRY (session by default; ci, loomwright); planner_tokens is the plan's own
// planner cost from freeze.json (input + output, null when unreported) — the run itself spends none.
//
// stdout: one line per criterion `<VERDICT> [<reason>] <criterion-id>`, then
// `verdict <VERDICT> <path to verdict.json>`. Exit codes (00-plan D7, precedence when several apply):
// 1 any FAIL, else 2 any BLOCKED (or a refusal above), else 3 any NOT_VERIFIABLE, else 0.
// Every reason comes from REASONS in env-config.mjs.
//
// --replay <frozen-run-dir> (replayRun) re-runs a frozen plan unchanged, for regression. Every
// check above runs against the frozen folder before anything is created, except already_run (a
// folder that ran is what a replay replays); the freeze-line check there is the frozen run's own
// line (a replay folder has none: replay the folder it replayed). Then a NEW run folder gets
// criteria.json, plan.json (the very bytes that were hashed), plan.sha256 and freeze.json copied,
// and runs as above with replay_of = the frozen run id (in run_start, verdict.json and the run
// line), the plan's own plan_revision, planner_tokens 0 and no planner-token budget check (the
// replay spends none). A replay that writes no evidence (a refusal, a failing hook) leaves no new
// folder behind.
//
// --trace: each criterion's context is traced and kept, redacted, as traces/<criterion-id>.zip
// (runner/execute.mjs, runner/trace-redact.mjs). Without it nothing is traced.
//
// Node >= 18, standard library only (Playwright is resolved at run time, never imported here).
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS, UsageError, isMain, isOriginAllowed, loadConfig, parseCliArgs, repoRoot } from '../env-config.mjs';
import { authEnvValues, authStatePath, hasState, stateFileProblem, validateSignedInCheck } from '../auth-state.mjs';
import { PLANNER_TOKEN_BUDGET_ENV } from '../plan-planner.mjs';
import { FREEZE_EVENT, RUN_FILES, initRun, readRunsLog, runsLogPath } from '../plan-runs.mjs';
import { SELVEDGE_BIN, plannerTokenBudget } from '../plan.mjs';
import { resolvePlaceholders } from '../plan-steps.mjs';
import { STEP_TIMEOUT_MS, placeholderValues } from '../snapshot.mjs';
import { firstLine, resolvePlaywright } from '../snapshot-playwright.mjs';
import { RUN_EVENT, deriveVerdict } from '../verdict.mjs';
import { SIGN_IN_HINT, signedInGate } from './auth-check.mjs';
import { CRITERION_OUTCOMES, DATA_STATES, EVIDENCE_FILE, EVIDENCE_KINDS, appendEvidence } from './evidence.mjs';
import { executeCriterion } from './execute.mjs';

export const ENTRY_ENV = 'SELVEDGE_ENTRY';
export const ENTRIES = Object.freeze({ session: 'session', ci: 'ci', loomwright: 'loomwright' });
export const RUN_BUDGET_ENV = 'SELVEDGE_RUN_BUDGET_MS';
export const DEFAULT_RUN_BUDGET_MS = 600000;
export const STEP_TIMEOUT_ENV = 'SELVEDGE_STEP_TIMEOUT_MS';
// The hooks a run runs, in this order. auth_setup is never one: it runs only through `selvedge auth
// setup` (lib/auth.mjs), never from a run.
export const RUN_HOOKS = Object.freeze(['reset', 'seed']);

// The file a run creates exclusively in its folder before any hook runs (the header's claim).
export const RUN_CLAIM_FILE = 'run.claim';

const BLOCKED_LINE = /^BLOCKED ([a-z_]+)$/m;

const USAGE = `Usage: selvedge run [--trace] [--non-interactive] <run-dir>
       selvedge run --replay <frozen-run-dir> [--trace] [--non-interactive]

Execute a frozen run folder's plan.json in the guarded browser (no model is called), write
<run-dir>/evidence.jsonl, screenshots/<criterion-id>.png and verdict.json, and append one line to
.selvedge/runs.jsonl. A folder runs once (already_run); a plan.json whose sha256 is not plan.sha256's
is refused (plan_modified).

  --replay <frozen-run-dir>  run the frozen plan again, byte for byte, in a NEW run folder
                             (replay_of = the frozen run id); also refused (plan_modified) when the
                             sha256 is not the one runs.jsonl's freeze line for that run records
  --trace                    keep a redacted Playwright trace per criterion, traces/<criterion-id>.zip
                             (Cookie, Set-Cookie, Authorization and {{NAME}} values removed; a trace
                             that cannot be redacted is dropped)
  --non-interactive          never wait for a sign-in: a failed auth.signed_in_check makes every
                             criterion BLOCKED needs_auth at once (also when stdin is not a terminal)

With "auth.signed_in_check" in selvedge.json the sign-in is checked once, before the first criterion,
with the session \`selvedge auth setup\` stored; on a terminal a failed check asks you to sign in
(\`selvedge auth setup --headed\`) and checks once more.

Environment: SELVEDGE_ENTRY (session | ci | loomwright, recorded in the run line; default session),
SELVEDGE_RUN_BUDGET_MS (wall clock for the run, default ${DEFAULT_RUN_BUDGET_MS}),
SELVEDGE_STEP_TIMEOUT_MS (per action, default ${STEP_TIMEOUT_MS}), ${PLANNER_TOKEN_BUDGET_ENV}
(the plan's planner tokens may not exceed it), SELVEDGE_PLAYWRIGHT_MODULE.

stdout: one line per criterion, \`<VERDICT> [<reason>] <criterion-id>\`, then
\`verdict <VERDICT> <path to verdict.json>\`.

Exit codes (precedence when several apply): 1 any FAIL, else 2 any BLOCKED (or a usage error:
not_frozen, already_run, plan_modified), else 3 any NOT_VERIFIABLE, else 0.`;

function err(line) {
  process.stderr.write(`selvedge run: ${line}\n`);
}

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

// A whole number of milliseconds from the environment, or `fallback` when unset.
function wholeMs(env, name, fallback, { min = 0 } = {}) {
  const raw = env[name];
  if (raw === undefined || raw === '') return fallback;
  if (!/^[0-9]+$/.test(raw) || Number(raw) < min) throw new UsageError(`${name} must be a whole number of milliseconds${min ? ` >= ${min}` : ''} (got ${JSON.stringify(raw)})`);
  return Number(raw);
}

// The run's entry point from SELVEDGE_ENTRY (session when unset); anything else is a usage error.
export function runEntry(env = process.env) {
  const raw = env[ENTRY_ENV];
  if (raw === undefined || raw === '') return ENTRIES.session;
  if (!Object.values(ENTRIES).includes(raw)) throw new UsageError(`${ENTRY_ENV} must be one of ${Object.values(ENTRIES).join(', ')} (got ${JSON.stringify(raw)})`);
  return raw;
}

const sha256Hex = (bytes) => createHash('sha256').update(bytes).digest('hex');

// The usage checks on the environment, before anything is read: { entry, runBudgetMs,
// stepTimeoutMs, tokenBudget }. Throws UsageError.
function runOptions(env) {
  return {
    entry: runEntry(env),
    runBudgetMs: wholeMs(env, RUN_BUDGET_ENV, DEFAULT_RUN_BUDGET_MS),
    stepTimeoutMs: wholeMs(env, STEP_TIMEOUT_ENV, STEP_TIMEOUT_MS, { min: 1 }),
    tokenBudget: plannerTokenBudget(env),
  };
}

// The frozen folder's plan, checked: { plan, planBytes, planSha256, freeze }. Throws EnvError
// not_frozen, already_run, plan_modified or plan_invalid (the header's order). With `replay`, a
// folder that already ran is not refused (it is the one being replayed).
export function readFrozenRun(runDir, { replay = false } = {}) {
  const shaFile = path.join(runDir, RUN_FILES.planSha);
  let recorded;
  try {
    recorded = readFileSync(shaFile, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') throw new EnvError(REASONS.not_frozen, `${runDir} holds no ${RUN_FILES.planSha}: the plan is not frozen; freeze it first: selvedge plan --freeze ${runDir}`);
    throw e;
  }
  if (!replay && existsSync(path.join(runDir, EVIDENCE_FILE))) {
    throw new EnvError(REASONS.already_run, `${path.join(runDir, EVIDENCE_FILE)} exists: this folder has already run; nothing in it is changed`);
  }
  if (!replay && existsSync(path.join(runDir, RUN_CLAIM_FILE))) {
    throw new EnvError(REASONS.already_run, `${path.join(runDir, RUN_CLAIM_FILE)} exists: another run of this folder is under way (or one was killed before it ended; remove the file once none is running)`);
  }
  const want = recorded.trim().split(/\s+/)[0];
  const planFile = path.join(runDir, RUN_FILES.plan);
  let bytes;
  try {
    bytes = readFileSync(planFile);
  } catch (e) {
    if (e && e.code === 'ENOENT') throw new EnvError(REASONS.plan_modified, `${planFile} is gone, but ${RUN_FILES.planSha} records ${want}`);
    throw e;
  }
  const have = sha256Hex(bytes);
  if (have !== want) {
    throw new EnvError(REASONS.plan_modified, `${planFile} has sha256 ${have}, but ${RUN_FILES.planSha} records ${want}: the frozen plan was edited; nothing was launched`);
  }
  let plan;
  try {
    plan = JSON.parse(bytes.toString('utf8'));
  } catch (e) {
    throw new EnvError(REASONS.plan_invalid, `${planFile} is not valid JSON: ${e && e.message}`);
  }
  if (!isPlainObject(plan) || !isPlainObject(plan.steps_by_criterion) || !Object.values(plan.steps_by_criterion).every((c) => isPlainObject(c) && Array.isArray(c.steps))) {
    throw new EnvError(REASONS.plan_invalid, `${planFile} is not a plan (steps_by_criterion of {steps: [...]})`);
  }
  let freeze;
  try {
    freeze = JSON.parse(readFileSync(path.join(runDir, RUN_FILES.freeze), 'utf8'));
  } catch (e) {
    throw new EnvError(REASONS.not_frozen, `${path.join(runDir, RUN_FILES.freeze)} cannot be read (${e && e.code ? e.code : firstLine(e)}): the freeze record is missing`);
  }
  if (!isPlainObject(freeze)) throw new EnvError(REASONS.not_frozen, `${path.join(runDir, RUN_FILES.freeze)} is not a freeze record`);
  return { plan, planBytes: bytes, planSha256: have, freeze };
}

// Throws plan_modified unless runs.jsonl (at `root`) holds the `event: "freeze"` line of run `runId`
// and every such line records `planSha256` (the sha256 of plan.json's bytes as read now).
export function assertFreezeLine(root, runId, planSha256, freeze) {
  const lines = readRunsLog(root).entries.filter((e) => e.event === FREEZE_EVENT && e.run_id === runId);
  if (!lines.length) {
    const hint = typeof freeze.run_id === 'string' && freeze.run_id !== runId ? ` (it was copied from run ${freeze.run_id}: replay that folder)` : '';
    throw new EnvError(REASONS.plan_modified, `${runsLogPath(root)} holds no freeze line for run ${runId}${hint}: the plan cannot be shown to be the one frozen; nothing was run`);
  }
  const bad = lines.find((l) => l.plan_sha256 !== planSha256);
  if (bad) {
    throw new EnvError(REASONS.plan_modified, `plan.json has sha256 ${planSha256}, but the freeze line for run ${runId} in ${runsLogPath(root)} records ${bad.plan_sha256}: the frozen plan was edited; nothing was run`);
  }
}

// The plan's planner tokens from freeze.json (input + output), or null when unreported.
function plannerTokens(freeze) {
  const t = freeze.planner_tokens;
  if (!isPlainObject(t) || !Number.isInteger(t.input_tokens) || !Number.isInteger(t.output_tokens)) return null;
  return t.input_tokens + t.output_tokens;
}

// Creates run.claim exclusively, or throws already_run (another run holds the folder).
function claimRun(runDir) {
  const file = path.join(runDir, RUN_CLAIM_FILE);
  try {
    writeFileSync(file, `${process.pid}\n`, { flag: 'wx' });
  } catch (e) {
    if (e && e.code === 'EEXIST') throw new EnvError(REASONS.already_run, `${file} exists: another run of this folder is under way; nothing in it is changed`);
    throw e;
  }
  return file;
}

// Runs the approved reset / seed hooks through `selvedge env hook <name>` at the repo root.
// → { ran: [names], blockedReason: null | reason }. A hook that fails to run throws an Error.
function runHooks(config, root, env) {
  const ran = [];
  for (const name of RUN_HOOKS) {
    if (!Object.prototype.hasOwnProperty.call(config.hooks, name)) continue;
    const res = spawnSync('bash', [SELVEDGE_BIN, 'env', 'hook', name], { cwd: root, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    for (const stream of [res.stdout, res.stderr]) {
      for (const l of String(stream || '').split('\n')) if (l.trim() !== '') err(`hook ${name}: ${l}`);
    }
    if (res.error) throw new Error(`hook ${name} could not start: ${res.error.message}`);
    if (res.status === 2) {
      const m = BLOCKED_LINE.exec(String(res.stdout || ''));
      const reason = m && Object.values(REASONS).includes(m[1]) ? m[1] : REASONS.env_hooks_unapproved;
      return { ran, blockedReason: reason };
    }
    if (res.status !== 0) throw new Error(`hook ${name} failed (${res.signal ? `signal ${res.signal}` : `exit ${res.status}`}); nothing was written to the run folder`);
    ran.push(name);
  }
  return { ran, blockedReason: null };
}

// The goto origin of a criterion selvedge.json no longer allows, or null.
function refusedGoto(config, steps) {
  const bad = steps.find((s) => isPlainObject(s) && s.type === 'goto' && !isOriginAllowed(config, s.url));
  return bad ? bad.url : null;
}

// runPlan(runDir, { env, started, replayOf, trace, interactive }) → Promise<exit code>. Writes the CLI's stdout /
// stderr itself; `started` (ms) is when the run began, what SELVEDGE_RUN_BUDGET_MS counts from;
// `replayOf` is the frozen run id a replay folder copies (replayRun), null otherwise.
// `interactive` is true only when someone can answer the sign-in prompt (cmdRun: stdin is a terminal
// and no --non-interactive).
export async function runPlan(runDir, { env = process.env, started = Date.now(), replayOf = null, trace = false, interactive = false } = {}) {
  const { entry, runBudgetMs, stepTimeoutMs, tokenBudget } = runOptions(env);

  const { plan, planSha256, freeze } = readFrozenRun(runDir);
  const runId = path.basename(path.resolve(runDir));
  // a first run checks its own freeze line, as a replay checks the frozen run's (a replay folder has
  // none of its own; replayRun checked the one it copies)
  if (replayOf === null) assertFreezeLine(repoRoot(runDir) || runDir, runId, planSha256, freeze);
  // selvedge.json of the repo that holds the run folder; the same root holds runs.jsonl.
  const { config, root } = loadConfig({ cwd: runDir });
  validateSignedInCheck(config); // a CSS / XPath sign-in locator: config_schema_violation, nothing claimed
  const claim = claimRun(runDir);
  try {
    return await claimedRun({ runDir, env, started, replayOf, trace, interactive, entry, runBudgetMs, stepTimeoutMs, tokenBudget, plan, planSha256, freeze, config, root, runId });
  } finally {
    rmSync(claim, { force: true });
  }
}

// The run proper, with the folder claimed (runPlan).
async function claimedRun({ runDir, env, started, replayOf, trace, interactive, entry, runBudgetMs, stepTimeoutMs, tokenBudget, plan, planSha256, freeze, config, root, runId }) {
  const planned = Object.entries(plan.steps_by_criterion);
  const notPlanned = Array.isArray(plan.not_planned) ? plan.not_planned.filter((np) => isPlainObject(np) && typeof np.id === 'string') : [];

  const secrets = placeholderValues(planned.flatMap(([, c]) => c.steps), env);
  secrets.push(...authEnvValues(config, env, secrets)); // auth.env values are redacted as {{NAME}} too
  // the stored sign-in session (only with an `auth` key, and only when its file exists), asked again
  // after the sign-in check: a person may sign in while the run waits
  const storageState = () => (config.auth && hasState({ root, env }) ? authStatePath({ root, env }) : null);
  const ends = new Map(); // criterion id → criterion_end line, for the ones decided before launch
  // a replay spends no planner tokens (its plan's own cost was its freeze's)
  const tokens = replayOf === null ? plannerTokens(freeze) : 0;
  let blockAll = null;
  let hooksRun = [];

  // 1. the planner-token budget (nothing else runs when it is spent)
  if (tokenBudget !== null && tokens !== null && tokens > tokenBudget) {
    err(`${REASONS.budget_exceeded}: the plan cost ${tokens} planner tokens; ${PLANNER_TOKEN_BUDGET_ENV} is ${tokenBudget}; nothing was launched`);
    blockAll = { outcome: CRITERION_OUTCOMES.budget_exceeded, reason: REASONS.budget_exceeded };
  }
  // 2. the hooks, before any browser
  if (blockAll === null) {
    const hooks = runHooks(config, root, env);
    hooksRun = hooks.ran;
    if (hooks.blockedReason) {
      err(`${hooks.blockedReason}: a hook did not run; every criterion is BLOCKED and nothing was launched`);
      blockAll = { outcome: CRITERION_OUTCOMES.blocked, reason: hooks.blockedReason };
    }
  }
  // 2b. with `auth` but no sign-in check: a stored session the criteria would load that Playwright
  //     would refuse is needs_auth before any browser (with a check, checkSignedIn asks the same)
  if (blockAll === null && config.auth && !config.auth.signed_in_check && planned.length) {
    const file = storageState();
    const problem = file === null ? null : stateFileProblem(file);
    if (problem) {
      err(`${REASONS.needs_auth}: the stored session ${file} ${problem}; every criterion is BLOCKED ${REASONS.needs_auth}. Sign in again with ${SIGN_IN_HINT}`);
      blockAll = { outcome: CRITERION_OUTCOMES.blocked, reason: REASONS.needs_auth };
    }
  }
  // 2c. the sign-in check, once, before any criterion (the header); its Playwright is step 4's
  let pw = null;
  if (blockAll === null && config.auth && config.auth.signed_in_check && planned.length) {
    try {
      pw = await resolvePlaywright({ root, env, cwd: process.cwd() });
      err(`playwright ${pw.version || '(version unknown)'} from ${pw.source} (${pw.path})`);
    } catch (e) {
      if (!(e instanceof EnvError)) throw e;
      err(`${e.reason}: ${e.message}; the sign-in could not be checked`);
      blockAll = { outcome: CRITERION_OUTCOMES.blocked, reason: e.reason };
    }
    if (pw !== null) {
      const gate = await signedInGate({ chromium: pw.chromium, config, storageState, interactive, stepTimeoutMs, secrets });
      if (!gate.signedIn) blockAll = { outcome: CRITERION_OUTCOMES.blocked, reason: gate.reason };
    }
  }
  // 3. per criterion: origins and {{NAME}} values
  const resolvedById = new Map();
  for (const [id, c] of planned) {
    if (blockAll) {
      ends.set(id, { outcome: blockAll.outcome, reason: blockAll.reason });
      continue;
    }
    const url = refusedGoto(config, c.steps);
    if (url !== null) {
      err(`${id}: ${REASONS.host_not_allowed}: goto ${JSON.stringify(url)} is not an origin selvedge.json allows`);
      ends.set(id, { outcome: CRITERION_OUTCOMES.blocked, reason: REASONS.host_not_allowed });
      continue;
    }
    try {
      resolvedById.set(id, resolvePlaceholders(c.steps, env));
    } catch (e) {
      if (!(e instanceof EnvError)) throw e;
      err(`${id}: ${e.reason}: ${e.message}`);
      ends.set(id, { outcome: CRITERION_OUTCOMES.blocked, reason: e.reason });
    }
  }
  // 4. Playwright, only when a criterion is left to run (and the sign-in check did not resolve it)
  if (resolvedById.size && pw === null) {
    try {
      pw = await resolvePlaywright({ root, env, cwd: process.cwd() });
      err(`playwright ${pw.version || '(version unknown)'} from ${pw.source} (${pw.path})`);
    } catch (e) {
      if (!(e instanceof EnvError)) throw e;
      err(`${e.reason}: ${e.message}`);
      for (const id of resolvedById.keys()) ends.set(id, { outcome: CRITERION_OUTCOMES.blocked, reason: e.reason });
      resolvedById.clear();
    }
  }

  // 5. the evidence: run_start (creates the file exclusively), then each criterion
  const write = (line, opts = {}) => appendEvidence(runDir, line, { secrets, ...opts });
  write({
    kind: EVIDENCE_KINDS.run_start,
    ts: new Date(started).toISOString(),
    run_id: runId,
    plan_sha256: planSha256,
    playwright_version: pw ? pw.version : null,
    data_state: hooksRun.length ? DATA_STATES.managed : DATA_STATES.unmanaged,
    hooks_run: hooksRun,
    plan_time_actions: Number.isInteger(freeze.plan_time_actions) && freeze.plan_time_actions >= 0 ? freeze.plan_time_actions : null,
    replay_of: replayOf,
  }, { first: true });
  for (const np of notPlanned) {
    write({ kind: EVIDENCE_KINDS.criterion_end, criterion: np.id, outcome: CRITERION_OUTCOMES.not_planned, reason: np.reason, failed_step: null, screenshot: null });
  }

  const chromium = pw ? pw.chromium : null;
  const criterionState = storageState();
  for (const [id, c] of planned) {
    const decided = ends.get(id);
    if (decided) {
      write({ kind: EVIDENCE_KINDS.criterion_end, criterion: id, outcome: decided.outcome, reason: decided.reason, failed_step: null, screenshot: null });
      continue;
    }
    if (Date.now() - started >= runBudgetMs) {
      err(`${id}: ${REASONS.budget_exceeded}: the run has spent ${RUN_BUDGET_ENV}=${runBudgetMs}; not started`);
      write({ kind: EVIDENCE_KINDS.criterion_end, criterion: id, outcome: CRITERION_OUTCOMES.budget_exceeded, reason: REASONS.budget_exceeded, failed_step: null, screenshot: null });
      continue;
    }
    err(`${id}: running ${c.steps.length} step(s)`);
    const end = await executeCriterion({ id, steps: c.steps, resolved: resolvedById.get(id), chromium, config, runDir, secrets, stepTimeoutMs, write, trace, storageState: criterionState });
    write(end);
  }
  write({ kind: EVIDENCE_KINDS.run_end, ts: new Date().toISOString(), duration_ms: Date.now() - started });

  // 6. the verdict, from disk, and the one run line
  const result = deriveVerdict(runDir, { root });
  const line = {
    event: RUN_EVENT,
    ts: new Date().toISOString(),
    run_id: runId,
    entry,
    counts: result.counts,
    verdict: result.overall,
    planner_tokens: tokens,
    duration_ms: Date.now() - started,
    plan_sha256: planSha256,
    criteria_sha256: typeof plan.criteria_sha256 === 'string' ? plan.criteria_sha256 : null,
    plan_revision: Number.isInteger(plan.plan_revision) ? plan.plan_revision : null,
    replay_of: replayOf,
  };
  mkdirSync(path.dirname(runsLogPath(root)), { recursive: true });
  appendFileSync(runsLogPath(root), `${JSON.stringify(line)}\n`);

  for (const [id, v] of Object.entries(result.verdict.criteria)) {
    process.stdout.write(`${v.verdict}${v.reason ? ` ${v.reason}` : ''} ${id}\n`);
  }
  process.stdout.write(`verdict ${result.overall} ${result.file}\n`);
  return result.exitCode;
}

// replayRun(frozenDir, { env, started, trace, interactive }) → Promise<exit code>: the header's --replay.
export async function replayRun(frozenDir, { env = process.env, started = Date.now(), trace = false, interactive = false } = {}) {
  runOptions(env); // usage first: a bad value creates nothing
  const { planBytes, planSha256, freeze } = readFrozenRun(frozenDir, { replay: true });
  const frozenId = path.basename(path.resolve(frozenDir));
  // the root loadConfig({ cwd: frozenDir }) resolves, read before selvedge.json is (the header's order)
  assertFreezeLine(repoRoot(frozenDir) || frozenDir, frozenId, planSha256, freeze);
  const criteriaFile = path.join(frozenDir, RUN_FILES.criteria);
  if (!existsSync(criteriaFile)) throw new EnvError(REASONS.not_frozen, `${frozenDir} holds no ${RUN_FILES.criteria}: not a complete frozen run folder; nothing was created`);
  const { config, root } = loadConfig({ cwd: frozenDir });
  validateSignedInCheck(config); // before the new folder is created

  const { runDir } = initRun({ root, criteriaFile });
  try {
    writeFileSync(path.join(runDir, RUN_FILES.plan), planBytes); // the bytes hashed above, unchanged
    copyFileSync(path.join(frozenDir, RUN_FILES.freeze), path.join(runDir, RUN_FILES.freeze));
    writeFileSync(path.join(runDir, RUN_FILES.planSha), `${planSha256}  ${RUN_FILES.plan}\n`, { flag: 'wx' });
    err(`replay of ${frozenId} in ${runDir}`);
    return await runPlan(runDir, { env, started, replayOf: frozenId, trace, interactive });
  } finally {
    // a replay that wrote no evidence leaves nothing behind
    if (!existsSync(path.join(runDir, EVIDENCE_FILE))) rmSync(runDir, { recursive: true, force: true });
  }
}

function assertDir(dir) {
  let isDir = false;
  try {
    isDir = statSync(dir).isDirectory();
  } catch {
    isDir = false;
  }
  if (!isDir) throw new UsageError(`${dir} is not a directory`);
}

function cmdRun(argv, started) {
  const { flags, positional } = parseCliArgs(argv, { values: ['replay'], booleans: ['trace', 'non-interactive'] });
  const trace = flags.trace === true;
  // someone can answer the sign-in prompt only on a terminal, and never with --non-interactive
  const interactive = flags['non-interactive'] !== true && process.stdin.isTTY === true;
  if (flags.replay !== undefined) {
    if (positional.length) throw new UsageError(`--replay takes the frozen run folder; no other <run-dir> (got ${positional[0]})`);
    assertDir(flags.replay);
    return replayRun(flags.replay, { started, trace, interactive });
  }
  if (positional.length !== 1) throw new UsageError(positional.length === 0 ? 'a <run-dir> is required' : `one <run-dir> only (got ${positional.length})`);
  assertDir(positional[0]);
  return runPlan(positional[0], { started, trace, interactive });
}

async function main(argv) {
  const started = Date.now();
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    err(`needs Node.js >= 18 (this is ${process.versions.node})`);
    return 1;
  }
  try {
    if (argv.length === 0) {
      process.stderr.write(`${USAGE}\n`);
      return 2;
    }
    if (['help', '-h', '--help'].includes(argv[0])) {
      process.stdout.write(`${USAGE}\n`);
      return 0;
    }
    return await cmdRun(argv, started);
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof EnvError) {
      if (e.blocked) process.stdout.write(`BLOCKED ${e.reason}\n`);
      err(`${e.reason}: ${e.message}`);
      return 2;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
