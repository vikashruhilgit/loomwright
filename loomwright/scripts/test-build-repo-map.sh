#!/usr/bin/env bash
# test-build-repo-map.sh — hermetic offline self-tests for build-repo-map.sh (the owned flat
# repo-map builder). Runs the builder inside ISOLATED mktemp sandbox git repos with fixtures
# generated in-sandbox (see repo-map-fixtures/README.md), so it never touches the real repo.
# No network, no installs, bash-3.2 safe. Exit 0 = all pass, non-zero = any failure
# (auto-registered by ci.yml's test-*.sh glob).
#
# Cases:
#   1. Tier B map produced: banner + `## Directory skeleton` + `## Exported symbols`, exit 0
#   2. Excluded dirs (node_modules, .git) absent from the map
#   3. Exported symbols found per language fixture (.js / .py / .sh)
#   4. Symbol lines ordered by symbol count descending (most symbols first)
#   5. --max-chars cap enforced: file ≤ cap, truncation marker is the final line
#   6. Empty repo ⇒ map with header, exit 0
#   7. tree-sitter-absent path (PATH scrubbed to /usr/bin:/bin) ⇒ Tier B used, exit 0
#   8. Output dir auto-created (default <repo>/.supervisor/repo-map.md, dir absent in worktrees)
#   9. Env overrides honored: REPO_MAP_OUT + REPO_MAP_MAX_CHARS (no flags)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="$SCRIPT_DIR/build-repo-map.sh"

PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }

# All sandboxes live under ONE root so a single trap reliably cleans everything.
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/repomap-test.XXXXXX")"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

new_repo() {
  # Create an isolated sandbox git repo and echo its path.
  local r
  r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  ( cd "$r" && git init -q . ) >/dev/null 2>&1
  echo "$r"
}

plant_fixtures() {
  # Generate the fixture tree in-sandbox (the repo-map-fixtures/ dir documents this convention).
  local sb="$1"
  mkdir -p "$sb/src" "$sb/lib" "$sb/node_modules/leftpad" "$sb/a/b/c/d/e"
  cat > "$sb/src/app.js" <<'EOF'
export function main() {}
export const config = {};
export class Runner {}
EOF
  cat > "$sb/src/model.py" <<'EOF'
class Model:
    pass


def train(x):
    return x
EOF
  cat > "$sb/lib/util.sh" <<'EOF'
#!/usr/bin/env bash
do_thing() {
  echo hi
}
helper_fn() {
  echo there
}
EOF
  echo "module.exports = leftpad" > "$sb/node_modules/leftpad/index.js"
  echo "export function excluded_symbol() {}" > "$sb/node_modules/leftpad/dep.js"
  echo "deep fixture (tests dir-depth cap)" > "$sb/a/b/c/d/e/deep.txt"
  echo "# fixture readme" > "$sb/README.md"
}

# ---------------------------------------------------------------------------
# Cases 1–5 share one populated sandbox
# ---------------------------------------------------------------------------
SB="$(new_repo)"
plant_fixtures "$SB"
MAP="$SB/out/map.md"

bash "$BUILDER" --repo "$SB" --out "$MAP" >/dev/null 2>&1
RC=$?

# Case 1: banner + both sections, exit 0
if [ "$RC" -eq 0 ] && [ -f "$MAP" ] \
   && grep -q '^# Repo map (generated .*advisory, regenerate on demand)$' "$MAP" \
   && grep -q '^## Directory skeleton$' "$MAP" \
   && grep -q '^## Exported symbols$' "$MAP"; then
  ok "Tier B map produced with banner + both sections, exit 0"
else
  no "Tier B map missing banner/sections or non-zero exit (rc=$RC)"
fi

# Case 2: excluded dirs absent (node_modules pruned; .git pruned; no leaked symbols)
if ! grep -q 'node_modules' "$MAP" && ! grep -q 'excluded_symbol' "$MAP" \
   && ! grep -qE '(^|[[:space:]])- \.git/$' "$MAP"; then
  ok "excluded dirs (node_modules, .git) absent from map"
else
  no "excluded dir content leaked into map"
fi

# Case 2b: depth cap — dir at depth 4 (d) present, depth 5 (e) absent
if grep -qE '^[[:space:]]*- d/$' "$MAP" && ! grep -qE '^[[:space:]]*- e/$' "$MAP"; then
  ok "directory skeleton depth-capped (d/ present, e/ absent)"
else
  no "depth cap not enforced in directory skeleton"
fi

# Case 3: exported symbols per language fixture
if grep -E '^src/app\.js: ' "$MAP" | grep -q 'main' \
   && grep -E '^src/app\.js: ' "$MAP" | grep -q 'Runner' \
   && grep -E '^src/model\.py: ' "$MAP" | grep -q 'Model' \
   && grep -E '^src/model\.py: ' "$MAP" | grep -q 'train' \
   && grep -E '^lib/util\.sh: ' "$MAP" | grep -q 'do_thing'; then
  ok "exported symbols found for .js / .py / .sh fixtures"
