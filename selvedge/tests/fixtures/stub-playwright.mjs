// stub-playwright.mjs — a stand-in Playwright for test-run.sh's no-browser arms, set as
// SELVEDGE_PLAYWRIGHT_MODULE=<this file>. Not named test-*, so selvedge/tests/run.sh never runs it.
//
// chromium.launch appends the line `launch` to $STUB_PW_LOG (the marker file "a browser was
// launched" is read from), then returns a fake browser: no Chromium runs. Its one page answers every
// goto with HTTP 200 after STUB_PW_GOTO_MS milliseconds (default 0), every read with $STUB_PW_TEXT
// (default "stub"), every action at once, and writes a small file for a screenshot. The guarded
// context's own proxy still starts (route-guard.mjs); nothing reaches it.
import { appendFileSync, writeFileSync } from 'node:fs';

const env = process.env;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const text = () => (env.STUB_PW_TEXT === undefined ? 'stub' : env.STUB_PW_TEXT);

function fakePage() {
  let url = 'about:blank';
  const locator = {
    click: async () => {},
    fill: async () => {},
    selectOption: async () => {},
    setChecked: async () => {},
    press: async () => {},
    waitFor: async () => {},
    innerText: async () => text(),
    inputValue: async () => text(),
    isChecked: async () => false,
    count: async () => 1,
    getAttribute: async () => text(),
    ariaSnapshot: async () => `- paragraph: ${text()}`,
  };
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
    getByRole: () => locator,
    getByLabel: () => locator,
    getByText: () => locator,
    getByTestId: () => locator,
    locator: () => locator,
    keyboard: { press: async () => {} },
    screenshot: async ({ path }) => writeFileSync(path, 'stub screenshot\n'),
  };
}

export const chromium = {
  launch: async () => {
    if (env.STUB_PW_LOG) appendFileSync(env.STUB_PW_LOG, 'launch\n');
    const context = { addInitScript: async () => {}, route: async () => {}, on: () => {}, newPage: async () => fakePage() };
    return { newContext: async () => context, close: async () => {} };
  },
};
