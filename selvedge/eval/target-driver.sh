#!/usr/bin/env bash
# target-driver.sh — brings one known-answer target up on localhost for selvedge/eval/harness.mjs,
# and takes it down again. Owner-only, like the rest of selvedge/eval/; nothing in bin/ or lib/ runs
# it. The harness calls it (SELVEDGE_EVAL_TARGET_DRIVER replaces it):
#
#   target-driver.sh up <target.json> <workdir>   prints origin=<url> and root=<dir>; exit 0
#   target-driver.sh down <workdir>               stops what `up` started for that target
#   target-driver.sh stop <dir>                   once, after the last target: stops the eval's own
#                                                 Supabase project (never any other)
#   target-driver.sh fonts <clone> <out.js>       the font step of `up` alone (the harness never
#                                                 calls it; tests/test-target-driver-fonts.sh does)
#
# <target.json> is a case's target plus the harness's additions: {"kind": "commit", "repo", "sha",
# "setup": [the real-bugs.json setup lines recorded for that commit]} or {"kind": "variant", "path",
# "dir": <the variant folder>}.
#
# A commit target runs item 07's revival recipe as code, with each recorded setup line as its
# specification. Every line must be one of the known steps below, or `up` fails naming it:
#   git checkout <sha> (scratch clone …)   a scratch clone OUTSIDE this repo
#                                          ($SELVEDGE_EVAL_CLONE_DIR, default
#                                          ${TMPDIR}/selvedge-eval-sm/clone), shared by every target
#   supabase/config.toml …                 copied READ-ONLY from the owner's local checkout
#                                          ($SELVEDGE_EVAL_SM_CHECKOUT; never written), patched to
#                                          project_id "selvedge-eval-sm" and ports 543xx -> 553xx
#   npm ci                                 when package-lock.json differs from the last install
#   supabase db reset --local …            this commit's migrations and seed, on that project only
#   fixture SQL (scratch DB only): <sql>   run with psql on that project's database
#   .env.local: …                          local Supabase URL/keys from `supabase status -o env`, a
#                                          local NEXTAUTH_SECRET, dummy Stripe test keys,
#                                          EMAIL_FROM, BETA_CLUB_CAP=0
#   NEXT_FONT_GOOGLE_MOCKED_RESPONSES: …   the commit's own next/font/google CSS URLs (computed with
#                                          the commit's own next), fetched with a desktop
#                                          Chrome user agent, again (up to five tries) when
#                                          Google serves one as fonts.gstatic.com/l/ files
#   rm -rf .next; next dev -p 3471 …       a fresh dev server per commit (also for the recorded
#   next dev -p 3471, already running …    "already running" lines), up when /login answers
#   sign in as …                           a probe step of item 07, not a revival step: skipped
# A step that no longer matches the commit (a missing file, a failed command) exits 1 with
# `target-driver: FAIL step '<step>': <why>` on stderr; nothing is guessed around it.
#
# A variant target is served with node: the variant folder is copied to <workdir>/app and its
# app-server.mjs runs `serve`, like the selvedge tests' fixture app.
#
# Needs bash 3.2+, node, git; for a commit also docker (running), supabase, npm, psql, curl, lsof.
set -uo pipefail

PROJECT_ID="selvedge-eval-sm"
PORT=3471
# A current desktop Chrome: for an older one Google serves some families (Archivo, for one) as
# fonts.gstatic.com/l/font?kit=… files, whose query Turbopack refuses ("next/font/google queries have
# exactly one entry"), and the page answers 500. Even with this agent Google still serves that form
# now and then, so a newer agent does not fix it alone: fonts_mock asks again (FONT_TRIES).
CHROME_UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
STEP="start"

step() { STEP="$1"; echo "target-driver: step: $1" >&2; }
fail() { echo "target-driver: FAIL step '$STEP': $*" >&2; exit 1; }
usage() { echo "usage: target-driver.sh up <target.json> <workdir> | down <workdir> | stop <dir> | fonts <clone> <out.js>" >&2; exit 2; }

