#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-wave-scope.sh — hermetic self-tests for how a set is kept wave-safe: the scope fence's declared
# set (`plan-waves --touches`: the planner's own Touches parser + companion expansion, printed for one
# item) as `lane-readiness`'s "c: scope fence" check reads it, and the Product Owner wave-shaping
# procedure (`skills/user-story-writing/SKILL.md` §"Shaping a set for parallel waves") run as written.
# Fixture: a minimal hand-made lane (lane.json, run file, lane-backlog, item file) under one mktemp dir;
# `gh` is a LOOMWRIGHT_GH_BIN stub answering `pr view` / `pr diff` / `pr checks`. The REAL
# automate-helpers.sh answers plan-waves. No network, no real gh. (wave-plan / wave-build's same-wave
# overlap check is tested where its fixture lives: test-wave-build.sh W4e2 / W8.)
#
# Groups: F1 a product-owner item (bare paths, one per line — the strict grammar) is read as declared
#   (regression: the fence read only backticked paths, so every bare-path item FAILed on its own files)
#   · F2 a directory entry and a companion-added path are declared · F3 a Touches section the planner
#   reads as unknown (backticked bullets) ⇒ only the brief's paths, and the fence line says why ·
#   F4 plan-waves --touches output contract (known / unknown <why>, exit codes, read-only) ·
#   S1 the skill's shaping command on a Product-Owner-shaped set (timestamp names, filename Depends,
#   bare Touches): a shared hotspot serialises and --explain names it; the reshape the skill names
#   (the hotspot given to one item) puts the set in one wave; the skill text carries that command
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L="$HERE/automate-lanes.sh"
H="$HERE/automate-helpers.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 900)]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3]" ;; *) ok "$1" ;; esac; }

export HOME="$T/home"; mkdir -p "$HOME"
unset LOOMWRIGHT_LANES_HELPERS

# ---- fixture: one lane L1 of parent run P ------------------------------------------------------------
P=automate-2026-10-17-000000
PRIM="$T/primary"; LD="$T/lanes/$P/L1"
mkdir -p "$PRIM/.supervisor/automate" "$LD/.supervisor/automate" "$LD/reqs"
jq -n --arg p "$P" --arg prim "$PRIM" '{lane: "L1", run_id: ($p + "-L1"), parent_run_id: $p, primary: $prim}' > "$LD/.supervisor/lane.json"
printf -- '- [ ] reqs/01-a.md\n' > "$LD/.supervisor/lane-backlog.md"
printf '# Automate Run: %s-L1\n\n## Current\n- item: reqs/01-a.md | status: ready_for_release | pr: https://github.com/o/r/pull/7 | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-17T00:00:00Z children-settled: settled\n' "$P" > "$LD/.supervisor/automate/$P-L1.md"
RD="$LD/.supervisor/automate/$P-L1.merge-readiness.md"

# The gh stub: the PR diff is $T/diff (one path per line).
cat > "$T/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") jq -n '{body: "", headRefOid: "abc123"}' ;;
  "pr diff") cat "$SF_T/diff" ;;
  "pr checks") echo '[{"name":"ci","bucket":"pass"}]' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/gh"
export SF_T="$T" LOOMWRIGHT_GH_BIN="$T/gh"

item() { cat > "$LD/reqs/01-a.md"; }
fence() { bash "$L" lane-readiness "$LD" >/dev/null 2>&1; sed -n '/^- scope-fence:/,/^- gates:/p' "$RD" | sed '$d'; }

# ---- F1: a product-owner item — bare paths, one per line ------------------------------------------------
item <<'EOF'
# 01 — a

## Depends on
none

## Touches
kernel/src/sessions/manager.ts
kernel/test/sessions-policy.test.ts
docs/ARCHITECTURE.md
EOF
printf 'kernel/src/sessions/manager.ts\nkernel/test/sessions-policy.test.ts\ndocs/ARCHITECTURE.md\nchangelog.d/a.md\n' > "$T/diff"
out="$(fence)"
has "F1 a bare-path Touches item whose PR stays inside it ⇒ scope-fence PASS" "$out" "- scope-fence: PASS — 4 file(s) within the declared files + changelog.d/"
printf 'kernel/src/sessions/manager.ts\nkernel/src/approvals/store.ts\n' > "$T/diff"
out="$(fence)"
has "F1b … a file outside it ⇒ FAIL" "$out" "- scope-fence: FAIL"
has "F1c … naming only that file" "$out" "  - kernel/src/approvals/store.ts"
hasnt "F1d … never a declared one" "$out" "  - kernel/src/sessions/manager.ts"
hasnt "F1e a known Touches set adds no Touches note" "$out" "Touches unknown"

