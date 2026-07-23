#!/usr/bin/env bash
# test-rules-docs.sh — STATIC doc-assertion self-test for the /rules substrate docs
# (commands/rules.md + skills/rules/SKILL.md). STATIC ONLY: greps the committed docs, no
# network, no jq, no shell execution of any rule — so it runs on the plugin's Ubuntu CI like
# every other test-*.sh (auto-registered by ci.yml's test-*.sh glob). Exit 0 = all pass, 1 = any fail.
#
# Mirrors test-setup-twin.sh / test-build-handoff.sh convention: pass/fail counters, ok()/no()
# helpers, a "RESULT: N passed, M failed" tail, exit 1 on any failure. Paths resolve from
# $BASH_SOURCE's dir so it runs from any CWD under the CI glob.
#
# Covers (each = an acceptance criterion of Subtask 4):
#   - commands/rules.md and skills/rules/SKILL.md both EXIST.
#   - BOTH carry the trust-boundary phrases: reader-never-executes-check (data only),
#     /rules check requires-confirmation, and the 3b-ii contract — unattended `check`
#     execution GATED via rules-check.sh --no-cmd, and /rules add mechanized via add-rule.sh.
#   - the category path-containment / slugging rule (slug + [a-z0-9-] + traversal rejection).
#   - the deterministic-id format (<category-slug>-<statement-slug> with -N collision suffix).
#   - the array-only parse gate (jq -e 'type=="array"').
#   - the provenance.source + provenance.added stamping of /rules add.
#
# Curation/anti-rot (ST-5a) additions — the retract action + the --supersedes flag on add:
#   - BOTH files document `--supersedes` as an optional flag on `add` (never a separate verb).
#   - BOTH files document the `retract` action's --target/--reason and its ALWAYS-REJECTED
#     --replacement.
#   - BOTH files document single-hop, non-transitive supersession (the reader hides the named
#     rule; it does not chase a chain).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
CMD="$PLUGIN_ROOT/commands/rules.md"
SKILL="$PLUGIN_ROOT/skills/rules/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# has <file> <pattern> — case-insensitive, extended-regex grep -q against a file.
has() { grep -qiE -- "$2" "$1" 2>/dev/null; }

# ---- (a) both files exist ---------------------------------------------------
[ -f "$CMD" ]   && ok "commands/rules.md exists"        || no "commands/rules.md MISSING ($CMD)"
[ -f "$SKILL" ] && ok "skills/rules/SKILL.md exists"    || no "skills/rules/SKILL.md MISSING ($SKILL)"

# ---- (b) trust-boundary phrases present in BOTH files -----------------------
# reader never executes a check / emits as data only
for f in "$CMD" "$SKILL"; do
  base="$(basename "$(dirname "$f")")/$(basename "$f")"
  has "$f" 'never (execute|run)s? (it|a `?check`?)|`?check`? (as|is) data only|emits .*`?check`? as data|data only.*never (run|execute)|never executed by (it|the reader)' \
    && ok "[$base] trust-boundary: reader never executes check (data only)" \
    || no "[$base] MISSING reader-never-executes-check phrasing"

  has "$f" '/rules check.*(confirm|human-invoked)|requires? (explicit )?confirmation|HUMAN-invoked|after explicit confirmation' \
    && ok "[$base] trust-boundary: /rules check requires confirmation" \
    || no "[$base] MISSING /rules-check-requires-confirmation phrasing"

  # 3b-ii contract: unattended `check` execution is GATED via rules-check.sh --no-cmd.
  has "$f" 'rules-check\.sh' && has "$f" '\-\-no-cmd' \
    && ok "[$base] trust-boundary: unattended check execution GATED via rules-check.sh --no-cmd" \
    || no "[$base] MISSING unattended-execution-gated-via-rules-check.sh--no-cmd phrasing"

  # 3b-ii contract: /rules add write path mechanized into the sole-writer add-rule.sh.
  has "$f" 'add-rule\.sh' \
    && ok "[$base] /rules add mechanized via add-rule.sh" \
    || no "[$base] MISSING add-rule.sh mechanization phrasing"
done

# ---- (c) category path-containment / slugging (in command and/or skill) -----
slug_ok=false
for f in "$CMD" "$SKILL"; do
  has "$f" 'slug' && has "$f" '\[a-z0-9-\]' \
    && has "$f" '\.\.|traversal|metachar|escape `?\.agent/rules' \
    && slug_ok=true
done
$slug_ok && ok "category path-containment/slugging documented (slug + [a-z0-9-] + traversal rejection)" \
         || no "MISSING category path-containment/slugging rule"

# ---- (d) deterministic-id format --------------------------------------------
id_ok=false
for f in "$CMD" "$SKILL"; do
  has "$f" '<category-slug>-<statement-slug>' && has "$f" '-N' && id_ok=true
done
$id_ok && ok "deterministic-id format documented (<category-slug>-<statement-slug> with -N suffix)" \
       || no "MISSING deterministic-id format"

# ---- (e) array-only parse gate ----------------------------------------------
gate_ok=false
for f in "$CMD" "$SKILL"; do
  has "$f" "jq -e 'type==\"array\"'" && gate_ok=true
done
$gate_ok && ok "array-only parse gate documented (jq -e 'type==\"array\"')" \
         || no "MISSING array-only parse gate"

# ---- (f) provenance.source + provenance.added stamping ----------------------
prov_ok=false
for f in "$CMD" "$SKILL"; do
  has "$f" 'provenance\.source' && has "$f" 'provenance\.added' && prov_ok=true
done
$prov_ok && ok "provenance.source + provenance.added stamping documented" \
         || no "MISSING provenance stamping"

# ---- (g) --supersedes documented as an optional ADD flag (curation/anti-rot) ------------
for f in "$CMD" "$SKILL"; do
  base="$(basename "$(dirname "$f")")/$(basename "$f")"
  has "$f" '\-\-supersedes' \
    && ok "[$base] --supersedes flag documented" \
    || no "[$base] MISSING --supersedes flag documentation"
done

# ---- (h) retract action documented: --target / --reason / --replacement rejected --------
for f in "$CMD" "$SKILL"; do
  base="$(basename "$(dirname "$f")")/$(basename "$f")"
  has "$f" 'retract' \
    && ok "[$base] retract action documented" \
    || no "[$base] MISSING retract action documentation"

  has "$f" '\-\-target' && has "$f" '\-\-reason' \
    && ok "[$base] retract --target/--reason documented" \
    || no "[$base] MISSING retract --target/--reason documentation"

  has "$f" '\-\-replacement.*(reject|never)|(reject|never).*\-\-replacement|always rejected' \
    && ok "[$base] retract --replacement-always-rejected documented" \
    || no "[$base] MISSING retract --replacement-rejected documentation"
done

# ---- (i) single-hop, non-transitive supersession semantics -------------------
for f in "$CMD" "$SKILL"; do
  base="$(basename "$(dirname "$f")")/$(basename "$f")"
  has "$f" 'single-hop' && has "$f" 'non-transitive|does not chase' \
    && ok "[$base] single-hop non-transitive supersession documented" \
    || no "[$base] MISSING single-hop/non-transitive supersession documentation"
done

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