clone_dir() { printf '%s\n' "${SELVEDGE_EVAL_CLONE_DIR:-${TMPDIR:-/tmp}/selvedge-eval-sm/clone}"; }
jget() { node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))[process.argv[2]]; process.stdout.write(v===undefined||v===null?"":String(v))' "$1" "$2"; }
realdir() { (cd "$1" 2>/dev/null && pwd -P); }

# kill_tree <pid> — the pid and every descendant, children first.
kill_tree() {
  local p c
  p="$1"
  for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  kill "$p" 2>/dev/null || true
}

stop_pidfile() {
  local f="$1" pid i=0
  [ -f "$f" ] || return 0
  pid="$(cat "$f")"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill_tree "$pid"
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.2; done
  fi
  rm -f "$f"
}

# The eval clone's own config must name the eval project and no 543xx port before anything uses it.
check_config() {
  local cfg="$1/supabase/config.toml"
  [ -f "$cfg" ] || return 1
  grep -qE "^project_id = \"$PROJECT_ID\"\$" "$cfg" || return 1
  if grep -qE '(^|[^0-9])543[0-9][0-9]([^0-9]|$)' "$cfg"; then return 1; fi
  return 0
}

# setup_plan <target.json> — prints "<kind>\t<arg>" per setup line, or fails on an unknown line.
setup_plan() {
  node -e '
const t = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const rules = [
  [/^git checkout [0-9a-f]{40}\b/, "checkout"],
  [/^supabase\/config\.toml\b/, "config"],
  [/^npm ci$/, "npm"],
  [/^supabase db reset --local\b/, "reset"],
  [/^fixture SQL \(scratch DB only\): (.+)$/, "sql"],
  [/^\.env\.local:/, "env"],
  [/^NEXT_FONT_GOOGLE_MOCKED_RESPONSES:/, "fonts"],
  [/^(rm -rf \.next; )?next dev -p 3471\b/, "dev"],
  [/^sign in as /, "probe"],
];
let bad = 0;
for (const line of Array.isArray(t.setup) ? t.setup : []) {
  const r = rules.find(([re]) => re.test(line));
  if (!r) { process.stderr.write(`unknown setup line: ${line}\n`); bad = 1; continue; }
  const m = r[0].exec(line);
  process.stdout.write(`${r[1]}\t${r[1] === "sql" ? m[1].replace(/\s+/g, " ") : ""}\n`);
}
process.exit(bad);' "$1"
}

