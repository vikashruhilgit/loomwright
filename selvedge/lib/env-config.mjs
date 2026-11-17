// env-config.mjs — selvedge.json: origin parsing, the allowlist match, config load and validation,
// and the closed list of reasons every selvedge emitter (env, guard, criteria, plan, snapshot, run,
// verdict) names.
//
// This is the ONE origin parser. The env commands, the forward proxy and the browser route layer all
// import parseOrigin / isOriginAllowed from here; nothing re-implements them. Origins are compared as
// parsed exact values (scheme, host AND port) — never a regex, a suffix or a substring.
//
// Node >= 18, standard library only.
import { execFileSync } from 'node:child_process';
import { readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The closed reason list. Every emitter imports a value from here; no reason is a string literal
// anywhere else. BLOCKED reasons print as a stdout line `BLOCKED <reason>`; config/usage reasons print
// on stderr. Both exit 2. NOT_VERIFIABLE reasons print as a stdout line `NOT_VERIFIABLE <reason>` and
// exit 3 when a command ends on one; a plan also carries them per criterion under `not_planned`.
export const REASONS = Object.freeze({
  // BLOCKED outcomes
  host_not_allowed: 'host_not_allowed',
  remote_resolves_private: 'remote_resolves_private',
  remote_mutation_refused: 'remote_mutation_refused',
  proxy_loopback_disabled: 'proxy_loopback_disabled',
  proxy_unavailable: 'proxy_unavailable',
  env_hooks_unapproved: 'env_hooks_unapproved',
  env_hooks_remote_origin: 'env_hooks_remote_origin',
  playwright_unavailable: 'playwright_unavailable',
  placeholder_unset: 'placeholder_unset',
  step_failed: 'step_failed',
  stuck_screen: 'stuck_screen',
  budget_exceeded: 'budget_exceeded',
  run_interrupted: 'run_interrupted',
  needs_auth: 'needs_auth',
  // NOT_VERIFIABLE outcomes
  criterion_not_testable: 'criterion_not_testable',
  side_effect_not_observable: 'side_effect_not_observable',
  exploration_budget: 'exploration_budget',
  no_value_read: 'no_value_read',
  material_assumption: 'material_assumption',
  // config / usage reasons
  origins_empty: 'origins_empty',
  origin_invalid: 'origin_invalid',
  remote_origin_without_allow_remote: 'remote_origin_without_allow_remote',
  config_absent: 'config_absent',
  config_invalid_json: 'config_invalid_json',
  config_schema_violation: 'config_schema_violation',
  base_config_unreadable: 'base_config_unreadable',
  approve_requires_tty: 'approve_requires_tty',
  port_required: 'port_required',
  already_frozen: 'already_frozen',
  plan_invalid: 'plan_invalid',
  criteria_invalid: 'criteria_invalid',
  criteria_not_found: 'criteria_not_found',
  planner_failed: 'planner_failed',
  plan_modified: 'plan_modified',
  already_run: 'already_run',
  not_frozen: 'not_frozen',
  evidence_missing: 'evidence_missing',
});

export const CONFIG_FILE = 'selvedge.json';

// The validator's accepted key sets. selvedge/schemas/selvedge-config.schema.json declares the same
// names; selvedge/tests/test-env.sh asserts the two are equal (the schema is not read at run time, so
// the check is a real second copy, not a tautology).
export const CONFIG_KEYS = Object.freeze(['schema_version', 'origins', 'allow_remote', 'allow_remote_mutation', 'hooks', 'auth']);
export const HOOK_KEYS = Object.freeze(['seed', 'reset', 'auth_setup']);
export const AUTH_KEYS = Object.freeze(['env', 'signed_in_check']);
export const SIGNED_IN_CHECK_KEYS = Object.freeze(['url', 'locator']);

// An `auth.env` entry: the name of an environment variable (the same form as a plan's `{{NAME}}`).
export const ENV_NAME_PATTERN = '^[A-Z_][A-Z0-9_]*$';

const LOCAL_HOSTS = Object.freeze(['localhost', '127.0.0.1', '[::1]']);

// A failure carrying one of REASONS. `blocked` marks an outcome reported as `BLOCKED <reason>`.
export class EnvError extends Error {
  constructor(reason, message, { blocked = false } = {}) {
    super(message);
    this.name = 'EnvError';
    this.reason = reason;
    this.blocked = blocked;
  }
}

// parseOrigin('http://localhost:3000') → { origin, protocol, hostname, port } | null.
// Valid only when the string is exactly `scheme://host[:port]` with scheme http or https: it must
// parse as a URL, carry no userinfo, and serialize back to itself as a URL origin (so a path, a
// query, a fragment, a trailing slash, upper case, a default port written out or a non-canonical IP
// form are all refused). `port` is the effective port ('80' / '443' when the default applies).
export function parseOrigin(input) {
  if (typeof input !== 'string' || input === '') return null;
  let url;
  try {
    url = new URL(input);
  } catch {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  if (url.username !== '' || url.password !== '') return null;
  if (url.origin !== input) return null;
  const port = url.port !== '' ? url.port : (url.protocol === 'https:' ? '443' : '80');
  return Object.freeze({ origin: url.origin, protocol: url.protocol, hostname: url.hostname, port });
}

// The origin of any http(s) URL (a request URL, a redirect target, a CONNECT `https://host:port`).
function originOfUrl(candidate) {
  if (typeof candidate !== 'string') return null;
  let url;
  try {
    url = new URL(candidate);
  } catch {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  return parseOrigin(url.origin);
}

// True when the origin's host is localhost, 127.0.0.1 or [::1]. Takes an origin string or a
// parseOrigin result; anything unparsable is not local.
export function isLocalOrigin(origin) {
  const parsed = typeof origin === 'string' ? parseOrigin(origin) : origin;
  if (!parsed || typeof parsed.hostname !== 'string') return false;
  return LOCAL_HOSTS.includes(parsed.hostname);
}

// True only when the candidate URL's origin equals a listed origin in scheme, host AND port.
// `candidate` may be an origin or a full URL (its origin is taken); `config` is a loaded config.
export function isOriginAllowed(config, candidate) {
  const want = originOfUrl(candidate);
  if (!want) return false;
  const list = config && Array.isArray(config.origins) ? config.origins : [];
  for (const entry of list) {
    const have = parseOrigin(entry);
    if (have && have.protocol === want.protocol && have.hostname === want.hostname && have.port === want.port) {
      return true;
    }
  }
  return false;
}

// A command-line usage problem (exit 2, the command's usage text follows).
export class UsageError extends Error {}

// isMain(import.meta.url) → true when that module is the script node was started with (the CLI
// entry), false when it is imported. Every command module guards its top-level main() with it, so
// importing one for its helpers never runs the command.
export function isMain(importMetaUrl) {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(importMetaUrl));
  } catch {
    return false;
  }
}

// parseCliArgs(args, { values, booleans }) → { flags, positional }.
// `--name <v>` / `--name=<v>` for each name in `values` (an empty value is refused); a bare `--name`
// for each name in `booleans` (true). Any other `--option` is a UsageError. Shared by the criteria
// and plan commands (and the commands that follow them) so each parses its flags the same way.
export function parseCliArgs(args, { values = [], booleans = [] } = {}) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (!a.startsWith('--')) {
      positional.push(a);
      continue;
    }
    const eq = a.indexOf('=');
    const name = eq > 0 ? a.slice(2, eq) : a.slice(2);
    if (booleans.includes(name)) {
      if (eq > 0) throw new UsageError(`--${name} takes no value`);
      flags[name] = true;
      continue;
    }
    if (!values.includes(name)) throw new UsageError(`unknown option --${name}`);
    let value;
    if (eq > 0) value = a.slice(eq + 1);
    else {
      i += 1;
      if (i >= args.length) throw new UsageError(`--${name} needs a value`);
      value = args[i];
    }
    if (value === '') throw new UsageError(`--${name} needs a value`);
    flags[name] = value;
  }
  return { flags, positional };
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

