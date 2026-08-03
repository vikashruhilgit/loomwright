#!/usr/bin/env bash
# check-contract-parity.sh — CI gate: hook ↔ agent-prompt contract parity.
#
# Two mechanical checks, deliberately conservative (high-confidence only, same
# philosophy as check-doc-currency.sh):
#
#   1. FIELD PRESENCE — for each SubagentStop validator in hooks.json, every
#      hook-required result-block field name (pinned in the MANIFEST below)
#      must (a) still appear in that validator's RULE SOURCE — the `type:
#      prompt` prompt string, or (since v15.17.0, for validators converted to
#      `type: command`) the source of the referenced validate-<x>-result.py
#      script WITH ITS PROSE STRIPPED — every string-literal statement
#      (docstrings included) and every `#` comment (pin-drift guard: if the hook
#      changes, the manifest must change with it) — and (b) appear
#      in the matched agent's prompt file (an agent
#      told to emit a block must name every hook-required field somewhere in
#      its emit instructions).
#
#      GUARD STRENGTH, stated honestly: after the strip, check (a)'s floor is
#      "the field name appears somewhere in non-prose source (no string statements, no comments)".
#      That is NOT "the field is checked" — a name in a string constant or an
#      orphaned reason constant still satisfies it. See the residual enumerated
#      above hook_prompt().
#
#   2. ENUM LITERALS — for result status/decision keys whose hook validator
#      enumerates a closed enum, any literal `key: token` in the agent prompt
#      must be inside the per-file allowlist (the enum plus that file's other
#      legitimate uses of the key, e.g. worktree `status: running`). This is
#      the class that caught the illegal `status: paused` in supervisor.md.
#
# Catches the v14.22.x hook-rejection-trap class mechanically: an agent whose
# documented emit format drops a hook-required field, or instructs an
# out-of-enum status literal, fails CI before it can fail at runtime.
#
# Usage: bash scripts/check-contract-parity.sh [--root <dir>]
#   --root defaults to the repo root (the directory containing
#   loomwright/). The self-test points it at a fixture tree.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" = "--root" ]; then
  ROOT="${2:?--root requires a directory}"
fi

PLUGIN="$ROOT/loomwright"
HOOKS="$PLUGIN/hooks/hooks.json"
AGENTS="$PLUGIN/agents"

[ -f "$HOOKS" ] || { echo "✗ contract-parity: hooks.json not found at $HOOKS" >&2; exit 1; }

fail=0
err() { echo "  PARITY [$1] $2" >&2; fail=1; }

# Sentinel emitted by hook_prompt() when a matcher's rule source cannot be
# resolved unambiguously. Callers MUST treat it as a hard pin-drift error —
# never as "no rule to check".
PARITY_UNRESOLVED="__PARITY_UNRESOLVED__"