# fonts_mock <clone> <out.js> — the commit's next/font/google CSS URLs, each fetched (again, up to
# FONT_TRIES times, while Google serves it as fonts.gstatic.com/l/ files).
fonts_mock() {
  node - "$1" "$2" "$CHROME_UA" <<'EOF'
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const [root, out, ua] = process.argv.slice(2);
const g = path.join(root, 'node_modules', 'next', 'dist', 'compiled', '@next', 'font', 'dist', 'google');
const { validateGoogleFontFunctionCall } = require(path.join(g, 'validate-google-font-function-call.js'));
const { getFontAxes } = require(path.join(g, 'get-font-axes.js'));
const { getGoogleFontsUrl } = require(path.join(g, 'get-google-fonts-url.js'));
const files = [];
const walk = (d) => {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (['node_modules', '.next', '.git', 'supabase'].includes(e.name)) continue;
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(t|j)sx?$/.test(e.name)) files.push(p);
  }
};
walk(root);
// The options object literal starting at text[open] ('{'), by brace depth (strings skipped).
const objectAt = (text, open) => {
  let depth = 0;
  let q = null;
  for (let i = open; i < text.length; i++) {
    const ch = text[i];
    if (q) { if (ch === '\\') i++; else if (ch === q) q = null; continue; }
    if (ch === '"' || ch === "'" || ch === '`') q = ch;
    else if (ch === '{') depth++;
    else if (ch === '}' && --depth === 0) return text.slice(open, i + 1);
  }
  throw new Error('unbalanced options object');
};
const urls = new Set();
for (const f of files) {
  const text = fs.readFileSync(f, 'utf8');
  const im = /import\s*\{([^}]*)\}\s*from\s*['"]next\/font\/google['"]/.exec(text);
  if (!im) continue;
  for (const spec of im[1].split(',').map((s) => s.trim()).filter(Boolean)) {
    const [fn, local] = spec.split(/\s+as\s+/).map((s) => s.trim());
    const re = new RegExp(`\\b${(local || fn).replace(/\$/g, '\\$')}\\s*\\(\\s*\\{`, 'g');
    let m;
    while ((m = re.exec(text))) {
      const options = new Function(`return (${objectAt(text, m.index + m[0].length - 1)});`)();
      const v = validateGoogleFontFunctionCall(fn, options);
      urls.add(getGoogleFontsUrl(v.fontFamily, getFontAxes(v.fontFamily, v.weights, v.styles, v.selectedVariableAxes), v.display));
    }
  }
}
const mocks = {};
// Google serves the same URL as fonts.gstatic.com/l/ files now and then (about 1 request in 15 for
// MuseoModerno, measured 2026-11-23), whatever the user agent: ask again, up to FONT_TRIES times.
const FONT_TRIES = 5;
for (const u of urls) {
  for (let i = 1; ; i++) {
    mocks[u] = execFileSync('curl', ['-fsSL', '--max-time', '60', '-A', ua, u], { encoding: 'utf8' });
    if (!mocks[u].includes('fonts.gstatic.com/l/')) break;
    if (i === FONT_TRIES) throw new Error(`${u} was served as fonts.gstatic.com/l/ files ${FONT_TRIES} times in a row, which Turbopack refuses`);
  }
}
fs.writeFileSync(out, `module.exports = ${JSON.stringify(mocks, null, 2)};\n`);
process.stdout.write(`${urls.size}\n`);
EOF
}

# fonts_step <clone> <out.js> <err file> — the font step as `up` and `fonts` run it: prints the
# number of stylesheets mocked, or fails the step with the error's own line (Error, TypeError,
# SyntaxError, …: not the stack's tail).
fonts_step() {
  local n
  n="$(fonts_mock "$1" "$2" 2>"$3")" || fail "$(grep -m1 -E '^[A-Za-z]*Error(:|$)' "$3" || tail -n 3 "$3")"
  echo "$n"
}

up_variant() {
  local target="$1" work="$2" dir port i=0
  step "variant folder"
  dir="$(jget "$target" dir)"
  [ -n "$dir" ] && [ -f "$dir/app-server.mjs" ] || fail "no app-server.mjs in the variant folder '$dir'"
  rm -rf "$work/app" && mkdir -p "$work" && cp -R "$dir" "$work/app" || fail "cannot copy $dir"
  step "node app-server.mjs serve"
  rm -f "$work/servers.json"
  nohup node "$work/app/app-server.mjs" serve "$work/servers.json" </dev/null >"$work/app.log" 2>&1 &
  echo "$!" >"$work/app.pid"
  while [ ! -s "$work/servers.json" ] && [ "$i" -lt 150 ]; do i=$((i + 1)); sleep 0.2; done
  port="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).app.port))' "$work/servers.json" 2>/dev/null)"
  [ -n "$port" ] || fail "the variant app did not start: $(tail -n 3 "$work/app.log")"
  echo "origin=http://localhost:$port"
  echo "root=$work/app"
}

