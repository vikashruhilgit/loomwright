// env.mjs — `selvedge env check|init|approve|hook`, run by selvedge/bin/selvedge.
//
// Exit codes (00-plan D7): 0 ok, 1 an operation failed, 2 usage error or BLOCKED. A BLOCKED outcome
// prints a stdout line `BLOCKED <reason>`; a config/usage problem names its reason on stderr. Every
// reason comes from REASONS in env-config.mjs.
//
// Node >= 18, standard library only.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { closeSync, lstatSync, openSync, readFileSync, writeSync } from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { CONFIG_FILE, EnvError, HOOK_KEYS, REASONS, isLocalOrigin, loadConfig, repoRoot } from './env-config.mjs';
import { approvalState, hooksSha256, writeApproval } from './env-approvals.mjs';

const MIN_NODE_MAJOR = 18;

const USAGE = `Usage: selvedge env <command>

Commands:
  check [--base <ref>]     validate selvedge.json and report the hook approval state; with --base,
                           read the committed <ref>:selvedge.json instead of the working tree
  init [--port <N>]        write a local-only selvedge.json (http://localhost:<N>); never overwrites
  approve [--base <ref>]   show the hooks and their sha256, and record your approval (needs a TTY)
  hook <name> [--base <ref>]
                           run an approved hook (${HOOK_KEYS.join(', ')}) at the repo root; only
                           when every origin is local

Exit codes: 0 ok, 1 an operation failed, 2 usage error or BLOCKED (a named reason on its own line).`;

const SCOPE_LINE =
  "scope: the guard covers the browser only; the verifier's shell is not behind the proxy (hooks and shell commands are not contained)";

class UsageError extends Error {}

function err(line) {
  process.stderr.write(`selvedge env: ${line}\n`);
}

// A config/usage reason: stderr, exit 2.
function failReason(reason, message) {
  err(`${reason}: ${message}`);
  return 2;
}

// A BLOCKED outcome: `BLOCKED <reason>` on stdout, the detail on stderr, exit 2.
function blocked(reason, message) {
  process.stdout.write(`BLOCKED ${reason}\n`);
  err(`${reason}: ${message}`);
  return 2;
}

function out(line = '') {
  process.stdout.write(`${line}\n`);
}

// Parse `[--base <ref>]` / `[--port <N>]` style flags; positional args are returned in order.
function parseArgs(args, allowed) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    const eq = a.indexOf('=');
    const name = a.startsWith('--') ? (eq > 0 ? a.slice(2, eq) : a.slice(2)) : null;
    if (name === null) {
      positional.push(a);
      continue;
    }
    if (!allowed.includes(name)) throw new UsageError(`unknown option --${name}`);
    let value;
    if (eq > 0) {
      value = a.slice(eq + 1);
    } else {
      i += 1;
      if (i >= args.length) throw new UsageError(`--${name} needs a value`);
      value = args[i];
    }
    if (value === '') throw new UsageError(`--${name} needs a value`);
    flags[name] = value;
  }
  return { flags, positional };
}

