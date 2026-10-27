#!/usr/bin/env bash
# test-classify-risk.sh — static self-tests for classify-risk.sh (the ONE high-risk-diff
# heuristic behind `automate-helpers.sh gate-eval` condition 6 and the Phase 4.5 red-team lens).
# Builds a fixture git repo in `mktemp -d` and runs the script from a DIFFERENT cwd with --root,
# proving the read-only / never-cd contract. No network, nothing outside the temp dir is touched.
# Exit 0 = all pass, 1 = any failure. Mirrors test-verify-provides.sh. UNCOUNTED by the doc-currency
# gate (a plain script, not an agent/command/skill/hook).
#
# Covers (AC3 / AC4 / AC5 / AC8 of brief 2026-09-13-high-risk-park-in-trusted-merge-gate):
#   A. output contract — one JSON object, always exit 0, fixed key set, source field
#   B. generic branches: (a) path match, (a) content-only match on an innocuous path, (b) workflow
#      directory (incl. a parts-only docs/command-parts/ edit), (b) word, (c) size by lines (>400), (c) size by files (>15); a clean small diff ⇒
#      false with reasons []; reasons are prefixed + name the pattern; case-insensitive
#   C. .agent/risk.json committed on a per-variant base branch (`base-rj-*`) — `paths` glob (`**`
#      across `/`) and `content` literal extend; malformed (string `paths`, non-object root, invalid
#      JSON) ⇒ generic-only + `risk_json_malformed` on stderr, never null; `exclude` ⇒ ignored +
#      `risk_json_exclude_ignored`, never honoured; absent at the base ⇒ silent; a cwd file is unread
#   D. unclassifiable ⇒ null + `unclassifiable: <reason>` + stderr, exit 0: bad ref, not a git
#      repo, bad args (missing refs, --root with no value, empty --root, unknown option); jq off
#      PATH ⇒ the ONE shell-templated object is still valid JSON
#   E. --kind-table == the docs/RESULT_SCHEMAS.md `<!-- risk-table:begin/end -->` block byte-for-byte
#   F. validate-supervisor-result.py accepts a SUPERVISOR_RESULT carrying the nested
#      `risk_classification` object (additive, schema_version stays 1)
#   G. read-only: the fixture repo's worktree and index are unchanged after every run
#   H. mutation control (LESSONS fa32a308): delete the content-match branch from a COPY of the
#      script (gated on non-empty + differs + `bash -n`) ⇒ the content-only case goes red while
#      the path case stays green — the case tests the branch, not the harness
#   I. cwd-independence (PR #219 review): the glob-SHAPED heuristic words (`*auth*`, `*token*`,
#      `migrations/`, ...) are word-split unquoted, so without `set -f` they pathname-expand against
#      the CALLER'S cwd. Run the auth diff from a cwd seeded with `oauth2-proxy.yml`, `tokens.css`,
#      `migrations/`, `payments/` ⇒ still true with the `*auth*` reason, and `--kind-table` is
#      byte-identical to the clean-cwd output; independent mutation control deletes the `-f` from a
#      COPY (gated on non-empty + differs + `bash -n`) ⇒ the seeded-cwd case goes red
#   J. trusted-root branch: one case per surface (reason form `trusted-root: <lowercased path>`);
#      add / edit / delete / rename (both sides, incl. a root-only `.mcp.json` rename under forced
#      rename detection); any-depth names vs repo-root-only entries; look-alike names never match
#      (no substring); a cwd seeded with trusted-root names changes nothing; symlink shapes — the
#      bare root config dir, an `.agent` ancestor, `.agent/rules` — are caught (exact / ancestor)
#   K. `.agent/risk.json` is read from `<base_ref>` only: a head that drops an entry is still judged
#      by the base's entry; an uncommitted working-tree file and a head-only file are unread; an
#      invalid base file is generic-only and trusted-root still applies; a present base blob whose
#      `git show` fails (PATH-stub git), a failed `ls-tree` presence probe, or a base blob missing
#      from the object store ⇒ null + `unclassifiable: git_failed`, never read as absent; a base
#      whose `.agent` (or `.agent/risk.json`) is a symlink ⇒ null + `unclassifiable: risk_json_symlink`;
#      an unrelated symlink under a real `.agent/` is not judged (true + project:); a base whose
#      `.agent` is a submodule (gitlink) ⇒ null + `unclassifiable: risk_json_gitlink`
#   L. mutation controls for J/K, one per pinned rule (reason line deleted, working-tree read,
#      `--no-renames` dropped, root-only arm made any-depth, exact arm made a substring, failed
#      `git show` falls through, exact arm deleted, ancestor arm deleted, failed `ls-tree` presence
#      probe falls through, symlink probe deleted, exact-path filter dropped, gitlink arm deleted),
#      each gated on non-empty + differs + `bash -n`

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/classify-risk.sh"
# docs/RESULT_SCHEMAS.md is an index; the risk table lives in the SUPERVISOR_RESULT split
# file. E2's one-copy count runs over the index AND every split file (the whole schema doc).
SCHEMAS="$HERE/../docs/result-schemas/supervisor-result.md"
SCHEMAS_ALL_DOC="$HERE/../docs/RESULT_SCHEMAS.md $(ls "$HERE"/../docs/result-schemas/*.md "$HERE"/../docs/result-schemas/automate-run/*.md 2>/dev/null | tr '\n' ' ')"
VALIDATOR="$HERE/validate-supervisor-result.py"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-classify-risk.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ELSEWHERE="$TMP/elsewhere"; mkdir -p "$ELSEWHERE"

# --- fixture repo -------------------------------------------------------------------------
# main: README.md + src/utils/format.ts; one branch per case, each ONE commit off main.
R="$TMP/repo"; mkdir -p "$R"
( cd "$R" && git init -q . && git config user.email t@example.com && git config user.name t \
  && git checkout -qb main && mkdir -p src/utils billing docs \
  && printf 'hello\n' > README.md && printf 'export const a = 1;\n' > src/utils/format.ts \
  && printf 'x\n' > billing/base.ts && git add -A && git commit -qm base )