# ---- F2: a directory entry, and a path a companion rule adds, are declared ---------------------------------
item <<'EOF'
# 01 — a

## Touches
kernel/src/approvals/
kernel/src/index.ts
EOF
mkdir -p "$LD/.agent"
printf '{"schema_version":1,"companions":[{"when":"kernel/src/*.ts","add":["kernel/src/barrel.d.ts"]}]}\n' > "$LD/.agent/companions.json"
printf 'kernel/src/approvals/store.ts\nkernel/src/approvals/deep/tool.ts\nkernel/src/index.ts\nkernel/src/barrel.d.ts\n' > "$T/diff"
out="$(fence)"
has "F2 directory entry covers its subtree, companion-added path is declared ⇒ PASS" "$out" "- scope-fence: PASS — 4 file(s)"
printf 'kernel/src/approvals-old.ts\n' > "$T/diff"
out="$(fence)"
has "F2b a sibling that only shares the directory's name prefix is outside (prefix + '/', never a string prefix)" "$out" "  - kernel/src/approvals-old.ts"
rm -rf "$LD/.agent"
printf 'kernel/src/barrel.d.ts\n' > "$T/diff"
out="$(fence)"
has "F2c mutation control: without the companion rule the same path is outside" "$out" "  - kernel/src/barrel.d.ts"

item <<'EOF'
# 01 — a

## Touches
src/
EOF
printf 'src/x.sh\n' > "$T/diff"
out="$(fence)"
has "F2d a top-level directory entry (normalized to \`src\`, no / or .) is declared, never filtered out" "$out" "- scope-fence: PASS — 1 file(s)"

# ---- F3: a Touches section the planner reads as unknown ⇒ only the brief's paths, and the line says why ----
item <<'EOF'
# 01 — a

## Touches
- `kernel/src/a.ts`
EOF
mkdir -p "$LD/.supervisor/jobs/in-progress"
printf '# brief for reqs/01-a.md\nfiles:\n  - path: "kernel/src/b.ts"\n' > "$LD/.supervisor/jobs/in-progress/b.md"
printf 'kernel/src/a.ts\nkernel/src/b.ts\n' > "$T/diff"
out="$(fence)"
has "F3 backticked bullets are unknown to the planner ⇒ never declared" "$out" "  - kernel/src/a.ts"
hasnt "F3b … the brief's path: line still is" "$out" "  - kernel/src/b.ts"
has "F3c … and the fence line says why" "$out" "; Touches unknown unparsable line 4: \"- \`kernel/src/a.ts\`\" — only the brief's paths are declared"
mkdir -p "$LD/.agent"; printf '{"schema_version":2}\n' > "$LD/.agent/companions.json"
item <<'EOF'
# 01 — a

## Touches
kernel/src/a.ts
EOF
out="$(fence)"
has "F3d malformed companions.json ⇒ Touches unreadable, the brief's paths only (never a silent PASS)" "$out" "; Touches unreadable (plan-waves --touches failed) — only the brief's paths are declared"
rm -rf "$LD/.agent" "$LD/.supervisor/jobs"

