// runner/execute.mjs — one criterion of a frozen plan, in its own guarded browser context.
//
// executeCriterion opens a FRESH guarded context (openGuardedContext, route-guard.mjs) for the one
// criterion, runs its steps through the one executor (steps.mjs), writes one evidence line per
// executed step through `write` (the run's appendEvidence), takes one end-state screenshot
// (screenshots/<criterion-id>.png in the run folder) and always closes the context. No cookie,
// storage or page state carries from one criterion to the next.
//
// How a criterion ends (its criterion_end outcome):
//   completed     every step ran; the verdict comes from its reads and expects (verdict.mjs)
//   step_failed   a step threw (a locator matching nothing or more than one element, a hidden or
//                 covered click target, a navigation answered >= 400, a step timeout); failed_step
//                 is its 0-based index and nothing after it runs
//   stuck_screen  STUCK_SCREEN_ACTIONS consecutive action steps each left the page exactly as it
//                 was (same url and accessibility tree); failed_step is the last of them
//   blocked       the guarded context could not be opened (its reason, else playwright_unavailable)
//
// Stable wait: every expect after a read waits before it is judged, whether its first read would
// match or not (a negative check such as `changed_from` would otherwise PASS on a read taken before
// an in-flight side effect landed). First the network goes idle (no
// request in flight for NETWORK_QUIET_MS, counted on the page's request / requestfinished /
// requestfailed events — Playwright's `networkidle` load state resolves at once after a load, so a
// fetch started by a later click would not be waited for), then the DOM settles (two equal
// page.content() reads DOM_SETTLE_MS apart), both within STABLE_TIMEOUT_MS. The criterion's last
// read runs again (a second read line, stable_wait: true) and the expect is judged on it alone. A value
// that arrives by a timer alone, with no request and a DOM unchanged for longer than the settle
// time, is not waited for (a documented limit).
//
// Trace (`run --trace`): the context is traced (DOM snapshots, no screenshots: an image of a typed
// value cannot be redacted, no sources) and, before it closes, the trace is written to a private
// temp folder, redacted by redactTraceZip (trace-redact.mjs) into traces/<criterion-id>.zip in the
// run folder, and the raw zip deleted. A trace that cannot be redacted whole is dropped, never kept;
// stderr says `trace: <path> (redacted)` or `trace: dropped (<why>)`. Without --trace nothing is
// traced.
//
// Node >= 18, standard library only (Playwright is the caller's).
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EnvError, REASONS } from '../env-config.mjs';
import { ACTION_TYPES } from '../plan-steps.mjs';
import { NAVIGATION_TIMEOUT_MS, redactValues } from '../snapshot.mjs';
import { firstLine } from '../snapshot-playwright.mjs';
import { CRITERION_OUTCOMES, EVIDENCE_KINDS, STEP_OUTCOMES, stepLine } from './evidence.mjs';
import { openGuardedContext } from './route-guard.mjs';
import { expectMatches, readEntry, readValue, runStep } from './steps.mjs';
import { redactTraceZip } from './trace-redact.mjs';

// Consecutive no-change action steps that make a criterion stuck_screen.
export const STUCK_SCREEN_ACTIONS = 3;
export const STABLE_TIMEOUT_MS = 5000;
export const NETWORK_QUIET_MS = 500;
export const DOM_SETTLE_MS = 500;
export const SCREENSHOTS_DIR = 'screenshots';
export const TRACES_DIR = 'traces';

const POLL_MS = 50;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The requests a page has in flight, from its own request events.
export function trackRequests(page) {
  const pending = new Set();
  page.on('request', (r) => pending.add(r));
  page.on('requestfinished', (r) => pending.delete(r));
  page.on('requestfailed', (r) => pending.delete(r));
  return { inFlight: () => pending.size };
}

