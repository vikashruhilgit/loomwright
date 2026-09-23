#!/usr/bin/env bash
# test-guard-test-integrity.sh — self-tests for guard-test-integrity.sh +
# guard-arm.sh (the six-phase-loop-gaps/02 test-integrity guard). Covers the
# full case matrix in the source requirement's Scope item 10
# (`.supervisor/requirements/six-phase-loop-gaps/02-test-integrity-guard.md`):
# every Bash pattern + its negation twin, every Write|Edit basename + allow
# case, the 6 gate cases, the guard-arm.sh subcommand cases, the concurrency
# case, the sentinel checks, and all 22 named mutation controls.
#
# Runs entirely in temp dirs (mktemp -d), never touches the real
# `.supervisor/`. Exit 0 = all pass, 1 = any failure (auto-registered by
# ci.yml's test-*.sh glob).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/guard-test-integrity.sh"
ARM="$SCRIPT_DIR/guard-arm.sh"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-guard-test-integrity: jq absent — guard denies closed without it. Skipping full matrix."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ---------------------------------------------------------------------------
# harness helpers
# ---------------------------------------------------------------------------
new_guarded_dir() {
  local d sid
  d="$(mktemp -d)"
  sid="${1:-sess-guard-test}"
  mkdir -p "$d/.supervisor/guard"
  printf '{\n  "session_id": "%s",\n  "armed_at": "%s",\n  "by": "test"\n}\n' "$sid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$d/.supervisor/guard/$sid.json"
  printf '%s' "$d"
}

# bash_rc <guard_dir> <session_id> <command> [agent_type]
bash_rc() {
  local d="$1" sid="$2" cmd="$3" at="${4:-}"
  local payload
  payload="$(jq -n --arg sid "$sid" --arg cmd "$cmd" --arg at "$at" \
    'if $at == "" then {session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}
     else {session_id:$sid, agent_type:$at, tool_name:"Bash", tool_input:{command:$cmd}} end')"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$d" bash "$GUARD" >/dev/null 2>/tmp/.guard-test-stderr.$$
  echo $?
}

bash_stderr() { cat /tmp/.guard-test-stderr.$$ 2>/dev/null; }

# edit_rc <guard_dir> <session_id> <tool_name> <file_path>
edit_rc() {
  local d="$1" sid="$2" tool="$3" fp="$4"
  local payload
  payload="$(jq -n --arg sid "$sid" --arg tool "$tool" --arg fp "$fp" '{session_id:$sid, tool_name:$tool, tool_input:{file_path:$fp}}')"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$d" bash "$GUARD" >/dev/null 2>/tmp/.guard-test-stderr.$$
  echo $?
}

assert_rc() {
  local desc="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then ok "$desc"; else no "$desc (want rc=$want got rc=$got, stderr=[$(bash_stderr)])"; fi
}

D="$(new_guarded_dir sess-A)"
SID="sess-A"

