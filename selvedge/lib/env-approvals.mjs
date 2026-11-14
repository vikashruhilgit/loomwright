// env-approvals.mjs — user-scoped approval of selvedge.json env hooks.
//
// An approval lives ONLY in $HOME/.claude/selvedge/approvals.json (dir 0700, file 0600, written
// atomically), keyed by repo identity → the sha256 of the canonical `hooks` object. Hooks run only
// when the current hash equals the stored one, so changing one byte of any hook needs a fresh
// approval. Nothing inside the repo is ever read as an approval: an approvals path that resolves
// inside the repo root is refused.
//
// Node >= 18, standard library only.
import { execFileSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { chmodSync, closeSync, fsyncSync, mkdirSync, openSync, readFileSync, realpathSync, renameSync, rmSync, writeSync } from 'node:fs';
import path from 'node:path';

const APPROVALS_SCHEMA_VERSION = 1;
const FILE_MODE = 0o600; // approvals.json (created with this mode; umask can only narrow it)
const DIR_MODE = 0o700; // $HOME/.claude/selvedge

// Canonical JSON: object keys sorted, no whitespace.
export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonicalJson(value[k])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

// sha256 hex of the canonical `hooks` object ({} when absent).
export function hooksSha256(hooks) {
  return createHash('sha256').update(canonicalJson(hooks || {}), 'utf8').digest('hex');
}

// Drop any userinfo from a URL-form remote so a token in the remote never lands in approvals.json.
function stripUserinfo(remote) {
  try {
    const u = new URL(remote);
    if (u.username === '' && u.password === '') return remote;
    u.username = '';
    u.password = '';
    return u.toString();
  } catch {
    return remote; // scp-like `git@host:owner/repo` is not a URL and carries no secret
  }
}

// Repo identity: the `origin` remote URL, else the repo root's realpath.
export function repoIdentity(root) {
  try {
    const url = execFileSync('git', ['remote', 'get-url', 'origin'], {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (url !== '') return stripUserinfo(url);
  } catch {
    // no git, not a repo, or no origin remote: fall through
  }
  return realpathSync(root);
}

// $HOME/.claude/selvedge/approvals.json, or null when HOME is unset.
export function approvalsPath(env = process.env) {
  const home = env.HOME;
  if (!home) return null;
  return path.join(home, '.claude', 'selvedge', 'approvals.json');
}

function realpathOrResolve(p) {
  // Resolve the deepest existing ancestor, then re-append the rest.
  let cur = path.resolve(p);
  const rest = [];
  for (;;) {
    try {
      return path.join(realpathSync(cur), ...rest);
    } catch {
      const parent = path.dirname(cur);
      if (parent === cur) return path.join(cur, ...rest);
      rest.unshift(path.basename(cur));
      cur = parent;
    }
  }
}

// True when the approvals file would sit inside the repo — never trusted.
function insideRepo(file, root) {
  const f = realpathOrResolve(file);
  const r = realpathOrResolve(root);
  return f === r || f.startsWith(r.endsWith(path.sep) ? r : r + path.sep);
}

// { ok: true, data } | { ok: false, error }. A missing file is ok with no approvals.
function readApprovals(file) {
  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (err) {
    if (err && err.code === 'ENOENT') return { ok: true, data: { schema_version: APPROVALS_SCHEMA_VERSION, approvals: {} } };
    return { ok: false, error: `cannot read ${file}: ${err && err.message}` };
  }
  let data;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    return { ok: false, error: `${file} is not valid JSON: ${err && err.message}` };
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)
      || data.approvals === null || typeof data.approvals !== 'object' || Array.isArray(data.approvals)) {
    return { ok: false, error: `${file} has no "approvals" object` };
  }
  return { ok: true, data };
}

// approvalState({ root, hooks }) → { state: 'no hooks' | 'approved' | 'unapproved', identity, sha256, detail }.
// Fails closed: an unreadable/malformed approvals file, an unset HOME or an approvals path inside the
// repo all read as unapproved.
export function approvalState({ root, hooks, env = process.env }) {
  const sha256 = hooksSha256(hooks);
  const identity = repoIdentity(root);
  if (!hooks || Object.keys(hooks).length === 0) return { state: 'no hooks', identity, sha256, detail: '' };
  const file = approvalsPath(env);
  if (!file) return { state: 'unapproved', identity, sha256, detail: 'HOME is not set' };
  if (insideRepo(file, root)) return { state: 'unapproved', identity, sha256, detail: `${file} is inside the repo; ignored` };
  const read = readApprovals(file);
  if (!read.ok) return { state: 'unapproved', identity, sha256, detail: read.error };
  const entry = Object.prototype.hasOwnProperty.call(read.data.approvals, identity) ? read.data.approvals[identity] : null;
  if (!entry || typeof entry !== 'object') return { state: 'unapproved', identity, sha256, detail: `no approval for ${identity}` };
  if (entry.hooks_sha256 !== sha256) {
    return { state: 'unapproved', identity, sha256, detail: `the hooks changed since they were approved (approved ${entry.hooks_sha256})` };
  }
  return { state: 'approved', identity, sha256, detail: '' };
}

// Record an approval of `sha256` for `identity`. Atomic (temp file + rename), dir 0700, file 0600.
// Refuses to overwrite a malformed approvals file or to write inside the repo. Returns the path.
export function writeApproval({ root, identity, sha256, env = process.env }) {
  const file = approvalsPath(env);
  if (!file) throw new Error('HOME is not set; cannot record an approval');
  if (insideRepo(file, root)) throw new Error(`${file} is inside the repo; refusing to record an approval there`);
  const dir = path.dirname(file);
  mkdirSync(dir, { recursive: true, mode: DIR_MODE });
  chmodSync(dir, DIR_MODE); // also tightens a directory that already existed
  const read = readApprovals(file);
  if (!read.ok) throw new Error(`${read.error}; fix or remove it, then approve again`);
  const data = read.data;
  data.schema_version = APPROVALS_SCHEMA_VERSION;
  data.approvals[identity] = { hooks_sha256: sha256, approved_at: new Date().toISOString() };
  const tmp = path.join(dir, `.approvals.${process.pid}.${randomBytes(6).toString('hex')}.tmp`);
  let fd;
  try {
    fd = openSync(tmp, 'wx', FILE_MODE);
    writeSync(fd, `${JSON.stringify(data, null, 2)}\n`);
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    renameSync(tmp, file);
  } catch (err) {
    if (fd !== undefined) {
      try { closeSync(fd); } catch { /* already closed */ }
    }
    rmSync(tmp, { force: true });
    throw err;
  }
  return file;
}