up_commit() {
  local target="$1" work="$2" gateway repo sha clone plan kinds lock have envfile secret i code n db_url api_url anon service jwt kind arg k tool
  repo="$(jget "$target" repo)"; sha="$(jget "$target" sha)"
  [ -n "$repo" ] && [ -n "$sha" ] || { STEP="target"; fail "target.json names no repo and sha"; }
  mkdir -p "$work" || fail "cannot create $work"
  step "setup lines"
  plan="$(setup_plan "$target" 2>"$work/setup.err")" || fail "$(cat "$work/setup.err")"
  kinds="$(printf '%s\n' "$plan" | cut -f1 | sort -u | tr '\n' ' ')"
  for k in checkout config npm reset env fonts dev; do
    case " $kinds " in *" $k "*) ;; *) fail "the recorded setup has no '$k' step for $repo@$sha; the recipe would be guessed" ;; esac
  done
  for tool in git node npm docker supabase psql curl lsof; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH"; done

  clone="$(clone_dir)"
  step "scratch clone"
  [ -n "${SELVEDGE_EVAL_SM_CHECKOUT:-}" ] || fail "SELVEDGE_EVAL_SM_CHECKOUT (the owner's local checkout, read for supabase/config.toml only) is not set"
  mkdir -p "$(dirname "$clone")" || fail "cannot create $(dirname "$clone")"
  if [ ! -d "$clone/.git" ]; then
    git clone -q "https://github.com/$repo.git" "$clone" >"$work/clone.log" 2>&1 || fail "git clone https://github.com/$repo.git: $(tail -n 2 "$work/clone.log")"
  fi
  [ "$(realdir "$clone")" != "$(realdir "$SELVEDGE_EVAL_SM_CHECKOUT")" ] || fail "the scratch clone $clone is the owner's checkout; it must be a separate folder"
  step "git checkout $sha"
  git -C "$clone" cat-file -e "$sha^{commit}" 2>/dev/null || git -C "$clone" fetch -q origin >"$work/fetch.log" 2>&1 || fail "git fetch: $(tail -n 2 "$work/fetch.log")"
  git -C "$clone" checkout -q --force --detach "$sha" 2>"$work/checkout.err" || fail "$(cat "$work/checkout.err")"
  git -C "$clone" clean -fdxq -e node_modules -e .env.local -e supabase/config.toml -e supabase/.temp -e supabase/.branches >/dev/null 2>&1 || fail "git clean failed"

  step "supabase/config.toml"
  [ -f "$SELVEDGE_EVAL_SM_CHECKOUT/supabase/config.toml" ] || fail "$SELVEDGE_EVAL_SM_CHECKOUT/supabase/config.toml does not exist"
  [ -d "$clone/supabase/migrations" ] || fail "this commit has no supabase/migrations"
  node -e '
