// snapshot-playwright.mjs — how the selvedge CLI finds Playwright at run time.
//
// selvedge ships no node_modules (it has no package.json), so the browser library comes from one of
// two places, in this order, and nowhere else:
//   (a) SELVEDGE_PLAYWRIGHT_MODULE — the path of an importable Playwright entry (e.g.
//       <dir>/node_modules/playwright/index.mjs). When it is set, it is the only place looked at: a
//       path that does not load is playwright_unavailable, never a silent fall-back to (b).
//   (b) the target project's own `playwright`, resolved from <repo root>/package.json exactly as
//       that project's own code would require it (createRequire), so its version is the one the
//       project already pins.
// Neither ⇒ EnvError playwright_unavailable (BLOCKED): nothing is launched.
//
// The resolved `version` is returned so a caller can record which Playwright produced its evidence.
// This module only loads the library; launching (through the guarded context) is the caller's
// (snapshot.mjs, runner/execute.mjs).
//
// Node >= 18, standard library only.
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { EnvError, REASONS } from './env-config.mjs';

export const PLAYWRIGHT_MODULE_ENV = 'SELVEDGE_PLAYWRIGHT_MODULE';

const INSTALL_HINT =
  'install it in the target project (`npm i -D playwright` then `npx playwright install chromium`), or set SELVEDGE_PLAYWRIGHT_MODULE to a Playwright entry file';

function unavailable(message) {
  return new EnvError(REASONS.playwright_unavailable, message, { blocked: true });
}

// The first line of an error's message (a Playwright error carries a multi-line call log).
export function firstLine(e) {
  return String(e && e.message ? e.message : e).split('\n')[0];
}

// The version in the nearest package.json at or above `file`'s directory, or null.
function versionNear(file) {
  let dir = path.dirname(file);
  for (;;) {
    const pkg = path.join(dir, 'package.json');
    if (existsSync(pkg)) {
      try {
        const v = JSON.parse(readFileSync(pkg, 'utf8')).version;
        return typeof v === 'string' ? v : null;
      } catch {
        return null;
      }
    }
    const up = path.dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
}

function chromiumOf(mod) {
  if (mod && mod.chromium && typeof mod.chromium.launch === 'function') return mod.chromium;
  if (mod && mod.default && mod.default.chromium && typeof mod.default.chromium.launch === 'function') return mod.default.chromium;
  return null;
}

// resolvePlaywright({ root, env, cwd }) → Promise<{ chromium, version, source, path }>
//   root  the target repo root (loadConfig().root); (b) resolves from <root>/package.json
//   env   the environment to read SELVEDGE_PLAYWRIGHT_MODULE from (default process.env)
//   cwd   a relative SELVEDGE_PLAYWRIGHT_MODULE is taken from here (default process.cwd())
// `source` is 'SELVEDGE_PLAYWRIGHT_MODULE' or 'repo'. Throws EnvError playwright_unavailable (BLOCKED).
export async function resolvePlaywright({ root, env = process.env, cwd = process.cwd() } = {}) {
  const fromEnv = env[PLAYWRIGHT_MODULE_ENV];
  if (fromEnv !== undefined && fromEnv !== '') {
    const file = path.resolve(cwd, fromEnv);
    let mod;
    try {
      mod = await import(pathToFileURL(file).href);
    } catch (e) {
      throw unavailable(`${PLAYWRIGHT_MODULE_ENV}=${fromEnv} does not load (${firstLine(e)}); ${INSTALL_HINT}`);
    }
    const chromium = chromiumOf(mod);
    if (!chromium) throw unavailable(`${PLAYWRIGHT_MODULE_ENV}=${fromEnv} loads but exports no chromium; ${INSTALL_HINT}`);
    return { chromium, version: versionNear(file), source: PLAYWRIGHT_MODULE_ENV, path: file };
  }

  if (typeof root !== 'string' || root === '') {
    throw unavailable(`${PLAYWRIGHT_MODULE_ENV} is unset and there is no repo root to resolve playwright from; ${INSTALL_HINT}`);
  }
  const req = createRequire(path.join(root, 'package.json'));
  let entry;
  try {
    entry = req.resolve('playwright');
  } catch {
    throw unavailable(`${PLAYWRIGHT_MODULE_ENV} is unset and \`playwright\` does not resolve from ${root}; ${INSTALL_HINT}`);
  }
  let mod;
  try {
    mod = req(entry);
  } catch (e) {
    throw unavailable(`playwright at ${entry} does not load (${firstLine(e)}); ${INSTALL_HINT}`);
  }
  const chromium = chromiumOf(mod);
  if (!chromium) throw unavailable(`playwright at ${entry} exports no chromium; ${INSTALL_HINT}`);
  let version = null;
  try {
    const v = req('playwright/package.json').version;
    version = typeof v === 'string' ? v : null;
  } catch {
    version = versionNear(entry);
  }
  return { chromium, version, source: 'repo', path: entry };
}