# Resolve a matcher's RUNTIME RULE SOURCE — the text the pin-drift guard greps
# for hook-required field names (python for reliable JSON parsing; jq is not
# guaranteed on every dev machine).
#
# Two sources, in order:
#   1. `type: prompt` hooks — the historical source; their prompt strings.
#   2. FALLBACK (v15.17.0): when the matcher has no prompt hook, the SOURCE of
#      the `validate-<x>-result.py` script referenced by one of its `type:
#      command` hooks. Five SubagentStop validators were converted from prompt
#      strings to deterministic scripts; the rule source moved from a prompt
#      into a .py file, so the guard follows it there. Field names appear
#      literally in those scripts (as dict keys / constants), which is what
#      makes the pin-drift grep still meaningful.
#
# The fallback's SELECTION RULE is load-bearing and deliberately fails CLOSED:
# exactly ONE command entry may reference a validate-*-result.py script, and it
# must name exactly one such script. Zero or more than one is a hard error.
# Three affected matchers carry ADDITIONAL command entries after the
# conversion — loomwright:worker also has emit-progress-event.sh,
# loomwright:qa-executor also has the telemetry fan-out, and
# loomwright:supervisor-runner has both the telemetry fan-out and
# send-webhook.sh — so "the matcher's command entry" is not well defined and
# both naive readings are wrong:
#   * concatenating every command entry's source fails OPEN —
#     send-telemetry-core.sh alone mentions pr_url / heal_decision /
#     heal_loop_ran / summary / schema_version, so a pin-drift grep would PASS
#     on a field the real validator had dropped, leaving the gate green while
#     enforcing nothing;
#   * taking the first entry fails CLOSED with spurious red CI and couples the
#     gate to hook ordering that nothing asserts.
#
# PROSE IS STRIPPED from the resolved validator source before it is returned —
# every string-literal STATEMENT (docstrings included) AND every `#` comment —
# and that is load-bearing too. Python source is code, strings and comments, so
# prose can hide in exactly four separable places, and all four are real here:
#   1. the MODULE docstring — every ST-1 validator opens with one transcribing
#      its numbered rules VERBATIM ("(4) if tests were run, coverage_estimate is
#      present");
#   2. CLASS / FUNCTION docstrings — several quote field names too;
#   3. `#` COMMENTS — every rule block carries a section-header comment naming
#      its field ("# ── (4) coverage_estimate present when tests were run ──";
#      4 of the 5 converted validators have them — qa 4 comment-lines, execute
#      2, supervisor 2, plan-review 2, worker 0);
#   4. BARE STRING STATEMENTS that are not body[0] — the PEP-258 "attribute
#      docstring" convention, or a stray one left by a partial deletion.
# Grepping the raw source therefore lets PROSE satisfy the pin-drift guard:
# deleting the executable rule-4 block from validate-qa-result.py leaves zero
# coverage_estimate mentions in code, yet a guard that misses ANY ONE of the
# four still prints ✓ and exits 0 — the same fail-open class as the concat
# reading above, one layer deeper. Since the five prompt strings this guard used
# to grep are gone, it is the only thing between a silently-weakened validator
# and CI, so it must grep CODE, not commentary. Each of the four was verified by
# construction against an implementation handling only the preceding ones — 1
# passed a raw grep, 2 passed a module-only strip, 3 passed a docstring-only
# strip, 4 passed a body[0]-only strip.
#
# String-statement removal is by AST NODE SPAN, and both obvious shortcuts are
# wrong:
#   * `src.replace(ast.get_docstring(tree), "")` removes the docstring TEXT
#     wherever it occurs, not the node — a short docstring whose wording recurs
#     in a string constant would be over-stripped;
#   * that same call also silently does NOTHING for indented function/class
#     docstrings, because get_docstring() dedents (clean=True) so its result is
#     not present verbatim in the source. Verified: the cleaned text of
#     validate-worker-result.py's module docstring is found in the source, its
#     _non_empty_list() docstring's is not.
# ALL docstrings are stripped, not just the module's: files_modified survives
# only in _non_empty_list()'s docstring and worktrees only in
# _check_worktree_paths()'s if their executable checks are deleted, so a
# module-only strip would narrow this hole rather than close it.
#
# Comment removal is by TOKENIZE, never by a line-based `#` strip: `#` inside a
# string literal is not a comment, and a regex/prefix strip would corrupt the
# very code the grep then inspects. Not hypothetical — validate-launch-pad-
# result.py contains `line.strip().startswith("#")`, the parser's own
# comment-marker literal. (Cited by NAME, not by line number: this change
# retired absolute line-refs precisely to stop that drift class, and this one
# points into a file we do not own.) A naive strip would leave
# `line.strip().startswith("` and change what the following grep sees. (Checked
# all six validators by tokenizing them: that file is the only one with `#`
# inside a string today, and it is exactly the kind of line a MANIFEST row could
# reach tomorrow.) tokenize reports COMMENT spans as CHARACTER
# offsets into each str line, while ast reports BYTE offsets (see the note in
# strip_string_statements) — the two passes are sequential and each slices with
# its own convention, so the conventions are never mixed.
#
# WHAT THIS DOES AND DOES NOT BUY — the honest floor, so a future reader does
# not over-trust it. After both strips, the guard proves only that THE FIELD
# NAME APPEARS SOMEWHERE IN NON-DOCSTRING, NON-COMMENT SOURCE. It does NOT prove
# the field is CHECKED. The residual is not mechanically separable and is
# knowingly accepted:
#   * a field name in a string constant is indistinguishable from one used as a
#     lookup key — `present(fields, "pr_url")` and `emit(False, "pr_url must be
#     present...")` are both an ast.Constant in executable position;
#   * these validators promote reason text to module-level constants
#     (REASON_V2_FIELDS, REASON_GAP_STATUS, REASON_TOOLSET_GAP,
#     REASON_ADJUDICATION_*, MISSING_BLOCK, REASON_RUBRIC_SCORE), so an ORPHANED
#     reason constant left behind by a partial deletion satisfies pin-drift with
#     no executable check anywhere.
# Closing that would need dataflow analysis of each validator, not a grep. The
# strips close the four prose placements that ARE separable; string constants
# and reason strings remain the acknowledged floor.
hook_prompt() { # $1 = matcher substring; prints rule source, or PARITY_UNRESOLVED + reason
  python3 - "$HOOKS" "$1" "$PLUGIN" "$PARITY_UNRESOLVED" <<'PY'
import ast,io,json,os,re,sys,tokenize
hooks_path, needle, plugin, sentinel = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
h=json.load(open(hooks_path))

def bail(msg):
    print("%s %s" % (sentinel, msg))
    sys.exit(0)

def _is_str_const(node):
    # py3.8+ spells a string literal ast.Constant; py<=3.7 spells it ast.Str.
    # The name is compared instead of referencing ast.Str, which is deprecated
    # (and warns) on py3.12+.
    # bytes is included alongside str: a bare b"""...""" statement is not a
    # documentation convention anyone uses, but it IS separable prose by the
    # same structural argument as str -- a constant in ast.Expr position is
    # evaluated and discarded, so it can never be a lookup key or an emit()
    # reason. Accepting it keeps the "separable placements" enumeration
    # exhaustive rather than nearly so.
    if isinstance(node, ast.Constant) and isinstance(node.value, (str, bytes)):
        return True
    return node.__class__.__name__ in ("Str", "Bytes")

def strip_string_statements(src, path):
    """Blank every string-literal expression STATEMENT, by node span.

    Docstrings are exactly the body[0] case of this rule, but restricting the
    rule to body[0] leaves a fifth prose placement open: a BARE string statement
    elsewhere in a body is equally non-executable prose and equally satisfies
    the pin-drift grep. The PEP-258 "attribute docstring" convention puts one
    directly after a module-level constant —

        REQUIRED = [...]
        \"\"\"The required fields, including coverage_estimate.\"\"\"

    — and a partial deletion can leave a stray one mid-function. Verified by
    construction: replacing validate-qa-result.py's executable rule-4 block with
    a single bare string statement passed a body[0]-only strip. Matching any
    ast.Expr whose value is a string is both simpler and strictly stronger, and
    it cannot over-strip: a string in ast.Expr position is a statement evaluated
    for no effect, so it can never be a lookup key or an emit() reason. (No real
    validator has one today — checked across all six.) JoinedStr is included so
    an f-string statement is not a loophole.

    Fails CLOSED (bail) rather than returning prose-bearing source: an
    unparseable validator cannot be verified, and a validator that does not
    parse is itself dead at runtime (its traceback is swallowed by the hook's
    `|| true`), so red CI is the correct signal.
    """
    try:
        tree = ast.parse(src)
    except (SyntaxError, ValueError) as exc:
        bail("validator source '%s' does not parse as Python (%s: %s) — the "
             "pin-drift guard cannot distinguish its executable checks from "
             "its prose, and an unparseable validator is dead at runtime"
             % (path, type(exc).__name__, exc))
    spans=[]
    for node in ast.walk(tree):
        if not isinstance(node, ast.Expr):
            continue
        s = node.value
        if not (_is_str_const(s) or isinstance(s, ast.JoinedStr)):
            continue
        if getattr(s, "end_lineno", None) is None or getattr(s, "end_col_offset", None) is None:
            bail("python %d.%d cannot report AST end positions (added in 3.8), so "
                 "prose strings in '%s' cannot be stripped by span — the pin-drift "
                 "guard would let prose satisfy it; run this gate on python >= 3.8"
                 % (sys.version_info[0], sys.version_info[1], path))
        spans.append((s.lineno, s.col_offset, s.end_lineno, s.end_col_offset))
    lines = src.splitlines(True)
    # ast's col_offset/end_col_offset are UTF-8 BYTE offsets, but the slicing
    # below indexes a Python str (characters). Latent, not live: no string
    # statement's delimiter line in these validators carries non-ASCII before
    # its end_col_offset today. The skew direction is also safe for this guard's
    # purpose — bytes >= chars means the slice removes MORE, never less, so a
    # non-ASCII docstring cannot leak prose into the grep (it could only cause a
    # spurious pin-drift, i.e. fail CLOSED). If that ever bites, convert the
    # line to bytes, slice, and decode back.
    #
    # Spans are disjoint and each line is REPLACED in place (never inserted or
    # deleted), so indices cannot shift and the iteration order is irrelevant to
    # correctness; reverse order is kept only because reading a text edit
    # bottom-up is easier to follow. Interior lines are rewritten as "\n"
    # regardless of the source's line endings — cosmetic only, and this repo is
    # unix-EOL throughout.
    for (l1, c1, l2, c2) in sorted(spans, reverse=True):
        if l1 == l2:
            lines[l1-1] = lines[l1-1][:c1] + lines[l1-1][c2:]
        else:
            lines[l1-1] = lines[l1-1][:c1] + "\n"
            for i in range(l1, l2-1):
                lines[i] = "\n"
            lines[l2-1] = lines[l2-1][c2:]
    return "".join(lines)

def strip_comments(src, path):
    """Blank every `#` comment, by token span.

    `#` comments are not AST nodes, so strip_string_statements() leaves them
    intact — the fourth prose placement. A section-header comment naming a
    pinned field ("# ── (4) coverage_estimate present when tests were run ──")
    survives the deletion of the executable block it labels and satisfies the
    pin-drift grep on its own.

    tokenize, NOT a line-based `#` strip: `#` occurs inside string literals in
    these validators, and a textual strip would corrupt the code the grep then
    inspects. tokenize's start/end columns are CHARACTER offsets into each str
    line (unlike ast's byte offsets), which is what the slicing below assumes.

    Fails CLOSED (bail) for the same reason strip_string_statements does: source
    cannot be tokenized cannot have its prose separated from its checks.
    """
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, SyntaxError) as exc:
        # IndentationError is a SyntaxError subclass, so it is covered here.
        bail("validator source '%s' does not tokenize (%s: %s) — the pin-drift "
             "guard cannot separate its executable checks from its comments"
             % (path, type(exc).__name__, exc))
    lines = src.splitlines(True)
    # A `#` comment runs to end of line, so a COMMENT token never spans lines
    # and at most one can occur per line; each edit replaces its line in place.
    for tok in toks:
        if tok.type != tokenize.COMMENT:
            continue
        (row, c0), (_, c1) = tok.start, tok.end
        lines[row-1] = lines[row-1][:c0] + lines[row-1][c1:]
    return "".join(lines)

