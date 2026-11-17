// auth-state.mjs — where a signed-in session lives, and the sign-in check's locator rule.
//
// The session is a Playwright storage state (cookies + localStorage) kept ONLY at
//   $HOME/.local/state/selvedge/<repo-id>/auth/storageState.json
// where <repo-id> is the sha256 hex of the repo identity (env-approvals.mjs repoIdentity: the
// `origin` remote URL without userinfo, else the repo root's realpath). Each directory selvedge
// creates under $HOME/.local/state/selvedge is mode 0700 and the file 0600 — the same modes, from the
// same constants, as the user-scoped approvals store — and a path that resolves inside the repo is
// never written or read (insideRepo, also from env-approvals.mjs). Nothing here copies those rules.
//
// Node >= 18, standard library only.
import { createHash } from 'node:crypto';
import { chmodSync, lstatSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS } from './env-config.mjs';
import { DIR_MODE, FILE_MODE, insideRepo, repoIdentity } from './env-approvals.mjs';
import { validateSteps } from './plan-steps.mjs';

export { DIR_MODE, FILE_MODE };

export const STATE_FILE = 'storageState.json';

// The env var `selvedge auth setup` hands the auth_setup hook: the path it writes the storage state to.
export const STORAGE_STATE_ENV = 'SELVEDGE_STORAGE_STATE';

// sha256 hex of the repo identity: the <repo-id> directory name.
export function repoId(root) {
  return createHash('sha256').update(repoIdentity(root), 'utf8').digest('hex');
}

// authStatePath({ root, env }) → the storage state path for this repo, or null when HOME is unset.
export function authStatePath({ root, env = process.env } = {}) {
  const home = env.HOME;
  if (!home) return null;
  return path.join(home, '.local', 'state', 'selvedge', repoId(root), 'auth', STATE_FILE);
}

// The state path, or an Error naming why it cannot be used (HOME unset, or it would sit inside the
// repo). Callers that write it (auth setup) report the error; readers (hasState) treat it as absent.
export function usableStatePath({ root, env = process.env } = {}) {
  const file = authStatePath({ root, env });
  if (!file) return { file: null, error: 'HOME is not set, so there is no place outside the repo to keep the session' };
  if (insideRepo(file, root)) return { file, error: `${file} is inside the repo; a session is never kept there` };
  return { file, error: null };
}

// hasState({ root, env }) → true when a storage state file (a regular file, not a symlink) exists at
// the state path. Fails closed: no HOME, a path inside the repo, or anything unreadable is false.
export function hasState({ root, env = process.env } = {}) {
  const { file, error } = usableStatePath({ root, env });
  if (error) return false;
  try {
    return lstatSync(file).isFile();
  } catch {
    return false;
  }
}

// ensureStateDir(file) — creates the state file's directory (and its <repo-id> parent) mode
// 0700, tightening ones that already exist; $HOME/.local/state itself is left as it is.
export function ensureStateDir(file) {
  const authDir = path.dirname(file);
  const idDir = path.dirname(authDir);
  mkdirSync(authDir, { recursive: true, mode: DIR_MODE });
  chmodSync(idDir, DIR_MODE);
  chmodSync(authDir, DIR_MODE);
  return authDir;
}

// validateSignedInCheck(config) → null when the config has no `auth.signed_in_check`, else the two
// steps the check stands for ([goto url, wait_for locator attached]). The locator must be exactly one
// plan-step locator form (role, label, text, testid — never CSS or XPath) and the URL on an origin
// selvedge.json lists: the ONE step validator (plan-steps.mjs validateSteps) decides both, and any
// problem it reports throws EnvError config_schema_violation naming the first one.
export function validateSignedInCheck(config) {
  const check = config && config.auth ? config.auth.signed_in_check : null;
  if (!check) return null;
  const steps = [
    { type: 'goto', url: check.url },
    { type: 'wait_for', locator: check.locator, state: 'attached' },
  ];
  const problems = validateSteps(steps, { config });
  if (problems.length) {
    const detail = problems[0].detail.replace(/^steps\[0\]\.url/, 'auth.signed_in_check.url').replace(/^steps\[1\]\.locator/, 'auth.signed_in_check.locator');
    throw new EnvError(REASONS.config_schema_violation, `"auth.signed_in_check": ${detail}`);
  }
  return steps;
}
