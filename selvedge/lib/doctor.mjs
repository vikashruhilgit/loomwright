// doctor.mjs — `selvedge doctor`, run by selvedge/bin/selvedge: is this machine and repo ready for a
// first `selvedge run`? One line per check, `ok <check>` or `FAIL <check>: <one-line fix>`; exit 0
// when every check passes, 1 when any fails, 2 on a usage error.
//
// This file is the only list of checks. Each one asks the helper the real command uses, so the
// doctor cannot drift from what `run`, `snapshot` and `plan` do:
//   Node >= 18          process.versions (bin/selvedge already refused a missing or older Node in
//                       bash, before this file could load, and printed the same FAIL line there)
//   Playwright library  resolvePlaywright (snapshot-playwright.mjs): SELVEDGE_PLAYWRIGHT_MODULE,
//                       else the repo's own node_modules, exactly as `run` finds it
//   Chromium browser    that Playwright's chromium.executablePath() exists on disk
//   selvedge.json       loadConfig (env-config.mjs): present, valid JSON, valid schema
//   hook approvals      approvalState (env-approvals.mjs); "no hooks" when there are none
//   planner             SELVEDGE_PLANNER set, else `claude` on PATH (PLANNER_ENV / CLAUDE_BIN,
//                       plan-planner.mjs)
// The app being up is not checked: the quick start starts it after the doctor.
//
// Node >= 18, standard library only.
import { accessSync, constants, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { EnvError, isMain, loadConfig, repoRoot } from './env-config.mjs';
import { approvalState } from './env-approvals.mjs';
import { CLAUDE_BIN, PLANNER_ENV } from './plan-planner.mjs';
import { PLAYWRIGHT_MODULE_ENV, firstLine, resolvePlaywright } from './snapshot-playwright.mjs';

const MIN_NODE_MAJOR = 18;

const USAGE = `Usage: selvedge doctor

Checks, one line each (ok, or FAIL with the one fix): Node >= ${MIN_NODE_MAJOR}, the Playwright library (as
\`run\` finds it), its Chromium browser, selvedge.json, hook approvals, and the planner. Run it at
the root of the repo you check (any folder inside it works).

Exit codes: 0 every check ok, 1 a check failed, 2 usage error.`;

// The executable `name` on `pathVar` (a PATH string), or null.
function onPath(name, pathVar) {
  for (const dir of String(pathVar || '').split(path.delimiter)) {
    if (dir === '') continue;
    const file = path.join(dir, name);
    try {
      if (!statSync(file).isFile()) continue;
      accessSync(file, constants.X_OK);
      return file;
    } catch {
      // not here
    }
  }
  return null;
}

function checkNode() {
  const v = String(process.versions.node);
  const major = Number(v.split('.')[0]);
  if (major >= MIN_NODE_MAJOR) return { ok: true, name: `Node >= ${MIN_NODE_MAJOR}`, detail: v };
  return { ok: false, name: `Node >= ${MIN_NODE_MAJOR}`, fix: `install Node.js >= ${MIN_NODE_MAJOR} (this is ${v})` };
}

async function checkPlaywright({ root, env, cwd }) {
  const name = 'Playwright library';
  try {
    const pw = await resolvePlaywright({ root, env, cwd });
    const where = pw.source === PLAYWRIGHT_MODULE_ENV ? PLAYWRIGHT_MODULE_ENV : 'this repo';
    return { result: { ok: true, name, detail: `${pw.version || 'version unknown'}, from ${where}` }, pw };
  } catch (e) {
    const fix = env[PLAYWRIGHT_MODULE_ENV]
      ? `${PLAYWRIGHT_MODULE_ENV} does not load (${firstLine(e)}); fix it or unset it, then run npm i -D playwright in ${root}`
      : `npm i -D playwright (in ${root})`;
    return { result: { ok: false, name, fix }, pw: null };
  }
}

function checkBrowser(pw) {
  const name = 'Chromium browser';
  if (!pw) return { ok: false, name, fix: 'npx playwright install chromium (after the Playwright library above is installed)' };
  let exe = null;
  try {
    exe = typeof pw.chromium.executablePath === 'function' ? pw.chromium.executablePath() : null;
  } catch (e) {
    return { ok: false, name, fix: `npx playwright install chromium (this Playwright reports no browser path: ${firstLine(e)})` };
  }
  if (typeof exe !== 'string' || exe === '') {
    return { ok: false, name, fix: 'npx playwright install chromium (this Playwright reports no browser path)' };
  }
  if (!existsSync(exe)) return { ok: false, name, fix: `npx playwright install chromium (not found: ${exe})` };
  return { ok: true, name, detail: exe };
}

function checkConfig(cwd) {
  const name = 'selvedge.json';
  try {
    const loaded = loadConfig({ cwd });
    return { result: { ok: true, name, detail: loaded.config.origins.join(', ') }, loaded };
  } catch (e) {
    if (!(e instanceof EnvError)) throw e;
    const fix = e.reason === 'config_absent'
      ? 'run selvedge env init --port <N> (N: the port your app serves on)'
      : `${e.reason}: ${firstLine(e)}; fix it, or move it aside and run selvedge env init --port <N>`;
    return { result: { ok: false, name, fix }, loaded: null };
  }
}

function checkApprovals(loaded, env) {
  const name = 'hook approvals';
  if (!loaded) return { ok: true, name, detail: 'no hooks: no valid selvedge.json yet' };
  const st = approvalState({ root: loaded.root, hooks: loaded.config.hooks, env });
  if (st.state === 'no hooks') return { ok: true, name, detail: 'no hooks' };
  if (st.state === 'approved') return { ok: true, name, detail: 'approved' };
  return { ok: false, name, fix: `run selvedge env approve in a terminal and read each hook first${st.detail ? ` (${st.detail})` : ''}` };
}

function checkPlanner(env) {
  const name = 'planner';
  // The same test `plan` applies: a blank SELVEDGE_PLANNER is unset, and `claude` is the planner.
  const command = env[PLANNER_ENV];
  if (typeof command === 'string' && command.trim() !== '') return { ok: true, name, detail: `${PLANNER_ENV} is set` };
  const found = onPath(CLAUDE_BIN, env.PATH);
  if (found) return { ok: true, name, detail: `${CLAUDE_BIN} at ${found}` };
  return { ok: false, name, fix: `install Claude Code (the ${CLAUDE_BIN} CLI) and sign in, or set SELVEDGE_PLANNER to your own planner command` };
}

function line(r) {
  return r.ok ? `ok ${r.name}${r.detail ? ` (${r.detail})` : ''}` : `FAIL ${r.name}: ${r.fix}`;
}

async function main(argv, { env = process.env, cwd = process.cwd() } = {}) {
  if (argv[0] === 'help' || argv[0] === '-h' || argv[0] === '--help') {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }
  if (argv.length > 0) {
    process.stderr.write(`selvedge doctor: takes no arguments (got ${argv[0]})\n\n${USAGE}\n`);
    return 2;
  }
  const root = repoRoot(cwd) || cwd;
  const results = [checkNode()];
  const pw = await checkPlaywright({ root, env, cwd });
  results.push(pw.result, checkBrowser(pw.pw));
  const cfg = checkConfig(cwd);
  results.push(cfg.result, checkApprovals(cfg.loaded, env), checkPlanner(env));
  for (const r of results) process.stdout.write(`${line(r)}\n`);
  return results.every((r) => r.ok) ? 0 : 1;
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