prompts=[]; commands=[]
for ev in h.get("hooks",{}).values():
    for e in ev if isinstance(ev,list) else []:
        if needle in str(e.get("matcher","")):
            for hk in e.get("hooks",[]):
                if hk.get("type")=="prompt":
                    prompts.append(hk.get("prompt",""))
                elif hk.get("type")=="command":
                    commands.append(str(hk.get("command","")))

if prompts:
    for p in prompts:
        print(p)
    sys.exit(0)

# ── fallback: the rule source moved into a validator script ──────────────────
REF=re.compile(r'[\w./${}-]*\bvalidate-[A-Za-z0-9_-]+-result\.py')
matching=[c for c in commands if REF.search(c)]
if len(matching)!=1:
    bail("matcher '%s' has no type:prompt hook and %d of its %d type:command "
         "entries reference a validate-*-result.py script (exactly 1 required) "
         "— the rule source is ambiguous; fix hooks.json or the MANIFEST"
         % (needle, len(matching), len(commands)))
refs=sorted(set(REF.findall(matching[0])))
if len(refs)!=1:
    bail("matcher '%s': its validator command entry references %d distinct "
         "validate-*-result.py scripts (exactly 1 required) — the rule source "
         "is ambiguous" % (needle, len(refs)))

path=refs[0]
for var in ("${CLAUDE_PLUGIN_ROOT}", "$CLAUDE_PLUGIN_ROOT"):
    path=path.replace(var, plugin)