# ---------------------------------------------------------------------------
# Bash-matcher patterns + negation twins
# ---------------------------------------------------------------------------
assert_rc "git commit -m x — allow"                              "$(bash_rc "$D" "$SID" 'git commit -m x')" 0
assert_rc "git commit -n -m x — deny"                             "$(bash_rc "$D" "$SID" 'git commit -n -m x')" 2
assert_rc "git commit -qm x --no-veri — deny"                     "$(bash_rc "$D" "$SID" 'git commit -qm x --no-veri')" 2
# Self-audit finding (PR #258, after the round-2 review pattern): git
# accepts GLOBAL options before the subcommand, so a fixed words[idx+1]
# read for the subcommand missed every subcommand-scoped check whenever
# any global flag came first.
assert_rc "git --no-optional-locks commit -n -m x — deny (global-flag-before-subcmd bypass)" "$(bash_rc "$D" "$SID" 'git --no-optional-locks commit -n -m x')" 2
assert_rc "git -C . commit -n -m x — deny (value-taking global flag)" "$(bash_rc "$D" "$SID" 'git -C . commit -n -m x')" 2
assert_rc "git --no-pager clean -fdx — deny (global-flag-before-clean)" "$(bash_rc "$D" "$SID" 'git --no-pager clean -fdx')" 2
assert_rc "git -C . status — allow (global flag, non-scoped subcmd)" "$(bash_rc "$D" "$SID" 'git -C . status')" 0
assert_rc "git push -n — allow"                                   "$(bash_rc "$D" "$SID" 'git push -n')" 0
assert_rc "git push --no-verify — deny"                           "$(bash_rc "$D" "$SID" 'git push --no-verify')" 2
assert_rc "HUSKY=0 git commit -m x — deny"                        "$(bash_rc "$D" "$SID" 'HUSKY=0 git commit -m x')" 2
assert_rc "export HUSKY=0; git commit -m x — deny"                "$(bash_rc "$D" "$SID" 'export HUSKY=0; git commit -m x')" 2
# PR #258 round-2 review finding: a second stacked leading VAR=val
# assignment was invisible to a words[0]/words[1]-only anchor check.
assert_rc "A=1 HUSKY=0 npm test — deny (stacked assignment bypass)" "$(bash_rc "$D" "$SID" 'A=1 HUSKY=0 npm test')" 2
assert_rc "A=1 B=2 SKIP=lint git commit -m x — deny (2 stacked)"   "$(bash_rc "$D" "$SID" 'A=1 B=2 SKIP=lint git commit -m x')" 2
assert_rc "CI_SKIP=1 npm test — allow"                             "$(bash_rc "$D" "$SID" 'CI_SKIP=1 npm test')" 0
assert_rc "A=1 CI_SKIP=1 npm test — allow (stacked, none match)"   "$(bash_rc "$D" "$SID" 'A=1 CI_SKIP=1 npm test')" 0
# PR #258 round-2 review finding: lefthook's real CLI accepts global flags
# BEFORE the subcommand, so a words[idx+1]-only uninstall check missed it.
assert_rc "lefthook uninstall — deny"                              "$(bash_rc "$D" "$SID" 'lefthook uninstall')" 2
assert_rc "lefthook --no-colors uninstall — deny (flag-before bypass)" "$(bash_rc "$D" "$SID" 'lefthook --no-colors uninstall')" 2
assert_rc "pre-commit uninstall — deny"                            "$(bash_rc "$D" "$SID" 'pre-commit uninstall')" 2
assert_rc "pre-commit --color=never uninstall — deny (flag-before bypass)" "$(bash_rc "$D" "$SID" 'pre-commit --color=never uninstall')" 2
assert_rc "git -c core.hooksPath=/dev/null commit — deny"          "$(bash_rc "$D" "$SID" 'git -c core.hooksPath=/dev/null commit')" 2
assert_rc "git config --get core.hooksPath — allow"                "$(bash_rc "$D" "$SID" 'git config --get core.hooksPath')" 0
assert_rc "git config core.hooksPath /dev/null — deny"             "$(bash_rc "$D" "$SID" 'git config core.hooksPath /dev/null')" 2
assert_rc 'GIT_CONFIG_PARAMETERS=... git commit — deny'            "$(bash_rc "$D" "$SID" "GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/dev/null'\" git commit")" 2
assert_rc "git clean -fdx — deny"                                  "$(bash_rc "$D" "$SID" 'git clean -fdx')" 2
assert_rc "git clean -fd — allow"                                  "$(bash_rc "$D" "$SID" 'git clean -fd')" 0
assert_rc "grep -- '--no-verify' docs/HOOKS.md — allow"            "$(bash_rc "$D" "$SID" "grep -- '--no-verify' docs/HOOKS.md")" 0
assert_rc "cat > jest.config.js <<EOF — deny"                      "$(bash_rc "$D" "$SID" 'cat > jest.config.js <<EOF')" 2
assert_rc "git diff jest.config.ts > /tmp/d.patch — allow"         "$(bash_rc "$D" "$SID" 'git diff jest.config.ts > /tmp/d.patch')" 0
assert_rc "sed -i '' s/a/b/ vitest.config.ts — deny"                "$(bash_rc "$D" "$SID" "sed -i '' s/a/b/ vitest.config.ts")" 2
assert_rc "rm .supervisor/guard/<sid>.json — deny"                 "$(bash_rc "$D" "$SID" "rm .supervisor/guard/$SID.json")" 2
assert_rc "bash guard-arm.sh disarm-session — deny"                "$(bash_rc "$D" "$SID" "bash $ARM disarm-session")" 2
assert_rc "bash guard-arm.sh arm-from-payload — deny"              "$(bash_rc "$D" "$SID" "bash $ARM arm-from-payload")" 2
assert_rc "bash guard-arm.sh arm supervisor — allow"               "$(bash_rc "$D" "$SID" "bash $ARM arm supervisor")" 0
# PR #258 review finding: an `arm` invocation is only "harmless by construction"
# when it can only name the CALLER's own session id — a --session-id flag lets
# a tool call arm an ARBITRARY other session, which is the real capability
# --session-id exists to grant, so it must be denied from a tool call (the
# only legitimate caller, dispatch-pr-review.sh, invokes guard-arm.sh directly
# as a subprocess, never through a tool call this matcher sees).
assert_rc "bash guard-arm.sh arm x --session-id <arbitrary-id> — deny (arbitrary-session arm)" "$(bash_rc "$D" "$SID" "bash $ARM arm x --session-id arbitrary-id")" 2
assert_rc "bash guard-arm.sh arm x --session-id=<arbitrary-id> — deny (= form)" "$(bash_rc "$D" "$SID" "bash $ARM arm x --session-id=arbitrary-id")" 2
# PR #258 review round-3 finding: the executable-word walk only recognized
# export/env as transparent prefix keywords, so `command`/`exec`/a leading
# `\` on the executable token — the standard shell ways to invoke a program
# while bypassing an alias/function of the same name — resolved exec_base
# to "command"/"exec"/"\git" and silently skipped EVERY exec_base-keyed
# check below, not just one pattern (the widest instance of this bug class
# found so far, since it defeats the whole dispatch mechanism at once).
assert_rc "command git commit -n -m x — deny (command-prefix bypass)" "$(bash_rc "$D" "$SID" 'command git commit -n -m x')" 2
assert_rc "exec git commit -n -m x — deny (exec-prefix bypass)"    "$(bash_rc "$D" "$SID" 'exec git commit -n -m x')" 2
assert_rc '\git commit -n -m x — deny (backslash-escape bypass)'   "$(bash_rc "$D" "$SID" '\git commit -n -m x')" 2
assert_rc "command pre-commit uninstall — deny (command-prefix bypass)" "$(bash_rc "$D" "$SID" 'command pre-commit uninstall')" 2
assert_rc "exec rm .supervisor/guard/<sid>.json — deny (exec-prefix self-disarm bypass)" "$(bash_rc "$D" "$SID" "exec rm .supervisor/guard/$SID.json")" 2
assert_rc "command bash guard-arm.sh arm x --session-id <id> — deny (command-prefix arbitrary-session arm)" "$(bash_rc "$D" "$SID" "command bash $ARM arm x --session-id arbitrary-id")" 2
assert_rc "command echo hi — allow (non-scoped exec_base, command-prefixed)" "$(bash_rc "$D" "$SID" 'command echo hi')" 0
# PR #258 review round-4 finding: the round-3 fix only stripped a leading
# backslash from the FINAL resolved exec_word, not from command/env/
# builtin/exec/export THEMSELVES, so `\env`/`\command`/`\exec`/`\builtin`/
# `\export` still resolved exec_base to the escaped keyword and skipped
# every downstream check — `\exec rm <guard marker>` was a full session
# self-disarm, the worst outcome in the whole matrix.
assert_rc '\env git commit -n -m x — deny (backslash-escaped env)' "$(bash_rc "$D" "$SID" '\env git commit -n -m x')" 2
assert_rc '\command git commit -n -m x — deny (backslash-escaped command)' "$(bash_rc "$D" "$SID" '\command git commit -n -m x')" 2
assert_rc '\exec rm <guard marker> — deny (backslash-escaped exec, self-disarm)' "$(bash_rc "$D" "$SID" "\\exec rm .supervisor/guard/$SID.json")" 2
assert_rc '\builtin exec rm <guard marker> — deny (stacked backslash-escapes)' "$(bash_rc "$D" "$SID" "\\builtin exec rm .supervisor/guard/$SID.json")" 2
assert_rc '\export HUSKY=1; git commit -m x — deny (backslash-escaped export, anchor check)' "$(bash_rc "$D" "$SID" '\export HUSKY=1; git commit -m x')" 2
# PR #258 review round-4 finding: `env`'s own flags/values (which real env
# CLIs legitimately accept before the wrapped command) were not walked
# past, so `env -i git ...` / `env -u FOO git ...` resolved exec_base to
# the flag/value token itself instead of the wrapped command.
assert_rc "env -i git commit -n -m x — deny (env flag before wrapped command)" "$(bash_rc "$D" "$SID" 'env -i git commit -n -m x')" 2
assert_rc "env -u FOO git commit -n -m x — deny (env value-taking flag)" "$(bash_rc "$D" "$SID" 'env -u FOO git commit -n -m x')" 2
assert_rc "env -i HUSKY=0 git commit -m x — deny (env flag before anchor-checked assignment)" "$(bash_rc "$D" "$SID" 'env -i HUSKY=0 git commit -m x')" 2
assert_rc "env FOO=1 npm test — allow (plain env-wrapped assignment, unaffected)" "$(bash_rc "$D" "$SID" 'env FOO=1 npm test')" 0
# PR #258 review round-5 finding: real BSD/GNU env supports BUNDLING its
# own boolean short flags into one token (`-iv`, `-i0`, ...) and bundling
# a trailing value-taking flag letter with them (`-iu FOO` = -i then -u
# FOO) — the round-4 fix only matched single unbundled flags, so a
# bundled cluster fell through unmatched and defeated exec_base
# resolution again, up to a full self-disarm via `env -iv rm <marker>`.
assert_rc "env -iv git commit -n -m x — deny (bundled boolean env flags)" "$(bash_rc "$D" "$SID" 'env -iv git commit -n -m x')" 2
assert_rc "env -vi git commit -n -m x — deny (bundled boolean env flags, reordered)" "$(bash_rc "$D" "$SID" 'env -vi git commit -n -m x')" 2
assert_rc "env -0iv HUSKY=0 npm test — deny (3-flag bundle before anchor-checked assignment)" "$(bash_rc "$D" "$SID" 'env -0iv HUSKY=0 npm test')" 2
assert_rc "env -iu FOO git commit -n -m x — deny (bundled boolean + value-taking flag)" "$(bash_rc "$D" "$SID" 'env -iu FOO git commit -n -m x')" 2
assert_rc "env -iv rm <guard marker> — deny (bundled-flag self-disarm)" "$(bash_rc "$D" "$SID" "env -iv rm .supervisor/guard/$SID.json")" 2
# PR #258 review round-9 finding (HIGH): env's -S/--split-string value is
# not a plain path/name like -u/-C/-P's — it is a WHOLE embedded command
# line that env itself re-splits and execs (`env -S "HUSKY=0 git commit
# -m x"` really runs that command, verified live on this platform).
# "Skip the value word" (correct for -u/-C/-P) would smuggle an unparsed
# command past every exec_base-keyed check at once, so -S/--split-string
# denies outright instead.
assert_rc 'env -S "HUSKY=0 git commit -m x" — deny (split-string smuggled command)' "$(bash_rc "$D" "$SID" 'env -S "HUSKY=0 git commit -m x"')" 2
assert_rc 'env --split-string="HUSKY=0 git commit -n -m x" — deny (long-form split-string)' "$(bash_rc "$D" "$SID" 'env --split-string="HUSKY=0 git commit -n -m x"')" 2
assert_rc 'env -iS "HUSKY=0 git commit -m x" — deny (bundled prefix + split-string)' "$(bash_rc "$D" "$SID" 'env -iS "HUSKY=0 git commit -m x"')" 2
assert_rc 'env -S "rm <guard marker>" — deny (split-string self-disarm)' "$(bash_rc "$D" "$SID" "env -S \"rm .supervisor/guard/$SID.json\"")" 2
assert_rc "env -C /tmp git commit -n -m x — allow-form regression: -C still a plain value-taking flag, still denies via git -n" "$(bash_rc "$D" "$SID" 'env -C /tmp git commit -n -m x')" 2
# PR #258 review round-4 finding: `ln`/`ln -s` clobbering a protected path
# or a git hook was not in the write-verb/`.git/hooks` verb lists at all.
assert_rc "ln -sf /dev/null jest.config.js — deny (symlink-clobber write-verb gap)" "$(bash_rc "$D" "$SID" 'ln -sf /dev/null jest.config.js')" 2
assert_rc "ln -s /dev/null <git-hooks-path> — deny (symlink into .git/hooks)" "$(bash_rc "$D" "$SID" "ln -s /dev/null .git/hooks/pre-commit")" 2
# PR #258 review round-5 finding: the round-4 `ln` check scanned ALL
# non-flag arguments, not just the LINK NAME actually being created —
# `ln` only READS its TARGET argument, so this false-denied a legitimate
# `ln -s realfile.txt /tmp/dest` whenever realfile.txt shared a protected
# basename.
assert_rc "ln -s jest.config.js /tmp/backup-jest-config — allow (protected basename is the READ target, not the link name)" "$(bash_rc "$D" "$SID" 'ln -s jest.config.js /tmp/backup-jest-config')" 0
assert_rc "ln -s realfile.txt /tmp/dest — allow (ordinary symlink, no protected basename anywhere)" "$(bash_rc "$D" "$SID" 'ln -s realfile.txt /tmp/dest')" 0
# PR #258 review round-4 finding: `>|` (bash's clobber-override redirect
# operator) was mis-tokenized as a pipe by split_simple_commands, hiding
# the write target from the redirect-target check entirely.
assert_rc "echo x >|jest.config.js — deny (clobber-redirect mis-tokenized as pipe)" "$(bash_rc "$D" "$SID" 'echo x >|jest.config.js')" 2
# PR #258 review round-6 finding: the write-verb/redirect-target checks
# only tested is_protected_basename + `.supervisor/guard`, never the
# `.husky/`, `.git/hooks/`, `.claude/settings*.json` directory-suffix set
# the Write|Edit matcher already enforces for the same paths — plain
# commands, no shell-grammar trick, and the settings.json gap in
# particular is a PERSISTENT cross-session disarm route the spec
# explicitly says the guard exists to close.
assert_rc "rm .husky/pre-commit — deny (.husky has zero Bash-matcher coverage)" "$(bash_rc "$D" "$SID" 'rm .husky/pre-commit')" 2
assert_rc "echo x > .husky/pre-commit — deny (.husky write via redirect)" "$(bash_rc "$D" "$SID" 'echo x > .husky/pre-commit')" 2
assert_rc "tee .husky/pre-commit — deny (.husky write via tee)" "$(bash_rc "$D" "$SID" 'tee .husky/pre-commit')" 2
assert_rc "rm -rf .husky — deny (bare directory arg, no trailing slash in the substring)" "$(bash_rc "$D" "$SID" 'rm -rf .husky')" 2
assert_rc "chmod -x .husky/pre-commit — deny (permission-only disable of a live hook)" "$(bash_rc "$D" "$SID" 'chmod -x .husky/pre-commit')" 2
assert_rc "echo x > .git/hooks/pre-commit — deny (.git/hooks protected only against rm/chmod/mv before this fix)" "$(bash_rc "$D" "$SID" 'echo x > .git/hooks/pre-commit')" 2
assert_rc "cp src.txt .git/hooks/pre-commit — deny (.git/hooks overwrite via cp)" "$(bash_rc "$D" "$SID" 'cp src.txt .git/hooks/pre-commit')" 2
assert_rc "echo x > .claude/settings.json — deny (persistent cross-session disarm route)" "$(bash_rc "$D" "$SID" 'echo x > .claude/settings.json')" 2
assert_rc "cp x .claude/settings.local.json — deny (settings.local.json via cp)" "$(bash_rc "$D" "$SID" 'cp x .claude/settings.local.json')" 2
assert_rc "ln -sf /dev/null .husky/pre-commit — deny (ln's link-name check now shares the directory-suffix set)" "$(bash_rc "$D" "$SID" 'ln -sf /dev/null .husky/pre-commit')" 2
assert_rc "rm -rf /tmp/scratch-dir — allow (ordinary directory removal, no protected suffix)" "$(bash_rc "$D" "$SID" 'rm -rf /tmp/scratch-dir')" 0
assert_rc "echo x > .claude/README.md — allow (.claude dir, non-settings file)" "$(bash_rc "$D" "$SID" 'echo x > .claude/README.md')" 0
assert_rc "cat guard-arm.sh — allow"                                "$(bash_rc "$D" "$SID" "cat $ARM")" 0
assert_rc "sed -n 1,40p guard-arm.sh — allow"                       "$(bash_rc "$D" "$SID" "sed -n 1,40p $ARM")" 0
assert_rc "shellcheck guard-arm.sh — allow (tool absence is not the point)" "$(bash_rc "$D" "$SID" "shellcheck $ARM")" 0
assert_rc "printf 'x' > notes.md — allow"                          "$(bash_rc "$D" "$SID" "printf 'x' > notes.md")" 0
assert_rc "sed -i s/a/b/ guard-test-integrity.sh — deny"            "$(bash_rc "$D" "$SID" "sed -i s/a/b/ $GUARD")" 2

