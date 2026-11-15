// snapshot.mjs — `selvedge snapshot`, run by selvedge/bin/selvedge.
//
//   selvedge snapshot <url> [--steps <prefix.json>] [--run-dir <dir>] [--base <ref>]
//
// Opens <url> in a guarded Chromium (openGuardedContext, item 02's proxy + route layer), runs an
// optional prefix of plan steps (a JSON array: goto, click, fill, select, check, press, wait_for —
// never read or expect, at most 15, checked by validateSteps in prefix mode), and prints the
// accessibility tree of the page body. A planner uses it to see a page in the state a criterion
// needs (a dialog open, a form filled) before it writes locators.
//
// Before anything launches, in this order (each exit 2, nothing launched):
//   - the prefix passes validateSteps (prefix mode) — else one stderr line per problem
//     `plan_invalid: (prefix): <code>: <detail>`;
//   - <url> and every prefix goto have an origin selvedge.json allows — else `BLOCKED <reason>`
//     (host_not_allowed) on stdout;
//   - every {{NAME}} in a fill/select value is set in the environment — else BLOCKED, naming each
//     unset name on stderr (resolvePlaceholders);
//   - Playwright resolves (snapshot-playwright.mjs) — else BLOCKED;
// then the run folder's budget: SELVEDGE_SNAPSHOT_BUDGET calls (default 20) per run folder, counted
// as the lines of <run-dir>/snapshots.jsonl; a call past it prints `NOT_VERIFIABLE <reason>` and
// exits 3 (00-plan D7 precedence: a BLOCKED call is reported as BLOCKED even when the budget is
// also spent). The count is read, not locked: calls started at the same moment in one run folder
// can each see room left, so they can exceed the budget by at most their own number. The budget
// bounds a planner's exploration cost; it is not a security boundary.
//
// Every call that gets as far as a run folder appends ONE line to <run-dir>/snapshots.jsonl,
// whatever its outcome (so a refused call still counts against the budget):
//   {ts, origin, prefix_steps, plan_time_actions, browser_launched, outcome, failed_step}
// prefix_steps are the steps as given — a {{NAME}} stays literal, its value is never written —
// and the line carries no page text and no tree. plan_time_actions counts the action steps
// (ACTION_TYPES: click, fill, select, check, press; never goto or wait_for) the browser attempted.
// outcome is one of OUTCOMES.
//
// stdout on a browser run (exit 0, or 1 when a prefix step or the page itself failed — the tree
// as it was then is still printed): one JSON object
//   {schema_version: 1, url, steps_run, failed_step: null | <0-based prefix index>,
//    error: null | <the error's first line>, aria_snapshot}
// failed_step is null with a non-null error when <url> itself did not load. A navigation (<url> or a
// prefix goto) answered with an HTTP status >= 400 has failed: the guard's proxy answers an
// unreachable listed origin with its own 502 page, which must not read as the app's page.
//
// Each call launches its own guarded browser and context (openGuardedContext) and closes it before
// it returns: no cookie, storage or page state carries from one call to the next.
//
// {{NAME}} values never reach stdout or stderr as given: before printing, every resolved value is
// replaced by its `{{NAME}}` (longest first, empty values skipped) in aria_snapshot, error and
// stderr (redactValues), and snapshots.jsonl keeps the steps as given. A short value (a "2") is
// redacted wherever it occurs, so the tree can read oddly. Exact matches only: a page that shows a
// value transformed (escaped, cut, re-cased, reversed) still shows it.
// OPEN (owner decision): any environment variable name is resolvable, not only names a plan
// declares, so a planner that may run `snapshot` can make the page hold any variable's value; the
// redaction above keeps the plain value off the output, nothing more.
//
// Run-folder and config pins (a planner run by `plan` gets both from it): with SELVEDGE_RUN_DIR set,
// a --run-dir naming another folder is a usage error (each call is counted where the caller said);
// with SELVEDGE_BASE set (`plan --base <ref>` sets it to <ref>, `plan` without --base to "", the
// working tree), the allowlist is read from that source and a --base naming another is a usage
// error. Both are refused before anything is recorded or launched.
//
// Exit codes (00-plan D7): 0 ok, 1 an operation failed, 2 usage error or BLOCKED, 3 NOT_VERIFIABLE.
// Every reason comes from REASONS in env-config.mjs.
//
// Node >= 18, standard library only (Playwright is resolved at run time, never imported here).
import { appendFileSync, mkdirSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS, UsageError, isMain, isOriginAllowed, loadConfig, parseCliArgs, parseOrigin } from './env-config.mjs';
import { ACTION_TYPES, placeholderNames, resolvePlaceholders, validateSteps } from './plan-steps.mjs';
import { problemLine } from './plan-validate.mjs';
import { openGuardedContext, reasonOfResponse } from './runner/route-guard.mjs';
import { firstLine, resolvePlaywright } from './snapshot-playwright.mjs';