// waitStable(page, tracker, { timeoutMs }) → Promise<boolean>: true when the network went idle and
// the DOM settled within the time (see the header), false when the time ran out first.
export async function waitStable(page, tracker, { timeoutMs = STABLE_TIMEOUT_MS } = {}) {
  const deadline = Date.now() + timeoutMs;
  let quietSince = null;
  let idle = false;
  while (Date.now() < deadline) {
    const none = tracker.inFlight() === 0;
    if (!none) quietSince = null;
    else if (quietSince === null) quietSince = Date.now();
    if (quietSince !== null && Date.now() - quietSince >= NETWORK_QUIET_MS) {
      idle = true;
      break;
    }
    await sleep(POLL_MS);
  }
  if (!idle) return false;
  let before = await page.content();
  while (Date.now() + DOM_SETTLE_MS <= deadline) {
    await sleep(DOM_SETTLE_MS);
    const now = await page.content();
    if (now === before) return true;
    before = now;
  }
  return false;
}

// What "the screen" is for stuck-screen detection: the url and the body's accessibility tree (which
// carries input values and checked states, unlike the HTML). null when it cannot be read.
async function screenState(page, timeout) {
  try {
    return `${page.url()}\n${await page.locator('body').ariaSnapshot({ timeout })}`;
  } catch {
    return null;
  }
}

// A file name for a criterion id (ids are c-<12 hex>; anything else is made safe).
function fileName(id, ext) {
  return `${String(id).replace(/[^A-Za-z0-9._-]/g, '_')}.${ext}`;
}

// Stops the context's tracing into a private temp folder and keeps only the redacted copy,
// traces/<criterion-id>.zip. Never throws: a failure drops the trace.
async function keepTrace({ context, id, runDir, secrets }) {
  const say = (line) => process.stderr.write(`selvedge run: ${id}: trace: ${redactValues(line, secrets)}\n`);
  let tmp = null;
  try {
    tmp = mkdtempSync(path.join(os.tmpdir(), 'selvedge-trace-'));
    const raw = path.join(tmp, 'raw.zip');
    await context.tracing.stop({ path: raw });
    const rel = path.join(TRACES_DIR, fileName(id, 'zip'));
    mkdirSync(path.join(runDir, TRACES_DIR), { recursive: true });
    const res = redactTraceZip(raw, path.join(runDir, rel), { secrets });
    say(res.kept ? `${rel} (redacted)` : `dropped (${res.why})`);
  } catch (e) {
    say(`dropped (${firstLine(e)})`);
  } finally {
    if (tmp !== null) rmSync(tmp, { recursive: true, force: true });
  }
}