# ---------------------------------------------------------------------------
# Write|Edit-matcher basenames + allow cases
# ---------------------------------------------------------------------------
assert_rc "Edit jest.config.ts — deny"                              "$(edit_rc "$D" "$SID" Edit "jest.config.ts")" 2
assert_rc "Edit ../repo-sub/jest.config.ts — deny"                  "$(edit_rc "$D" "$SID" Edit "../repo-sub/jest.config.ts")" 2
assert_rc "Edit .claude/settings.json — deny"                       "$(edit_rc "$D" "$SID" Edit ".claude/settings.json")" 2
assert_rc "Edit ~/.claude/settings.local.json — deny"               "$(edit_rc "$D" "$SID" Edit "/home/x/.claude/settings.local.json")" 2
assert_rc "Edit cache-path guard-test-integrity.sh — deny"          "$(edit_rc "$D" "$SID" Edit "/home/x/.claude/plugins/cache/atelier/loomwright/1/scripts/guard-test-integrity.sh")" 2
assert_rc "Edit hooks.json — deny"                                  "$(edit_rc "$D" "$SID" Edit "loomwright/hooks/hooks.json")" 2
assert_rc "Edit guard-arm.sh — deny"                                "$(edit_rc "$D" "$SID" Edit "loomwright/scripts/guard-arm.sh")" 2
assert_rc "Edit src/foo.test.ts — allow"                            "$(edit_rc "$D" "$SID" Edit "src/foo.test.ts")" 0
assert_rc "Edit package.json — allow"                               "$(edit_rc "$D" "$SID" Edit "package.json")" 0
assert_rc "Edit docs/jest.config.md — allow"                        "$(edit_rc "$D" "$SID" Edit "docs/jest.config.md")" 0
assert_rc "Write new/dir/file.ts — allow"                           "$(edit_rc "$D" "$SID" Write "new/dir/file.ts")" 0
assert_rc "Write new/dir/conftest.py — allow (not a git toplevel)"  "$(edit_rc "$D" "$SID" Write "new/dir/conftest.py")" 0
# PR #258 review round-7 finding (MEDIUM): the case above never exercises
# the toplevel-DENY branch — new_guarded_dir() never runs `git init`, so
# `git -C "$dirpart" rev-parse --show-toplevel` fails for every fixture
# dir and the deny branch was correct-by-inspection but had zero direct
# test evidence. Dedicated git-initialized fixture for the toplevel case.
CONFTEST_D="$(mktemp -d)"
mkdir -p "$CONFTEST_D/.supervisor/guard" "$CONFTEST_D/sub"
printf '{\n  "session_id": "%s",\n  "armed_at": "%s",\n  "by": "test"\n}\n' "$SID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CONFTEST_D/.supervisor/guard/$SID.json"
git -C "$CONFTEST_D" init -q
assert_rc "Edit <toplevel>/conftest.py — deny (git toplevel)" "$(edit_rc "$CONFTEST_D" "$SID" Edit "$CONFTEST_D/conftest.py")" 2
assert_rc "Edit <toplevel>/sub/conftest.py — allow (not toplevel)" "$(edit_rc "$CONFTEST_D" "$SID" Edit "$CONFTEST_D/sub/conftest.py")" 0
# PR #258 review round-7 finding (HIGH): conftest.py's toplevel rule
# existed only in evaluate_write_edit — the Bash matcher's write-verb/
# redirect/ln checks had no equivalent, so a plain `echo x > conftest.py`
# / `tee conftest.py` / `cp x conftest.py` at repo root bypassed the
# guard entirely while the identical Edit call was denied.
assert_rc "echo x > <toplevel>/conftest.py — deny (Bash-matcher parity)" "$(bash_rc "$CONFTEST_D" "$SID" "echo x > $CONFTEST_D/conftest.py")" 2
assert_rc "tee <toplevel>/conftest.py — deny (Bash-matcher parity)" "$(bash_rc "$CONFTEST_D" "$SID" "tee $CONFTEST_D/conftest.py")" 2
assert_rc "cp fixture.py <toplevel>/conftest.py — deny (Bash-matcher parity)" "$(bash_rc "$CONFTEST_D" "$SID" "cp fixture.py $CONFTEST_D/conftest.py")" 2
assert_rc "echo x > <toplevel>/sub/conftest.py — allow (not toplevel)" "$(bash_rc "$CONFTEST_D" "$SID" "echo x > $CONFTEST_D/sub/conftest.py")" 0
assert_rc "Edit .vscode/settings.json — allow"                      "$(edit_rc "$D" "$SID" Edit ".vscode/settings.json")" 0
assert_rc "Edit config/settings.json — allow"                       "$(edit_rc "$D" "$SID" Edit "config/settings.json")" 0
assert_rc "Edit .github/workflows/ci.yml — allow by default"        "$(edit_rc "$D" "$SID" Edit ".github/workflows/ci.yml")" 0
gextra_rc="$(LOOMWRIGHT_GUARD_EXTRA_GLOBS='.github/workflows/*' bash -c "printf '%s' \"\$(jq -n --arg sid '$SID' '{session_id:\$sid, tool_name:\"Edit\", tool_input:{file_path:\".github/workflows/ci.yml\"}}}')\" 2>/dev/null" 2>/dev/null || true)"
gextra_rc="$(printf '%s' "$(jq -n --arg sid "$SID" '{session_id:$sid, tool_name:"Edit", tool_input:{file_path:".github/workflows/ci.yml"}}')" | CLAUDE_PROJECT_DIR="$D" LOOMWRIGHT_GUARD_EXTRA_GLOBS='.github/workflows/*' bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "Edit .github/workflows/ci.yml — deny under LOOMWRIGHT_GUARD_EXTRA_GLOBS" "$gextra_rc" 2
# PR #258 review round-8 finding (HIGH): `for glob in $extra` is
# unquoted, so bash pathname-expands each colon-split token against the
# GUARD PROCESS's own CWD in addition to field-splitting it — no `set -f`
# anywhere in the script. The case above coincidentally targets ci.yml, a
# file this repo's own .github/workflows/ already contains, which is one
# of the literal filenames ".github/workflows/*" expands to when the test
# runs from the repo root — masking the bug. A file that does NOT already
# exist on disk is the real regression case: it fails the resulting
# literal `case` comparison and was silently ALLOWED (the opposite of the
# admin's intent), non-deterministically depending on the process's CWD
# contents at the moment the hook fires.
gextra_new_rc="$(printf '%s' "$(jq -n --arg sid "$SID" '{session_id:$sid, tool_name:"Edit", tool_input:{file_path:".github/workflows/new-workflow-not-on-disk.yml"}}')" | CLAUDE_PROJECT_DIR="$D" LOOMWRIGHT_GUARD_EXTRA_GLOBS='.github/workflows/*' bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "Edit .github/workflows/new-workflow-not-on-disk.yml — deny under EXTRA_GLOBS (CWD-independent, PR #258 round-8)" "$gextra_new_rc" 2
# PR #258 review round-8 finding (MEDIUM): the conftest.py branch above
# unconditionally returned on BOTH the deny and non-toplevel-allow path,
# so it never reached is_protected_basename/EXTRA_GLOBS for that one
# basename — an admin extending protection to non-toplevel conftest.py
# files via LOOMWRIGHT_GUARD_EXTRA_GLOBS was silently ignored.
gextra_conftest_rc="$(printf '%s' "$(jq -n --arg sid "$SID" --arg fp "$CONFTEST_D/sub/conftest.py" '{session_id:$sid, tool_name:"Edit", tool_input:{file_path:$fp}}')" | CLAUDE_PROJECT_DIR="$CONFTEST_D" LOOMWRIGHT_GUARD_EXTRA_GLOBS='conftest.py' bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "Edit <non-toplevel>/conftest.py — deny under EXTRA_GLOBS=conftest.py (PR #258 round-8, was dead code)" "$gextra_conftest_rc" 2

# ---------------------------------------------------------------------------
# Gate cases
# ---------------------------------------------------------------------------
EMPTY_D="$(mktemp -d)"
assert_rc "guard/ absent — allow"                                  "$(bash_rc "$EMPTY_D" "$SID" 'git commit -n -m x')" 0

FOREIGN_D="$(mktemp -d)"; mkdir -p "$FOREIGN_D/.supervisor/guard"
echo '{"session_id":"other","armed_at":"2026-09-23T00:00:00Z","by":"test"}' > "$FOREIGN_D/.supervisor/guard/other.json"
assert_rc "guard/ holds only a foreign-id file — allow"            "$(bash_rc "$FOREIGN_D" "$SID" 'git commit -n -m x')" 0

optout_rc="$(printf '%s' "$(jq -n --arg sid "$SID" --arg cmd 'git commit -n -m x' '{session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}')" | CLAUDE_PROJECT_DIR="$D" LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1 bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "env opt-out — allow"                                    "$optout_rc" 0

nojq_deny_rc="$(printf '%s' "$(jq -n --arg sid "$SID" '{session_id:$sid, tool_name:"Bash", tool_input:{command:"echo hi"}}')" | env -i PATH=/bin CLAUDE_PROJECT_DIR="$D" bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "no jq + own-id file present — guard_unavailable deny"   "$nojq_deny_rc" 2

nojq_allow_rc="$(printf '%s' "$(jq -n '{session_id:"x", tool_name:"Bash", tool_input:{command:"echo hi"}}')" | env -i PATH=/bin CLAUDE_PROJECT_DIR="$EMPTY_D" bash "$GUARD" >/dev/null 2>&1; echo $?)"
assert_rc "no jq + empty guard/ — allow"                           "$nojq_allow_rc" 0

# ---------------------------------------------------------------------------
# guard-arm.sh subcommand cases
# ---------------------------------------------------------------------------
ARM_D="$(mktemp -d)"
unset_rc="$(cd "$ARM_D" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm supervisor >/dev/null 2>&1; echo $?)"
assert_rc "arm with CLAUDE_CODE_SESSION_ID unset — exit 3, no file" "$unset_rc" 3
[ ! -e "$ARM_D/.supervisor/guard" ] || [ -z "$(ls -A "$ARM_D/.supervisor/guard" 2>/dev/null)" ] && ok "arm unset-env writes no file" || no "arm unset-env writes no file"

set_rc="$(CLAUDE_PROJECT_DIR="$ARM_D" CLAUDE_CODE_SESSION_ID=sess-arm-1 bash "$ARM" arm supervisor >/dev/null 2>&1; echo $?)"
assert_rc "arm with session id set — exit 0" "$set_rc" 0
[ -e "$ARM_D/.supervisor/guard/sess-arm-1.json" ] && ok "arm writes <id>.json" || no "arm writes <id>.json"

idem_before="$(cat "$ARM_D/.supervisor/guard/sess-arm-1.json")"
CLAUDE_PROJECT_DIR="$ARM_D" CLAUDE_CODE_SESSION_ID=sess-arm-1 bash "$ARM" arm supervisor >/dev/null 2>&1
idem_after="$(cat "$ARM_D/.supervisor/guard/sess-arm-1.json")"
[ "$idem_before" = "$idem_after" ] && ok "arm same id twice — unchanged (idempotent)" || no "arm same id twice — unchanged (idempotent)"

CLAUDE_PROJECT_DIR="$ARM_D" CLAUDE_CODE_SESSION_ID=sess-arm-2 bash "$ARM" arm x >/dev/null 2>&1
[ -e "$ARM_D/.supervisor/guard/sess-arm-1.json" ] && [ -e "$ARM_D/.supervisor/guard/sess-arm-2.json" ] && ok "second arm under different env id creates a second file and keeps the first" || no "second arm under different env id creates a second file and keeps the first"
after2="$(cat "$ARM_D/.supervisor/guard/sess-arm-1.json")"
[ "$idem_after" = "$after2" ] && ok "first file byte-identical after a second session's arm" || no "first file byte-identical after a second session's arm"

CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm dispatcher --session-id uuid-disp-1 >/dev/null 2>&1
[ -e "$ARM_D/.supervisor/guard/uuid-disp-1.json" ] && ok "arm dispatcher --session-id X writes X.json" || no "arm dispatcher --session-id X writes X.json"

afp_match="$(printf '%s' "$(jq -n '{session_id:"sess-afp-1", tool_input:{subagent_type:"loomwright:loomwright:worker"}}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload >/dev/null 2>&1; echo $?)"
[ -e "$ARM_D/.supervisor/guard/sess-afp-1.json" ] && ok "arm-from-payload arms on namespaced :worker subagent_type" || no "arm-from-payload arms on namespaced :worker subagent_type"

printf '%s' "$(jq -n '{session_id:"sess-afp-2", tool_input:{subagent_type:"general-purpose"}}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload >/dev/null 2>&1
[ ! -e "$ARM_D/.supervisor/guard/sess-afp-2.json" ] && ok "arm-from-payload does not arm on general-purpose" || no "arm-from-payload does not arm on general-purpose"

printf '%s' "$(jq -n '{session_id:"sess-afp-3", tool_input:{subagent_type:"my-worker"}}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" arm-from-payload >/dev/null 2>&1
[ ! -e "$ARM_D/.supervisor/guard/sess-afp-3.json" ] && ok "arm-from-payload does not arm on unnamespaced my-worker" || no "arm-from-payload does not arm on unnamespaced my-worker"

printf '%s' "$(jq -n '{session_id:"sess-arm-1"}')" | CLAUDE_PROJECT_DIR="$ARM_D" bash "$ARM" disarm-session >/dev/null 2>&1
[ ! -e "$ARM_D/.supervisor/guard/sess-arm-1.json" ] && [ -e "$ARM_D/.supervisor/guard/sess-arm-2.json" ] && ok "disarm-session removes only the payload's own id" || no "disarm-session removes only the payload's own id"

# prune: 8-day-old file removed, 6-day-old file kept
PRUNE_D="$(mktemp -d)"; mkdir -p "$PRUNE_D/.supervisor/guard"
echo '{"session_id":"old8","armed_at":"x","by":"test"}' > "$PRUNE_D/.supervisor/guard/old8.json"
echo '{"session_id":"old6","armed_at":"x","by":"test"}' > "$PRUNE_D/.supervisor/guard/old6.json"
old8_epoch=$(( $(date -u +%s) - (8 * 86400) ))
old6_epoch=$(( $(date -u +%s) - (6 * 86400) ))
old8_ts="$(date -u -r "$old8_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$old8_epoch" +%Y%m%d%H%M.%S 2>/dev/null)"
old6_ts="$(date -u -r "$old6_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$old6_epoch" +%Y%m%d%H%M.%S 2>/dev/null)"
touch -t "$old8_ts" "$PRUNE_D/.supervisor/guard/old8.json" 2>/dev/null || true
touch -t "$old6_ts" "$PRUNE_D/.supervisor/guard/old6.json" 2>/dev/null || true
CLAUDE_PROJECT_DIR="$PRUNE_D" CLAUDE_CODE_SESSION_ID=sess-prune-trigger bash "$ARM" arm x >/dev/null 2>&1
[ ! -e "$PRUNE_D/.supervisor/guard/old8.json" ] && [ -e "$PRUNE_D/.supervisor/guard/old6.json" ] && ok "arm prunes an 8-day-old marker and keeps a 6-day-old one" || no "arm prunes an 8-day-old marker and keeps a 6-day-old one"

# ---------------------------------------------------------------------------
# Concurrency case
# ---------------------------------------------------------------------------
CONC_D="$(mktemp -d)"; mkdir -p "$CONC_D/.supervisor/guard"
echo '{"session_id":"A","armed_at":"2026-09-23T00:00:00Z","by":"test"}' > "$CONC_D/.supervisor/guard/A.json"
before_denied="$(bash_rc "$CONC_D" A 'git commit -n -m x')"
CLAUDE_PROJECT_DIR="$CONC_D" CLAUDE_CODE_SESSION_ID=B bash "$ARM" arm-from-payload <<<'{}' >/dev/null 2>&1 || true
CLAUDE_PROJECT_DIR="$CONC_D" CLAUDE_CODE_SESSION_ID=B bash "$ARM" arm supervisor >/dev/null 2>&1
after_denied="$(bash_rc "$CONC_D" A 'git commit -n -m x')"
if [ "$before_denied" = 2 ] && [ "$after_denied" = 2 ]; then
  ok "concurrency: payload A stays denied after B's arm runs"
else
  no "concurrency: payload A stays denied after B's arm runs (before=$before_denied after=$after_denied)"
fi

# ---------------------------------------------------------------------------
# Sentinels
# ---------------------------------------------------------------------------
if [ -f "$HOOKS_JSON" ]; then
  bash_leaf="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command // empty' "$HOOKS_JSON" 2>/dev/null)"
  editleaf="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Write|Edit") | .hooks[]?.command // empty' "$HOOKS_JSON" 2>/dev/null)"
  case "$bash_leaf$editleaf" in
    *guard-test-integrity.sh*) ok "hooks.json guard leaves reference guard-test-integrity.sh" ;;
    *) no "hooks.json guard leaves reference guard-test-integrity.sh" ;;
  esac
  case "$bash_leaf" in
    *'|| true'*) no "PreToolUse[Bash] guard leaf must NOT carry || true" ;;
    *) ok "PreToolUse[Bash] guard leaf has no || true" ;;
  esac
  case "$editleaf" in
    *'|| true'*) no "PreToolUse[Write|Edit] guard leaf must NOT carry || true" ;;
    *) ok "PreToolUse[Write|Edit] guard leaf has no || true" ;;
  esac