function hasTty() {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

// One line from stdin (no raw mode: the line discipline delivers it), or null at EOF.
async function readLine() {
  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  try {
    for await (const line of rl) return line;
    return null;
  } finally {
    rl.close();
    process.stdin.pause();
  }
}

function hookApprovalLine(state) {
  if (state.state === 'unapproved') {
    return `hook approval: unapproved (${state.detail}; run \`selvedge env approve\`)`;
  }
  return `hook approval: ${state.state}`;
}

// ---- env check ---------------------------------------------------------------------------------
function cmdCheck(args) {
  const { flags, positional } = parseArgs(args, ['base']);
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  const { config, root, source } = loadConfig({ base: flags.base });
  const state = approvalState({ root, hooks: config.hooks });
  out(`config source: ${source}`);
  out('origins:');
  for (const o of config.origins) out(`  ${o} (${isLocalOrigin(o) ? 'local' : 'remote'})`);
  out(`allow_remote: ${config.allow_remote}`);
  out(`allow_remote_mutation: ${config.allow_remote_mutation}`);
  const names = Object.keys(config.hooks).sort();
  out(`hooks: ${names.length ? names.join(', ') : 'none'}`);
  for (const n of names) out(`  ${n}: ${JSON.stringify(config.hooks[n])}`);
  if (names.length) out(`hooks sha256: ${state.sha256}`);
  out(hookApprovalLine(state));
  if (names.length && config.origins.some((o) => !isLocalOrigin(o))) {
    out('note: hooks never run while any origin is remote');
  }
  out(SCOPE_LINE);
  out('env check: ok');
  return 0;
}

// ---- env init ----------------------------------------------------------------------------------
function validPort(s) {
  if (typeof s !== 'string' || !/^[0-9]{1,5}$/.test(s)) return null;
  const n = Number(s);
  return n >= 1 && n <= 65535 ? n : null;
}

// A port named in package.json scripts.dev or scripts.start: `--port N`, `--port=N`, `-p N`, `PORT=N`.
function detectPort(dir) {
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(path.join(dir, 'package.json'), 'utf8'));
  } catch {
    return null;
  }
  const scripts = pkg && typeof pkg.scripts === 'object' && pkg.scripts ? pkg.scripts : {};
  for (const key of ['dev', 'start']) {
    const s = scripts[key];
    if (typeof s !== 'string') continue;
    const m = s.match(/(?:--port(?:=|\s+)|(?:^|\s)-p\s+|(?:^|\s)PORT=)([0-9]{1,5})(?![0-9])/);
    if (m && validPort(m[1]) !== null) return { port: validPort(m[1]), from: `package.json scripts.${key}` };
  }
  return null;
}

async function cmdInit(args) {
  const { flags, positional } = parseArgs(args, ['port']);
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  const dir = repoRoot() || process.cwd();
  const file = path.join(dir, CONFIG_FILE);
  let exists = true;
  try {
    lstatSync(file);
  } catch {
    exists = false;
  }
  if (exists) {
    err(`refusing to overwrite ${file}: it already exists (edit it, or move it aside and re-run)`);
    return 1;
  }

  let port = null;
  let from = '';
  if (flags.port !== undefined) {
    port = validPort(flags.port);
    if (port === null) throw new UsageError(`--port must be a number from 1 to 65535 (got ${JSON.stringify(flags.port)})`);
    from = '--port';
  } else {
    const found = detectPort(dir);
    if (found) {
      ({ port, from } = found);
    } else if (hasTty()) {
      process.stdout.write('selvedge env init: the local port your app listens on: ');
      const answer = await readLine();
      port = validPort(answer === null ? '' : answer.trim());
      from = 'prompt';
    }
  }
  if (port === null) {
    return failReason(
      REASONS.port_required,
      'no port given or detected; pass --port <N> (no --port/-p/PORT= found in package.json scripts.dev or scripts.start)',
    );
  }

  const config = {
    schema_version: 1,
    origins: [`http://localhost:${port}`],
    allow_remote: false,
    allow_remote_mutation: false,
  };
  const fd = openSync(file, 'wx', 0o644); // 'wx': never replace a file that appeared meanwhile
  try {
    writeSync(fd, `${JSON.stringify(config, null, 2)}\n`);
  } finally {
    closeSync(fd);
  }
  out(`selvedge env: wrote ${file} (origin http://localhost:${port}, port from ${from})`);
  return 0;
}