// Schema validation (mirrors selvedge/schemas/selvedge-config.schema.json). Throws
// config_schema_violation naming the first offending key.
export function validateSchema(cfg) {
  const fail = (msg) => {
    throw new EnvError(REASONS.config_schema_violation, msg);
  };
  if (!isPlainObject(cfg)) fail('the top level must be a JSON object');
  for (const key of Object.keys(cfg)) {
    if (!CONFIG_KEYS.includes(key)) fail(`unknown top-level key "${key}" (allowed: ${CONFIG_KEYS.join(', ')})`);
  }
  if (cfg.schema_version !== 1) fail('"schema_version" must be 1');
  if ('origins' in cfg) {
    if (!Array.isArray(cfg.origins)) fail('"origins" must be an array of strings');
    for (const o of cfg.origins) if (typeof o !== 'string') fail('"origins" must be an array of strings');
  }
  for (const key of ['allow_remote', 'allow_remote_mutation']) {
    if (key in cfg && typeof cfg[key] !== 'boolean') fail(`"${key}" must be true or false`);
  }
  if ('hooks' in cfg) {
    if (!isPlainObject(cfg.hooks)) fail('"hooks" must be an object');
    for (const [name, cmd] of Object.entries(cfg.hooks)) {
      if (!HOOK_KEYS.includes(name)) fail(`unknown hook "${name}" (allowed: ${HOOK_KEYS.join(', ')})`);
      if (typeof cmd !== 'string') fail(`hook "${name}" must be a string`);
    }
  }
  if ('auth' in cfg) {
    const auth = cfg.auth;
    if (!isPlainObject(auth)) fail('"auth" must be an object');
    for (const key of Object.keys(auth)) {
      if (!AUTH_KEYS.includes(key)) fail(`unknown "auth" key "${key}" (allowed: ${AUTH_KEYS.join(', ')})`);
    }
    if ('env' in auth) {
      if (!Array.isArray(auth.env)) fail('"auth.env" must be an array of environment variable names');
      const nameRe = new RegExp(ENV_NAME_PATTERN);
      for (const n of auth.env) {
        if (typeof n !== 'string' || !nameRe.test(n)) fail(`"auth.env" entry ${JSON.stringify(n)} is not an environment variable name (${ENV_NAME_PATTERN})`);
      }
    }
    if ('signed_in_check' in auth) {
      const check = auth.signed_in_check;
      if (!isPlainObject(check)) fail('"auth.signed_in_check" must be an object with "url" and "locator"');
      for (const key of Object.keys(check)) {
        if (!SIGNED_IN_CHECK_KEYS.includes(key)) fail(`unknown "auth.signed_in_check" key "${key}" (allowed: ${SIGNED_IN_CHECK_KEYS.join(', ')})`);
      }
      if (typeof check.url !== 'string' || check.url === '') fail('"auth.signed_in_check.url" must be a non-empty string');
      if (!isPlainObject(check.locator)) fail('"auth.signed_in_check.locator" must be an object (one plan-step locator form: role, label, text or testid)');
    }
  }
}