export const SNAPSHOT_SCHEMA_VERSION = 1;
export const SNAPSHOTS_FILE = 'snapshots.jsonl';
export const BUDGET_ENV = 'SELVEDGE_SNAPSHOT_BUDGET';
export const DEFAULT_SNAPSHOT_BUDGET = 20;
export const STEP_TIMEOUT_MS = 5000;
export const NAVIGATION_TIMEOUT_MS = 15000;

// The outcome a snapshots.jsonl line records.
export const OUTCOMES = Object.freeze({
  ok: 'ok', // the tree was printed, exit 0
  step_failed: 'step_failed', // a prefix step failed, exit 1
  failed: 'failed', // the url, the launch or the tree read failed, exit 1
  blocked: 'blocked', // BLOCKED before or at launch, exit 2
  invalid: 'invalid', // a prefix problem, a config or usage reason, exit 2
  not_verifiable: 'not_verifiable', // the budget was spent, exit 3
});

// The problem code validateSteps gives an unlisted goto: snapshot reports that one as BLOCKED
// (the origin check below), every other code as plan_invalid.
const ORIGIN_PROBLEM = 'origin_not_allowed';

// The prefix id plan_invalid lines carry (validateSteps' detail names the step index).
const PREFIX_SCOPE = '(prefix)';

const USAGE = `Usage: selvedge snapshot <url> [--steps <prefix.json>] [--run-dir <dir>] [--base <ref>]

Print the accessibility tree of <url> (an origin selvedge.json allows), opened in the guarded
browser, after an optional prefix of plan steps (a JSON array of goto, click, fill, select, check,
press, wait_for; at most 15; a fill/select value may use {{NAME}} from the environment).

  --run-dir <dir>   the run folder (or SELVEDGE_RUN_DIR); required: each call appends one line to
                    <dir>/snapshots.jsonl and counts against SELVEDGE_SNAPSHOT_BUDGET (default 20).
                    With SELVEDGE_RUN_DIR set, a --run-dir naming another folder is refused.
  --base <ref>      read the allowlist from the committed <ref>:selvedge.json (as env check --base).
                    SELVEDGE_BASE (set by plan for its planner) pins it; a different --base is refused.

A {{NAME}} value is printed as {{NAME}}, never as the value (exact matches only).

Playwright comes from SELVEDGE_PLAYWRIGHT_MODULE when set, else the repo's own node_modules.
stdout: one JSON object {schema_version, url, steps_run, failed_step, error, aria_snapshot}.

Exit codes: 0 ok, 1 an operation failed (a prefix step failed: the tree is still printed),
2 usage error or BLOCKED, 3 NOT_VERIFIABLE (the snapshot budget is spent).`;

// The origin of an http(s) URL through the one origin parser, or null.
function originOf(url) {
  try {
    const u = new URL(url);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    const o = parseOrigin(u.origin);
    return o ? o.origin : null;
  } catch {
    return null;
  }
}

// The budget from the environment: a whole number of calls, DEFAULT_SNAPSHOT_BUDGET when unset.
export function snapshotBudget(env = process.env) {
  const raw = env[BUDGET_ENV];
  if (raw === undefined || raw === '') return DEFAULT_SNAPSHOT_BUDGET;
  if (!/^[0-9]+$/.test(raw)) throw new UsageError(`${BUDGET_ENV} must be a whole number of calls (got ${JSON.stringify(raw)})`);
  return Number(raw);
}