# ---- F4: plan-waves --touches output contract ---------------------------------------------------------------
R="$T/pw"; mkdir -p "$R/q"
printf '# a\n## Touches\nsrc/\nb/c.ts\nsrc/x.ts\n' > "$R/q/01-a.md"
printf '# b\n## Touches\nunknown\n' > "$R/q/02-b.md"
printf '# c\n## Depends on\nnone\n' > "$R/q/03-c.md"
before="$(cd "$R" && find . -type f | LC_ALL=C sort | xargs cksum)"
o="$(bash "$H" plan-waves "$R/q/01-a.md" --touches --root "$R" 2>/dev/null)"; rc=$?
check "F4 known ⇒ \`known\` + normalized, sorted, unique entries, exit 0" "$rc|$(printf '%s' "$o" | paste -sd ',' -)" "0|known,b/c.ts,src,src/x.ts"
o="$(bash "$H" plan-waves "$R/q/02-b.md" --touches --root "$R" 2>/dev/null)"; rc=$?
check "F4b sole \`unknown\` ⇒ one line, exit 0" "$rc|$o" "0|unknown declared unknown"
o="$(bash "$H" plan-waves "$R/q/03-c.md" --touches --root "$R" 2>/dev/null)"; rc=$?
check "F4c no section ⇒ unknown missing" "$rc|$o" "0|unknown missing"
o="$(bash "$H" plan-waves "$R/q/09-gone.md" --touches --root "$R" 2>"$T/err")"; rc=$?
check "F4d item not found ⇒ exit 1, empty stdout" "$rc|$o" "1|"
has "F4d' … named on stderr" "$(cat "$T/err")" "plan-waves: input not found:"
o="$(bash "$H" plan-waves "$R/q" --touches --root "$R" 2>/dev/null)"; rc=$?
check "F4e a directory is not ONE item ⇒ usage, exit 1" "$rc|$o" "1|"
o="$(bash "$H" plan-waves "$R/q/01-a.md" --touches --lint --root "$R" 2>/dev/null)"; rc=$?
check "F4f --touches with --lint ⇒ usage, exit 1" "$rc|$o" "1|"
check "F4g read-only: the fixture tree is unchanged" "$(cd "$R" && find . -type f | LC_ALL=C sort | xargs cksum)" "$before"

# ---- S1: the Product Owner shaping procedure, run as the skill writes it ------------------------------
SK="$HERE/../skills/user-story-writing/SKILL.md"
has "S1 the skill names the planning command (item list, --max <item count>, --explain)" "$(cat "$SK")" \
  "run \`automate-helpers.sh plan-waves <file> --max <item count> --explain\`"
has "S1b … and that N is chosen from the plan, never a fixed default" "$(cat "$SK")" "**Choose N from the plan, never a fixed default**"
Q="$T/po/.supervisor/requirements"; mkdir -p "$Q"
A1="2026-10-17-090000-adapter-reads-contract.md"; A2="2026-10-17-090001-approvals-store.md"; A3="2026-10-17-090002-tool-loading.md"
printf '# a\n\n## Depends on\nnone\n\n## Touches\nkernel/src/loomwright/adapter.ts\nkernel/src/index.ts\n' > "$Q/$A1"
printf '# b\n\n## Depends on\nnone\n\n## Touches\nkernel/src/approvals/\nkernel/src/index.ts\n' > "$Q/$A2"
printf '# c\n\n## Depends on\n%s\n\n## Touches\nkernel/src/sessions/manager.ts\n' "$A1" > "$Q/$A3"
printf '%s\n' ".supervisor/requirements/$A1" ".supervisor/requirements/$A2" ".supervisor/requirements/$A3" > "$T/po.list"
o="$(bash "$H" plan-waves "$T/po.list" --max 3 --explain --root "$T/po" 2>/dev/null)"; rc=$?
check "S1c a hotspot both items declare serialises them (three stories, no width cap ⇒ two waves)" "$rc|$(printf '%s\n' "$o" | grep -c '^wave ' | tr -d ' ')" "0|2"
has "S1d … and --explain names the hotspot and the item it conflicts with" "$o" "conflicts with .supervisor/requirements/$A1 on kernel/src/index.ts (declared)"
printf '# b\n\n## Depends on\nnone\n\n## Touches\nkernel/src/approvals/\n' > "$Q/$A2"
o="$(bash "$H" plan-waves "$T/po.list" --max 3 --explain --root "$T/po" 2>/dev/null)"
check "S1e the reshape the skill names (the hotspot given to ONE item) puts both in wave 1; the real dependency still waits" \
  "$(printf '%s\n' "$o" | grep '^wave ' | sed 's#\.supervisor/requirements/##g')" "wave 1: $A1 $A2
wave 2: $A3"
has "S1f … and --explain says why the third waits (a dependency, not a file)" "$o" "depends on .supervisor/requirements/$A1"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
