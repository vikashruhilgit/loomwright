// env-config.mjs — selvedge.json: origin parsing, the allowlist match, config load and validation,
// and the closed list of reasons every selvedge env/guard emitter names.
//
// This is the ONE origin parser. The env commands, the forward proxy and the browser route layer all
// import parseOrigin / isOriginAllowed from here; nothing re-implements them. Origins are compared as
// parsed exact values (scheme, host AND port) — never a regex, a suffix or a substring.
//
// Node >= 18, standard library only.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';

// The closed reason list. Every emitter imports a value from here; no reason is a string literal
// anywhere else. BLOCKED reasons print as a stdout line `BLOCKED <reason>`; config/usage reasons print
// on stderr. Both exit 2.
export const REASONS = Object.freeze({
  // BLOCKED outcomes
  host_not_allowed: 'host_not_allowed',
  remote_resolves_private: 'remote_resolves_private',
  remote_mutation_refused: 'remote_mutation_refused',
  proxy_loopback_disabled: 'proxy_loopback_disabled',
  proxy_unavailable: 'proxy_unavailable',
  env_hooks_unapproved: 'env_hooks_unapproved',
  env_hooks_remote_origin: 'env_hooks_remote_origin',
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
});

export const CONFIG_FILE = 'selvedge.json';

// The validator's accepted key sets. selvedge/schemas/selvedge-config.schema.json declares the same
// names; selvedge/tests/test-env.sh asserts the two are equal (the schema is not read at run time, so
// the check is a real second copy, not a tautology).
export const CONFIG_KEYS = Object.freeze(['schema_version', 'origins', 'allow_remote', 'allow_remote_mutation', 'hooks']);
export const HOOK_KEYS = Object.freeze(['seed', 'reset', 'auth_setup']);

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
// never read, so a PR branch cannot widen its own allowlist or hooks. Without it, the working-tree
// file at the repo root (or cwd outside git) is read and `source` says so.
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