// ---- env approve -------------------------------------------------------------------------------
async function cmdApprove(args) {
  const { flags, positional } = parseArgs(args, ['base']);
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  if (!hasTty()) {
    return failReason(REASONS.approve_requires_tty, 'approving hooks needs an interactive terminal; nothing was written');
  }
  const { config, root, source } = loadConfig({ base: flags.base });
  const names = Object.keys(config.hooks).sort();
  if (names.length === 0) {
    out('selvedge env: selvedge.json has no hooks; nothing to approve');
    return 0;
  }
  const state = approvalState({ root, hooks: config.hooks });
  out(`config source: ${source}`);
  out(`repo: ${state.identity}`);
  out('hooks (each runs as `bash -c <command>` at the repo root, with your permissions):');
  for (const n of names) {
    const cmd = config.hooks[n];
    const one = createHash('sha256').update(cmd, 'utf8').digest('hex');
    // JSON-quoted so control characters or escape sequences in a command cannot hide what runs.
    out(`  ${n}: ${JSON.stringify(cmd)}`);
    out(`    sha256: ${one}`);
  }
  out(`hooks sha256 (what is recorded): ${hooksSha256(config.hooks)}`);
  if (config.origins.some((o) => !isLocalOrigin(o))) out('note: hooks never run while any origin is remote');
  if (state.state === 'approved') {
    out('selvedge env: these hooks are already approved; nothing to do');
    return 0;
  }
  process.stdout.write('Approve these hooks for this repo? [y/N] ');
  const answer = await readLine();
  if (answer === null || !/^(y|yes)$/i.test(answer.trim())) {
    out('');
    out('selvedge env: not approved; nothing was written');
    return 1;
  }
  const file = writeApproval({ root, identity: state.identity, sha256: state.sha256 });
  out(`selvedge env: approved; recorded in ${file}`);
  return 0;
}

// ---- env hook ----------------------------------------------------------------------------------
function cmdHook(args) {
  const { flags, positional } = parseArgs(args, ['base']);
  if (positional.length !== 1) throw new UsageError(`env hook takes one hook name (${HOOK_KEYS.join(', ')})`);
  const name = positional[0];
  if (!HOOK_KEYS.includes(name)) throw new UsageError(`unknown hook: ${name} (one of ${HOOK_KEYS.join(', ')})`);
  const { config, root, source } = loadConfig({ base: flags.base });
  err(`config source: ${source}`);
  const remote = config.origins.filter((o) => !isLocalOrigin(o));
  if (remote.length) {
    return blocked(REASONS.env_hooks_remote_origin, `hooks never run while an origin is remote (${remote.join(', ')})`);
  }
  if (!Object.prototype.hasOwnProperty.call(config.hooks, name)) {
    out(`selvedge env: no ${name} hook in selvedge.json; nothing to run`);
    return 0;
  }
  const state = approvalState({ root, hooks: config.hooks });
  if (state.state !== 'approved') {
    return blocked(REASONS.env_hooks_unapproved, `${state.detail}; run \`selvedge env approve\` in a terminal`);
  }
  err(`running hook ${name} at ${root}`);
  const res = spawnSync('bash', ['-c', config.hooks[name]], { cwd: root, stdio: 'inherit' });
  if (res.error) {
    err(`hook ${name} could not start: ${res.error.message}`);
    return 1;
  }
  if (res.status !== 0) {
    err(`hook ${name} failed (${res.signal ? `signal ${res.signal}` : `exit ${res.status}`})`);
    return 1;
  }
  return 0;
}

async function main(argv) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= MIN_NODE_MAJOR)) {
    err(`needs Node.js >= ${MIN_NODE_MAJOR} (this is ${process.versions.node})`);
    return 1;
  }
  const [cmd, ...rest] = argv;
  try {
    switch (cmd) {
      case 'check': return cmdCheck(rest);
      case 'init': return await cmdInit(rest);
      case 'approve': return await cmdApprove(rest);
      case 'hook': return cmdHook(rest);
      case 'help': case '-h': case '--help':
        out(USAGE);
        return 0;
      case undefined:
        process.stderr.write(`${USAGE}\n`);
        return 2;
      default:
        throw new UsageError(`unknown env command: ${cmd}`);
    }
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof EnvError) return e.blocked ? blocked(e.reason, e.message) : failReason(e.reason, e.message);
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
process.exitCode = await main(process.argv.slice(2));