mk_from() {  # mk_from <base branch> <name> <shell snippet run inside the repo>  — commits everything
  ( cd "$R" && git checkout -q "$1" && git checkout -qb "$2" && eval "$3" && git add -A && git commit -qm "$2" ) >/dev/null 2>&1
}
mk_branch() { mk_from main "$@"; }  # mk_branch <name> <snippet> — one commit off main
mk_branch clean       'printf "one\ntwo\nthree\n" >> README.md'
mk_branch path-auth   'mkdir -p src/Auth && printf "x\n" > src/Auth/login.ts'
mk_branch content-tok 'printf "const token = \"abc\";\n" >> src/utils/format.ts'
mk_branch wf-dir      'mkdir -p .github/workflows && printf "on: push\n" > .github/workflows/ci.yml'
mk_branch skills-dir  'mkdir -p loomwright/skills/x && printf "y\n" > loomwright/skills/x/SKILL.md'
mk_branch parts-dir   'mkdir -p loomwright/docs/command-parts/setup && printf "y\n" > loomwright/docs/command-parts/setup/memory.md'
mk_branch word-path   'mkdir -p docs; printf "z\n" > docs/Orchestration.md'
mk_branch big-lines   'i=0; while [ $i -lt 401 ]; do printf "line %s\n" $i >> README.md; i=$((i+1)); done'
mk_branch many-files  'mkdir -p docs; i=0; while [ $i -lt 16 ]; do printf "f\n" > "docs/f$i.md"; i=$((i+1)); done'
mk_branch billing     'printf "charge()\n" > billing/x.ts'
mk_branch stripe      'printf "call Stripe here\n" >> README.md'
mk_branch stub-header 'printf "++x\n" >> README.md'
# .agent/risk.json is read from the BASE ref's tip, so each risk.json variant is its own base branch
# (main itself carries none). The generic heads above are cut from main, so `<base-rj-*>...<head>`
# diffs from the merge base (main) and never includes the risk.json commit.
mk_branch base-rj-ok           'mkdir -p .agent && printf "{\"schema_version\":1,\"paths\":[\"billing/**\"],\"content\":[\"stripe\"]}\n" > .agent/risk.json'
mk_branch base-rj-str          'mkdir -p .agent && printf "{\"schema_version\":1,\"paths\":\"billing/**\"}\n" > .agent/risk.json'
mk_branch base-rj-nonobj       'mkdir -p .agent && printf "[1,2]\n" > .agent/risk.json'
mk_branch base-rj-invalid      'mkdir -p .agent && printf "{not json\n" > .agent/risk.json'
mk_branch base-rj-exclude      'mkdir -p .agent && printf "{\"schema_version\":1,\"paths\":[\"billing/**\"],\"exclude\":[\"billing/**\"]}\n" > .agent/risk.json'
mk_branch base-rj-exclude-only 'mkdir -p .agent && printf "{\"schema_version\":1,\"exclude\":[\"*\"]}\n" > .agent/risk.json'
# Symlinked bases (review iteration 2): git reads never follow an in-tree link (mode 120000).
mk_branch base-rj-agentlink 'mkdir -p agentcfg && printf "{\"schema_version\":1,\"paths\":[\"billing/**\"]}\n" > agentcfg/risk.json && ln -s agentcfg .agent'
mk_branch base-rj-filelink  'mkdir -p .agent rjcfg && printf "{\"schema_version\":1,\"paths\":[\"billing/**\"]}\n" > rjcfg/risk.json && ln -s ../rjcfg/risk.json .agent/risk.json'
# Review iteration 3: an UNRELATED symlink under a real `.agent/` dir must not be judged; a base whose
# `.agent` is a submodule (gitlink, mode 160000) — built with update-index, since `git add -A` would
# stage the missing work-tree dir as a deletion.
mk_branch base-rj-notelink 'mkdir -p .agent && printf "{\"schema_version\":1,\"paths\":[\"billing/**\"]}\n" > .agent/risk.json && ln -s ../x.txt .agent/notes-link'
( cd "$R" && git checkout -q main && git checkout -qb base-rj-gitlink \
  && git update-index --add --cacheinfo "160000,$(git rev-parse main),.agent" && git commit -qm base-rj-gitlink \
  && git checkout -q main ) >/dev/null 2>&1
# Heads cut FROM base-rj-ok (a PR against a base that has the project extension).
mk_from base-rj-ok rj-drop 'printf "{\"schema_version\":1,\"paths\":[],\"content\":[\"stripe\"]}\n" > .agent/risk.json && printf "y\n" > billing/x.txt'
mk_from base-rj-ok rj-keep 'printf "y\n" > billing/x.txt'
# Trusted-root fixtures: base-tr carries the root-only files so heads can edit / delete / rename them.
mk_branch base-tr 'printf "rules v1\n" > CLAUDE.md && printf "{\"mcpServers\":{}}\n" > .mcp.json && mkdir -p .agent/rules && printf "{\"r\":1}\n" > .agent/rules/process.json && printf "{\"v\":1}\n" > .agent/verify.json'
mk_from base-tr tr-claude-edit  'printf "rules v2\n" >> CLAUDE.md'
mk_from base-tr tr-rules-del    'git rm -q .agent/rules/process.json'
mk_from base-tr tr-claude-mv    'mkdir -p docs && git mv CLAUDE.md docs/CLAUDE.md'
mk_from base-tr tr-mcp-mv       'mkdir -p config && git mv .mcp.json config/mcp.json'
mk_from base-tr tr-verify-edit  'printf "{\"v\":2}\n" > .agent/verify.json'
mk_from base-tr tr-verify-del   'git rm -q .agent/verify.json'
mk_branch tr-claude-new    'printf "rules v1\n" > CLAUDE.md'
mk_branch tr-agents        'printf "rules\n" > AGENTS.md'
mk_branch tr-mcp           'printf "{\"mcpServers\":{}}\n" > .mcp.json'
TR_CDIR_FILE='.claude/settings.json'   # the root-only config-dir fixture, named once (vendor-coupling: reuse)
mk_branch tr-claude-dir    "mkdir -p \"\$(dirname $TR_CDIR_FILE)\" && printf '{}\n' > $TR_CDIR_FILE"
mk_branch tr-rules         'mkdir -p .agent/rules && printf "{\"r\":1}\n" > .agent/rules/process.json'
mk_branch tr-riskjson      'mkdir -p .agent && printf "{\"schema_version\":1,\"paths\":[\"*\"]}\n" > .agent/risk.json'
mk_branch tr-verify        'mkdir -p .agent && printf "{\"v\":1}\n" > .agent/verify.json'
mk_branch tr-review        'printf "rules\n" > REVIEW.md'
mk_branch tr-claude-local  'printf "rules\n" > CLAUDE.local.md'
mk_branch tr-nested-claude 'mkdir -p sub/dir && printf "rules\n" > sub/dir/CLAUDE.md'
mk_branch tr-nested-agents 'mkdir -p sub && printf "rules\n" > sub/AGENTS.md'
mk_branch tr-nested-mcp    'mkdir -p sub && printf "{}\n" > sub/.mcp.json'
mk_branch tr-nested-verify 'mkdir -p sub/.agent && printf "{}\n" > sub/.agent/verify.json'
# Symlink shapes: the diff names only the link itself (mode 120000), never a path under it.
mk_branch tr-cdir-symlink  'mkdir -p cfg && printf "{}\n" > cfg/settings.json && ln -s cfg "$(dirname '"$TR_CDIR_FILE"')"'
mk_branch tr-agent-symlink 'mkdir -p agentcfg/rules && printf "{}\n" > agentcfg/rules/p.json && printf "{}\n" > agentcfg/verify.json && ln -s agentcfg .agent'
mk_branch tr-rules-symlink 'mkdir -p .agent rulescfg && printf "{}\n" > rulescfg/p.json && ln -s ../rulescfg .agent/rules'
# Names that merely CONTAIN a trusted-root name (as a substring, or at the wrong depth / boundary).
mk_branch tr-lookalike     'mkdir -p docs src .agent && for f in docs/claude-md-notes.md src/mcp.json.ts docs/verify.json.md src/.mcp.json.ts docs/old-claude.md .agent/verify.json.md .claude-notes.md .agent/rules-old.json; do printf "x\n" > "$f"; done'