else
  echo "  (hooks.json not found yet at $HOOKS_JSON — skipping hooks.json sentinel)"
fi

grep_hits="$(grep -rln ALLOW_GATE_CONFIG_EDITS "$SCRIPT_DIR/../agents" "$SCRIPT_DIR/../skills" 2>/dev/null || true)"
[ -z "$grep_hits" ] && ok "ALLOW_GATE_CONFIG_EDITS never named in agents/skills prose" || no "ALLOW_GATE_CONFIG_EDITS named in: $grep_hits"

deny_line1="$(bash_rc "$D" "$SID" 'git commit -n -m x' >/dev/null; bash_stderr)"
deny_line2="$(bash_rc "$D" "$SID" 'git commit -n -m x' 'general-purpose' >/dev/null; bash_stderr)"
sentinel_clean=1
for term in ALLOW_GATE '.json' settings config.json guard-arm; do
  case "$deny_line1$deny_line2" in
    *"$term"*) sentinel_clean=0 ;;
  esac
done
[ "$sentinel_clean" = 1 ] && ok "deny lines contain none of ALLOW_GATE/.json/settings/config.json/guard-arm" || no "deny lines contain a forbidden substring: [$deny_line1] / [$deny_line2]"

# ---------------------------------------------------------------------------
# Mutation controls (a)-(h) — each demonstrates the guard fails CLOSED-to-open
# (or open-to-closed) when the named mechanism is broken, and passes on the
# real script. Each mutant is a throwaway COPY, gated non-empty + cmp-different
# + `bash -n` clean, never the real file.
# ---------------------------------------------------------------------------
MUT_D="$(mktemp -d)"

