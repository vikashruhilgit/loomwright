// stub-playwright.mjs — a stand-in Playwright for test-run.sh's and test-auth.sh's no-browser arms,
// set as SELVEDGE_PLAYWRIGHT_MODULE=<this file>. Not named test-*, so selvedge/tests/run.sh never
// runs it.
//
// chromium.launch appends the line `launch` to $STUB_PW_LOG (the marker file "a browser was
// launched" is read from), then returns a fake browser: no Chromium runs. Its one page answers every
// goto with HTTP 200 after STUB_PW_GOTO_MS milliseconds (default 0), every read with $STUB_PW_TEXT
// (default "stub"), every action at once, and writes a small file for a screenshot. The guarded
// context's own proxy still starts (route-guard.mjs); nothing reaches it.
//
// Options are logged apart from $STUB_PW_LOG (whose `launch` lines are counted): with $STUB_PW_OPTS_LOG
// set, `launch <json>` (the launch options), `newContext <json>` (the context options) and
// `storageState` (each context.storageState call) are appended to it, one per line.
// context.storageState({ path }) returns STUB_STATE and, given a path, writes it there as JSON.
// locator.count() is 1 unless $STUB_PW_COUNTS_FILE (re-read on every call, so a test can change it
// while a command waits) or else $STUB_PW_COUNTS holds a JSON object naming the locator's key:
// `role:<role>` or `role:<role>:<name>`, `label:<label>`, `text:<text>`, `testid:<id>`, `css:<sel>`.
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';

const env = process.env;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const text = () => (env.STUB_PW_TEXT === undefined ? 'stub' : env.STUB_PW_TEXT);

export const STUB_STATE = Object.freeze({
  cookies: Object.freeze([Object.freeze({ name: 'stub_session', value: 'stub', domain: 'localhost', path: '/' })]),
  origins: Object.freeze([]),
});

function optsLog(line) {
  if (env.STUB_PW_OPTS_LOG) appendFileSync(env.STUB_PW_OPTS_LOG, `${line}\n`);
}

// The count configured for a locator key, or 1 (the default every existing test relies on).
function countFor(key) {
  let table = null;
  try {
    if (env.STUB_PW_COUNTS_FILE) table = JSON.parse(readFileSync(env.STUB_PW_COUNTS_FILE, 'utf8'));
    else if (env.STUB_PW_COUNTS) table = JSON.parse(env.STUB_PW_COUNTS);
  } catch {
    table = null;
  }
  return table && Object.prototype.hasOwnProperty.call(table, key) ? Number(table[key]) : 1;
}

function fakeLocator(key) {
  return {
    click: async () => {},
    fill: async () => {},
    selectOption: async () => {},
    setChecked: async () => {},
    press: async () => {},
    waitFor: async () => {},
    innerText: async () => text(),
    inputValue: async () => text(),
    isChecked: async () => false,
    count: async () => countFor(key),
    getAttribute: async () => text(),
    ariaSnapshot: async () => `- paragraph: ${text()}`,
  };
}

function fakePage() {
  let url = 'about:blank';
  return {
    setDefaultTimeout: () => {},
    setDefaultNavigationTimeout: () => {},
    on: () => {},
    goto: async (u) => {
      await sleep(Number(env.STUB_PW_GOTO_MS || 0));
      url = u;
      return { status: () => 200, headers: () => ({}) };
    },
    url: () => url,
    content: async () => '<html><body>stub</body></html>',
    getByRole: (role, opts = {}) => fakeLocator(opts && opts.name !== undefined ? `role:${role}:${opts.name}` : `role:${role}`),
    getByLabel: (label) => fakeLocator(`label:${label}`),
    getByText: (t) => fakeLocator(`text:${t}`),
    getByTestId: (id) => fakeLocator(`testid:${id}`),
    locator: (sel) => fakeLocator(`css:${sel}`),
    keyboard: { press: async () => {} },
    screenshot: async ({ path }) => writeFileSync(path, 'stub screenshot\n'),
  };
}

export const chromium = {
  launch: async (options) => {
    if (env.STUB_PW_LOG) appendFileSync(env.STUB_PW_LOG, 'launch\n');
    optsLog(`launch ${JSON.stringify(options === undefined ? null : options)}`);
    const context = {
      addInitScript: async () => {},
      route: async () => {},
      on: () => {},
      newPage: async () => fakePage(),
      storageState: async ({ path } = {}) => {
        optsLog('storageState');
        if (path) writeFileSync(path, `${JSON.stringify(STUB_STATE)}\n`);
        return JSON.parse(JSON.stringify(STUB_STATE));
      },
    };
    return {
      newContext: async (options) => {
        optsLog(`newContext ${JSON.stringify(options === undefined ? null : options)}`);
        return context;
      },
      close: async () => {},
    };
  },
};
