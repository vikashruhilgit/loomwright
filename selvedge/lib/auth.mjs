// auth.mjs — `selvedge auth setup [--headed] [--base <ref>]`, run by selvedge/bin/selvedge.
//
// Signs in to the app under test once, outside the model, and keeps the session (a Playwright storage
// state) at auth-state.mjs authStatePath — $HOME/.local/state/selvedge/<repo-id>/auth/storageState.json,
// dir 0700, file 0600, never inside the repo — for `selvedge run` to load.
//
//   setup            the scripted path. In order: load selvedge.json (working tree, or --base <ref>);
//                    every origin local, else BLOCKED env_hooks_remote_origin; every `auth.env` name
//                    set, else BLOCKED placeholder_unset naming the names (never a value); create the
//                    state directory 0700 (refused, exit 1, when it resolves inside the repo); run the
//                    approved hook through `selvedge env hook auth_setup` with SELVEDGE_STORAGE_STATE
//                    set to a temp path beside the state file (its exit 2 and `BLOCKED <reason>` line
//                    are passed through; any other failure is exit 1); the hook's file must be a
//                    regular file holding a storage state Playwright loads (auth-state.mjs
//                    stateFileProblem, the check `run` makes too), else exit 1 with nothing kept; then
//                    it is made 0600 and renamed into place. The credentials reach the hook through the
//                    environment it inherits; selvedge never reads, prints or stores a value.
//   setup --headed   a human signs in: needs `auth.signed_in_check` (validateSignedInCheck first, so a
//                    CSS locator is config_schema_violation before anything launches), opens the
//                    guarded browser headed at its URL, waits up to SELVEDGE_AUTH_TIMEOUT_MS (default
//                    300000) for its locator to match at least one element, then writes the context's
//                    storage state 0600. No hook runs and no credential passes through selvedge.
//
// Exit codes (as every selvedge command): 0 ok, 1 an operation failed, 2 usage error or BLOCKED (a
// BLOCKED outcome prints a stdout line `BLOCKED <reason>`; a config reason is named on stderr).
//
// Node >= 18, standard library only (Playwright is resolved at run time).
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { chmodSync, lstatSync, renameSync, rmSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS, UsageError, isLocalOrigin, isMain, loadConfig, parseCliArgs } from './env-config.mjs';
import { writePrivateFileAtomic } from './env-approvals.mjs';
import { FILE_MODE, STORAGE_STATE_ENV, ensureStateDir, stateFileProblem, usableStatePath, validateSignedInCheck } from './auth-state.mjs';
import { SELVEDGE_BIN } from './plan.mjs';
import { firstLine, resolvePlaywright } from './snapshot-playwright.mjs';
import { openGuardedContext } from './runner/route-guard.mjs';
import { locate } from './runner/steps.mjs';

export const AUTH_TIMEOUT_ENV = 'SELVEDGE_AUTH_TIMEOUT_MS';
export const DEFAULT_AUTH_TIMEOUT_MS = 300000;
const POLL_MS = 250;

const BLOCKED_LINE = /^BLOCKED ([a-z_]+)$/m;

const USAGE = `Usage: selvedge auth setup [--headed] [--base <ref>]

  setup            run the approved hooks.auth_setup (credentials only from the env vars auth.env
                   names) and keep the session it writes to $${STORAGE_STATE_ENV} at
                   $HOME/.local/state/selvedge/<repo-id>/auth/storageState.json (dir 0700, file 0600)
  setup --headed   open the guarded browser at auth.signed_in_check.url, wait for you to sign in
                   (up to ${AUTH_TIMEOUT_ENV}, default ${DEFAULT_AUTH_TIMEOUT_MS}) until its locator
                   matches, and keep that session there; no hook and no credential pass through selvedge
  --base <ref>     read the committed <ref>:selvedge.json instead of the working tree

Exit codes: 0 ok, 1 an operation failed, 2 usage error or BLOCKED (a named reason on its own line).`;

function err(line) {
  process.stderr.write(`selvedge auth: ${line}\n`);
}

function out(line) {
  process.stdout.write(`${line}\n`);
}