const fs = require("fs");
let t = fs.readFileSync(process.argv[1], "utf8");
t = t.replace(/^project_id = ".*"$/m, `project_id = "${process.argv[3]}"`).replace(/(^|[^0-9])543([0-9][0-9])(?![0-9])/g, "$1553$2");
fs.writeFileSync(process.argv[2], t);' "$SELVEDGE_EVAL_SM_CHECKOUT/supabase/config.toml" "$clone/supabase/config.toml" "$PROJECT_ID" || fail "cannot patch config.toml"
  check_config "$clone" || fail "the patched config.toml does not name project_id \"$PROJECT_ID\" with 553xx ports only"

  step "npm ci"
  lock="$(shasum -a 256 "$clone/package-lock.json" 2>/dev/null | cut -d' ' -f1)"
  [ -n "$lock" ] || fail "this commit has no package-lock.json"
  have="$(cat "$clone/node_modules/.selvedge-eval-lock" 2>/dev/null || true)"
  if [ "$have" != "$lock" ]; then
    (cd "$clone" && npm ci --no-audit --no-fund) >"$work/npm-ci.log" 2>&1 || fail "npm ci: $(tail -n 3 "$work/npm-ci.log")"
    echo "$lock" >"$clone/node_modules/.selvedge-eval-lock"
  fi

  step "supabase start ($PROJECT_ID)"
  docker info >/dev/null 2>&1 || fail "docker is not running"
  if ! supabase status --workdir "$clone" >/dev/null 2>&1; then
    supabase start --workdir "$clone" -x studio,imgproxy,logflare,vector,edge-runtime >"$work/supabase-start.log" 2>&1 || fail "supabase start: $(tail -n 3 "$work/supabase-start.log")"
  fi
  step "supabase db reset --local"
  # `db reset` applies the migrations and seed.sql, restarts the storage, auth and realtime
  # containers, then seeds the [storage.buckets] through the API gateway. The gateway (kong) keeps
  # the restarted storage container's old address and answers 502, so that last call fails although
  # the database is done. Only in that case: restart this project's own gateway, then run the CLI's
  # own last step, `supabase seed buckets`. Any other failure stops the run.
  gateway="$(sed -n '/^\[api\]/,/^\[/s/^port = \([0-9]*\)$/\1/p' "$clone/supabase/config.toml" | head -n 1)"
  [ -n "$gateway" ] || fail "the patched config.toml names no [api] port"
  if ! supabase db reset --local --workdir "$clone" >"$work/db-reset.log" 2>&1; then
    grep -q 'Restarting containers' "$work/db-reset.log" && grep -q 'Error status 502' "$work/db-reset.log" \
      || fail "supabase db reset: $(grep -v '^$' "$work/db-reset.log" | tail -n 3 | tr '\n' ' ')"
    echo "target-driver: db reset applied the database but the gateway answered 502 on its bucket seeding; restarting supabase_kong_$PROJECT_ID, then supabase seed buckets" >&2
    docker restart "supabase_kong_$PROJECT_ID" >"$work/kong-restart.log" 2>&1 || fail "docker restart supabase_kong_$PROJECT_ID: $(tail -n 2 "$work/kong-restart.log")"
    i=0
    # Wait (up to 120 s) until the gateway answers with anything but no answer (000) or 502.
    while [ "$i" -lt 120 ]; do
      case "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$gateway/storage/v1/bucket" 2>/dev/null)" in 000|502) ;; *) break ;; esac
      i=$((i + 2)); sleep 2
    done
    supabase seed buckets --workdir "$clone" >"$work/seed-buckets.log" 2>&1 || fail "supabase seed buckets: $(grep -v '^$' "$work/seed-buckets.log" | tail -n 3 | tr '\n' ' ')"
  fi
  supabase status -o env --workdir "$clone" >"$work/status.env" 2>/dev/null || fail "supabase status -o env failed"
  db_url="$(sed -n 's/^DB_URL="\(.*\)"$/\1/p' "$work/status.env")"
  api_url="$(sed -n 's/^API_URL="\(.*\)"$/\1/p' "$work/status.env")"
  anon="$(sed -n 's/^ANON_KEY="\(.*\)"$/\1/p' "$work/status.env")"
  service="$(sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p' "$work/status.env")"
  jwt="$(sed -n 's/^JWT_SECRET="\(.*\)"$/\1/p' "$work/status.env")"
  [ -n "$db_url" ] && [ -n "$api_url" ] && [ -n "$anon" ] && [ -n "$service" ] || fail "supabase status -o env lacks DB_URL, API_URL, ANON_KEY or SERVICE_ROLE_KEY"
  case "$db_url$api_url" in *:543[0-9][0-9]*) fail "the eval project answers on a 543xx port; refusing (the owner's stack keeps 543xx)" ;; esac

  n=0
  while IFS="$(printf '\t')" read -r kind arg; do
    [ "$kind" = "sql" ] || continue
    n=$((n + 1))
    step "fixture SQL $n"
    psql "$db_url" -v ON_ERROR_STOP=1 -q -c "$arg" >>"$work/fixture-sql.log" 2>&1 || fail "psql: $(tail -n 2 "$work/fixture-sql.log")"
  done <<EOF