else
  no "expected exported symbols missing (js: main/Runner, py: Model/train, sh: do_thing)"
fi

# Case 4: files ordered by symbol count descending (app.js has 3 symbols, model.py 2)
APP_LINE="$(grep -n '^src/app\.js: ' "$MAP" | cut -d: -f1 | head -n 1)"
PY_LINE="$(grep -n '^src/model\.py: ' "$MAP" | cut -d: -f1 | head -n 1)"
if [ -n "$APP_LINE" ] && [ -n "$PY_LINE" ] && [ "$APP_LINE" -lt "$PY_LINE" ]; then
  ok "symbol lines ordered by symbol count descending"
else
  no "symbol ordering wrong (app.js line=$APP_LINE, model.py line=$PY_LINE)"
fi

# Case 5: cap enforced with truncation marker on tiny --max-chars
CAPMAP="$SB/out/capped.md"
bash "$BUILDER" --repo "$SB" --out "$CAPMAP" --max-chars 200 >/dev/null 2>&1
RC=$?
CAPSIZE="$(wc -c < "$CAPMAP" 2>/dev/null | tr -d '[:space:]')"
if [ "$RC" -eq 0 ] && [ -f "$CAPMAP" ] \
   && [ -n "$CAPSIZE" ] && [ "$CAPSIZE" -le 200 ] \
   && [ "$(tail -n 1 "$CAPMAP")" = "[repo-map truncated at 200 chars]" ]; then
  ok "--max-chars cap enforced (size=$CAPSIZE ≤ 200) with truncation marker as final line"
else
  no "cap not enforced (rc=$RC size=$CAPSIZE tail='$(tail -n 1 "$CAPMAP" 2>/dev/null)')"
fi

# ---------------------------------------------------------------------------
# Case 6: empty repo ⇒ map with header, exit 0
# ---------------------------------------------------------------------------
EMPTY="$(new_repo)"
EMPTYMAP="$EMPTY/out/map.md"
bash "$BUILDER" --repo "$EMPTY" --out "$EMPTYMAP" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$EMPTYMAP" ] \
   && grep -q '^# Repo map (generated ' "$EMPTYMAP" \
   && grep -q '^## Directory skeleton$' "$EMPTYMAP" \
   && grep -q '^## Exported symbols$' "$EMPTYMAP"; then
  ok "empty repo ⇒ map with header + sections, exit 0"
else
  no "empty repo case failed (rc=$RC)"
fi

# ---------------------------------------------------------------------------
# Case 7: tree-sitter-absent path (PATH scrubbed) ⇒ Tier B used, exit 0
# ---------------------------------------------------------------------------
SCRUBMAP="$SB/out/scrubbed.md"
env PATH=/usr/bin:/bin /bin/bash "$BUILDER" --repo "$SB" --out "$SCRUBMAP" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$SCRUBMAP" ] \
   && grep -q '^## Exported symbols$' "$SCRUBMAP" \
   && grep -E '^src/app\.js: ' "$SCRUBMAP" | grep -q 'main'; then
  ok "tree-sitter-absent (scrubbed PATH) ⇒ Tier B floor used, exit 0"
else
  no "scrubbed-PATH Tier B path failed (rc=$RC)"
fi

# ---------------------------------------------------------------------------
# Case 8: output dir auto-created (default .supervisor/ path, absent in worktrees)
# ---------------------------------------------------------------------------
bash "$BUILDER" --repo "$SB" >/dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ -f "$SB/.supervisor/repo-map.md" ]; then
  ok "output dir auto-created (default <repo>/.supervisor/repo-map.md)"
else
  no "default output dir not auto-created (rc=$RC)"
fi

# ---------------------------------------------------------------------------
# Case 9: env overrides honored (REPO_MAP_OUT + REPO_MAP_MAX_CHARS, no flags)
# ---------------------------------------------------------------------------
ENVMAP="$SB/envout/map-env.md"
env REPO_MAP_OUT="$ENVMAP" REPO_MAP_MAX_CHARS=200 bash "$BUILDER" --repo "$SB" >/dev/null 2>&1
RC=$?
ENVSIZE="$(wc -c < "$ENVMAP" 2>/dev/null | tr -d '[:space:]')"
if [ "$RC" -eq 0 ] && [ -f "$ENVMAP" ] \
   && [ -n "$ENVSIZE" ] && [ "$ENVSIZE" -le 200 ] \
   && [ "$(tail -n 1 "$ENVMAP")" = "[repo-map truncated at 200 chars]" ]; then
  ok "env overrides REPO_MAP_OUT + REPO_MAP_MAX_CHARS honored"
else
  no "env overrides not honored (rc=$RC size=$ENVSIZE)"
fi

# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED ($PASS/$TOTAL)"
  exit 0
else
  echo "TESTS FAILED ($FAIL of $TOTAL failed)" >&2
  exit 1
fi