run() {  # run <base> <head> [extra args...] — from ELSEWHERE; sets OUT / ERR / RC
  OUT="$(cd "$ELSEWHERE" && bash "$S" "$@" --root "$R" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}
j() { printf '%s' "$OUT" | jq -r "$1"; }
jc() { printf '%s' "$OUT" | jq -c "$1"; }
one_json() { [ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ] && printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; }
has_reason() { printf '%s' "$OUT" | jq -e --arg r "$1" '.reasons | index([$r]) != null' >/dev/null 2>&1; }
tr_count() { printf '%s' "$OUT" | jq -r '[.reasons[] | select(startswith("trusted-root:"))] | length'; }
at_head() { ( cd "$R" && git checkout -q "$1" ) >/dev/null 2>&1; }  # check the fixture repo out at a branch

# =============================================================================
echo "== A. output contract =="
run main clean
if [ "$RC" -eq 0 ] && one_json && [ "$(j '.source')" = "classify-risk.sh" ] \
   && [ "$(j 'keys|join(",")')" = "changed_files,changed_lines,high_risk,reasons,source" ]; then
  ok "A1 one JSON object, exit 0, fixed key set {high_risk,reasons,changed_files,changed_lines,source}"
else
  no "A1 output contract (rc=$RC out='$OUT')"
fi

# =============================================================================
echo "== B. generic heuristic branches =="
run main clean
if [ "$(j '.high_risk')" = "false" ] && [ "$(j '.reasons|length')" = "0" ] \
   && [ "$(j '.changed_files')" = "1" ] && [ "$(j '.changed_lines')" = "3" ]; then
  ok "B1 clean 3-line README change ⇒ high_risk=false, reasons=[], changed_files=1, changed_lines=3"
else
  no "B1 clean diff wrong ($OUT)"
fi

run main path-auth
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.reasons|index(["path: src/auth/login.ts matched *auth*"])')" != "null" ]; then
  ok "B2 (a) path match: src/Auth/login.ts ⇒ true with 'path: … matched *auth*' (case-insensitive)"
else
  no "B2 path-auth wrong ($OUT)"
fi

run main content-tok
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["content: 1 changed line(s) matched *token*"]')" ]; then
  ok "B3 (a) content-only match: 'const token' on an innocuous path ⇒ true with ONLY the content reason"
else
  no "B3 content-tok wrong ($OUT)"
fi

run main wf-dir
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.reasons|index(["path: .github/workflows/ci.yml matched .github/workflows/"])')" != "null" ]; then
  ok "B4 (b) workflow directory ⇒ true with the directory reason"
else
  no "B4 wf-dir wrong ($OUT)"
fi
# .github/workflows/ci.yml also contains the (b) word "workflow" as a path substring — both fire.
[ "$(j '.reasons|index(["path: .github/workflows/ci.yml matched workflow"])')" != "null" ] \
  && ok "B4b (b) word 'workflow' also matched on the same path (path OR content, verbatim)" \
  || no "B4b word match on workflow path missing ($OUT)"

run main skills-dir
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["path: loomwright/skills/x/skill.md matched skills/"]')" ]; then
  ok "B5 (b) skills/ anywhere below the root (loomwright/skills/…) ⇒ true, one-line change is enough"
else
  no "B5 skills-dir wrong ($OUT)"
fi

run main parts-dir
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["path: loomwright/docs/command-parts/setup/memory.md matched command-parts/"]')" ]; then
  ok "B5b (b) a parts-only edit under docs/command-parts/ (split command text) ⇒ true, same as its router"
else
  no "B5b parts-dir wrong — a split command part must classify like commands/ ($OUT)"
fi

run main word-path
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["path: docs/orchestration.md matched orchestration"]')" ]; then
  ok "B6 (b) word in path (Orchestration.md, case-insensitive) ⇒ true"
else
  no "B6 word-path wrong ($OUT)"
fi

run main big-lines
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.changed_lines')" = "401" ] && [ "$(jc '.reasons')" = "$(jq -nc '["size: changed_lines 401 > 400"]')" ]; then
  ok "B7 (c) 401 added lines ⇒ true with 'size: changed_lines 401 > 400' (400 itself is not > 400)"
else
  no "B7 big-lines wrong ($OUT)"
fi

run main many-files
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.changed_files')" = "16" ] && [ "$(jc '.reasons')" = "$(jq -nc '["size: changed_files 16 > 15"]')" ]; then
  ok "B8 (c) 16 changed files ⇒ true with 'size: changed_files 16 > 15'"
else
  no "B8 many-files wrong ($OUT)"
fi

run main stub-header
if [ "$(j '.high_risk')" = "false" ] && [ "$(j '.changed_lines')" = "0" ]; then
  ok "B9 honest limit pinned: an added line beginning '++' diffs as '+++x', indistinguishable from a header, and is not counted"
else
  no "B9 header-lookalike wrong ($OUT)"
fi

# =============================================================================
echo "== C. .agent/risk.json project extension (add-only, committed on the base ref) =="
run base-rj-ok billing
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["project: billing/x.ts matched billing/**"]')" ] && [ -z "$ERR" ]; then
  ok "C1 base risk.json paths glob billing/** + billing/x.ts diff ⇒ true with a project: reason, no stderr"
else
  no "C1 billing wrong ($OUT err='$ERR')"
fi
run base-rj-ok stripe
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["project: 1 changed line(s) matched stripe"]')" ]; then
  ok "C2 content literal 'stripe' matches 'Stripe' in a changed line (case-insensitive) ⇒ project: reason"
else
  no "C2 stripe wrong ($OUT)"
fi
run base-rj-ok clean
[ "$(j '.high_risk')" = "false" ] && ok "C3 the extension only ADDS: the clean diff stays false with risk.json present" || no "C3 clean diff flipped by risk.json ($OUT)"

run base-rj-str billing
if [ "$(j '.high_risk')" = "false" ] && grep -q 'risk_json_malformed' < <(printf '%s' "$ERR"); then
  ok "C4 paths as a string (not array) ⇒ generic-only (false) + risk_json_malformed on stderr, never null"
else
  no "C4 malformed-string wrong ($OUT err='$ERR')"
fi
run base-rj-nonobj billing
[ "$(j '.high_risk')" = "false" ] && grep -q 'risk_json_malformed' < <(printf '%s' "$ERR") \
  && ok "C5 non-object root ⇒ generic-only + risk_json_malformed" || no "C5 non-object wrong ($OUT err='$ERR')"
run base-rj-invalid billing
[ "$(j '.high_risk')" = "false" ] && grep -q 'risk_json_malformed' < <(printf '%s' "$ERR") \
  && ok "C6 invalid JSON ⇒ generic-only + risk_json_malformed" || no "C6 invalid-json wrong ($OUT err='$ERR')"
run base-rj-exclude billing
if [ "$(j '.high_risk')" = "true" ] && grep -q 'risk_json_exclude_ignored' < <(printf '%s' "$ERR"); then
  ok "C7 exclude key is IGNORED (still true) + risk_json_exclude_ignored on stderr — never honoured (R5)"
else
  no "C7 exclude wrong ($OUT err='$ERR')"
fi
run base-rj-exclude-only path-auth
[ "$(j '.high_risk')" = "true" ] && ok "C8 an exclude-only file cannot lower a generic classification" || no "C8 exclude lowered generic ($OUT)"
run main billing
[ "$(j '.high_risk')" = "false" ] && [ -z "$ERR" ] && ok "C9 absent risk.json at the base ⇒ silent generic-only (billing diff is false)" || no "C9 absent wrong ($OUT err='$ERR')"
# --root picks the repository: a risk.json in the CWD must not be picked up.
mkdir -p "$ELSEWHERE/.agent"; printf '{"schema_version":1,"paths":["billing/**"]}\n' > "$ELSEWHERE/.agent/risk.json"
run main billing
[ "$(j '.high_risk')" = "false" ] && ok "C10 a .agent/risk.json in the caller's cwd is NOT read — only <base_ref> in --root's repo" || no "C10 cwd risk.json was read ($OUT)"
rm -rf "$ELSEWHERE/.agent"

# =============================================================================
echo "== D. unclassifiable ⇒ null, always exit 0 =="
unc() {  # unc <label> <reason> <args...>
  local label="$1" reason="$2"; shift 2
  OUT="$(cd "$ELSEWHERE" && bash "$S" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
  if [ "$RC" -eq 0 ] && one_json && [ "$(j '.high_risk')" = "null" ] \
     && [ "$(jc '.reasons')" = "$(jq -nc --arg r "unclassifiable: $reason" '[$r]')" ] \
     && grep -q "$reason" < <(printf '%s' "$ERR"); then
    ok "$label ⇒ null + [\"unclassifiable: $reason\"] + stderr, exit 0"
  else
    no "$label wrong (rc=$RC out='$OUT' err='$ERR')"
  fi
}
unc "D1 bad head ref"           bad_ref         main no-such-branch --root "$R"
unc "D2 bad base ref"           bad_ref         no-such-branch clean --root "$R"
unc "D3 not a git repo"         not_a_git_repo  main clean --root "$ELSEWHERE"
unc "D4 missing refs"           bad_args        --root "$R"
unc "D5 --root with no value"   bad_args        main clean --root
unc "D6 empty --root"           bad_args        main clean --root=
unc "D7 unknown option"         bad_args        main clean --exclude x --root "$R"
OUT="$(cd "$ELSEWHERE" && PATH=/nonexistent "$BASH_BIN" "$S" main clean --root "$R" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
if [ "$RC" -eq 0 ] && one_json && [ "$(j '.high_risk')" = "null" ] && [ "$(j '.reasons[0]')" = "unclassifiable: jq_missing" ] \
   && [ "$(j '.source')" = "classify-risk.sh" ] && grep -q jq_missing < <(printf '%s' "$ERR"); then
  ok "D8 jq off PATH ⇒ the ONE shell-templated object is valid JSON with null + unclassifiable: jq_missing"
else
  no "D8 jq-missing wrong (rc=$RC out='$OUT' err='$ERR')"
fi
OUT="$(cd "$ELSEWHERE" && PATH=/nonexistent "$BASH_BIN" "$S" --root 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && one_json && [ "$(j '.reasons[0]')" = "unclassifiable: bad_args" ] \
  && ok "D9 bad_args seen before jq is known ⇒ templated object, still valid JSON" || no "D9 templated bad_args wrong (out='$OUT')"

# =============================================================================
echo "== E. --kind-table is the single source; RESULT_SCHEMAS carries its ONE copy =="
bash "$S" --kind-table > "$TMP/table"; RC=$?
awk '$0=="<!-- risk-table:end -->"{p=0} p{print} $0=="<!-- risk-table:begin -->"{p=1}' "$SCHEMAS" > "$TMP/doc"
if [ "$RC" -eq 0 ] && [ -s "$TMP/table" ] && [ -s "$TMP/doc" ] && cmp -s "$TMP/table" "$TMP/doc"; then
  ok "E1 --kind-table output == RESULT_SCHEMAS <!-- risk-table:begin/end --> block byte-for-byte"
else
  no "E1 risk-table drift (regenerate the block from \`classify-risk.sh --kind-table\`):"; diff "$TMP/doc" "$TMP/table" | head -10
fi
# shellcheck disable=SC2086  # SCHEMAS_ALL_DOC is a space-separated path list (no spaces in any path)
[ "$(cat $SCHEMAS_ALL_DOC | grep -c '^<!-- risk-table:begin -->$')" -eq 1 ] && ok "E2 exactly ONE committed copy of the table" || no "E2 marker count != 1"
grep -q '`\*token\*`' "$TMP/table" && grep -q 'changed_lines > 400' "$TMP/table" && grep -q 'changed_files > 15' "$TMP/table" \
  && grep -q '`skills/`' "$TMP/table" && grep -q 'NO `exclude` key' "$TMP/table" \
  && grep -q '^| trusted-root .*`CLAUDE.md`.*`.agent/verify.json`.*| `trusted-root:` |$' "$TMP/table" \
  && grep -q 'read from `<base_ref>` only' "$TMP/table" \
  && ok "E3 the table names every branch's data (a/b/c + trusted-root + project from <base_ref>, no exclude)" || no "E3 table content incomplete"
# The lens and the loop POINT at the table instead of restating the pattern list.
# automate-loop is a split index (parallel-automate/22): read its documented-order assembly (index
# segments + split files); a failed assembly leaves no file, so both greps below fail closed.
LENS="$HERE/../skills/self-heal-advisory/completion-tail.md"; LOOP="$TMP/automate-loop-skill.md"
bash "$HERE/fixtures/automate-loop-split/assemble.sh" "$HERE/../skills/automate-loop/SKILL.md" "$LOOP"
grep -q 'classify-risk.sh' "$LENS" && ! grep -q '\*authz\*' "$LENS" \
  && ok "E4 self-heal-advisory lens calls classify-risk.sh and no longer restates the pattern list" || no "E4 lens still restates the heuristic or lacks the call"
grep -q 'classify-risk.sh' "$LOOP" && ! grep -q '\*authz\*' "$LOOP" \
  && ok "E5 automate-loop §10 cond 6 calls classify-risk.sh and does not restate the pattern list" || no "E5 loop restates or lacks the call"

# =============================================================================
echo "== F. validate-supervisor-result.py accepts the nested risk_classification object =="
cat > "$TMP/block.md" <<'EOF'
Phase 4.5 completed.

```yaml
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: 2026-09-13-example
  status: completed
  pr_url: https://github.com/owner/repo/pull/1
  branch: feature/example
  subtasks_completed: 1
  subtasks_failed: 0
  heal_loop_ran: true
  heal_iterations: 0
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: "1/1 subtasks completed. red_team_advisory: skipped_low_risk"
  risk_classification:
    high_risk: false
    reasons: []
```
EOF
python3 -c 'import json,sys
sys.stdout.write(json.dumps({"session_id":"test-classify-risk","hook_event_name":"SubagentStop","agent_type":"test","last_assistant_message":open(sys.argv[1]).read()}))' "$TMP/block.md" > "$TMP/payload.json"
# A validator PASS is `{}` — the documented SubagentStop shape carries no `decision` on allow
# (`{"decision":"block",…}` on reject); see result_block_parser.emit.
VOUT="$(cd "$ELSEWHERE" && python3 "$VALIDATOR" < "$TMP/payload.json" 2>/dev/null)"; VRC=$?
if [ "$VRC" -eq 0 ] && printf '%s' "$VOUT" | jq -e 'type == "object" and (has("decision") | not)' >/dev/null 2>&1; then
  ok "F1 a SUPERVISOR_RESULT carrying risk_classification {high_risk:false, reasons:[]} validates (additive, schema_version 1)"
else
  no "F1 validator rejected the nested object (rc=$VRC out='$VOUT')"
fi
sed -e 's/high_risk: false/high_risk: null/' -e 's/reasons: \[\]/reasons: ["unclassifiable: bad_ref"]/' "$TMP/block.md" > "$TMP/block2.md"
python3 -c 'import json,sys
sys.stdout.write(json.dumps({"session_id":"test-classify-risk","hook_event_name":"SubagentStop","agent_type":"test","last_assistant_message":open(sys.argv[1]).read()}))' "$TMP/block2.md" > "$TMP/payload2.json"
VOUT="$(cd "$ELSEWHERE" && python3 "$VALIDATOR" < "$TMP/payload2.json" 2>/dev/null)"; VRC=$?
[ "$VRC" -eq 0 ] && printf '%s' "$VOUT" | jq -e 'type == "object" and (has("decision") | not)' >/dev/null 2>&1 \
  && ok "F2 high_risk: null + an unclassifiable reason also validates" || no "F2 validator rejected null form (out='$VOUT')"

# =============================================================================
echo "== G. read-only =="
( cd "$R" && git checkout -q main ) 2>/dev/null
before="$(cd "$R" && git status --porcelain && git rev-parse HEAD && ls -a)"
run main path-auth; run main big-lines; run main no-such
after="$(cd "$R" && git status --porcelain && git rev-parse HEAD && ls -a)"
[ "$before" = "$after" ] && ok "G1 worktree, index, HEAD and directory listing unchanged after runs (incl. a failing one)" || no "G1 repo mutated: $(diff <(printf '%s' "$before") <(printf '%s' "$after"))"

# =============================================================================
echo "== H. mutation control — delete the content-match branch from a COPY =="
MUT="$TMP/mut"; mkdir -p "$MUT"
# Remove the two lines that record the content hit in the generic (a)/(b)-word loop.
awk '/^  n="\$\(content_hits "\$lit"\)"$/ {getline; next} {print}' "$S" > "$MUT/classify-risk.sh"
if [ -s "$MUT/classify-risk.sh" ] && ! cmp -s "$S" "$MUT/classify-risk.sh" && bash -n "$MUT/classify-risk.sh" 2>/dev/null \
   && ! grep -q 'content: \$n changed line(s) matched \$pat' "$MUT/classify-risk.sh"; then
  M_OUT="$(cd "$ELSEWHERE" && bash "$MUT/classify-risk.sh" main content-tok --root "$R" 2>/dev/null)"
  if [ "$(printf '%s' "$M_OUT" | jq -r '.high_risk')" = "false" ]; then
    ok "H1 (mutant) content branch deleted ⇒ the content-only case reads false — B3 is live, not vacuous"
  else
    no "H1 mutant not discriminated (out='$M_OUT')"
  fi
  M_OUT="$(cd "$ELSEWHERE" && bash "$MUT/classify-risk.sh" main path-auth --root "$R" 2>/dev/null)"
  [ "$(printf '%s' "$M_OUT" | jq -r '.high_risk')" = "true" ] \
    && ok "H2 (mutant) the path case stays green on the mutant" || no "H2 path case went red on the content mutant (out='$M_OUT')"
else
  no "H1 mutant not gated (empty, identical, bash -n failed, or the branch was not removed)"
fi

# =============================================================================
echo "== I. cwd-independence — glob-shaped heuristic words must not pathname-expand =="
# The Phase 4.5 lens runs with the default --root . from the project root and the /automate loop
# runs with cwd = the checkout, so any repo with a top-level oauth*/tokens*/payments/migrations
# entry would otherwise silently narrow rule (a) to the literal filename (fail-OPEN).
SEEDED="$TMP/seeded"; mkdir -p "$SEEDED/migrations" "$SEEDED/payments"
: > "$SEEDED/oauth2-proxy.yml"; : > "$SEEDED/tokens.css"
run_from() {  # run_from <cwd> <script> <args...> — sets OUT
  local cwd="$1" script="$2"; shift 2
  OUT="$(cd "$cwd" && bash "$script" "$@" 2>/dev/null)"
}
run_from "$SEEDED" "$S" main path-auth --root "$R"
if [ "$(j '.high_risk')" = "true" ] && [ "$(j '.reasons|index(["path: src/auth/login.ts matched *auth*"])')" != "null" ]; then
  ok "I1 auth diff from a cwd holding oauth2-proxy.yml/tokens.css/migrations//payments/ ⇒ still true with the *auth* reason"
else
  no "I1 seeded cwd changed the classification (out='$OUT')"
fi
run_from "$SEEDED" "$S" --kind-table; printf '%s\n' "$OUT" > "$TMP/table-seeded"
run_from "$ELSEWHERE" "$S" --kind-table; printf '%s\n' "$OUT" > "$TMP/table-clean"
if [ -s "$TMP/table-seeded" ] && cmp -s "$TMP/table-seeded" "$TMP/table-clean" && grep -q '`\*token\*`' "$TMP/table-seeded"; then
  ok "I2 --kind-table from the seeded cwd is byte-identical to the clean-cwd table (row (a) still names *token*)"
else
  no "I2 --kind-table differs by cwd:"; diff "$TMP/table-clean" "$TMP/table-seeded" | head -5
fi
# Mutation control (independent of H): drop the -f from `set -fuo pipefail` in a COPY.
MUTF="$TMP/mutf"; mkdir -p "$MUTF"
sed 's/^set -fuo pipefail$/set -uo pipefail/' "$S" > "$MUTF/classify-risk.sh"
if [ -s "$MUTF/classify-risk.sh" ] && ! cmp -s "$S" "$MUTF/classify-risk.sh" && bash -n "$MUTF/classify-risk.sh" 2>/dev/null \
   && ! grep -q '^set -f' "$MUTF/classify-risk.sh"; then
  run_from "$SEEDED" "$MUTF/classify-risk.sh" main path-auth --root "$R"
  if [ "$(j '.high_risk')" = "false" ]; then
    ok "I3 (mutant) without set -f the seeded cwd reads false — I1 is live, not vacuous"
  else
    no "I3 mutant not discriminated (out='$OUT')"
  fi
  run_from "$SEEDED" "$MUTF/classify-risk.sh" --kind-table
  printf '%s\n' "$OUT" | cmp -s - "$TMP/table-clean" \
    && no "I4 (mutant) --kind-table unchanged on the mutant — I2 is vacuous" \
    || ok "I4 (mutant) --kind-table from the seeded cwd differs without set -f — I2 is live"
  run_from "$ELSEWHERE" "$MUTF/classify-risk.sh" main path-auth --root "$R"
  [ "$(j '.high_risk')" = "true" ] \
    && ok "I5 (mutant) the clean-cwd path case stays green on the noglob mutant — the defect is cwd-shaped" \
    || no "I5 clean-cwd case went red on the noglob mutant (out='$OUT')"
else
  no "I3 mutant not gated (empty, identical, bash -n failed, or set -f survived)"
fi

# =============================================================================
echo "== J. trusted-root — instruction / config surfaces are high risk =="
# Reason form pinned: `trusted-root: <lowercased path>`.
tr_case() {  # tr_case <label> <base> <head> <expected reason>
  run "$2" "$3"
  if [ "$(j '.high_risk')" = "true" ] && has_reason "$4"; then
    ok "$1 ⇒ true with '$4'"
  else
    no "$1 wrong — expected '$4' ($OUT err='$ERR')"
  fi
}
run base-tr tr-claude-edit
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["trusted-root: claude.md"]')" ]; then
  ok "J1 one edited line in root CLAUDE.md ⇒ true with exactly ['trusted-root: claude.md'] (AC1)"
else
  no "J1 CLAUDE.md edit wrong ($OUT)"
fi
tr_case "J2a AGENTS.md (AC2)"                 main tr-agents        "trusted-root: agents.md"
tr_case "J2b .mcp.json (AC2)"                 main tr-mcp           "trusted-root: .mcp.json"
tr_case "J2c root config-dir settings (AC2)"  main tr-claude-dir    "trusted-root: $TR_CDIR_FILE"
tr_case "J2d .agent/rules/process.json (AC2)" main tr-rules         "trusted-root: .agent/rules/process.json"
tr_case "J2e .agent/risk.json (AC2)"          main tr-riskjson      "trusted-root: .agent/risk.json"
tr_case "J2f .agent/verify.json (AC2)"        main tr-verify        "trusted-root: .agent/verify.json"
tr_case "J2g REVIEW.md (AC2)"                 main tr-review        "trusted-root: review.md"
tr_case "J2h CLAUDE.local.md (AC2)"           main tr-claude-local  "trusted-root: claude.local.md"
tr_case "J3a .agent/verify.json added (AC3)"  main    tr-verify      "trusted-root: .agent/verify.json"
tr_case "J3b .agent/verify.json edited (AC3)" base-tr tr-verify-edit "trusted-root: .agent/verify.json"
tr_case "J3c .agent/verify.json deleted (AC3)" base-tr tr-verify-del "trusted-root: .agent/verify.json"
tr_case "J4a sub/dir/CLAUDE.md, any depth (AC4)" main tr-nested-claude "trusted-root: sub/dir/claude.md"
tr_case "J4b sub/AGENTS.md, any depth (AC4)"     main tr-nested-agents "trusted-root: sub/agents.md"
run main tr-nested-mcp
[ "$(tr_count)" = "0" ] && [ "$(j '.high_risk')" = "false" ] \
  && ok "J4c sub/.mcp.json ⇒ no trusted-root: reason (.mcp.json is repo-root only) (AC4)" || no "J4c sub/.mcp.json matched ($OUT)"
run main tr-nested-verify
[ "$(tr_count)" = "0" ] && [ "$(j '.high_risk')" = "false" ] \
  && ok "J4d sub/.agent/verify.json ⇒ no trusted-root: reason (repo-root only) (AC4)" || no "J4d sub/.agent/verify.json matched ($OUT)"
tr_case "J5a .agent/rules/process.json deleted (AC5)" base-tr tr-rules-del "trusted-root: .agent/rules/process.json"
run base-tr tr-claude-mv
if [ "$(j '.high_risk')" = "true" ] && has_reason "trusted-root: claude.md" && has_reason "trusted-root: docs/claude.md"; then
  ok "J5b CLAUDE.md renamed to docs/CLAUDE.md ⇒ true, both sides named (AC5)"
else
  no "J5b CLAUDE.md rename wrong ($OUT)"
fi
# AC5b: rename detection FORCED on (env-level git config, git >= 2.31), so the case proves the
# trusted-root list uses --no-renames rather than relying on the caller's diff.renames setting.
RENAMES_ON=(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.renames GIT_CONFIG_VALUE_0=true)
OUT="$(cd "$ELSEWHERE" && "${RENAMES_ON[@]}" bash "$S" base-tr tr-mcp-mv --root "$R" 2>/dev/null)"
if [ "$(j '.high_risk')" = "true" ] && has_reason "trusted-root: .mcp.json"; then
  ok "J5c root .mcp.json renamed to config/mcp.json (content unchanged) ⇒ true naming the OLD path (AC5b)"
else
  no "J5c root-only rename escaped ($OUT)"
fi
run main clean
[ "$(j '.high_risk')" = "false" ] && [ "$(tr_count)" = "0" ] \
  && ok "J6 a diff touching no trusted-root and no generic surface stays false (AC10)" || no "J6 clean diff flipped ($OUT)"
run main tr-lookalike
if [ "$(tr_count)" = "0" ] && [ "$(j '.high_risk')" = "false" ]; then
  ok "J7 names that merely contain a trusted-root name (claude-md-notes, mcp.json.ts, .mcp.json.ts, old-claude.md, verify.json.md, .claude-notes.md, rules-old.json) ⇒ no match, never a substring (AC11)"
else
  no "J7 substring look-alike matched ($OUT)"
fi
# Exact / ancestor path shapes (review iteration 1): a symlink in place of a root-only directory.
TR_CDIR="$(dirname "$TR_CDIR_FILE")"
tr_case "J10a symlink config dir -> cfg/ (bare path, mode 120000)" main tr-cdir-symlink  "trusted-root: $TR_CDIR"
tr_case "J10b symlink .agent -> agentcfg/ (ancestor of the .agent entries)" main tr-agent-symlink "trusted-root: .agent"
tr_case "J10c symlink .agent/rules -> ../rulescfg (bare path of .agent/rules/)" main tr-rules-symlink "trusted-root: .agent/rules"
# AC12: a cwd holding untracked files named like the trusted-root entries leaves the result unchanged.
TRSEED="$TMP/trseed"; mkdir -p "$TRSEED/.claude" "$TRSEED/.agent/rules"
: > "$TRSEED/CLAUDE.md"; : > "$TRSEED/.mcp.json"; : > "$TRSEED/AGENTS.md"
run_from "$TRSEED" "$S" base-tr tr-claude-edit --root "$R"
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["trusted-root: claude.md"]')" ]; then
  ok "J8 CLAUDE.md diff from a cwd holding untracked trusted-root names (files + the config dir) ⇒ unchanged (AC12)"
else
  no "J8 seeded cwd changed the trusted-root result ($OUT)"
fi
# The trusted-root data lists are plain words — nothing for noglob to protect (AC12's premise).
if ! grep -q '[][*?]' < <(grep -E "^TRUSTED_ROOT_(ANYDEPTH|ROOTONLY)=" "$S"); then
  ok "J9 TRUSTED_ROOT_* lists hold no glob character (*, ?, [) — the any-depth rule is built in code"
else
  no "J9 a TRUSTED_ROOT_* entry is glob-shaped — the seeded cwd in J8 must then hold a matching path"
fi

# =============================================================================
echo "== K. .agent/risk.json is read from <base_ref> only =="
at_head rj-drop
run base-rj-ok rj-drop
if [ "$(j '.high_risk')" = "true" ] && has_reason "project: billing/x.txt matched billing/**" && has_reason "trusted-root: .agent/risk.json"; then
  ok "K1 head drops billing/** AND changes billing/x.txt, --root at the head checkout ⇒ project: (from the base) + trusted-root: (AC6)"
else
  no "K1 base-ref read wrong ($OUT)"
fi
at_head rj-keep
printf '{}\n' > "$R/.agent/risk.json"   # uncommitted working-tree edit — must not be read
run base-rj-ok rj-keep
if [ "$(j '.high_risk')" = "true" ] && has_reason "project: billing/x.txt matched billing/**"; then
  ok "K2 working tree's uncommitted risk.json is {} ⇒ the base's project: reason is still present (AC7)"
else
  no "K2 working tree was read ($OUT)"
fi
( cd "$R" && git checkout -q -- .agent/risk.json ) >/dev/null 2>&1
at_head main
run main tr-riskjson
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["trusted-root: .agent/risk.json"]')" ]; then
  ok "K3 base has no risk.json, head ADDS one with paths [\"*\"] ⇒ trusted-root: only, no project: (AC9)"
else
  no "K3 head risk.json was read ($OUT)"
fi
run base-rj-invalid tr-claude-new
if [ "$(j '.high_risk')" = "true" ] && [ "$(jc '.reasons')" = "$(jq -nc '["trusted-root: claude.md"]')" ] \
   && grep -q 'risk_json_malformed' < <(printf '%s' "$ERR"); then
  ok "K4 base risk.json invalid ⇒ risk_json_malformed on stderr, and trusted-root: claude.md still applies (AC14)"
else
  no "K4 malformed base + CLAUDE.md wrong ($OUT err='$ERR')"
fi
unc "K5 bad base ref (AC13)" bad_ref no-such-branch tr-claude-new --root "$R"
# AC14b: a PATH stub `git` that delegates every call to the real git except `show`.
REAL_GIT="$(command -v git)"
GSTUB="$TMP/gitstub"; mkdir -p "$GSTUB"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = show ] && { echo "stub: git show refused" >&2; exit 1; }; done\nexec %q "$@"\n' "$REAL_GIT" > "$GSTUB/git"
chmod +x "$GSTUB/git"
SAVED_PATH="$PATH"; PATH="$GSTUB:$PATH"
unc "K6 base risk.json present but git show fails (AC14b)" git_failed base-rj-ok billing --root "$R"
run main billing
PATH="$SAVED_PATH"
[ "$(j '.high_risk')" = "false" ] && [ -z "$ERR" ] \
  && ok "K7 control: same git stub, base WITHOUT risk.json ⇒ normal false result (the stub delegates; only show fails)" \
  || no "K7 stub control wrong ($OUT err='$ERR')"