// A deep-frozen copy of a JSON value (the auth locator), so the normalized config stays immutable.
function frozenCopy(value) {
  if (Array.isArray(value)) return Object.freeze(value.map(frozenCopy));
  if (isPlainObject(value)) return Object.freeze(Object.fromEntries(Object.entries(value).map(([k, v]) => [k, frozenCopy(v)])));
  return value;
}

// The normalized `auth` block (null when absent). The check URL's origin must be one the config lists
// (checked here, after the origin list itself is valid); the locator's FORM (exactly one plan-step
// locator, never CSS / XPath) is checked where it is used — validateSignedInCheck in auth-state.mjs —
// because this module cannot import plan-steps.mjs (plan-steps.mjs imports it).
function normalizeAuth(cfg, origins) {
  if (!('auth' in cfg)) return null;
  const check = cfg.auth.signed_in_check;
  if (check !== undefined && !isOriginAllowed({ origins }, check.url)) {
    throw new EnvError(
      REASONS.config_schema_violation,
      `"auth.signed_in_check.url" ${JSON.stringify(check.url)} is not on an origin selvedge.json lists (${origins.join(', ')})`,
    );
  }
  return Object.freeze({
    env: Object.freeze([...(cfg.auth.env || [])]),
    signed_in_check: check === undefined ? null : Object.freeze({ url: check.url, locator: frozenCopy(check.locator) }),
  });
}