// The calls already recorded in the run folder: one non-empty snapshots.jsonl line each.
export function recordedCalls(runDir) {
  let raw;
  try {
    raw = readFileSync(path.join(runDir, SNAPSHOTS_FILE), 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return 0;
    throw e;
  }
  return raw.split('\n').filter((l) => l.trim() !== '').length;
}

// The base `plan --base <ref>` hands its planner: snapshot reads the allowlist the plan is checked
// against, never a wider one. Set (even to "", the working tree) it pins the config source.
export const BASE_ENV = 'SELVEDGE_BASE';

// The config base for this call. With SELVEDGE_BASE set, a --base naming another ref is a usage
// error (a planner cannot read a wider committed allowlist than its plan's); "" means the working
// tree, so any --base then conflicts.
export function pinnedBase(flags, env = process.env) {
  if (!Object.prototype.hasOwnProperty.call(env, BASE_ENV) || env[BASE_ENV] === undefined) return flags.base;
  const pinned = env[BASE_ENV];
  if (flags.base !== undefined && flags.base !== pinned) {
    const want = pinned === '' ? 'the working tree (no --base)' : `--base ${pinned}`;
    throw new UsageError(`--base ${flags.base} conflicts with ${BASE_ENV}: the run that set it reads its allowlist from ${want}`);
  }
  return pinned === '' ? undefined : pinned;
}

// With SELVEDGE_RUN_DIR set, a --run-dir naming another folder is a usage error: each call is
// counted (budget and plan_time_actions) in the run folder the caller was given.
export function pinnedRunDir(flags, env = process.env, cwd = process.cwd()) {
  if (!flags['run-dir'] || !env.SELVEDGE_RUN_DIR) return;
  const real = (p) => {
    try {
      return realpathSync(p);
    } catch {
      return p;
    }
  };
  const given = path.resolve(cwd, flags['run-dir']);
  const pinned = path.resolve(cwd, env.SELVEDGE_RUN_DIR);
  if (given !== pinned && real(given) !== real(pinned)) {
    throw new UsageError(`--run-dir ${flags['run-dir']} conflicts with SELVEDGE_RUN_DIR (${pinned}): every call is counted in that run folder`);
  }
}

// The resolved value of each {{NAME}} the steps use, as [{ name, value }] (empty values skipped).
export function placeholderValues(steps, env = process.env) {
  return placeholderNames(steps)
    .filter((n) => typeof env[n] === 'string' && env[n] !== '')
    .map((n) => ({ name: n, value: env[n] }));
}

// redactValues(text, secrets) → text with every secret value replaced by its `{{NAME}}`, longest
// value first, in one pass (a replacement is never re-scanned). Exact matches only: a page that
// shows the value transformed (escaped, cut, re-cased) is not caught.
export function redactValues(text, secrets) {
  if (typeof text !== 'string' || !secrets.length) return text;
  const sorted = [...secrets].sort((a, b) => b.value.length - a.value.length);
  const byValue = new Map();
  for (const s of sorted) if (!byValue.has(s.value)) byValue.set(s.value, s.name);
  const re = new RegExp([...byValue.keys()].map((v) => v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'g');
  return text.replace(re, (m) => `{{${byValue.get(m)}}}`);
}

// The Playwright locator for a plan-step locator (role / label / text / testid; never CSS).
function locate(page, loc) {
  if ('role' in loc) {
    const opts = {};
    if ('name' in loc) opts.name = loc.name;
    if ('exact' in loc) opts.exact = loc.exact;
    return page.getByRole(loc.role, opts);
  }
  if ('label' in loc) return page.getByLabel(loc.label);
  if ('text' in loc) return page.getByText(loc.text);
  return page.getByTestId(loc.testid);
}

// Navigate, and fail on an HTTP error status (naming the guard's reason when the guard refused it).
async function navigate(page, url) {
  const response = await page.goto(url);
  if (response && response.status() >= 400) {
    const reason = reasonOfResponse(response);
    throw new Error(`${url} answered HTTP ${response.status()}${reason ? ` (the guard refused it: ${reason})` : ''}`);
  }
}

// Run one validated, resolved prefix step. Playwright's strict mode makes a locator that matches
// more than one element fail the step, as a locator matching nothing does (after the timeout).
async function runStep(page, step) {
  switch (step.type) {
    case 'goto':
      await navigate(page, step.url);
      return;
    case 'click':
      await locate(page, step.locator).click();
      return;
    case 'fill':
      await locate(page, step.locator).fill(step.value);
      return;
    case 'select':
      await locate(page, step.locator).selectOption(step.value);
      return;
    case 'check':
      await locate(page, step.locator).setChecked(step.checked !== false);
      return;
    case 'press':
      if (step.locator) await locate(page, step.locator).press(step.key);
      else await page.keyboard.press(step.key);
      return;
    case 'wait_for':
      await locate(page, step.locator).waitFor({ state: step.state });
      return;
    default:
      // validateSteps (prefix mode) admits nothing else; refuse rather than skip.
      throw new Error(`step type ${JSON.stringify(step.type)} cannot run in a snapshot prefix`);
  }
}

// The prefix file: a JSON array of steps, or plan_invalid problems when it cannot be read as one.
function readPrefix(file, cwd) {
  const at = path.resolve(cwd, file);
  let raw;
  try {
    raw = readFileSync(at, 'utf8');
  } catch (e) {
    return { problems: [{ index: null, code: 'plan_schema_violation', detail: `cannot read ${file}: ${e && e.code ? e.code : firstLine(e)}` }] };
  }
  let steps;
  try {
    steps = JSON.parse(raw);
  } catch (e) {
    return { problems: [{ index: null, code: 'plan_schema_violation', detail: `${file} is not valid JSON: ${firstLine(e)}` }] };
  }
  if (!Array.isArray(steps)) return { problems: [{ index: null, code: 'plan_schema_violation', detail: `${file} must hold a JSON array of steps` }] };
  return { steps };
}

// runSnapshot(argv, { cwd, env }) → Promise<{ code, stdout, stderr }>. The CLI writes the two
// streams and exits with `code`; a test can call it more than once in one process.
export async function runSnapshot(argv, { cwd = process.cwd(), env = process.env } = {}) {
  const out = [];
  const errs = [];
  const say = (line) => out.push(`${line}\n`);
  const warn = (line) => errs.push(`selvedge snapshot: ${line}\n`);
  // Every resolved {{NAME}} value, once known. stdout's JSON is redacted field by field before it
  // is printed (a raw pass could corrupt the JSON itself, e.g. a value "1"); stderr on the way out.
  const secrets = [];
  const done = (code) => ({ code, stdout: out.join(''), stderr: redactValues(errs.join(''), secrets) });

  let flags;
  let positional;
  let budget;
  let base;
  try {
    ({ flags, positional } = parseCliArgs(argv, { values: ['steps', 'run-dir', 'base'] }));
    if (positional.length !== 1) throw new UsageError(positional.length ? `unexpected argument: ${positional[1]}` : 'snapshot needs a <url>');
    if (!flags['run-dir'] && !env.SELVEDGE_RUN_DIR) {
      throw new UsageError('--run-dir <dir> (or SELVEDGE_RUN_DIR) is required: the snapshot budget is counted per run folder');
    }
    pinnedRunDir(flags, env, cwd);
    base = pinnedBase(flags, env);
    budget = snapshotBudget(env);
  } catch (e) {
    if (!(e instanceof UsageError)) throw e;
    warn(e.message);
    errs.push(`\n${USAGE}\n`);
    return done(2);
  }

  const url = positional[0];
  const runDir = path.resolve(cwd, flags['run-dir'] || env.SELVEDGE_RUN_DIR);
  try {
    mkdirSync(runDir, { recursive: true });
  } catch (e) {
    warn(`cannot create the run folder ${runDir}: ${firstLine(e)}`);
    return done(1);
  }

  const record = {
    ts: new Date().toISOString(),
    origin: originOf(url),
    prefix_steps: [],
    plan_time_actions: 0,
    browser_launched: false,
    outcome: OUTCOMES.failed,
    failed_step: null,
  };

  let code;
  try {
    code = await snapshotIn({ url, flags, base, runDir, budget, cwd, env, record, secrets, say, warn });
  } catch (e) {
    if (e instanceof EnvError) {
      if (e.blocked) say(`BLOCKED ${e.reason}`);
      warn(`${e.reason}: ${e.message}`);
      record.outcome = e.blocked ? OUTCOMES.blocked : OUTCOMES.invalid;
      code = 2;
    } else {
      warn(firstLine(e));
      record.outcome = OUTCOMES.failed;
      code = 1;
    }
  }

  try {
    appendFileSync(path.join(runDir, SNAPSHOTS_FILE), `${JSON.stringify(record)}\n`);
  } catch (e) {
    warn(`cannot record the call in ${path.join(runDir, SNAPSHOTS_FILE)}: ${firstLine(e)}`);
    code = 1;
  }
  return done(code);
}

async function snapshotIn({ url, flags, base, runDir, budget, cwd, env, record, secrets, say, warn }) {
  const blocked = (reason, message) => new EnvError(reason, message, { blocked: true });

  // The prefix as given (what snapshots.jsonl records), then the allowlist it is checked against.
  let steps = [];
  let readProblems = [];
  if (flags.steps !== undefined) {
    const read = readPrefix(flags.steps, cwd);
    if (read.problems) readProblems = read.problems;
    else steps = read.steps;
  }
  record.prefix_steps = steps;
  const { config, root, source } = loadConfig({ cwd, base });

  // 1. the prefix: the one step validator, prefix mode. An unlisted goto is the origin check's.
  const problems = readProblems.length ? readProblems : validateSteps(steps, { config, prefix: true });
  if (problems.some((p) => p.code !== ORIGIN_PROBLEM)) {
    for (const p of problems) warn(problemLine({ id: PREFIX_SCOPE, code: p.code, detail: p.detail }));
    warn(`${problems.length} problem(s) in the prefix ${flags.steps}; nothing was launched`);
    record.outcome = OUTCOMES.invalid;
    return 2;
  }

  // 2. the url's origin, before any browser exists.
  if (!isOriginAllowed(config, url)) {
    throw blocked(REASONS.host_not_allowed, `${url}: origin ${record.origin || '(none)'} is not in selvedge.json's origins (config source: ${source}); nothing was launched`);
  }

  // 3. every prefix goto's origin, before any browser exists.
  for (const [i, step] of steps.entries()) {
    if (step.type === 'goto' && !isOriginAllowed(config, step.url)) {
      throw blocked(REASONS.host_not_allowed, `steps[${i}].url ${JSON.stringify(step.url)}: origin ${originOf(step.url) || '(none)'} is not in selvedge.json's origins; nothing was launched`);
    }
  }

  // 4. {{NAME}} values: an unset name is BLOCKED (never an empty string). `resolved` is used to
  //    drive the page only; the record keeps `steps`.
  const resolved = resolvePlaceholders(steps, env);
  secrets.push(...placeholderValues(steps, env));

  // 5. Playwright.
  const pw = await resolvePlaywright({ root, env, cwd });
  warn(`playwright ${pw.version || '(version unknown)'} from ${pw.source} (${pw.path})`);

  // 6. the budget (exit 3; precedence keeps every exit-2 check above it).
  const used = recordedCalls(runDir);
  if (used >= budget) {
    say(`NOT_VERIFIABLE ${REASONS.exploration_budget}`);
    warn(`${REASONS.exploration_budget}: ${used} snapshot call(s) already recorded in ${path.join(runDir, SNAPSHOTS_FILE)}; the budget is ${budget} (${BUDGET_ENV}); nothing was launched`);
    record.outcome = OUTCOMES.not_verifiable;
    return 3;
  }

  // 7. a fresh guarded browser and context for this call alone.
  const chromium = {
    launch: async (options) => {
      const browser = await pw.chromium.launch(options);
      record.browser_launched = true;
      return browser;
    },
  };
  const result = { schema_version: SNAPSHOT_SCHEMA_VERSION, url, steps_run: 0, failed_step: null, error: null, aria_snapshot: null };
  const guard = await openGuardedContext({ chromium, config });
  try {
    const { page } = guard;
    page.setDefaultTimeout(STEP_TIMEOUT_MS);
    page.setDefaultNavigationTimeout(NAVIGATION_TIMEOUT_MS);
    try {
      await navigate(page, url);
    } catch (e) {
      result.error = firstLine(e);
    }
    if (result.error === null) {
      for (const [i, step] of resolved.entries()) {
        if (ACTION_TYPES.includes(step.type)) record.plan_time_actions += 1;
        try {
          await runStep(page, step);
          result.steps_run += 1;
        } catch (e) {
          result.failed_step = i;
          result.error = firstLine(e);
          break;
        }
      }
    }
    try {
      result.aria_snapshot = await page.locator('body').ariaSnapshot({ timeout: STEP_TIMEOUT_MS });
    } catch (e) {
      if (result.error === null) result.error = firstLine(e);
    }
  } finally {
    await guard.close();
  }

  if (guard.blocks.length) {
    const seen = [...new Set(guard.blocks.map((b) => `${b.reason} ${b.host}`))];
    warn(`the guard refused ${guard.blocks.length} request(s): ${seen.join(', ')}`);
  }
  // Redacted field by field before JSON escaping, so a value holding a quote or a backslash is
  // still found. url is the caller's own argument (it holds no {{NAME}}).
  result.aria_snapshot = result.aria_snapshot === null ? null : redactValues(result.aria_snapshot, secrets);
  result.error = result.error === null ? null : redactValues(result.error, secrets);
  say(JSON.stringify(result, null, 2));
  if (result.failed_step !== null) {
    record.failed_step = result.failed_step;
    record.outcome = OUTCOMES.step_failed;
    return 1;
  }
  if (result.error !== null) {
    record.outcome = OUTCOMES.failed;
    return 1;
  }
  record.outcome = OUTCOMES.ok;
  return 0;
}

async function main(argv) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    process.stderr.write(`selvedge snapshot: needs Node.js >= 18 (this is ${process.versions.node})\n`);
    return 1;
  }
  if (['help', '-h', '--help'].includes(argv[0])) {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }
  let r;
  try {
    r = await runSnapshot(argv);
  } catch (e) {
    process.stderr.write(`selvedge snapshot: ${firstLine(e)}\n`);
    return 1;
  }
  process.stdout.write(r.stdout);
  process.stderr.write(r.stderr);
  return r.code;
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
