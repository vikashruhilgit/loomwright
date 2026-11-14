#!/usr/bin/env bash
# playwright-cache.sh — SOURCED (never run) by selvedge's browser-facing tests (test-route-guard.sh).
# Installs the pinned `playwright` library and its Chromium build into a selvedge-owned cache, so
# selvedge reads nothing under loomwright/ (decision D4) and needs no package.json of its own.
#
#   PW_VERSION=<x.y.z>         the one pin line: bump it here and nowhere else
#   SELVEDGE_TEST_PW_CACHE     the cache dir (default ${TMPDIR:-/tmp}/selvedge-test-pw); holds
#                              node_modules/playwright and browsers/
#   PLAYWRIGHT_BROWSERS_PATH   exported as $SELVEDGE_TEST_PW_CACHE/browsers unless already set, BEFORE
#                              a test changes HOME, so a temp HOME never triggers a second download
#
# pw_acquire sets PW_READY=1 and PW_MODULE (the absolute path of playwright's ESM entry, which the
# fixture driver imports), or PW_SKIP=<why>. pw_require_or_skip applies the bimodal rule:
#   CI set     ⇒ an install failure is a hard FAIL: prints `FAIL playwright_install_failed: <why>`
#                and returns 1 — the caller exits 1 and runs no browser arm;
#   CI unset   ⇒ prints `SKIP (playwright_install_failed: <why>)` and returns 2 — the caller skips
#                its browser arms and its non-browser arms still decide.
# This file and its downloads are the only network the selvedge suite uses.

PW_VERSION=1.65.1

_selvedge_pw_tmp="${TMPDIR:-/tmp}"
SELVEDGE_TEST_PW_CACHE="${SELVEDGE_TEST_PW_CACHE:-${_selvedge_pw_tmp%/}/selvedge-test-pw}"
SELVEDGE_TEST_PW_CACHE="${SELVEDGE_TEST_PW_CACHE%/}"
unset _selvedge_pw_tmp
export SELVEDGE_TEST_PW_CACHE
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$SELVEDGE_TEST_PW_CACHE/browsers}"

PW_READY=0
PW_SKIP=""
PW_MODULE=""

# pw_acquire — idempotent. Reinstalls the library on a version MISMATCH, not merely on absence, so a
# cache left by an older pin never keeps satisfying the check. `playwright install` is itself a
# no-op when the matching Chromium build is already under PLAYWRIGHT_BROWSERS_PATH.
pw_acquire() {
  local log tool have
  PW_READY=0; PW_SKIP=""; PW_MODULE=""
  for tool in node npm; do
    command -v "$tool" >/dev/null 2>&1 || { PW_SKIP="$tool is not on PATH"; return 1; }
  done
  mkdir -p "$SELVEDGE_TEST_PW_CACHE" 2>/dev/null || { PW_SKIP="cannot create $SELVEDGE_TEST_PW_CACHE"; return 1; }
  log="$SELVEDGE_TEST_PW_CACHE/install.log"
  have=""
  if [ -f "$SELVEDGE_TEST_PW_CACHE/node_modules/playwright/package.json" ]; then
    have="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version))' \
      "$SELVEDGE_TEST_PW_CACHE/node_modules/playwright/package.json" 2>/dev/null)"
  fi
  if [ "$have" != "$PW_VERSION" ]; then
    npm install --prefix "$SELVEDGE_TEST_PW_CACHE" --no-audit --no-fund --no-save "playwright@$PW_VERSION" >"$log" 2>&1 \
      || { PW_SKIP="npm install playwright@$PW_VERSION into $SELVEDGE_TEST_PW_CACHE failed: $(tail -n 1 "$log" 2>/dev/null)"; return 1; }
  fi
  [ -x "$SELVEDGE_TEST_PW_CACHE/node_modules/.bin/playwright" ] \
    || { PW_SKIP="no playwright bin under $SELVEDGE_TEST_PW_CACHE/node_modules/.bin"; return 1; }
  [ -f "$SELVEDGE_TEST_PW_CACHE/node_modules/playwright/index.mjs" ] \
    || { PW_SKIP="no playwright/index.mjs under $SELVEDGE_TEST_PW_CACHE/node_modules"; return 1; }
  # ${CI:+--with-deps} is deliberately unquoted: empty ⇒ no argument (apt + sudo only on the CI runner).
  # shellcheck disable=SC2086
  "$SELVEDGE_TEST_PW_CACHE/node_modules/.bin/playwright" install ${CI:+--with-deps} chromium >"$log" 2>&1 \
    || { PW_SKIP="playwright install chromium into $PLAYWRIGHT_BROWSERS_PATH failed: $(tail -n 1 "$log" 2>/dev/null)"; return 1; }
  PW_MODULE="$SELVEDGE_TEST_PW_CACHE/node_modules/playwright/index.mjs"
  export PW_MODULE
  PW_READY=1
  return 0
}

# pw_require_or_skip — 0 ready; 1 hard FAIL (CI); 2 skip (not CI). Prints the outcome line.
pw_require_or_skip() {
  if pw_acquire; then
    echo "  playwright $PW_VERSION ready (cache $SELVEDGE_TEST_PW_CACHE)"
    return 0
  fi
  if [ -n "${CI:-}" ]; then
    echo "  FAIL playwright_install_failed: $PW_SKIP"
    return 1
  fi
  echo "  SKIP (playwright_install_failed: $PW_SKIP)"
  return 2
}
