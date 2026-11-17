// runner/auth-check.mjs — the login-wall check `selvedge run` makes once, before the first criterion.
//
// selvedge.json's `auth.signed_in_check` names a page on a listed origin and one plan-step locator
// that matches only when signed in. checkSignedIn opens ONE guarded context (route-guard.mjs) with
// the stored session (auth-state.mjs; none when no state file exists), goes to that page and passes
// when the locator matches at least one element within the step timeout. Anything else — the page
// answers >= 400, a redirect the guard refuses, the locator matching nothing (a login page instead),
// a stored session file that is not a JSON object (read before any browser opens) — is needs_auth. A guarded browser that does not open is that failure's own reason (its EnvError's
// reason, else playwright_unavailable), never needs_auth.
//
// signedInGate decides what a failed check means for the run:
//   non-interactive (stdin is not a terminal, or `run --non-interactive`): one check only; a failure
//                  is needs_auth at once (every criterion BLOCKED; there is no retry loop)
//   interactive    on a failed check it says on stderr what is needed (`selvedge auth setup
//                  --headed`), reads exactly ONE line from stdin, checks exactly once more and either
//                  goes on or returns needs_auth. There is never a third check.
// `run` never signs in itself: it never runs the auth_setup hook (only `selvedge auth setup` does).
//
// authEnvValues lists the values of the environment variables `auth.env` names, as the run's
// redaction list takes them ({ name, value }), so a credential a page shows is written back as
// {{NAME}}.
//
// Node >= 18, standard library only (Playwright is the caller's; never imported here).
import { readFileSync } from 'node:fs';
import readline from 'node:readline';
import { EnvError, REASONS } from '../env-config.mjs';
import { NAVIGATION_TIMEOUT_MS, STEP_TIMEOUT_MS, redactValues } from '../snapshot.mjs';
import { firstLine } from '../snapshot-playwright.mjs';
import { openGuardedContext } from './route-guard.mjs';
import { locate, navigate } from './steps.mjs';

const POLL_MS = 100;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// What a person can run to sign in (named in every needs_auth message).
export const SIGN_IN_HINT = '`selvedge auth setup --headed` (you sign in, in a browser window), or `selvedge auth setup` (the approved hooks.auth_setup)';

// authEnvValues(config, env, taken) → [{ name, value }] for each `auth.env` name set to a non-empty
// value and not already in `taken` (the run's other secrets).
export function authEnvValues(config, env = process.env, taken = []) {
  const names = config && config.auth ? config.auth.env : [];
  return names
    .filter((n) => typeof env[n] === 'string' && env[n] !== '' && !taken.some((s) => s.name === n))
    .map((n) => ({ name: n, value: env[n] }));
}

// Why the stored session file cannot be loaded (Playwright would refuse it), or null.
function stateFileProblem(file) {
  let data;
  try {
    data = JSON.parse(readFileSync(file, 'utf8'));
  } catch (e) {
    return e && e.code ? `cannot be read (${e.code})` : 'is not valid JSON';
  }
  return data !== null && typeof data === 'object' && !Array.isArray(data) ? null : 'is not a storage state (a JSON object)';
}

// One line from stdin (the line discipline delivers it), or null at EOF.
export async function readOneLine(input = process.stdin) {
  const rl = readline.createInterface({ input, terminal: false });
  try {
    for await (const line of rl) return line;
    return null;
  } finally {
    rl.close();
    input.pause();
  }
}

// checkSignedIn({ chromium, config, storageState, stepTimeoutMs, secrets }) → Promise<
//   { signedIn: true } | { signedIn: false, reason, detail }>
//   storageState   the stored session's path, or null (the context then starts empty)
//   secrets        [{ name, value }] removed from `detail` (it is printed)
export async function checkSignedIn({ chromium, config, storageState = null, stepTimeoutMs = STEP_TIMEOUT_MS, secrets = [] }) {
  const { url, locator } = config.auth.signed_in_check;
  const clean = (text) => redactValues(text, secrets);
  const options = { chromium, config };
  if (typeof storageState === 'string') {
    const problem = stateFileProblem(storageState);
    if (problem) return { signedIn: false, reason: REASONS.needs_auth, detail: `the stored session ${storageState} ${problem}` };
    options.storageState = storageState;
  }
  let guard;
  try {
    guard = await openGuardedContext(options);
  } catch (e) {
    return { signedIn: false, reason: e instanceof EnvError ? e.reason : REASONS.playwright_unavailable, detail: `the guarded browser did not open for the sign-in check: ${clean(firstLine(e))}` };
  }
  const session = storageState ? 'with the stored session (it may have expired)' : 'with no stored session';
  try {
    const { page } = guard;
    page.setDefaultTimeout(stepTimeoutMs);
    page.setDefaultNavigationTimeout(NAVIGATION_TIMEOUT_MS);
    try {
      await navigate(page, url);
    } catch (e) {
      return { signedIn: false, reason: REASONS.needs_auth, detail: `the sign-in check page did not open ${session}: ${clean(firstLine(e))}` };
    }
    const deadline = Date.now() + stepTimeoutMs;
    for (;;) {
      let n = 0;
      try {
        n = await locate(page, locator).count();
      } catch {
        n = 0; // the page was navigating; look again
      }
      if (n > 0) return { signedIn: true };
      if (Date.now() >= deadline) break;
      await sleep(POLL_MS);
    }
    return { signedIn: false, reason: REASONS.needs_auth, detail: `${JSON.stringify(locator)} matched nothing at ${url} ${session}` };
  } finally {
    await guard.close();
  }
}

// signedInGate({ chromium, config, storageState, interactive, readLine, stepTimeoutMs, secrets, say })
//   → Promise<{ signedIn: true, checks } | { signedIn: false, reason, detail, checks }>
//   storageState   () → the stored session's path or null, asked before EACH check (a person may sign
//                  in between the two)
//   interactive    true only when someone can answer (the header); readLine is called only then
//   readLine       () → Promise<line | null>; one line from stdin by default
//   say            one stderr line (default `selvedge run: <line>`)
export async function signedInGate({
  chromium,
  config,
  storageState = () => null,
  interactive = false,
  readLine = readOneLine,
  stepTimeoutMs = STEP_TIMEOUT_MS,
  secrets = [],
  say = (line) => process.stderr.write(`selvedge run: ${line}\n`),
}) {
  const options = () => ({ chromium, config, storageState: storageState(), stepTimeoutMs, secrets });
  const first = await checkSignedIn(options());
  if (first.signedIn) return { signedIn: true, checks: 1 };
  if (first.reason !== REASONS.needs_auth) return { ...first, checks: 1 };
  say(`${REASONS.needs_auth}: not signed in: ${first.detail}`);
  if (!interactive) {
    say(`nobody can sign in here (stdin is not a terminal, or --non-interactive): every criterion is BLOCKED ${REASONS.needs_auth}. Sign in with ${SIGN_IN_HINT}, then run the plan again (selvedge run --replay <run-dir>)`);
    return { ...first, checks: 1 };
  }
  say(`sign in with ${SIGN_IN_HINT} in another terminal, then press Enter here: the sign-in is checked once more`);
  await readLine();
  const second = await checkSignedIn(options());
  if (second.signedIn) {
    say('signed in; the run goes on');
    return { signedIn: true, checks: 2 };
  }
  say(`${second.reason}: still not signed in: ${second.detail}; every criterion is BLOCKED ${second.reason}`);
  return { ...second, checks: 2 };
}