# The presence probe itself failing must never read as "absent": a stub whose `ls-tree` fails.
GSTUB_LT="$TMP/gitstub-lstree"; mkdir -p "$GSTUB_LT"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = ls-tree ] && { echo "stub: git ls-tree refused" >&2; exit 1; }; done\nexec %q "$@"\n' "$REAL_GIT" > "$GSTUB_LT/git"
chmod +x "$GSTUB_LT/git"
PATH="$GSTUB_LT:$SAVED_PATH"
unc "K8 risk.json presence probe (ls-tree) fails ⇒ never read as absent" git_failed base-rj-ok billing --root "$R"
PATH="$SAVED_PATH"
# The reviewer's real-repo shape: the base risk.json blob is missing from the object store.
RC_R="$TMP/repo-corrupt"; mkdir -p "$RC_R"
( cd "$RC_R" && git init -q . && git config user.email t@example.com && git config user.name t \
  && git checkout -qb main && mkdir -p .agent billing \
  && printf '{"schema_version":1,"paths":["billing/**"],"note":"corrupt-fixture"}\n' > .agent/risk.json \
  && printf 'x\n' > billing/base.ts && git add -A && git commit -qm base \
  && git checkout -qb head && printf 'y\n' > billing/x.txt && git add -A && git commit -qm head \
  && blob="$(git rev-parse main:.agent/risk.json)" && rm -f ".git/objects/${blob:0:2}/${blob:2}" ) >/dev/null 2>&1