make_mutant() {
  local out="$1"; shift
  cp "$GUARD" "$out"
  "$@" "$out"
  [ -s "$out" ] || { no "mutant $out is empty — aborting this control"; return 1; }
  cmp -s "$GUARD" "$out" && { no "mutant $out is byte-identical to the original — aborting this control"; return 1; }
  bash -n "$out" || { no "mutant $out fails bash -n — aborting this control"; return 1; }
  return 0
}

mut_rc() {
  local mutant="$1" d="$2" sid="$3" cmd="$4"
  printf '%s' "$(jq -n --arg sid "$sid" --arg cmd "$cmd" '{session_id:$sid, tool_name:"Bash", tool_input:{command:$cmd}}')" \
    | CLAUDE_PROJECT_DIR="$d" bash "$mutant" >/dev/null 2>&1
  echo $?
}

# mut_edit_rc <mutant> <guard_dir> <session_id> <file_path> [extra_globs_env]
mut_edit_rc() {
  local mutant="$1" d="$2" sid="$3" fp="$4" extra="${5:-}"
  printf '%s' "$(jq -n --arg sid "$sid" --arg fp "$fp" '{session_id:$sid, tool_name:"Edit", tool_input:{file_path:$fp}}')" \
    | CLAUDE_PROJECT_DIR="$d" LOOMWRIGHT_GUARD_EXTRA_GLOBS="$extra" bash "$mutant" >/dev/null 2>&1
  echo $?
}

# (a) delete `exit 2` from deny() -> git commit -n case fails (no longer denies)
MUT_A="$MUT_D/mut-a.sh"
if make_mutant "$MUT_A" perl -pi -e 's/^  exit 2\n$// if $. > 60 && $. < 75' 2>/dev/null; then
  rc="$(mut_rc "$MUT_A" "$D" "$SID" 'git commit -n -m x')"
  [ "$rc" != "2" ] && ok "(a) mutation control: removing exit 2 from deny() breaks the commit -n case" || no "(a) mutation control did not break the case (still rc=2)"
fi

# (b) append `|| true` to a guard hook string in a hooks.json copy -> sentinel fails
if [ -f "$HOOKS_JSON" ]; then
  MUT_B="$MUT_D/hooks-mut-b.json"
  jq '(.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command|test("guard-test-integrity")) | .command) |= . + " || true"' "$HOOKS_JSON" > "$MUT_B" 2>/dev/null || true
  if [ -s "$MUT_B" ] && ! cmp -s "$HOOKS_JSON" "$MUT_B"; then
    leaf="$(jq -r '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command // empty' "$MUT_B" 2>/dev/null)"
    case "$leaf" in
      *'|| true'*) ok "(b) mutation control: appending || true to the guard leaf breaks the sentinel" ;;
      *) no "(b) mutation control did not break the sentinel" ;;
    esac
  else
    echo "  (b) skipped: could not construct mutant hooks.json)"
  fi
fi

# (c) make the guard read a fixed armed.json instead of <sid>.json -> the
#     foreign-id-only case fails (now denies on a marker that isn't its own)
MUT_C="$MUT_D/mut-c.sh"
if make_mutant "$MUT_C" perl -pi -e 's/\$GUARD_DIR\/\$SESSION_ID\.json/\$GUARD_DIR\/armed.json/g'; then
  cp "$FOREIGN_D/.supervisor/guard/other.json" "$FOREIGN_D/.supervisor/guard/armed.json" 2>/dev/null || true
  rc="$(mut_rc "$MUT_C" "$FOREIGN_D" "$SID" 'git commit -n -m x')"
  [ "$rc" = "2" ] && ok "(c) mutation control: fixed armed.json filename denies on a foreign marker" || no "(c) mutation control did not break the foreign-id-only case (rc=$rc)"
fi

# (d) --no-ver[a-z]* -> --no-verify (exact match only) -> --no-veri case fails
MUT_D2="$MUT_D/mut-d.sh"
if make_mutant "$MUT_D2" perl -pi -e 's/--no-ver\[a-z\]\*\|--no-verify\)/--no-verify)/g'; then
  rc="$(mut_rc "$MUT_D2" "$D" "$SID" 'git commit -qm x --no-veri')"
  [ "$rc" != "2" ] && ok "(d) mutation control: exact --no-verify match misses --no-veri" || no "(d) mutation control did not break the --no-veri case (rc=$rc)"
fi