if not os.path.isabs(path):
    path=os.path.join(plugin, path)
try:
    with open(path, encoding="utf-8") as fh:
        src=fh.read()
except (OSError, UnicodeDecodeError) as exc:
    bail("matcher '%s': cannot read validator source '%s' (%s)" % (needle, path, exc))
# Prose must not satisfy the pin-drift grep — see the comment block above.
# Docstrings first (by AST span), then `#` comments (by token span).
sys.stdout.write(strip_comments(strip_string_statements(src, path), path))
PY
}

# ── MANIFEST ─────────────────────────────────────────────────────────────────
# matcher | agent file | block name | comma-separated hook-ENFORCED fields
#   "enforced" = required OR validated-when-present. `out_of_lane` is the latter:
#   validate-worker-result.py rule 9 accepts its ABSENCE at any schema_version but rejects a
#   present-but-malformed value. Both of this gate's real checks (pin-drift against the
#   validator source, field-presence in the agent prompt) are satisfied either way.
#
#   That definition is applied CONSISTENTLY, which it was not before v15.20.0: the
#   EXECUTE_CHECKPOINT row pinned only the four unconditional base fields while
#   `adjudication_required` / `missing_outputs` / `adjudication_options` — all validated by
#   rule 6/6a for as long as they have existed — went unpinned, so the comment read as a
#   membership rule the row itself violated. Review flagged the new `adjudication_kind` /
#   `colliding_lanes` as the asymmetry; the asymmetry was in fact older and wider. All five
#   conditional adjudication fields are now pinned together. Verified to have teeth: renaming
#   `adjudication_kind` in execute-manager.md fails this gate with a field-presence error.
MANIFEST="
worker|worker.md|WORKER_RESULT|schema_version,task_id,status,files_modified,summary,outputs_verified,outputs_gap,out_of_lane
execute-manager|execute-manager.md|EXECUTE_RESULT|schema_version,subtasks_completed,worktrees,merge_order,summary
execute-manager|execute-manager.md|EXECUTE_CHECKPOINT|completed_so_far,remaining,resume_context,reason,adjudication_required,missing_outputs,adjudication_options,adjudication_kind,colliding_lanes
qa-executor|qa-executor.md|QA_RESULT|schema_version,tests_generated,tests_passed,summary,coverage_estimate
supervisor-runner|supervisor.md|SUPERVISOR_RESULT|schema_version,status,pr_url,heal_loop_ran,heal_iterations,heal_decision,heal_fixable_issues_fixed,heal_remaining_issues,error,summary
plan-reviewer|plan-reviewer.md|PLAN_REVIEW_RESULT|schema_version,decision,issues,severity,section,description,summary
code-reviewer|code-reviewer.md|CODE_REVIEW_RESULT|schema_version,decision,summary,severity,category,review_mode,audit_focus,trigger_paths_detected,scope_expanded,files_checked
"