$plan
EOF

  step ".env.local"
  secret="$(cat "$(dirname "$clone")/nextauth-secret" 2>/dev/null || true)"
  if [ -z "$secret" ]; then secret="$(node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))')"; echo "$secret" >"$(dirname "$clone")/nextauth-secret"; fi
  envfile="$clone/.env.local"
  {
    echo "NEXT_PUBLIC_SUPABASE_URL=$api_url"
    echo "NEXT_PUBLIC_SUPABASE_ANON_KEY=$anon"
    echo "SUPABASE_SERVICE_ROLE_KEY=$service"
    echo "SUPABASE_JWT_SECRET=$jwt"
    echo "DATABASE_URL=$db_url"
    echo "DIRECT_URL=$db_url"
    echo "NEXTAUTH_URL=http://localhost:$PORT"
    echo "NEXT_PUBLIC_APP_URL=http://localhost:$PORT"
    echo "NEXTAUTH_SECRET=$secret"
    echo "STRIPE_SECRET_KEY=sk_test_selvedgeevaldummy"
    echo "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_selvedgeevaldummy"
    echo "STRIPE_WEBHOOK_SECRET=whsec_selvedgeevaldummy"
    echo "STRIPE_CONNECT_WEBHOOK_SECRET=whsec_selvedgeevaldummy"
    echo "EMAIL_FROM=selvedge-eval@example.invalid"
    echo "BETA_CLUB_CAP=0"
  } >"$envfile" || fail "cannot write $envfile"

  step "NEXT_FONT_GOOGLE_MOCKED_RESPONSES"
  n="$(fonts_step "$clone" "$work/font-mocks.js" "$work/fonts.err")" || exit 1
  echo "target-driver: $n next/font/google stylesheet(s) mocked" >&2

  step "next dev -p $PORT"
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then fail "port $PORT is already in use (not by this target); free it first"; fi
  [ -x "$clone/node_modules/.bin/next" ] || fail "node_modules/.bin/next is missing after npm ci"
  rm -rf "$clone/.next"
  # The background job's own shell must not keep this script's stdout open: the harness reads it to
  # the end, and would wait for the dev server to exit.
  (cd "$clone" && NEXT_FONT_GOOGLE_MOCKED_RESPONSES="$work/font-mocks.js" NEXT_TELEMETRY_DISABLED=1 nohup ./node_modules/.bin/next dev -p "$PORT" </dev/null >"$work/next-dev.log" 2>&1 &
    echo "$!" >"$work/next.pid") </dev/null >/dev/null 2>&1
  i=0; code=000
  while [ "$i" -lt "${SELVEDGE_EVAL_START_TIMEOUT_S:-900}" ]; do
    code="$(curl -s -o /dev/null -m 120 -w '%{http_code}' "http://localhost:$PORT/login" 2>/dev/null || true)"
    case "$code" in 2??|3??) break ;; esac
    kill -0 "$(cat "$work/next.pid")" 2>/dev/null || fail "next dev exited: $(tail -n 3 "$work/next-dev.log")"
    i=$((i + 5)); sleep 5
  done
  case "$code" in 2??|3??) ;; *) fail "GET /login answered $code within ${SELVEDGE_EVAL_START_TIMEOUT_S:-900} s: $(tail -n 3 "$work/next-dev.log")" ;; esac
  echo "origin=http://localhost:$PORT"
  echo "root=$clone"
}

case "${1:-}" in
  up)
    [ "$#" -eq 3 ] || usage
    [ -f "$2" ] || { echo "target-driver: FAIL step 'target': $2 does not exist" >&2; exit 1; }
    mkdir -p "$3" || exit 1
    work="$(cd "$3" && pwd)"
    case "$(jget "$2" kind)" in
      commit) up_commit "$2" "$work" ;;
      variant) up_variant "$2" "$work" ;;
      *) STEP="target"; fail "target kind is neither commit nor variant" ;;
    esac
    ;;
  down)
    [ "$#" -eq 2 ] || usage
    stop_pidfile "$2/next.pid"
    stop_pidfile "$2/app.pid"
    exit 0
    ;;
  fonts)
    # fonts <clone> <out.js>: the font step alone (what `up` runs for a commit), for the tests.
    [ "$#" -eq 3 ] || usage
    STEP="NEXT_FONT_GOOGLE_MOCKED_RESPONSES"
    err="$(mktemp "${TMPDIR:-/tmp}/target-driver-fonts.XXXXXX")" || exit 1
    ( fonts_step "$2" "$3" "$err" >/dev/null ); rc=$?
    rm -f "$err"
    exit "$rc"
    ;;
  stop)
    [ "$#" -eq 2 ] || usage
    clone="$(clone_dir)"
    if [ -d "$clone/supabase" ] && check_config "$clone" && command -v supabase >/dev/null 2>&1; then
      supabase stop --workdir "$clone" >/dev/null 2>&1 || true
    fi
    exit 0
    ;;
  *) usage ;;
esac