// executeCriterion({ id, steps, resolved, chromium, config, runDir, secrets, stepTimeoutMs, write,
//                    trace }) → Promise<criterion_end line>
//   steps     the plan's steps AS GIVEN (what the evidence records)
//   resolved  the same steps with {{NAME}} resolved (what drives the page)
//   write     appends one evidence line (the run's appendEvidence)
//   trace     true for `run --trace` (the header's Trace paragraph)
export async function executeCriterion({ id, steps, resolved, chromium, config, runDir, secrets = [], stepTimeoutMs, write, trace = false }) {
  const end = (outcome, reason = null, failedStep = null, screenshot = null) => ({
    kind: EVIDENCE_KINDS.criterion_end,
    criterion: id,
    outcome,
    reason,
    failed_step: failedStep,
    screenshot,
  });

  let guard;
  try {
    guard = await openGuardedContext({ chromium, config });
  } catch (e) {
    process.stderr.write(`selvedge run: ${id}: the guarded browser did not open: ${redactValues(firstLine(e), secrets)}\n`);
    return end(CRITERION_OUTCOMES.blocked, e instanceof EnvError ? e.reason : REASONS.playwright_unavailable);
  }

  let tracing = false;
  if (trace) {
    try {
      await guard.context.tracing.start({ screenshots: false, snapshots: true, sources: false });
      tracing = true;
    } catch (e) {
      process.stderr.write(`selvedge run: ${id}: trace: dropped (tracing did not start: ${redactValues(firstLine(e), secrets)})\n`);
    }
  }

  let result = null;
  try {
    const { page } = guard;
    page.setDefaultTimeout(stepTimeoutMs);
    page.setDefaultNavigationTimeout(NAVIGATION_TIMEOUT_MS);
    const tracker = trackRequests(page);
    const reads = [];
    let lastRead = -1;
    let before = null; // the screen before the next action (null: take it then)
    let unchanged = 0; // consecutive actions that changed nothing

    const failed = (i, t0, e) => {
      write(stepLine({ criterion: id, index: i, step: steps[i], outcome: STEP_OUTCOMES.failed, durationMs: Date.now() - t0, error: firstLine(e) }));
      return end(CRITERION_OUTCOMES.step_failed, REASONS.step_failed, i);
    };

    for (let i = 0; i < resolved.length && result === null; i += 1) {
      const step = resolved[i];
      const t0 = Date.now();

      if (step.type === 'read') {
        let value;
        try {
          value = await readValue(page, step);
        } catch (e) {
          result = failed(i, t0, e);
          break;
        }
        reads.push(readEntry(step, value));
        lastRead = i;
        write(stepLine({ criterion: id, index: i, step: steps[i], outcome: STEP_OUTCOMES.ok, value, durationMs: Date.now() - t0 }));
        continue;
      }

      if (step.type === 'expect') {
        let matched = lastRead >= 0 ? null : expectMatches(step, reads);
        let waited = false;
        if (lastRead >= 0) {
          // the stable wait, then the last read once more (header)
          waited = true;
          try {
            await waitStable(page, tracker);
          } catch {
            // the page could not be read while waiting: re-read anyway; the read decides
          }
          before = null;
          const tr = Date.now();
          let again;
          try {
            again = await readValue(page, resolved[lastRead]);
          } catch (e) {
            result = failed(lastRead, tr, e);
            break;
          }
          reads[reads.length - 1] = readEntry(resolved[lastRead], again);
          write(stepLine({ criterion: id, index: lastRead, step: steps[lastRead], outcome: STEP_OUTCOMES.ok, value: again, durationMs: Date.now() - tr, stableWait: true }));
          matched = expectMatches(step, reads);
        }
        write(stepLine({
          criterion: id,
          index: i,
          step: steps[i],
          outcome: matched ? STEP_OUTCOMES.matched : STEP_OUTCOMES.mismatched,
          durationMs: Date.now() - t0,
          stableWait: waited,
        }));
        continue;
      }

      const action = ACTION_TYPES.includes(step.type);
      if (action && before === null) before = await screenState(page, stepTimeoutMs);
      try {
        await runStep(page, step);
      } catch (e) {
        result = failed(i, t0, e);
        break;
      }
      write(stepLine({ criterion: id, index: i, step: steps[i], outcome: STEP_OUTCOMES.ok, durationMs: Date.now() - t0 }));
      if (!action) {
        // goto / wait_for: a new page or a wait, not an action that could be stuck
        before = null;
        unchanged = 0;
        continue;
      }
      const after = await screenState(page, stepTimeoutMs);
      unchanged = after !== null && after === before ? unchanged + 1 : 0;
      before = after;
      if (unchanged >= STUCK_SCREEN_ACTIONS) {
        process.stderr.write(`selvedge run: ${id}: steps ${i - STUCK_SCREEN_ACTIONS + 1}..${i}: ${STUCK_SCREEN_ACTIONS} actions in a row left the screen unchanged\n`);
        result = end(CRITERION_OUTCOMES.stuck_screen, REASONS.stuck_screen, i);
      }
    }
    if (result === null) result = end(CRITERION_OUTCOMES.completed);

    // the end-state screenshot (a failure to take it leaves screenshot null)
    const rel = path.join(SCREENSHOTS_DIR, fileName(id, 'png'));
    try {
      mkdirSync(path.join(runDir, SCREENSHOTS_DIR), { recursive: true });
      await page.screenshot({ path: path.join(runDir, rel), timeout: stepTimeoutMs });
      result.screenshot = rel;
    } catch (e) {
      process.stderr.write(`selvedge run: ${id}: no end-state screenshot: ${redactValues(firstLine(e), secrets)}\n`);
    }
  } finally {
    if (tracing) await keepTrace({ context: guard.context, id, runDir, secrets });
    await guard.close();
  }
  if (guard.blocks.length) {
    const seen = [...new Set(guard.blocks.map((b) => `${b.reason} ${b.host}`))];
    process.stderr.write(`selvedge run: ${id}: the guard refused ${guard.blocks.length} request(s): ${seen.join(', ')}\n`);
  }
  return result;
}