# ── Check 1: field presence ──────────────────────────────────────────────────
while IFS='|' read -r matcher agent block fields; do
  [ -n "$matcher" ] || continue
  agent_path="$AGENTS/$agent"
  [ -f "$agent_path" ] || { err field-presence "$agent missing at $agent_path"; continue; }
  prompt="$(hook_prompt "$matcher")"
  # An unresolvable rule source is a HARD error, never a silent pass: falling
  # through to an unrelated script (or to "no rule") is exactly how this guard
  # would go green while enforcing nothing.
  case "$prompt" in
    "$PARITY_UNRESOLVED"*) err pin-drift "${prompt#"$PARITY_UNRESOLVED" }"; continue ;;
  esac
  [ -n "$prompt" ] || { err pin-drift "no prompt-type hook and no validator command hook found for matcher '$matcher' in hooks.json — update the MANIFEST"; continue; }
  IFS=',' read -ra fl <<<"$fields"
  for f in "${fl[@]}"; do
    # (a) pin-drift guard: the matcher's rule source (prompt string, or the
    #     referenced validator script's source) must still require this field
    if ! grep -qw -- "$f" <<<"$prompt"; then
      err pin-drift "hooks.json [$matcher] rule source no longer mentions '$f' — update the MANIFEST in this script"
    fi
    # (b) agent prompt must name the field. NOTE guard strength: this is
    #     name-presence anywhere in the file, not emit-block membership — it
    #     catches a field deleted entirely (the v14.22.x trap class) but not
    #     one mentioned in prose yet dropped from the emit format.
    if ! grep -qw -- "$f" "$agent_path"; then
      err field-presence "$agent: hook-enforced $block field '$f' (required, or validated-when-present) not found anywhere in the agent prompt"
    fi
  done