function blocked(reason, message) {
  out(`BLOCKED ${reason}`);
  err(`${reason}: ${message}`);
  return 2;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The sign-in wait from SELVEDGE_AUTH_TIMEOUT_MS (a positive whole number of ms), else the default.
export function authTimeoutMs(env = process.env) {
  const raw = env[AUTH_TIMEOUT_ENV];
  if (raw === undefined || raw === '') return DEFAULT_AUTH_TIMEOUT_MS;
  if (!/^[0-9]+$/.test(raw) || Number(raw) < 1) throw new UsageError(`${AUTH_TIMEOUT_ENV} must be a positive whole number of milliseconds (got ${JSON.stringify(raw)})`);
  return Number(raw);
}

// The state path with its directory created 0700, or throws an Error (exit 1) when it cannot be used.
function prepareStatePath(root) {
  const { file, error } = usableStatePath({ root });
  if (error) throw new Error(`${error}; nothing was written`);
  ensureStateDir(file);
  return file;
}

function tempBeside(file, suffix) {
  return path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.${randomBytes(6).toString('hex')}${suffix}`);
}

// Writes `data` to `file` atomically, mode exactly 0600 whatever the umask (the one writer the
// approvals store uses too, env-approvals.mjs writePrivateFileAtomic).
function writeStateFile(file, data) {
  writePrivateFileAtomic(file, `${JSON.stringify(data)}\n`, { exactMode: true });
}

// ---- auth setup (the hook) ---------------------------------------------------------------------
function setupWithHook({ config, root, base }) {
  const remote = config.origins.filter((o) => !isLocalOrigin(o));
  if (remote.length) {
    return blocked(REASONS.env_hooks_remote_origin, `hooks never run while an origin is remote (${remote.join(', ')}); nothing was written`);
  }
  const names = config.auth ? config.auth.env : [];
  const unset = names.filter((n) => process.env[n] === undefined);
  if (unset.length) throw new EnvError(REASONS.placeholder_unset, `unset: ${unset.join(', ')} (auth.env names them; set each in the environment); the hook did not run`, { blocked: true });

  const file = prepareStatePath(root);
  const tmp = tempBeside(file, '.json');
  const args = [SELVEDGE_BIN, 'env', 'hook', 'auth_setup'];
  if (base !== undefined) args.push('--base', base);
  const res = spawnSync('bash', args, {
    cwd: root,
    env: { ...process.env, [STORAGE_STATE_ENV]: tmp },
    encoding: 'utf8',
    stdio: ['inherit', 'pipe', 'inherit'],
    maxBuffer: 16 * 1024 * 1024,
  });
  const hookOut = String(res.stdout || '');
  const m = res.status === 2 ? BLOCKED_LINE.exec(hookOut) : null; // `env hook`'s own outcome line
  for (const l of hookOut.split('\n')) if (l.trim() !== '' && !(m && l === m[0])) err(`hook auth_setup: ${l}`);
  try {
    if (res.error) throw new Error(`hook auth_setup could not start: ${res.error.message}`);
    if (res.status === 2) return blocked(m && Object.values(REASONS).includes(m[1]) ? m[1] : REASONS.env_hooks_unapproved, 'the auth_setup hook did not run; nothing was written');
    if (res.status !== 0) throw new Error(`hook auth_setup failed (${res.signal ? `signal ${res.signal}` : `exit ${res.status}`}); nothing was written`);
    let st;
    try {
      st = lstatSync(tmp);
    } catch {
      throw new Error(`the auth_setup hook exited 0 but wrote nothing to $${STORAGE_STATE_ENV}; nothing was written`);
    }
    if (!st.isFile()) throw new Error(`$${STORAGE_STATE_ENV} is not a regular file after the hook (a symlink or a directory is never kept); nothing was written`);
    const problem = stateFileProblem(tmp); // the same check `run` makes before it loads the file
    if (problem) throw new Error(`the file the hook wrote to $${STORAGE_STATE_ENV} ${problem}; nothing was written`);
    chmodSync(tmp, FILE_MODE);
    renameSync(tmp, file);
  } finally {
    rmSync(tmp, { force: true });
  }
  out(`selvedge auth: saved the session to ${file} (mode 0600)`);
  return 0;
}

// ---- auth setup --headed -----------------------------------------------------------------------
async function setupHeaded({ config, root }) {
  if (!config.auth || !config.auth.signed_in_check) {
    throw new UsageError('--headed needs "auth.signed_in_check" in selvedge.json (the page and locator that show you are signed in)');
  }
  validateSignedInCheck(config);
  const timeoutMs = authTimeoutMs();
  const file = prepareStatePath(root);
  const { url, locator } = config.auth.signed_in_check;

  const pw = await resolvePlaywright({ root, env: process.env, cwd: process.cwd() });
  err(`playwright ${pw.version || '(version unknown)'} from ${pw.source} (${pw.path})`);
  const guarded = await openGuardedContext({ chromium: pw.chromium, config, headed: true });
  try {
    try {
      await guarded.page.goto(url);
    } catch (e) {
      throw new Error(`could not open ${url}: ${firstLine(e)}; nothing was written`);
    }
    err(`sign in in the browser window; waiting up to ${timeoutMs} ms for ${JSON.stringify(locator)} to match at ${url}`);
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      let n = 0;
      try {
        n = await locate(guarded.page, locator).count();
      } catch {
        n = 0; // the page was navigating; look again
      }
      if (n > 0) break;
      if (typeof guarded.page.isClosed === 'function' && guarded.page.isClosed()) {
        throw new Error('the browser window was closed before the sign-in check matched; nothing was written');
      }
      if (Date.now() >= deadline) {
        throw new Error(`the sign-in check did not match within ${timeoutMs} ms (${AUTH_TIMEOUT_ENV}); nothing was written`);
      }
      await sleep(POLL_MS);
    }
    writeStateFile(file, await guarded.context.storageState());
  } finally {
    await guarded.close();
  }
  out(`selvedge auth: saved the session to ${file} (mode 0600)`);
  return 0;
}

async function main(argv) {
  const [cmd, ...rest] = argv;
  try {
    switch (cmd) {
      case 'setup': {
        const { flags, positional } = parseCliArgs(rest, { values: ['base'], booleans: ['headed'] });
        if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
        const { config, root, source } = loadConfig({ base: flags.base });
        err(`config source: ${source}`);
        if (flags.headed) return await setupHeaded({ config, root });
        if (!Object.prototype.hasOwnProperty.call(config.hooks, 'auth_setup')) {
          throw new UsageError('selvedge.json has no "hooks.auth_setup"; add one (and approve it with `selvedge env approve`), or sign in yourself with `selvedge auth setup --headed`');
        }
        return setupWithHook({ config, root, base: flags.base });
      }
      case 'help': case '-h': case '--help':
        out(USAGE);
        return 0;
      case undefined:
        process.stderr.write(`${USAGE}\n`);
        return 2;
      default:
        throw new UsageError(`unknown auth command: ${cmd}`);
    }
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof EnvError) {
      if (e.blocked) return blocked(e.reason, e.message);
      err(`${e.reason}: ${e.message}`);
      return 2;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