# (i) drop the --session-id scan from the `arm` exemption -> a tool call can
#     arm an ARBITRARY other session again (PR #258 review finding — closes
#     the demonstrated bypass, proving the new check is load-bearing)
MUT_I="$MUT_D/mut-i.sh"
if make_mutant "$MUT_I" perl -0pi -e 's/    local w2\n    for w2 in "\$\{words\[\@\]:\$\(\(ga_idx \+ 2\)\)\}"; do\n      case "\$w2" in\n        --session-id\|--session-id=\*\)\n          deny_variant bash "internal control script invocation"\n          ;;\n      esac\n    done\n//'; then
  rc="$(mut_rc "$MUT_I" "$D" "$SID" "bash $ARM arm x --session-id arbitrary-id")"
  [ "$rc" != "2" ] && ok "(i) mutation control: dropping the --session-id scan re-opens the arbitrary-session-arm bypass" || no "(i) mutation control did not break the case (still rc=2)"
fi

# (j) narrow the pre-commit/lefthook uninstall scan back to the single word
#     immediately after the executable -> the flag-before-uninstall bypass
#     reopens (PR #258 round-2 review finding)
MUT_J="$MUT_D/mut-j.sh"
python3 - "$GUARD" "$MUT_J" <<'PYEOF' 2>/dev/null || true
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
old = '''    pre-commit|lefthook)
      local w7
      for w7 in "${words[@]:$((idx + 1))}"; do
        [ "$w7" = "uninstall" ] && deny_variant bash "git-hook manager uninstall"
      done
      ;;
'''
new = '''    pre-commit|lefthook)
      local w7="${words[$((idx + 1))]:-}"
      [ "$w7" = "uninstall" ] && deny_variant bash "git-hook manager uninstall"
      ;;
'''
assert old in c, "anchor not found for mutation (j)"
c = c.replace(old, new, 1)
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_J" ] && ! cmp -s "$GUARD" "$MUT_J" && bash -n "$MUT_J" 2>/dev/null; then
  rc="$(mut_rc "$MUT_J" "$D" "$SID" 'lefthook --no-colors uninstall')"
  [ "$rc" != "2" ] && ok "(j) mutation control: narrowing the uninstall scan to one word re-opens the flag-before-uninstall bypass" || no "(j) mutation control did not break the case (still rc=2)"
else
  no "(j) mutation control: could not construct mutant"
fi

# (k) narrow the env-var anchor scan back to words[0]/words[1] only -> the
#     stacked-assignment bypass reopens (PR #258 round-2 review finding)
MUT_K="$MUT_D/mut-k.sh"
python3 - "$GUARD" "$MUT_K" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
old_block = re.search(
    r'  local anchor_i=0\n  local w0=.*?\n  done\n',
    c, re.S)
