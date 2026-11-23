// stub-playwright.mjs — a stand-in Playwright for test-eval-harness.sh's browser preflight arms, set
// as SELVEDGE_PLAYWRIGHT_MODULE=<this file>. Not named test-*, so selvedge/tests/run.sh never runs it.
//
// chromium.launch appends `launch <options json>` to $STUB_LOG/browser.log and returns a fake browser
// whose close appends `close`. With $STUB_PW_LAUNCH_FAIL set, launch logs the same line and then
// throws a two-line error (as real Playwright does when its browser build is not in the cache), so a
// test can check that only the first line is printed. No Chromium runs.
import { appendFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

function log(line) {
  const dir = process.env.STUB_LOG;
  if (!dir) return;
  mkdirSync(dir, { recursive: true });
  appendFileSync(join(dir, 'browser.log'), `${line}\n`);
}

export const chromium = {
  async launch(options) {
    log(`launch ${JSON.stringify(options === undefined ? null : options)}`);
    if (process.env.STUB_PW_LAUNCH_FAIL) {
      throw new Error("browserType.launch: Executable doesn't exist at /stub/ms-playwright/chromium_headless_shell-1194/chrome-mac/headless_shell\nCALL-LOG-SECOND-LINE: please run npx playwright install");
    }
    return {
      async close() {
        log('close');
      },
    };
  },
};