// Full validation: schema, then the origin rules. Returns a normalized frozen config.
export function validateConfig(cfg) {
  validateSchema(cfg);
  const origins = Array.isArray(cfg.origins) ? cfg.origins : [];
  if (origins.length === 0) {
    throw new EnvError(
      REASONS.origins_empty,
      'selvedge.json lists no origins; add the app you test, e.g. "origins": ["http://localhost:3000"]',
    );
  }
  for (const o of origins) {
    if (!parseOrigin(o)) {
      throw new EnvError(
        REASONS.origin_invalid,
        `${JSON.stringify(o)} is not exactly scheme://host[:port] (http or https; no path, query, userinfo or trailing slash)`,
      );
    }
  }
  const allowRemote = cfg.allow_remote === true;
  if (!allowRemote) {
    for (const o of origins) {
      if (!isLocalOrigin(o)) {
        throw new EnvError(
          REASONS.remote_origin_without_allow_remote,
          `${o} is not local (localhost, 127.0.0.1, [::1]); set "allow_remote": true to list it`,
        );
      }
    }
  }
  return Object.freeze({
    schema_version: 1,
    origins: Object.freeze([...origins]),
    allow_remote: allowRemote,
    allow_remote_mutation: cfg.allow_remote_mutation === true,
    hooks: Object.freeze({ ...(cfg.hooks || {}) }),
    auth: normalizeAuth(cfg, origins),
  });
}

// The git top level for cwd, or null outside a work tree / without git.
export function repoRoot(cwd = process.cwd()) {
  try {
    const out = execFileSync('git', ['rev-parse', '--show-toplevel'], {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? null : out;
  } catch {
    return null;
  }
}

function readBase(root, ref) {
  const unreadable = (why) =>
    new EnvError(REASONS.base_config_unreadable, `cannot read ${ref}:${CONFIG_FILE}${why ? ` (${why})` : ''}`);
  if (typeof ref !== 'string' || ref === '' || ref.startsWith('-')) throw unreadable('not a usable ref');
  if (!root) throw unreadable('not inside a git work tree');
  try {
    // <ref>:<path> resolves the path from the tree root; --no-textconv keeps a .gitattributes driver
    // from rewriting the bytes.
    return execFileSync('git', ['show', '--no-textconv', `${ref}:${CONFIG_FILE}`], {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 1024 * 1024,
    });
  } catch (err) {
    const msg = err && err.stderr ? String(err.stderr).trim().split('\n')[0] : (err && err.message) || '';
    throw unreadable(msg);
  }
}

// loadConfig({ cwd, base }) → { config, raw, root, source }.
// With `base`, the config is the committed `<base>:selvedge.json` (git show) and the working tree is
// never read, so a PR branch cannot widen its own allowlist or change its hook command text. (A hook
// that runs a repo script still runs the working tree's copy: the approval pins the command text
// only.) Without it, the working-tree file at the repo root (or cwd outside git) is read and
// `source` says so.
export function loadConfig({ cwd = process.cwd(), base } = {}) {
  const root = repoRoot(cwd);
  let raw;
  let source;
  if (base !== undefined && base !== null) {
    raw = readBase(root, base);
    source = `${base} (git show ${base}:${CONFIG_FILE})`;
  } else {
    const file = path.join(root || cwd, CONFIG_FILE);
    try {
      raw = readFileSync(file, 'utf8');
    } catch (err) {
      if (err && err.code === 'ENOENT') {
        throw new EnvError(REASONS.config_absent, `no ${CONFIG_FILE} at ${root || cwd}; run \`selvedge env init\``);
      }
      throw new EnvError(REASONS.config_absent, `cannot read ${file}: ${err && err.message}`);
    }
    source = 'working tree (no --base)';
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new EnvError(REASONS.config_invalid_json, `${CONFIG_FILE} is not valid JSON: ${err && err.message}`);
  }
  return { config: validateConfig(parsed), raw, root: root || cwd, source };
}