OUT="$(cd "$ELSEWHERE" && bash "$S" main head --root "$RC_R" 2>"$TMP/err")"; ERR="$(cat "$TMP/err")"
[ "$(j '.high_risk')" = "null" ] && has_reason "unclassifiable: git_failed" \
  && ok "K9 base risk.json blob missing from the object store ⇒ null + unclassifiable: git_failed, never a silent false" \
  || no "K9 missing base blob read as absent ($OUT err='$ERR')"
# Symlinked base config: the owner's entries cannot be read without following a link ⇒ fail CLOSED.
unc "K10 base .agent is a symlink to a dir holding risk.json" risk_json_symlink base-rj-agentlink billing --root "$R"
unc "K11 base .agent/risk.json is itself a symlink" risk_json_symlink base-rj-filelink billing --root "$R"
run main clean
[ "$(j '.high_risk')" = "false" ] && [ -z "$ERR" ] \
  && ok "K12 control: base without .agent at all ⇒ silent false (the symlink probe does not fire on absence)" \
  || no "K12 absent-.agent control wrong ($OUT err='$ERR')"
run base-rj-notelink billing
if [ "$(j '.high_risk')" = "true" ] && has_reason "project: billing/x.ts matched billing/**" \
   && ! printf '%s' "$OUT" | grep -q 'unclassifiable'; then
  ok "K13 base .agent/ holds an unrelated symlink (notes-link) next to a regular risk.json ⇒ true with the project: reason, never unclassifiable"
