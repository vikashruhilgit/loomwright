#!/usr/bin/env bash
# test-setup-twin.sh — STATIC, fixture-driven self-tests for setup-twin.sh (the `/setup twin`
# module engine: Twin-readiness `check` + guided cold-start `bootstrap`). STATIC ONLY: no graphify
# CLI, no network, no Docker — so it runs on the plugin's Ubuntu CI like every other test-*.sh
# (auto-registered by ci.yml's test-*.sh glob). Exit 0 = all pass, 1 = any failure.
#
# Mirrors test-setup-observability.sh / test-build-bridge.sh convention: pass/fail counters,
# ok()/no() helpers, a "RESULT: N passed, M failed" tail, exit 1 on any failure. Every fixture is a
# `mktemp -d` dir passed via --root; a `trap ... EXIT` cleans them up. The harness NEVER touches the
# developer's real $HOME/.claude/ or the real repo's .supervisor/.
#
# Covers (each = an acceptance criterion):
#   (a)  check on populated vs empty fixture (bootstrapped vs needs bootstrap; graph cell absent)
#   (b)  prefix-tolerant staleness (abbreviated built_at == fresh; divergent sha == stale; non-git
#        --root → freshness unknown, never a crash) — guards the exact-`!=` regression
#   (c)  graphify-absent bootstrap GUIDES without failing (exit 0 + graphify guidance text)
#   (d)  scoped-writes invariant (never overwrites CLAUDE.md; never creates CLAUDE.md; skeleton is
#        stdout-only; never writes <root>/.claude/settings.json)
#   (d2) write-containment vs config redirect (explicit --out beats .build_bridge.out; nothing lands
#        in the redirect dir) — python3-gated skip-with-pass when python3 unavailable
#   (e)  idempotency (check twice → byte-identical stdout; bootstrap twice → exit 0 + same verdict)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TWIN="$HERE/setup-twin.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# ---- fixture lifecycle ------------------------------------------------------
FIXTURES=()
mkfix() { local d; d="$(mktemp -d)"; FIXTURES+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${FIXTURES[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

# new git repo with an identity + one commit (so HEAD resolves). Echoes the dir.
newgit() {
  local d; d="$(mkfix)"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && echo seed > seed.txt && git add seed.txt && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "$d"
}

# write_graph <dir> <built_at_commit> — minimal graph the build-bridge.py engine accepts
# (reuses the exact minimal shape test-build-bridge.sh constructs: built_at_commit + nodes[] with
# source_file + integer community + a links[] array).
write_graph() {
  local dir="$1" built_at="$2"
  mkdir -p "$dir/graphify-out"
  cat > "$dir/graphify-out/graph.json" <<EOF
{"built_at_commit":"$built_at","directed":false,"multigraph":false,"graph":{},"nodes":[
  {"id":"a","source_file":"loomwright/agents/supervisor.md","community":1},
  {"id":"b","source_file":"loomwright/skills/lessonfile.md","community":1}
],"links":[]}
EOF
}

# run the twin helper against a fixture; prints stdout, captures rc into the named var.
# usage: out="$(twin <dir> check)" ; rc=$?
# NOTE: helper stderr is passed THROUGH to the test's stderr (not swallowed) so a fail-safe
# diagnostic — e.g. "[bridge] build-bridge.sh exited non-zero — continuing" — stays visible in
# CI logs when a bootstrap exits 0 but a step silently errored. stdout (the parsed cells) is
# unaffected: command substitution captures stdout only.
twin() { bash "$TWIN" --root "$1" "$2"; }

# extract the graph cell value from a `check`/render report.
graph_cell() { printf '%s\n' "$1" | grep -E '^[[:space:]]*graph:' | sed -E 's/^[[:space:]]*graph:[[:space:]]*//'; }
verdict_line() { printf '%s\n' "$1" | grep -E '^Twin readiness:' | sed -E 's/^Twin readiness:[[:space:]]*//'; }

PY="$(command -v python3 || command -v python || true)"

# ============================================================================
echo "== 0. script under test exists =="
[ -f "$TWIN" ] && ok "setup-twin.sh present" || no "setup-twin.sh missing at $TWIN"
if [ ! -f "$TWIN" ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

# ============================================================================
echo "== (a) check: populated fixture → bootstrapped; empty fixture → needs bootstrap =="
# Populated: graph + bridge + CLAUDE.md all present. Use a git fixture with a fresh graph so the
# graph cell is "present (fresh)" (any present* satisfies the verdict's has_graph).
Pa="$(newgit)"
HEADa="$( cd "$Pa" && git rev-parse HEAD )"
write_graph "$Pa" "${HEADa:0:8}"
mkdir -p "$Pa/.supervisor/bridge"; echo '{}' > "$Pa/.supervisor/bridge/bridge.json"
echo "# CLAUDE.md" > "$Pa/CLAUDE.md"
out_pop="$(twin "$Pa" check)"; rc_pop=$?
[ "$rc_pop" -eq 0 ] && ok "check exits 0 on populated fixture" || no "check non-zero on populated ($rc_pop)"
[ "$(verdict_line "$out_pop")" = "bootstrapped" ] && ok "populated fixture verdict = bootstrapped" || no "populated verdict not bootstrapped (got: $(verdict_line "$out_pop"))"

# Empty: none of the three present.
Ea="$(mkfix)"
out_emp="$(twin "$Ea" check)"; rc_emp=$?
[ "$rc_emp" -eq 0 ] && ok "check exits 0 on empty fixture" || no "check non-zero on empty ($rc_emp)"
[ "$(verdict_line "$out_emp")" = "needs bootstrap" ] && ok "empty fixture verdict = needs bootstrap" || no "empty verdict not 'needs bootstrap' (got: $(verdict_line "$out_emp"))"
printf '%s' "$(graph_cell "$out_emp")" | grep -q '^absent$' && ok "empty fixture graph cell = absent" || no "empty graph cell not 'absent' (got: $(graph_cell "$out_emp"))"

# (a2) STALE graph + bridge + CLAUDE.md → verdict 'needs bootstrap' (a drifting graph is NOT
# bootstrapped; matches the command layer's 'needs bootstrap (stale graph)' dashboard cell).
A2="$(newgit)"
write_graph "$A2" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"   # divergent sha → stale
mkdir -p "$A2/.supervisor/bridge"; echo '{}' > "$A2/.supervisor/bridge/bridge.json"
echo "# CLAUDE.md" > "$A2/CLAUDE.md"
out_a2="$(twin "$A2" check)"
printf '%s' "$(graph_cell "$out_a2")" | grep -qi 'stale' && ok "stale-graph fixture graph cell = stale" || no "stale-graph cell not stale (got: $(graph_cell "$out_a2"))"
[ "$(verdict_line "$out_a2")" = "needs bootstrap" ] && ok "stale graph + bridge + CLAUDE.md → verdict 'needs bootstrap' (stale ≠ bootstrapped)" || no "stale-graph fixture wrongly verdict '$(verdict_line "$out_a2")' (expected 'needs bootstrap')"

# ============================================================================
echo "== (b) prefix-tolerant staleness — guards the exact-'!=' regression =="
Sb="$(newgit)"
HEADb="$( cd "$Sb" && git rev-parse HEAD )"
# (b1) ABBREVIATED prefix of the real HEAD → must read as fresh (NOT stale).
write_graph "$Sb" "${HEADb:0:8}"
out_fresh="$(twin "$Sb" check)"
cell_fresh="$(graph_cell "$out_fresh")"
printf '%s' "$cell_fresh" | grep -q 'present (fresh)' && ok "abbreviated-prefix built_at → graph cell 'present (fresh)' (prefix-tolerant compare holds)" || no "abbreviated prefix wrongly NOT fresh (got: $cell_fresh)"
printf '%s' "$cell_fresh" | grep -qi 'stale' && no "abbreviated-prefix fixture wrongly flagged stale (exact-!= regression!)" || ok "abbreviated-prefix fixture NOT flagged stale"
# (b2) genuinely divergent sha → must read as stale.
write_graph "$Sb" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
out_stale="$(twin "$Sb" check)"
cell_stale="$(graph_cell "$out_stale")"
printf '%s' "$cell_stale" | grep -qi 'stale' && ok "divergent built_at → graph cell contains 'stale'" || no "divergent built_at NOT flagged stale (got: $cell_stale)"
# (b3 bonus) non-git --root fixture WITH a graph → 'freshness unknown', never a crash.
Nb="$(mkfix)"
write_graph "$Nb" "${HEADb:0:8}"
out_ng="$(twin "$Nb" check)"; rc_ng=$?
[ "$rc_ng" -eq 0 ] && ok "non-git --root with a graph → check exits 0 (no crash)" || no "non-git --root crashed ($rc_ng)"
printf '%s' "$(graph_cell "$out_ng")" | grep -qi 'freshness unknown' && ok "non-git --root graph cell = 'present (freshness unknown)'" || no "non-git graph cell not 'freshness unknown' (got: $(graph_cell "$out_ng"))"

# ============================================================================
echo "== (c) bootstrap on a graph-absent fixture GUIDES without failing =="
Cc="$(mkfix)"
out_boot="$(twin "$Cc" bootstrap)"; rc_boot=$?
[ "$rc_boot" -eq 0 ] && ok "bootstrap exits 0 with no graph" || no "bootstrap non-zero with no graph ($rc_boot)"
printf '%s' "$out_boot" | grep -qi 'graphify' && ok "bootstrap stdout mentions graphify (guidance present)" || no "bootstrap stdout lacks graphify guidance"
printf '%s' "$out_boot" | grep -qiE '/graphify|run .?graphify' && ok "bootstrap guidance tells you to run /graphify" || no "bootstrap guidance does not mention running graphify"
[ ! -e "$Cc/graphify-out/graph.json" ] && ok "graphify-absent bootstrap wrote NO graph (guide-only, never ran graphify)" || no "bootstrap unexpectedly produced a graph"

# ============================================================================
echo "== (c2) STALE graph + --run-graphify → graphify REFRESHES it (stale verdict can clear) =="
# Regression guard for the stale-dead-end: a stale graph must be REFRESHABLE via /setup twin,
# not just flagged. Uses a STUB graphify on PATH (no real CLI, no network) that rewrites
# graph.json's built_at_commit to the current HEAD — simulating a refresh.
C2="$(newgit)"
HEADc2="$( cd "$C2" && git rev-parse HEAD )"
write_graph "$C2" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"   # divergent → stale
# pre-confirm it reads stale
printf '%s' "$(graph_cell "$(twin "$C2" check)")" | grep -qi 'stale' && ok "(c2) precondition: graph reads stale" || no "(c2) precondition failed: graph not stale"
# stub graphify that refreshes built_at to HEAD (runs in repo cwd, like the real one)
STUBDIR="$(mkfix)"; mkdir -p "$STUBDIR/bin"
cat > "$STUBDIR/bin/graphify" <<STUB
#!/usr/bin/env bash
# stub graphify: rewrite graphify-out/graph.json built_at_commit to the current HEAD
h="\$(git rev-parse HEAD 2>/dev/null)"
mkdir -p graphify-out
printf '{"built_at_commit":"%s","directed":false,"multigraph":false,"graph":{},"nodes":[{"id":"a","source_file":"x.md","community":1}],"links":[]}\n' "\$h" > graphify-out/graph.json
STUB
chmod +x "$STUBDIR/bin/graphify"
out_c2="$(PATH="$STUBDIR/bin:$PATH" bash "$TWIN" --root "$C2" bootstrap --run-graphify)"; rc_c2=$?
[ "$rc_c2" -eq 0 ] && ok "(c2) bootstrap --run-graphify exits 0" || no "(c2) bootstrap --run-graphify non-zero ($rc_c2)"
printf '%s' "$(graph_cell "$(twin "$C2" check)")" | grep -q 'present (fresh)' && ok "(c2) stale graph REFRESHED to 'present (fresh)' after --run-graphify (stale dead-end fixed)" || no "(c2) graph still not fresh after refresh (got: $(graph_cell "$(twin "$C2" check)"))"

echo "== (c3) STALE graph WITHOUT --run-graphify → bridge rebuilt, stale hint printed, graph unchanged =="
C3="$(newgit)"
write_graph "$C3" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
out_c3="$(twin "$C3" bootstrap)"; rc_c3=$?
[ "$rc_c3" -eq 0 ] && ok "(c3) plain bootstrap on stale graph exits 0" || no "(c3) plain bootstrap non-zero ($rc_c3)"
printf '%s' "$out_c3" | grep -qi 'stale' && ok "(c3) bootstrap prints a stale-graph hint" || no "(c3) no stale hint printed on a stale graph"
printf '%s' "$out_c3" | grep -qiE '/graphify|graphify .' && ok "(c3) stale hint points to running graphify" || no "(c3) stale hint does not mention graphify"
printf '%s' "$(graph_cell "$(twin "$C3" check)")" | grep -qi 'stale' && ok "(c3) graph still stale (plain bootstrap never refreshed it)" || no "(c3) graph unexpectedly changed without --run-graphify"

echo "== (c4) ABSENT graph + --run-graphify + graphify present → graph BUILT (not just refreshed) =="
# Closes the build-branch (RUN_GRAPHIFY=yes, graphify on PATH, graph absent) — distinct from the
# (c2) REFRESH branch. Reuses a stub graphify that writes a graph at the current HEAD.
C4="$(newgit)"   # NO graph written → absent
mkdir -p "$C4"   # (newgit already made the dir)
STUBDIR4="$(mkfix)"; mkdir -p "$STUBDIR4/bin"
cat > "$STUBDIR4/bin/graphify" <<STUB
#!/usr/bin/env bash
h="\$(git rev-parse HEAD 2>/dev/null)"
mkdir -p graphify-out
printf '{"built_at_commit":"%s","directed":false,"multigraph":false,"graph":{},"nodes":[{"id":"a","source_file":"x.md","community":1}],"links":[]}\n' "\$h" > graphify-out/graph.json
STUB
chmod +x "$STUBDIR4/bin/graphify"
[ ! -e "$C4/graphify-out/graph.json" ] && ok "(c4) precondition: graph absent" || no "(c4) precondition failed: graph present"
out_c4="$(PATH="$STUBDIR4/bin:$PATH" bash "$TWIN" --root "$C4" bootstrap --run-graphify)"; rc_c4=$?
[ "$rc_c4" -eq 0 ] && ok "(c4) bootstrap --run-graphify exits 0 on absent graph" || no "(c4) non-zero ($rc_c4)"
[ -e "$C4/graphify-out/graph.json" ] && ok "(c4) absent graph was BUILT by --run-graphify" || no "(c4) graph not built"
printf '%s' "$(graph_cell "$(twin "$C4" check)")" | grep -q 'present (fresh)' && ok "(c4) built graph reads 'present (fresh)'" || no "(c4) built graph not fresh (got: $(graph_cell "$(twin "$C4" check)"))"

echo "== (c5) graphify present but NOT confirmed (plain bootstrap, absent graph) → build guidance, no graph =="
# The 'graphify available but --run-graphify NOT set' guidance branch (build case).
C5="$(newgit)"   # absent graph
STUBDIR5="$(mkfix)"; mkdir -p "$STUBDIR5/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBDIR5/bin/graphify"; chmod +x "$STUBDIR5/bin/graphify"
out_c5="$(PATH="$STUBDIR5/bin:$PATH" bash "$TWIN" --root "$C5" bootstrap)"; rc_c5=$?
[ "$rc_c5" -eq 0 ] && ok "(c5) plain bootstrap exits 0 (graphify present, unconfirmed)" || no "(c5) non-zero ($rc_c5)"
printf '%s' "$out_c5" | grep -qiE 'graphify .|run .?graphify|--run-graphify' && ok "(c5) prints build guidance without running graphify" || no "(c5) missing build guidance"
[ ! -e "$C5/graphify-out/graph.json" ] && ok "(c5) no graph built without --run-graphify (guide-only)" || no "(c5) graph unexpectedly built without confirm"

# ============================================================================
echo "== (d) scoped-writes invariant — never overwrites/creates CLAUDE.md, never writes settings.json =="
# (d-i) bootstrap on a fixture that HAS a CLAUDE.md with sentinel content → byte-identical afterward.
Di="$(mkfix)"
SENTINEL="# CLAUDE.md
DO_NOT_TOUCH_SENTINEL_$$ project guidance"
printf '%s\n' "$SENTINEL" > "$Di/CLAUDE.md"
before_md="$(cat "$Di/CLAUDE.md")"
twin "$Di" bootstrap >/dev/null 2>&1; rc_di=$?
after_md="$(cat "$Di/CLAUDE.md")"
[ "$rc_di" -eq 0 ] && ok "bootstrap exits 0 with a pre-existing CLAUDE.md" || no "bootstrap non-zero with pre-existing CLAUDE.md ($rc_di)"
[ "$before_md" = "$after_md" ] && ok "pre-existing CLAUDE.md byte-identical after bootstrap (NOT overwritten)" || no "bootstrap MUTATED an existing CLAUDE.md"
[ ! -e "$Di/.claude/settings.json" ] && ok "no <root>/.claude/settings.json written (scoped-writes)" || no "bootstrap wrote <root>/.claude/settings.json"

# (d-ii) bootstrap on a fixture with NO CLAUDE.md → none created; skeleton went to stdout only.
Dii="$(mkfix)"
out_dii="$(twin "$Dii" bootstrap)"; rc_dii=$?
[ "$rc_dii" -eq 0 ] && ok "bootstrap exits 0 with no CLAUDE.md" || no "bootstrap non-zero with no CLAUDE.md ($rc_dii)"
[ ! -e "$Dii/CLAUDE.md" ] && ok "bootstrap created NO CLAUDE.md (skeleton is stdout-only)" || no "bootstrap CREATED a CLAUDE.md (must be stdout-only)"
printf '%s' "$out_dii" | grep -q '# CLAUDE.md' && ok "skeleton '# CLAUDE.md' marker present on stdout" || no "skeleton '# CLAUDE.md' marker missing from stdout"
printf '%s' "$out_dii" | grep -q 'Tech Stack' && ok "skeleton 'Tech Stack' marker present on stdout" || no "skeleton 'Tech Stack' marker missing from stdout"
[ ! -e "$Dii/.claude/settings.json" ] && ok "no <root>/.claude/settings.json written (no-CLAUDE.md path)" || no "bootstrap wrote <root>/.claude/settings.json"
# (d-iii) skeleton is MACHINE-EXTRACTABLE: BEGIN/END sentinels present, and the documented
# extraction (sed between sentinels, drop both) yields clean CLAUDE.md content with NO preamble
# and NO code fence — so a confirmed write can't accidentally persist the fence/preamble.
printf '%s\n' "$out_dii" | grep -q 'CLAUDE_MD_STARTER:BEGIN' && ok "skeleton has BEGIN sentinel" || no "skeleton missing BEGIN sentinel"
printf '%s\n' "$out_dii" | grep -q 'CLAUDE_MD_STARTER:END' && ok "skeleton has END sentinel" || no "skeleton missing END sentinel"
extracted="$(printf '%s\n' "$out_dii" | sed -n '/CLAUDE_MD_STARTER:BEGIN/,/CLAUDE_MD_STARTER:END/p' | sed '1d;$d')"
printf '%s\n' "$extracted" | head -1 | grep -qx '# CLAUDE.md' && ok "(d-iii) extracted region starts exactly at '# CLAUDE.md'" || no "(d-iii) extracted region does not start at '# CLAUDE.md' (got: $(printf '%s' "$extracted" | head -1))"
printf '%s' "$extracted" | grep -q 'A repo CLAUDE.md is ABSENT' && no "(d-iii) extracted region leaked the preamble" || ok "(d-iii) extracted region excludes the preamble"
printf '%s' "$extracted" | grep -q '```' && no "(d-iii) extracted region contains a code fence" || ok "(d-iii) extracted region has no code fence"
printf '%s' "$extracted" | grep -q 'CLAUDE_MD_STARTER' && no "(d-iii) extracted region leaked a sentinel line" || ok "(d-iii) extracted region excludes the sentinels"
printf '%s' "$extracted" | grep -q 'How to Run & Test' && ok "(d-iii) extracted region includes the full template body" || no "(d-iii) extracted region truncated the template"

# ============================================================================
echo "== (d2) write-containment vs config redirect (explicit --out beats .build_bridge.out) =="
if [ -z "$PY" ]; then
  ok "python3/python unavailable — build-bridge engine cannot run; redirect-containment check skipped (pass)"
else
  D2="$(newgit)"
  HEAD2="$( cd "$D2" && git rev-parse HEAD )"
  write_graph "$D2" "${HEAD2:0:8}"          # valid graph so build-bridge.py actually builds
  mkdir -p "$D2/.supervisor"
  printf '{"build_bridge":{"out":"%s/REDIRECTED"}}\n' "$D2" > "$D2/.supervisor/config.json"
  twin "$D2" bootstrap >/dev/null 2>&1; rc_d2=$?
  [ "$rc_d2" -eq 0 ] && ok "bootstrap exits 0 building a real bridge" || no "bootstrap non-zero on real build ($rc_d2)"
  if [ -f "$D2/.supervisor/bridge/bridge.json" ]; then
    ok "bridge landed under <root>/.supervisor/bridge/ (explicit --out honored)"
  else
    no "bridge.json NOT under <root>/.supervisor/bridge/ — explicit --out not passed"
  fi
  if [ ! -e "$D2/REDIRECTED" ]; then
    ok "NOTHING written to the config redirect dir (<root>/REDIRECTED absent → config redirect ignored)"
  else
    no "config redirect dir <root>/REDIRECTED was written — explicit --out did not short-circuit the redirect"
  fi
fi

# ============================================================================
echo "== (e) idempotency — check twice byte-identical; bootstrap twice exit 0 + same verdict =="
Ee="$(newgit)"
HEADe="$( cd "$Ee" && git rev-parse HEAD )"
write_graph "$Ee" "${HEADe:0:8}"
mkdir -p "$Ee/.supervisor/bridge"; echo '{}' > "$Ee/.supervisor/bridge/bridge.json"
echo "# CLAUDE.md" > "$Ee/CLAUDE.md"
chk1="$(twin "$Ee" check)"
chk2="$(twin "$Ee" check)"
[ "$chk1" = "$chk2" ] && ok "check stdout byte-identical across two runs (idempotent)" || no "check stdout differed between runs"
out_b1="$(twin "$Ee" bootstrap)"; rc_b1=$?
out_b2="$(twin "$Ee" bootstrap)"; rc_b2=$?
[ "$rc_b1" -eq 0 ] && [ "$rc_b2" -eq 0 ] && ok "bootstrap exits 0 on both runs" || no "bootstrap non-zero on a run (b1=$rc_b1 b2=$rc_b2)"
v1="$(verdict_line "$out_b1")"; v2="$(verdict_line "$out_b2")"
[ -n "$v1" ] && [ "$v1" = "$v2" ] && ok "post-bootstrap readiness verdict unchanged across runs ($v1)" || no "bootstrap verdict changed between runs (v1=$v1 v2=$v2)"

# ============================================================================
echo "== (f) brain-wiki SET branch + build-bridge-not-found fail-safe branch =="
# (f-i) probe_brain SET branch — LOOMWRIGHT_BRAIN_ROOT set AND <root>/wiki exists → 'set'.
Fbrain="$(mkfix)"; mkdir -p "$Fbrain/wiki"
out_brain="$(LOOMWRIGHT_BRAIN_ROOT="$Fbrain" twin "$(mkfix)" check)"
printf '%s\n' "$out_brain" | grep -E '^[[:space:]]*brain wiki:' | grep -qi 'set' \
  && ok "(f-i) brain wiki cell = 'set' when BRAIN_ROOT + wiki/ present" \
  || no "(f-i) brain wiki cell not 'set' (got: $(printf '%s\n' "$out_brain" | grep -E '^[[:space:]]*brain wiki:'))"
# and the FALSE-ready guard: BRAIN_ROOT set but NO wiki/ subdir → 'not set' (matches brain-context Signal 2).
Fnowiki="$(mkfix)"   # no wiki/ subdir
out_nowiki="$(LOOMWRIGHT_BRAIN_ROOT="$Fnowiki" twin "$(mkfix)" check)"
printf '%s\n' "$out_nowiki" | grep -E '^[[:space:]]*brain wiki:' | grep -qi 'not set' \
  && ok "(f-i) brain wiki = 'not set' when BRAIN_ROOT set but wiki/ absent (no false-ready)" \
  || no "(f-i) brain wiki wrongly 'set' without a wiki/ subdir"

# (f-ii) build-bridge.sh NOT FOUND fail-safe branch. Run a COPY of the helper from a dir with no
# sibling build-bridge.sh, with CLAUDE_PLUGIN_ROOT unset → BUILD_BRIDGE resolves to the (absent)
# sibling → the helper prints the fail-safe skip to stderr and STILL exits 0.
Fcopy="$(mkfix)"; cp "$TWIN" "$Fcopy/setup-twin.sh"   # no build-bridge.sh beside it
Fbb="$(newgit)"; HEADbb="$( cd "$Fbb" && git rev-parse HEAD )"; write_graph "$Fbb" "${HEADbb:0:8}"
err_bb="$(env -u CLAUDE_PLUGIN_ROOT bash "$Fcopy/setup-twin.sh" --root "$Fbb" bootstrap 2>&1 >/dev/null)"; rc_bb=$?
[ "$rc_bb" -eq 0 ] && ok "(f-ii) bootstrap exits 0 when build-bridge.sh is not found (fail-safe)" || no "(f-ii) bootstrap non-zero on missing build-bridge ($rc_bb)"
printf '%s' "$err_bb" | grep -qi 'build-bridge.sh not found' && ok "(f-ii) prints the 'build-bridge.sh not found' fail-safe diagnostic" || no "(f-ii) missing the not-found diagnostic (got: $err_bb)"
[ ! -e "$Fbb/.supervisor/bridge/bridge.json" ] && ok "(f-ii) no bridge written when builder absent" || no "(f-ii) bridge unexpectedly written without the builder"

# (f-iii) probe_claude_md clamps a future/clock-skewed mtime to 0d (no negative age).
Fage="$(mkfix)"; echo "# CLAUDE.md" > "$Fage/CLAUDE.md"
touch -t 203001010000 "$Fage/CLAUDE.md" 2>/dev/null   # future mtime (portable -t form, BSD+GNU)
cell_age="$(twin "$Fage" check | grep -E '^[[:space:]]*CLAUDE.md:')"
printf '%s' "$cell_age" | grep -q -- '-' && no "(f-iii) future-mtime CLAUDE.md rendered a NEGATIVE age ($cell_age)" || ok "(f-iii) future-mtime CLAUDE.md age clamped (no negative): $cell_age"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
