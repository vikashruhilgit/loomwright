#!/usr/bin/env bash
# test-target-driver-fonts.sh — pins the eval target driver's font step (`target-driver.sh fonts`):
# Google now and then serves a next/font/google CSS URL as fonts.gstatic.com/l/ files, which
# Turbopack refuses, so the driver asks again, up to five tries in all, and only then fails, naming the URL.
#
# Hermetic: a fake clone (one layout importing next/font/google, stub next internals) and a fake
# `curl` on PATH that serves the /l/ form for its first $FAKE_L_COUNT calls. No network.
# Needs node and bash; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="$(cd "$TESTS_DIR/.." && pwd)/eval/target-driver.sh"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

command -v node >/dev/null 2>&1 || { echo "  FAIL node is not on PATH"; echo "test-target-driver-fonts: 0 passed, 1 failed"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-driver-fonts.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# The fake clone: one layout calling MuseoModerno from next/font/google, and the three next
# internals the font step requires, reduced to what it reads.
C="$TMP/clone"
G="$C/node_modules/next/dist/compiled/@next/font/dist/google"
mkdir -p "$C/src/app" "$G"
cat > "$C/src/app/layout.tsx" <<'EOF'
import { MuseoModerno } from 'next/font/google';
const museo = MuseoModerno({ weight: ['400', '700'], subsets: ['latin'] });
export default function Layout() { return museo; }
EOF
cat > "$G/validate-google-font-function-call.js" <<'EOF'
exports.validateGoogleFontFunctionCall = (fn, o) => ({ fontFamily: fn, weights: o.weight, styles: [], selectedVariableAxes: undefined, display: 'swap' });
EOF
echo 'exports.getFontAxes = (f, w) => ({ wght: w });' > "$G/get-font-axes.js"
echo 'exports.getGoogleFontsUrl = (f, a, d) => `https://fonts.googleapis.com/css2?family=${f}:wght@${a.wght.join(";")}&display=${d}`;' > "$G/get-google-fonts-url.js"

# The fake curl: the /l/ form for the first $FAKE_L_COUNT calls, then the normal form.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_CURL_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_CURL_COUNT"
if [ "$n" -le "${FAKE_L_COUNT:-0}" ]; then echo '@font-face { src: url(https://fonts.gstatic.com/l/font?kit=abc) }'
else echo '@font-face { src: url(https://fonts.gstatic.com/s/museomoderno/v29/x.woff2) }'; fi
EOF
chmod +x "$TMP/bin/curl"

# fonts <bad calls> — runs the font step with the fake curl; sets rc, err, calls, out.
fonts() {
  export FAKE_L_COUNT="$1" FAKE_CURL_COUNT="$TMP/count.$1"
  rm -f "$FAKE_CURL_COUNT" "$TMP/mocks.js"
  err="$(PATH="$TMP/bin:$PATH" bash "$DRIVER" fonts "$C" "$TMP/mocks.js" 2>&1 >/dev/null)"; rc=$?
  calls="$(cat "$FAKE_CURL_COUNT" 2>/dev/null || echo 0)"
  out="$(cat "$TMP/mocks.js" 2>/dev/null || true)"
}

fonts 0
{ [ "$rc" -eq 0 ] && [ "$calls" = 1 ] && grep -qF '/s/museomoderno/' <<<"$out" && grep -qF 'family=MuseoModerno:wght@400;700&display=swap' <<<"$out"; } \
  && ok "a normal response is used as is: one fetch per URL, the mock keyed by the font URL" || ko "normal: rc=$rc calls=$calls err='$err' out='$out'"
fonts 2
{ [ "$rc" -eq 0 ] && [ "$calls" = 3 ] && grep -qF '/s/museomoderno/' <<<"$out" && ! grep -qF 'gstatic.com/l/' <<<"$out"; } \
  && ok "two /l/ responses, then a normal one: asked three times, the normal one kept" || ko "retry: rc=$rc calls=$calls err='$err' out='$out'"
fonts 4
{ [ "$rc" -eq 0 ] && [ "$calls" = 5 ]; } && ok "four /l/ responses: the fifth try is still made and used" || ko "fifth try: rc=$rc calls=$calls err='$err'"
fonts 99
{ [ "$rc" -eq 1 ] && [ "$calls" = 5 ] && [ ! -e "$TMP/mocks.js" ] && [ "$(wc -l <<<"$err" | tr -d ' ')" = 1 ] \
  && grep -qxF "target-driver: FAIL step 'NEXT_FONT_GOOGLE_MOCKED_RESPONSES': Error: https://fonts.googleapis.com/css2?family=MuseoModerno:wght@400;700&display=swap was served as fonts.gstatic.com/l/ files 5 times in a row, which Turbopack refuses" <<<"$err"; } \
  && ok "/l/ every time: five tries, then exit 1 with ONE FAIL line carrying the Error line (no stack), no mock file written" || ko "give up: rc=$rc calls=$calls err='$err'"

# Any other error class (here a TypeError from the next internals) is reported by its own line too.
C2="$TMP/clone-typeerror"; cp -R "$C" "$C2"
echo 'exports.validateGoogleFontFunctionCall = () => { throw new TypeError("unknown font option"); };' > "$C2/node_modules/next/dist/compiled/@next/font/dist/google/validate-google-font-function-call.js"
err="$(PATH="$TMP/bin:$PATH" bash "$DRIVER" fonts "$C2" "$TMP/mocks2.js" 2>&1 >/dev/null)"; rc=$?
{ [ "$rc" -eq 1 ] && [ "$(wc -l <<<"$err" | tr -d ' ')" = 1 ] \
  && grep -qxF "target-driver: FAIL step 'NEXT_FONT_GOOGLE_MOCKED_RESPONSES': TypeError: unknown font option" <<<"$err"; } \
  && ok "a TypeError is reported by its own line, not the stack's tail" || ko "TypeError line: rc=$rc err='$err'"

echo "test-target-driver-fonts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