else
  no "K13 unrelated .agent child symlink was judged ($OUT err='$ERR')"
fi
[ "$(git -C "$R" ls-tree base-rj-gitlink -- .agent | cut -c1-6)" = "160000" ] \
  && ok "K14a fixture: base-rj-gitlink's .agent is a gitlink (mode 160000)" || no "K14a gitlink fixture not built"
unc "K14 base .agent is a submodule (gitlink)" risk_json_gitlink base-rj-gitlink billing --root "$R"

# =============================================================================
echo "== L. mutation controls for J / K (each gated on non-empty + differs + bash -n) =="
mutant() {  # mutant <name> <sed-or-grep program applied via the remaining args> — writes $TMP/m-<name>/classify-risk.sh
  local name="$1"; shift
  mkdir -p "$TMP/m-$name"
  "$@" "$S" > "$TMP/m-$name/classify-risk.sh"
  MS="$TMP/m-$name/classify-risk.sh"
  [ -s "$MS" ] && ! cmp -s "$S" "$MS" && bash -n "$MS" 2>/dev/null
}
mrun() {  # mrun <args...> — run the current mutant $MS from ELSEWHERE; sets OUT
  OUT="$(cd "$ELSEWHERE" && bash "$MS" "$@" --root "$R" 2>/dev/null)"
}
# L1 — delete the trusted-root reason line ⇒ the AC1 case goes red.
if mutant no-tr grep -v '^  trusted_root_hit "\$p" && reason "trusted-root: \$p"$' && ! grep -q 'reason "trusted-root: ' "$MS"; then
  mrun base-tr tr-claude-edit
  [ "$(j '.high_risk')" = "false" ] && ok "L1 (mutant) trusted-root reason line deleted ⇒ J1 reads false — J1 is live" || no "L1 mutant not discriminated ($OUT)"