done <<<"$MANIFEST"

# ── Check 2: enum literals ───────────────────────────────────────────────────
# path (plugin-root-relative) | key | allowed tokens (enum + that file's other
# legitimate uses). Allowlists are deliberately supersets: they also cover
# sub-object statuses (e.g. supervisor's pass/advisory_failures/unverified/
# skipped — sub-object enums on contract_conformance/ground_truth, not
# SUPERVISOR_RESULT.status values). Skills that carry emit-shaping prose
# extracted from an agent (the v14.23.0 supervisor diet) are IN SCOPE below —
# when a refactor moves status-literal-bearing text into a new skill, add a
# row here so the gate's coverage moves with it.
ENUMS="
agents/supervisor.md|status|completed,completed_with_escalation,failed,checkpoint,enum,pass,advisory_failures,unverified,skipped,running
agents/supervisor.md|heal_decision|PASS,ESCALATED,null,enum
agents/worker.md|status|completed,failed,partial,present,missing,pending,enum
agents/qa-executor.md|status|passed,failed,partial,skipped,needs_human,plan_created,all_scopes_completed,enum
agents/execute-manager.md|status|completed,failed,in_progress,pending,running,missing,checkpoint,enum
agents/code-reviewer.md|decision|PASS,FAIL,NEEDS_HUMAN,enum
agents/plan-reviewer.md|decision|PASS,FAIL,NEEDS_HUMAN,enum
skills/self-heal-advisory/SKILL.md|status|pass,advisory_failures,advisory_violations,unverified,skipped,failed,checkpoint,enum
skills/preflight-sync/SKILL.md|status|checkpoint,failed,enum
skills/supervisor-config/SKILL.md|status|failed,enum
skills/self-heal-advisory/SKILL.md|heal_decision|PASS,ESCALATED,null,enum
"

while IFS='|' read -r agent key allowed; do
  [ -n "$agent" ] || continue
  agent_path="$PLUGIN/$agent"
  [ -f "$agent_path" ] || { err enum-literal "scoped file $agent missing at $agent_path — update ENUMS"; continue; }
  # bare literals only: `key: token` (quoted strings, {placeholders}, and
  # comparison forms like `key ==` deliberately do not match)
  while read -r tok; do
    [ -n "$tok" ] || continue
    case ",$allowed," in
      *",$tok,"*) ;;
      *) err enum-literal "$agent: '$key: $tok' is outside the allowed set [$allowed] — out-of-enum literals get hook-rejected at runtime" ;;
    esac
  done < <(grep -ohE "\b${key}:[[:space:]]+[A-Za-z_]+" "$agent_path" | sed -E "s/^${key}:[[:space:]]+//" | sort -u)
done <<<"$ENUMS"

if [ "$fail" -ne 0 ]; then
  echo "✗ contract-parity: drift detected — fix the agent prompt, the hook, or the pinned MANIFEST/ENUMS (keep all three in sync)." >&2
  exit 1
fi
echo "✓ contract-parity: all hook-enforced fields present and all status/decision literals in-enum."