assert old_block, "anchor block not found for mutation (k)"
new = '''  local anchor_tok="${words[0]}"
  if [ "$anchor_tok" = "export" ] || [ "$anchor_tok" = "env" ]; then
    if [ "${#words[@]}" -gt 1 ]; then anchor_tok="${words[1]}"; else anchor_tok=""; fi
  fi
  case "$anchor_tok" in
    HUSKY=*|HUSKY_SKIP_HOOKS=*|SKIP=*|PRE_COMMIT_ALLOW_NO_CONFIG=*|GIT_CONFIG_PARAMETERS=*)
      deny_variant bash "commit/push-hook bypass env"
      ;;
  esac
'''
c = c[:old_block.start()] + new + c[old_block.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_K" ] && ! cmp -s "$GUARD" "$MUT_K" && bash -n "$MUT_K" 2>/dev/null; then
  rc="$(mut_rc "$MUT_K" "$D" "$SID" 'A=1 HUSKY=0 npm test')"
  [ "$rc" != "2" ] && ok "(k) mutation control: narrowing the env-anchor scan to one word re-opens the stacked-assignment bypass" || no "(k) mutation control did not break the case (still rc=2)"
else
  no "(k) mutation control: could not construct mutant"
fi

# (l) revert the git subcommand-detection to a fixed words[idx+1] read ->
#     a global flag before the subcommand re-opens the bypass (self-audit
#     finding after the round-2 review pattern)
MUT_L="$MUT_D/mut-l.sh"
python3 - "$GUARD" "$MUT_L" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
# Replace the whole subcommand-detection walk with the old fixed-index read,
# and put back the old idx+2 slice in the three downstream loops.
old_walk = re.search(
    r'    local subcmd="" subcmd_idx=\$\(\(idx \+ 1\)\)\n.*?\n    done\n',
    c, re.S)
assert old_walk, "subcommand walk anchor not found for mutation (l)"
c = c[:old_walk.start()] + '    local subcmd="${words[$((idx + 1))]:-}"\n' + c[old_walk.end():]
c = c.replace('${words[@]:$((subcmd_idx + 1))}', '${words[@]:$((idx + 2))}')
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_L" ] && ! cmp -s "$GUARD" "$MUT_L" && bash -n "$MUT_L" 2>/dev/null; then
  rc="$(mut_rc "$MUT_L" "$D" "$SID" 'git --no-optional-locks commit -n -m x')"
  [ "$rc" != "2" ] && ok "(l) mutation control: reverting to a fixed-index subcommand read re-opens the global-flag-before-subcmd bypass" || no "(l) mutation control did not break the case (still rc=2)"
else
  no "(l) mutation control: could not construct mutant"
fi

# (m) revert the exec-word walk to only recognize export/env, and drop the
#     backslash-strip -> command/exec-prefix and backslash-escape bypasses
#     re-open (round-3 review finding, the widest instance of the "only
#     inspects the adjacent word" bug class — it defeats every
#     exec_base-keyed check at once, not just one pattern)
MUT_M="$MUT_D/mut-m.sh"
python3 - "$GUARD" "$MUT_M" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
old_block = re.search(
    r'  local idx=0\n  local after_env=0\n  while \[ "\$idx" -lt.*?\n  done\n',
    c, re.S)
assert old_block, "exec-word walk block not found for mutation (m)"
new = '''  local idx=0
  while [ "$idx" -lt "${#words[@]}" ]; do
    local t="${words[$idx]}"
    case "$t" in
      export|env) idx=$((idx + 1)); continue ;;
      *=*)
        case "$t" in
          [A-Za-z_]*=*)
            local var_part="${t%%=*}"
            case "$var_part" in
              *[!A-Za-z0-9_]*) break ;;
              "") break ;;
              *) idx=$((idx + 1)); continue ;;
            esac
            ;;
          *) break ;;
        esac
        ;;
      *) break ;;
    esac
  done
'''
c = c[:old_block.start()] + new + c[old_block.end():]
assert 'local exec_word="${words[$idx]:-}"\n  case "$exec_word" in\n' in c, \
    "backslash-strip block not found for mutation (m)"
backslash_strip = re.search(
    r'  local exec_word="\$\{words\[\$idx\]:-\}"\n'
    r'  case "\$exec_word" in\n'
    r'.*?\n'
    r'  esac\n'
    r'  local exec_base\n',
    c, re.S)
assert backslash_strip, "backslash-strip block not found for mutation (m)"
c = c[:backslash_strip.start()] + '  local exec_word="${words[$idx]:-}"\n  local exec_base\n' + c[backslash_strip.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_M" ] && ! cmp -s "$GUARD" "$MUT_M" && bash -n "$MUT_M" 2>/dev/null; then
  rc="$(mut_rc "$MUT_M" "$D" "$SID" 'command git commit -n -m x')"
  [ "$rc" != "2" ] && ok "(m) mutation control: narrowing the exec-word walk back to export/env re-opens the command/exec/backslash-prefix bypass" || no "(m) mutation control did not break the case (still rc=2)"
else
  no "(m) mutation control: could not construct mutant"
fi

# (n) drop the backslash-strip on the exec-word loop's keyword token itself
#     -> a backslash-escaped keyword (`\exec`, `\env`, ...) re-opens the
#     full-guard bypass, including a full session self-disarm via
#     `\exec rm <guard marker>` (PR #258 round-4 review finding)
MUT_N="$MUT_D/mut-n.sh"
python3 - "$GUARD" "$MUT_N" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
pat = re.compile(
    r'(    local t="\$\{words\[\$idx\]\}"\n)'
    r'    case "\$t" in\n'
    r'.*?\n'
    r'    esac\n'
    r'(    if \[ "\$after_env" -eq 1 \]; then\n)')
m = pat.search(c)
assert m, "exec-word-loop backslash-strip block not found for mutation (n)"
c = c[:m.start()] + m.group(1) + m.group(2) + c[m.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_N" ] && ! cmp -s "$GUARD" "$MUT_N" && bash -n "$MUT_N" 2>/dev/null; then
  rc="$(mut_rc "$MUT_N" "$D" "$SID" "\\exec rm .supervisor/guard/$SID.json")"
  [ "$rc" != "2" ] && ok "(n) mutation control: dropping the exec-word-loop backslash-strip re-opens the backslash-escaped-keyword self-disarm bypass" || no "(n) mutation control did not break the case (still rc=2)"
else
  no "(n) mutation control: could not construct mutant"
fi

# (o) drop the env-flag walk (after_env block) -> `env -i git ...` /
#     `env -u FOO git ...` re-open, resolving exec_base to the flag/value
#     token instead of the wrapped command (PR #258 round-4 review finding)
MUT_O="$MUT_D/mut-o.sh"
python3 - "$GUARD" "$MUT_O" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
pat = re.compile(
    r'    if \[ "\$after_env" -eq 1 \]; then\n'
    r'.*?\n'
    r'    fi\n',
    re.S)
m = pat.search(c)
assert m, "after_env block not found for mutation (o)"
c = c[:m.start()] + c[m.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_O" ] && ! cmp -s "$GUARD" "$MUT_O" && bash -n "$MUT_O" 2>/dev/null; then
  rc="$(mut_rc "$MUT_O" "$D" "$SID" 'env -i git commit -n -m x')"
  [ "$rc" != "2" ] && ok "(o) mutation control: dropping the env-flag walk re-opens the env-flag-before-wrapped-command bypass" || no "(o) mutation control did not break the case (still rc=2)"
else
  no "(o) mutation control: could not construct mutant"
fi

# (p) drop the dedicated `ln` last-arg-only block entirely -> a
#     symlink-clobber of a protected basename re-opens (PR #258 round-4
#     finding first added ln coverage; round-5 review then found its
#     original all-argument-scan form false-denied `ln -s realfile.txt
#     /tmp/dest` and moved it to this dedicated last-arg-only block)
MUT_P="$MUT_D/mut-p.sh"
python3 - "$GUARD" "$MUT_P" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
pat = re.compile(
    r'  # ---- ln: symlink-clobber.*?\n'
    r'  if \[ "\$exec_base" = "ln" \]; then\n'
    r'.*?\n'
    r'  fi\n',
    re.S)
m = pat.search(c)
assert m, "ln last-arg block not found for mutation (p)"
c = c[:m.start()] + c[m.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_P" ] && ! cmp -s "$GUARD" "$MUT_P" && bash -n "$MUT_P" 2>/dev/null; then
  rc="$(mut_rc "$MUT_P" "$D" "$SID" 'ln -sf /dev/null jest.config.js')"
  [ "$rc" != "2" ] && ok "(p) mutation control: dropping the ln last-arg-only block re-opens the symlink-clobber bypass" || no "(p) mutation control did not break the case (still rc=2)"
else
  no "(p) mutation control: could not construct mutant"
fi

# (q) revert the `>|` clobber-redirect handling in both the simple-command
#     splitter and the tokenizer -> `echo x >|jest.config.js` re-opens,
#     mis-tokenized as an unrelated pipe segment that hides the write
#     target from the redirect-target check (PR #258 round-4 review finding)
MUT_Q="$MUT_D/mut-q.sh"
python3 - "$GUARD" "$MUT_Q" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
split_old = re.search(
    r"      '\|'\)\n"
    r'        if \[ "\$\{buf: -1\}" = .>. \]; then\n'
    r'.*?\n'
    r"        elif \[ \"\$\{s:\$\(\(i \+ 1\)\):1\}\" = '\|' \]; then\n",
    c, re.S)
assert split_old, "split_simple_commands >| branch not found for mutation (q)"
split_new = ("      '|')\n"
             "        if [ \"${s:$((i + 1)):1}\" = '|' ]; then\n")
c = c[:split_old.start()] + split_new + c[split_old.end():]
tok_old = re.search(
    r"        if \[ \"\$\{s:\$\(\(i \+ 1\)\):1\}\" = '>' \]; then\n"
    r'          out\+=\(">>"\); i=\$\(\(i \+ 1\)\)\n'
    r"        elif \[ \"\$\{s:\$\(\(i \+ 1\)\):1\}\" = '\|' \]; then\n"
    r'.*?\n'
    r'          out\+=\(">\|"\); i=\$\(\(i \+ 1\)\)\n'
    r'        else\n',
    c, re.S)
assert tok_old, "tokenize_words >| branch not found for mutation (q)"
tok_new = ('        if [ "${s:$((i + 1)):1}" = \'>\' ]; then\n'
           '          out+=(">>"); i=$((i + 1))\n'
           '        else\n')
c = c[:tok_old.start()] + tok_new + c[tok_old.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_Q" ] && ! cmp -s "$GUARD" "$MUT_Q" && bash -n "$MUT_Q" 2>/dev/null; then
  rc="$(mut_rc "$MUT_Q" "$D" "$SID" 'echo x >|jest.config.js')"
  [ "$rc" != "2" ] && ok "(q) mutation control: reverting the >| clobber-redirect handling re-opens the mis-tokenized-as-pipe bypass" || no "(q) mutation control did not break the case (still rc=2)"
else
  no "(q) mutation control: could not construct mutant"
fi

# (r) narrow is_protected_path_arg back to is_protected_basename +
#     .supervisor/guard only (drop the .husky/.git/hooks/settings.json
#     directory-suffix set) -> the write-verb/redirect-target checks lose
#     Bash-matcher parity with the Write|Edit matcher again, re-opening
#     `echo x > .husky/pre-commit` (PR #258 round-6 review finding)
MUT_R="$MUT_D/mut-r.sh"
python3 - "$GUARD" "$MUT_R" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
pat = re.compile(
    r'  case "\$w" in\n'
    r'    \*\.supervisor/guard\*\) return 0 ;;\n'
    r'.*?\n'
    r'  esac\n',
    re.S)
m = pat.search(c)
assert m, "is_protected_path_arg directory-suffix case block not found for mutation (r)"
new = ('  case "$w" in\n'
       '    *.supervisor/guard*) return 0 ;;\n'
       '  esac\n')
c = c[:m.start()] + new + c[m.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_R" ] && ! cmp -s "$GUARD" "$MUT_R" && bash -n "$MUT_R" 2>/dev/null; then
  rc="$(mut_rc "$MUT_R" "$D" "$SID" 'echo x > .husky/pre-commit')"
  [ "$rc" != "2" ] && ok "(r) mutation control: dropping the directory-suffix set from is_protected_path_arg re-opens the .husky/.git-hooks/settings.json Bash-matcher gap" || no "(r) mutation control did not break the case (still rc=2)"
else
  no "(r) mutation control: could not construct mutant"
fi

# (s) drop the is_toplevel_conftest fallback from is_protected_path_arg ->
#     conftest.py's toplevel rule re-opens for the Bash matcher (PR #258
#     round-7 review finding: the Write|Edit matcher's toplevel rule had
#     no Bash-matcher equivalent at all)
MUT_S="$MUT_D/mut-s.sh"
python3 - "$GUARD" "$MUT_S" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
old = ('  if is_protected_basename "$(basename_of "$w")"; then\n'
       '    return 0\n'
       '  fi\n'
       '  is_toplevel_conftest "$w"\n'
       '}\n')
assert old in c, "is_protected_path_arg tail not found for mutation (s)"
new = '  is_protected_basename "$(basename_of "$w")"\n}\n'
c = c.replace(old, new, 1)
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_S" ] && ! cmp -s "$GUARD" "$MUT_S" && bash -n "$MUT_S" 2>/dev/null; then
  rc="$(mut_rc "$MUT_S" "$CONFTEST_D" "$SID" "echo x > $CONFTEST_D/conftest.py")"
  [ "$rc" != "2" ] && ok "(s) mutation control: dropping the is_toplevel_conftest fallback re-opens the Bash-matcher conftest.py gap" || no "(s) mutation control did not break the case (still rc=2)"
else
  no "(s) mutation control: could not construct mutant"
fi

# (t) drop `set -f`/`set +f` from the EXTRA_GLOBS loop -> a glob pattern
#     matching pre-existing files in the guard PROCESS's own CWD silently
#     expands to that literal filename list, and a brand-new file matching
#     the same intended pattern is then silently ALLOWED (PR #258 round-8
#     review finding — CWD-dependent, non-deterministic under the exact
#     documented worked example)
MUT_T="$MUT_D/mut-t.sh"
python3 - "$GUARD" "$MUT_T" <<'PYEOF' 2>/dev/null || true
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
assert "    set -f\n    for glob in $extra; do\n" in c, "set -f line not found for mutation (t)"
c = c.replace("    set -f\n    for glob in $extra; do\n", "    for glob in $extra; do\n", 1)
assert "    done\n    set +f\n    IFS=\"$saved_ifs\"\n" in c, "set +f line not found for mutation (t)"
c = c.replace("    done\n    set +f\n    IFS=\"$saved_ifs\"\n", "    done\n    IFS=\"$saved_ifs\"\n", 1)
with open(dst, 'w') as f:
    f.write(c)
PYEOF
MUT_T_CWD="$(mktemp -d)"
mkdir -p "$MUT_T_CWD/.github/workflows"
printf 'x\n' > "$MUT_T_CWD/.github/workflows/existing.yml"
if [ -s "$MUT_T" ] && ! cmp -s "$GUARD" "$MUT_T" && bash -n "$MUT_T" 2>/dev/null; then
  rc="$(cd "$MUT_T_CWD" && mut_edit_rc "$MUT_T" "$D" "$SID" ".github/workflows/new-workflow.yml" '.github/workflows/*')"
  [ "$rc" != "2" ] && ok "(t) mutation control: dropping set -f re-opens the CWD-dependent EXTRA_GLOBS expansion bypass" || no "(t) mutation control did not break the case (still rc=2)"
else
  no "(t) mutation control: could not construct mutant"
fi
rm -rf "$MUT_T_CWD"

# (u) revert the conftest.py branch to its unconditional `return 0` ->
#     LOOMWRIGHT_GUARD_EXTRA_GLOBS becomes dead code for that one
#     basename again (PR #258 round-8 review finding)
MUT_U="$MUT_D/mut-u.sh"
python3 - "$GUARD" "$MUT_U" <<'PYEOF' 2>/dev/null || true
import sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
pat = re.compile(
    r'(    # A failed toplevel lookup or a non-toplevel conftest\.py means\n'
    r'.*?)\n'
    r'  fi\n',
    re.S)
m = pat.search(c)
assert m, "conftest.py fallthrough comment block not found for mutation (u)"
c = c[:m.start()] + m.group(1) + '\n    return 0\n  fi\n' + c[m.end():]
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_U" ] && ! cmp -s "$GUARD" "$MUT_U" && bash -n "$MUT_U" 2>/dev/null; then
  rc="$(mut_edit_rc "$MUT_U" "$CONFTEST_D" "$SID" "$CONFTEST_D/sub/conftest.py" 'conftest.py')"
  [ "$rc" != "2" ] && ok "(u) mutation control: restoring the unconditional conftest.py return re-opens the EXTRA_GLOBS dead-code bug" || no "(u) mutation control did not break the case (still rc=2)"
else
  no "(u) mutation control: could not construct mutant"
fi

# (v) drop the EFC_IS_SPLIT_STRING=1 assignment in env_flag_cluster_consume
#     -> -S/--split-string is treated like -u/-C/-P (skip the value word
#     instead of denying), re-opening the embedded-command smuggling
#     bypass (PR #258 round-9 review finding)
MUT_V="$MUT_D/mut-v.sh"
python3 - "$GUARD" "$MUT_V" <<'PYEOF' 2>/dev/null || true
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    c = f.read()
old = ('        [ -n "$rest" ] && return 1  # attached-value form, not covered\n'
       '        EFC_TAKES_VALUE=1\n'
       '        EFC_IS_SPLIT_STRING=1\n'
       '        return 0\n')
assert old in c, "EFC_IS_SPLIT_STRING assignment not found for mutation (v)"
new = ('        [ -n "$rest" ] && return 1  # attached-value form, not covered\n'
       '        EFC_TAKES_VALUE=1\n'
       '        return 0\n')
c = c.replace(old, new, 1)
with open(dst, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_V" ] && ! cmp -s "$GUARD" "$MUT_V" && bash -n "$MUT_V" 2>/dev/null; then
  rc="$(mut_rc "$MUT_V" "$D" "$SID" 'env -S "HUSKY=0 git commit -m x"')"
  [ "$rc" != "2" ] && ok "(v) mutation control: dropping EFC_IS_SPLIT_STRING re-opens the env -S embedded-command smuggling bypass" || no "(v) mutation control did not break the case (still rc=2)"
else
  no "(v) mutation control: could not construct mutant"
fi

# (e) delete the empty-id check in arm -> the unset-env case fails (writes a
#     file instead of exit 3)
MUT_E="$MUT_D/guard-arm-mut-e.sh"
cp "$ARM" "$MUT_E"
python3 - "$MUT_E" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
old = '  if ! valid_session_id "$sid"; then\n    printf \'guard_arm_failed: no session id\\n\' >&2\n    exit 3\n  fi\n'
new = '  if false; then\n    printf \'guard_arm_failed: no session id\\n\' >&2\n    exit 3\n  fi\n'
assert old in c, "anchor not found for mutation (e)"
c = c.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_E" ] && ! cmp -s "$ARM" "$MUT_E" && bash -n "$MUT_E" 2>/dev/null; then
  ARM_MUT_D="$(mktemp -d)"
  rc="$(cd "$ARM_MUT_D" && env -u CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR="$ARM_MUT_D" bash "$MUT_E" arm supervisor >/dev/null 2>&1; echo $?)"
  [ "$rc" != "3" ] && ok "(e) mutation control: removing the empty-id check no longer exits 3" || no "(e) mutation control did not break the unset-env case (rc=$rc)"
  rm -rf "$ARM_MUT_D"
else
  no "(e) mutation control: could not construct mutant"
fi

# (f) drop the same-simple-command rule (treat the whole line as one blob) ->
#     git diff jest.config.ts > /tmp/d.patch case fails
MUT_F2="$MUT_D/mut-f2.sh"
cp "$GUARD" "$MUT_F2"
python3 - "$MUT_F2" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
anchor = 'evaluate_bash_command() {\n  local full_cmd="$1"'
inject = 'evaluate_bash_command() {\n  local full_cmd="$1"\n  case "$full_cmd" in *jest.config*|*vitest.config*) deny_variant bash "protected configuration write" ;; esac'
c = c.replace(anchor, inject, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_F2" ] && ! cmp -s "$GUARD" "$MUT_F2" && bash -n "$MUT_F2" 2>/dev/null; then
  rc="$(mut_rc "$MUT_F2" "$D" "$SID" 'git diff jest.config.ts > /tmp/d.patch')"
  [ "$rc" = "2" ] && ok "(f) mutation control: dropping the same-simple-command rule breaks the git-diff-redirect case" || no "(f) mutation control did not break the case (rc=$rc)"
else
  no "(f) mutation control: could not construct mutant"
fi

# (g) let arm write a file named from a caller-supplied id (the `by`
#     positional) OUTSIDE the `dispatcher --session-id` shape -> a bare,
#     Bash-tool-reachable `arm <by>` call now writes a file named after an
#     ARBITRARY caller-chosen value instead of always $CLAUDE_CODE_SESSION_ID
#     (the exact invariant the AC pins: "arm never writes a file whose name
#     is not its own CLAUDE_CODE_SESSION_ID, or — dispatcher shape only —
#     the explicit --session-id").
MUT_G="$MUT_D/guard-arm-mut-g.sh"
cp "$ARM" "$MUT_G"
python3 - "$MUT_G" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
old = '  if [ "$saw_flag" -eq 0 ]; then\n    sid="${CLAUDE_CODE_SESSION_ID:-}"\n  fi\n'
new = '  if [ "$saw_flag" -eq 0 ]; then\n    sid="$by"\n  fi\n'
assert old in c, "anchor not found for mutation (g)"
c = c.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_G" ] && ! cmp -s "$ARM" "$MUT_G" && bash -n "$MUT_G" 2>/dev/null; then
  MUT_G_D="$(mktemp -d)"
  CLAUDE_PROJECT_DIR="$MUT_G_D" CLAUDE_CODE_SESSION_ID=B bash "$MUT_G" arm FOREIGN-CALLER-ID >/dev/null 2>&1
  if [ -e "$MUT_G_D/.supervisor/guard/FOREIGN-CALLER-ID.json" ] && [ ! -e "$MUT_G_D/.supervisor/guard/B.json" ]; then
    ok "(g) mutation control: a bare tool-reachable 'arm <by>' now names the marker from the caller-supplied value, not the session id"
  else
    no "(g) mutation control did not break the own-id-only invariant"
  fi
  rm -rf "$MUT_G_D"
else
  no "(g) mutation control: could not construct mutant"
fi

# (h) drop the namespace-colon requirement from arm-from-payload -> the
#     my-worker case fails (now arms on an unnamespaced suffix match)
MUT_H="$MUT_D/guard-arm-mut-h.sh"
cp "$ARM" "$MUT_H"
python3 - "$MUT_H" <<'PYEOF' 2>/dev/null || true
import sys
p = sys.argv[1]
with open(p) as f:
    c = f.read()
old = '    *:worker|*:execute-manager|*:supervisor-runner|*:review-pr-runner) ;;\n'
new = '    *worker|*execute-manager|*supervisor-runner|*review-pr-runner) ;;\n'
assert old in c, "anchor not found for mutation (h)"
c = c.replace(old, new, 1)
with open(p, 'w') as f:
    f.write(c)
PYEOF
if [ -s "$MUT_H" ] && ! cmp -s "$ARM" "$MUT_H" && bash -n "$MUT_H" 2>/dev/null; then
  MUT_H_D="$(mktemp -d)"
  printf '%s' "$(jq -n '{session_id:"sess-h", tool_input:{subagent_type:"my-worker"}}')" | CLAUDE_PROJECT_DIR="$MUT_H_D" bash "$MUT_H" arm-from-payload >/dev/null 2>&1
  if [ -e "$MUT_H_D/.supervisor/guard/sess-h.json" ]; then
    ok "(h) mutation control: dropping the namespace-colon requirement arms on unnamespaced my-worker"
  else
    no "(h) mutation control did not break the my-worker case"
  fi
  rm -rf "$MUT_H_D"
else
  no "(h) mutation control: could not construct mutant"
fi

rm -f /tmp/.guard-test-stderr.$$
rm -rf "$D" "$EMPTY_D" "$FOREIGN_D" "$ARM_D" "$PRUNE_D" "$CONC_D" "$MUT_D" "$CONFTEST_D"

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