else
  no "L1 mutant not gated"
fi
# L2 — read risk.json from the working tree instead of the base ⇒ the AC6 case goes red.
if mutant wt-read sed 's|git -C "$root" show "$base:.agent/risk.json"|cat "$root/.agent/risk.json"|' && ! grep -q 'show "\$base:.agent/risk.json"' "$MS"; then
  at_head rj-drop
  mrun base-rj-ok rj-drop
  at_head main
  if [ "$(j '.high_risk')" = "true" ] && ! has_reason "project: billing/x.txt matched billing/**"; then
    ok "L2 (mutant) working-tree read ⇒ K1 loses the base's project: reason — K1 is live"
  else
    no "L2 mutant not discriminated ($OUT)"
  fi
else
  no "L2 mutant not gated"
fi
# L3 — drop --no-renames from the trusted-root path list ⇒ the AC5b case goes red.
if mutant renames sed 's/^\(if ! git -C "\$root" diff --name-only\) --no-renames -z /\1 -z /' && ! grep -q '^if ! git.*--no-renames' "$MS"; then
  OUT="$(cd "$ELSEWHERE" && "${RENAMES_ON[@]}" bash "$MS" base-tr tr-mcp-mv --root "$R" 2>/dev/null)"
  [ "$(j '.high_risk')" = "false" ] && ! has_reason "trusted-root: .mcp.json" \
    && ok "L3 (mutant) without --no-renames the .mcp.json → config/mcp.json rename escapes (false) — J5c is live" \
    || no "L3 mutant not discriminated ($OUT)"
else
  no "L3 mutant not gated"
fi
# L4 — root-only exact arm flipped to the any-depth form ⇒ the AC4 negative goes red.
if mutant rootonly-anydepth sed 's/^    case "\$1" in "\$m") return 0 ;; esac$/    case "$1" in "$m"|*\/"$m") return 0 ;; esac/'; then
  mrun main tr-nested-mcp
  [ "$(tr_count)" != "0" ] && ok "L4 (mutant) root-only arm made any-depth ⇒ sub/.mcp.json matches — J4c is live" || no "L4 mutant not discriminated ($OUT)"
else
  no "L4 mutant not gated"
fi
# L5 — exact arm flipped to a substring match ⇒ the AC11 look-alike case goes red.
if mutant substring sed 's/^    case "\$1" in "\$m") return 0 ;; esac$/    case "$1" in *"$m"*) return 0 ;; esac/'; then
  mrun main tr-lookalike
  [ "$(tr_count)" != "0" ] && ok "L5 (mutant) exact arm made a substring ⇒ src/.mcp.json.ts matches — J7 is live" || no "L5 mutant not discriminated ($OUT)"
else
  no "L5 mutant not gated"
fi
# L6 — silent fall-through after a failed `git show` of a present blob ⇒ the AC14b case goes red.
if mutant show-silent sed 's/^    emit_unclassifiable "git_failed" "base risk.json unreadable: .*$/    :/'; then
  PATH="$GSTUB:$SAVED_PATH"
  mrun base-rj-ok billing
  PATH="$SAVED_PATH"
  [ "$(j '.high_risk')" = "false" ] && ok "L6 (mutant) failed base read falls through ⇒ K6 reads a silent false — K6 is live" || no "L6 mutant not discriminated ($OUT)"
else
  no "L6 mutant not gated"
fi
# L7 — delete the exact-path arm ⇒ the bare symlinked config dir (J10a) escapes.
if mutant no-exact grep -v '^    case "\$1" in "\$m") return 0 ;; esac$'; then
  mrun main tr-cdir-symlink
  [ "$(j '.high_risk')" = "false" ] && ok "L7 (mutant) exact-path arm deleted ⇒ the config-dir symlink reads false — J10a is live" || no "L7 mutant not discriminated ($OUT)"
else
  no "L7 mutant not gated"
fi
# L8 — delete the ancestor arm ⇒ the `.agent -> agentcfg` symlink (J10b) escapes.
if mutant no-ancestor grep -v '^    case "\$m" in "\$1"/\*) return 0 ;; esac$'; then
  mrun main tr-agent-symlink
  [ "$(j '.high_risk')" = "false" ] && ok "L8 (mutant) ancestor arm deleted ⇒ the .agent symlink reads false — J10b is live" || no "L8 mutant not discriminated ($OUT)"
else
  no "L8 mutant not gated"
fi
# L9 — a failed presence probe falls through as "absent" ⇒ the K8 case goes red.
if mutant probe-silent sed 's/^  emit_unclassifiable "git_failed" "base risk.json probe failed: .*$/  :/'; then
  PATH="$GSTUB_LT:$SAVED_PATH"
  mrun base-rj-ok billing
  PATH="$SAVED_PATH"
  [ "$(j '.high_risk')" = "false" ] && ok "L9 (mutant) failed ls-tree probe falls through ⇒ K8 reads a silent false — K8 is live" || no "L9 mutant not discriminated ($OUT)"
else
  no "L9 mutant not gated"
fi
# L10 — delete the symlink probe's emit ⇒ the K10 `.agent -> agentcfg` base reads a silent false.
if mutant symlink-silent sed 's/^      emit_unclassifiable "risk_json_symlink" .*$/      : ;;/' && ! grep -q 'emit_unclassifiable "risk_json_symlink"' "$MS"; then
  OUT="$(cd "$ELSEWHERE" && bash "$MS" base-rj-agentlink billing --root "$R" 2>"$TMP/err")"; ERR="$(cat "$TMP/err")"
  [ "$(j '.high_risk')" = "false" ] && [ -z "$ERR" ] \
    && ok "L10 (mutant) symlink probe deleted ⇒ K10 reads a silent false with nothing on stderr — K10 is live" \
    || no "L10 mutant not discriminated ($OUT err='$ERR')"
else
  no "L10 mutant not gated"
fi
# L11 — restore the any-record mode check (drop the exact-path filter) ⇒ K13's unrelated child symlink reads null.
if mutant any-record grep -v '^  case "\$rp" in .agent|.agent/risk.json) ;; \*) continue ;; esac$' && ! grep -q 'continue ;; esac' "$MS"; then
  mrun base-rj-notelink billing
  [ "$(j '.high_risk')" = "null" ] && has_reason "unclassifiable: risk_json_symlink" \
    && ok "L11 (mutant) mode check on every record ⇒ K13 reads null risk_json_symlink — K13 is live" \
    || no "L11 mutant not discriminated ($OUT)"
else
  no "L11 mutant not gated"
fi
# L12 — delete the gitlink arm's emit ⇒ the K14 submodule base reads a silent false.
if mutant gitlink-silent sed 's/^      emit_unclassifiable "risk_json_gitlink" .*$/      : ;;/' && ! grep -q 'emit_unclassifiable "risk_json_gitlink"' "$MS"; then
  OUT="$(cd "$ELSEWHERE" && bash "$MS" base-rj-gitlink billing --root "$R" 2>"$TMP/err")"; ERR="$(cat "$TMP/err")"
  [ "$(j '.high_risk')" = "false" ] && [ -z "$ERR" ] \
    && ok "L12 (mutant) gitlink arm deleted ⇒ K14 reads a silent false with nothing on stderr — K14 is live" \
    || no "L12 mutant not discriminated ($OUT err='$ERR')"
else
  no "L12 mutant not gated"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
