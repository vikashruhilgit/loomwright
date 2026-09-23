#!/usr/bin/env bash
# guard-test-integrity.sh — PreToolUse[Bash] + PreToolUse[Write|Edit] fail-CLOSED deny
# gate. The plugin's FIRST blocking `type: command` hook (see CLAUDE.md's
# `|| true` convention — the two hooks.json leaves that invoke this script
# carry NO `|| true`, unlike every other command hook in the plugin).
#
# Companion: guard-arm.sh (writes/removes the per-session marker files this
# script reads). Source spec:
# `.supervisor/requirements/six-phase-loop-gaps/02-test-integrity-guard.md`
# (4 red-team revisions; read that file before touching a pattern below —
# every pattern here is a precise transcription of its Scope item 2, not a
# paraphrase).
#
# bash 3.2 COMPATIBLE ON PURPOSE (macOS ships bash 3.2 as /bin/bash) — no
# `local -n` namerefs, no `mapfile`/`readarray`, no associative arrays.
#
# EVALUATION ORDER (cheap-first, no `jq` on the inert path):
#   (i)   .supervisor/guard/ absent or empty            -> allow, no jq
#   (ii)  LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1 in env    -> allow
#   (iii) jq missing / payload unparseable / tool_input  -> deny guard_unavailable
#         absent / session_id absent (reachable only with >=1 marker present)
#   (iv)  no marker file named by THIS payload's session -> allow (foreign or
#         id                                                dead marker is inert)
#   (v)   evaluate patterns
#
# DENY MECHANICS: exit 2 AND emit `hookSpecificOutput.permissionDecision:
# "deny"` JSON (Claude Code's exit 2 blocks unconditionally regardless of the
# JSON; the JSON is the documented structured form — do both, per the source
# requirement's own instruction, independently re-verified against the
# current hooks reference during planning). ONE stderr line, one of exactly
# two variants keyed on `agent_type` presence in the payload (P2, probed
# 2026-09-23 — a Task-spawned subagent's own PreToolUse payload carries
# agent_type/agent_id, the main thread's does not — see
# progress-event-fixtures/guard-probe-2026-09-23/README.md). NEITHER variant
# ever names the opt-out env var, the marker path, `settings`, `config.json`,
# or `guard-arm` — labels below are deliberately generic.
set -u

GUARD_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.supervisor/guard"

# ---------------------------------------------------------------------------
# deny/allow plumbing
# ---------------------------------------------------------------------------

json_escape() {
  # Minimal JSON string escaping without jq or sed (used only on the
  # guard_unavailable "jq missing" path, where jq is by definition
  # unavailable — kept dependency-free with pure bash parameter expansion
  # rather than assuming `sed` is on PATH either). Our own deny messages
  # never contain control characters, so this only needs to escape
  # backslashes and double quotes.
  local out="$1"
  out="${out//\\/\\\\}"
  out="${out//\"/\\\"}"
  printf '%s' "$out"
}

emit_deny_json() {
  local msg="$1" escaped
  if command -v jq >/dev/null 2>&1; then
    escaped="$(printf '%s' "$msg" | jq -Rs . 2>/dev/null)"
    [ -n "$escaped" ] || escaped="\"$(json_escape "$msg")\""
  else
    escaped="\"$(json_escape "$msg")\""
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$escaped"
}

deny() {
  local msg="$1"
  printf '%s\n' "$msg" >&2
  emit_deny_json "$msg"
  exit 2
}

allow() {
  exit 0
}

# ---------------------------------------------------------------------------
# (i) cheap: guard dir absent or empty -> allow, no jq
# ---------------------------------------------------------------------------
GUARD_FILE_COUNT=0
if [ -d "$GUARD_DIR" ]; then
  for f in "$GUARD_DIR"/*.json; do
    [ -e "$f" ] || continue
    GUARD_FILE_COUNT=$((GUARD_FILE_COUNT + 1))
  done
fi
if [ "$GUARD_FILE_COUNT" -eq 0 ]; then
  allow
fi

# ---------------------------------------------------------------------------
# (ii) opt-out — process env only
# ---------------------------------------------------------------------------
if [ "${LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS:-}" = "1" ]; then
  allow
fi

PAYLOAD="$(cat 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# (iii) jq missing / payload unparseable / tool_input absent / session_id
#       absent -> deny guard_unavailable: <reason>
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  deny "test_integrity_guard: denied — guard_unavailable: jq missing"
fi
if ! printf '%s' "$PAYLOAD" | jq -e . >/dev/null 2>&1; then
  deny "test_integrity_guard: denied — guard_unavailable: payload unparseable"
fi
HAS_TOOL_INPUT="$(printf '%s' "$PAYLOAD" | jq -r 'has("tool_input")' 2>/dev/null || echo false)"
if [ "$HAS_TOOL_INPUT" != "true" ]; then
  deny "test_integrity_guard: denied — guard_unavailable: tool_input absent"
fi
SESSION_ID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)"
if [ -z "$SESSION_ID" ]; then
  deny "test_integrity_guard: denied — guard_unavailable: session_id absent"
fi

# ---------------------------------------------------------------------------
# (iv) no marker for THIS session -> allow (foreign/dead marker is inert)
# ---------------------------------------------------------------------------
case "$SESSION_ID" in
  */*|.|..) allow ;;
esac
MARKER="$GUARD_DIR/$SESSION_ID.json"
if [ ! -e "$MARKER" ]; then
  allow
fi

# ---------------------------------------------------------------------------
# (v) evaluate patterns
# ---------------------------------------------------------------------------
TOOL_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null)"
AGENT_TYPE="$(printf '%s' "$PAYLOAD" | jq -r '.agent_type // empty' 2>/dev/null)"

deny_variant() {
  # $1 = bash|edit  $2 = pattern label
  local kind="$1" label="$2"
  if [ -n "$AGENT_TYPE" ]; then
    deny "test_integrity_guard: denied ${kind} — ${label} — this session is a Loomwright run; record the need in outputs_gap / escalate NEEDS_HUMAN instead"
  else
    deny "test_integrity_guard: denied ${kind} — ${label} — a Loomwright run is armed in this session; finish or end the session before editing gate configuration"
  fi
}

# ===== protected-basename table (shared by both matchers) =================
is_protected_basename() {
  # Config-shaped basenames use a CLOSED extension set (js/cjs/mjs/ts/cts/mts/json)
  # rather than a bare `name.*` glob — a bare wildcard would also swallow
  # `docs/jest.config.md`, an ordinary doc file (explicit ALLOW case in the
  # source requirement's Scope item 10 test matrix).
  case "$1" in
    jest.config.js|jest.config.cjs|jest.config.mjs|jest.config.ts|jest.config.cts|jest.config.mts|jest.config.json| \
    vitest.config.js|vitest.config.cjs|vitest.config.mjs|vitest.config.ts|vitest.config.cts|vitest.config.mts| \
    vitest.workspace.js|vitest.workspace.cjs|vitest.workspace.mjs|vitest.workspace.ts|vitest.workspace.cts|vitest.workspace.mts| \
    playwright.config.js|playwright.config.cjs|playwright.config.mjs|playwright.config.ts|playwright.config.cts|playwright.config.mts| \
    cypress.config.js|cypress.config.cjs|cypress.config.mjs|cypress.config.ts|cypress.config.cts|cypress.config.mts| \
    eslint.config.js|eslint.config.cjs|eslint.config.mjs|eslint.config.ts|eslint.config.cts|eslint.config.mts| \
    karma.conf.js|karma.conf.cjs|karma.conf.mjs|karma.conf.ts| \
    .mocharc|.mocharc.js|.mocharc.cjs|.mocharc.json|.mocharc.yml|.mocharc.yaml| \
    pytest.ini|tox.ini| \
    .eslintrc|.eslintrc.js|.eslintrc.cjs|.eslintrc.json|.eslintrc.yml|.eslintrc.yaml| \
    .eslintignore|.prettierrc|.prettierrc.js|.prettierrc.cjs|.prettierrc.json|.prettierrc.yml|.prettierrc.yaml| \
    .prettierignore|biome.json|biome.jsonc| \
    ruff.toml|.ruff.toml|.flake8|mypy.ini|.pylintrc| \
    .pre-commit-config.yaml|lefthook.yml| \
    guard-test-integrity.sh|guard-arm.sh|hooks.json)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

basename_of() {
  # portable ${f##*/} basename, no external process
  printf '%s\n' "${1##*/}"
}

# ---------------------------------------------------------------------------
# Shared protected-path test for a single Bash-matcher WORD argument (a raw
# command-line token, not a Write|Edit `file_path`). Mirrors
# evaluate_write_edit's directory-suffix set (`.husky/`, `.git/hooks/`,
# `.claude/settings.json`/`settings.local.json`) plus the existing
# `.supervisor/guard` + is_protected_basename checks (PR #258 round-6
# review finding: the write-verb and redirect-target checks below only
# tested is_protected_basename + `.supervisor/guard`, so `echo x >
# .husky/pre-commit`, `tee .git/hooks/pre-commit`, and `cp x
# .claude/settings.json` were all allowed outright — no shell-grammar
# trick needed. The settings.json gap in particular is a PERSISTENT
# cross-session disarm route: the source requirement's own stated reason
# for protecting that path is closing "the next launch route" — an armed
# agent writing the opt-out into settings.json's `env` block for a LATER
# `claude -p` process to honor, which the Write|Edit matcher already
# closes but the Bash matcher did not). ------------------------------------
is_protected_path_arg() {
  local w="$1"
  case "$w" in
    *.supervisor/guard*) return 0 ;;
    # No required trailing "/" after .husky (unlike evaluate_write_edit's
    # `*/.husky/*`, which only ever sees a FILE path): the Bash matcher
    # also sees bare directory arguments like `rm -rf .husky`, which
    # contain no "/" after the dir name at all and would otherwise slip
    # past a `*.husky/*` substring test (PR #258 round-6 review finding,
    # live-demonstrated). Mirrors the pre-existing `.git/hooks*` style.
    *.husky*) return 0 ;;
    *.git/hooks*) return 0 ;;
    *.claude/settings.json|*.claude/settings.local.json) return 0 ;;
  esac
  if is_protected_basename "$(basename_of "$w")"; then
    return 0
  fi
  is_toplevel_conftest "$w"
}

# conftest.py is protected only when it sits at the git toplevel (an
# explicit spec-listed test-tampering vector — a non-toplevel conftest.py
# is an ordinary test fixture, allowed by design). evaluate_write_edit
# had this check; the Bash matcher's write-verb/redirect/ln checks did
# not, so `echo x > conftest.py` / `tee conftest.py` / `cp x conftest.py`
# at repo root all bypassed the guard while the identical Edit call was
# denied (PR #258 round-7 review finding — the same bug class round 6
# just fixed, on the one protected path round 6's directory-suffix
# extension didn't enumerate). A failed toplevel lookup (new/non-git
# directory) means "not toplevel -> allow", same as evaluate_write_edit.
is_toplevel_conftest() {
  local w="$1"
  [ "$(basename_of "$w")" = "conftest.py" ] || return 1
  local dirpart top dirpart_abs
  dirpart="$(dirname "$w")"
  top="$(git -C "$dirpart" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || return 1
  dirpart_abs="$(cd "$dirpart" 2>/dev/null && pwd -P || true)"
  [ -n "$dirpart_abs" ] && [ "$dirpart_abs" = "$top" ]
}

# ---------------------------------------------------------------------------
# env's own short-flag CLUSTER forms: a run of boolean flags (0/i/v in any
# combination/order — BSD env's own usage string groups them as `[-0iv]`,
# and GNU env supports the same bundling) optionally followed by ONE
# value-taking flag letter (u/C/P/S) whose value is the NEXT word — real
# getopt-style bundling both BSD and GNU env support (verified live:
# `env -iv FOO=bar /usr/bin/env` and `env -iu FOO true` both real,
# succeeding invocations on this platform). PR #258 round-5 review
# finding: the round-4 env-flag walk only matched SINGLE unbundled flags
# (`-i`, `-u`), so `env -iv ...` / `env -iu FOO ...` fell through
# unmatched and defeated exec_base resolution exactly like round-4's
# unbundled-flag gap — up to and including a full session self-disarm via
# `env -iv rm <guard marker>`. Sets EFC_TAKES_VALUE=1 when the cluster
# ends in a value-taking letter (caller must then also skip the next
# word); an attached value on the SAME token (`-uFOO`) is not covered —
# it is rejected here (returns 1) rather than mis-consumed. -------------
env_flag_cluster_consume() {
  local w="$1" rest c
  EFC_TAKES_VALUE=0
  EFC_IS_SPLIT_STRING=0
  case "$w" in
    -?*) rest="${w#-}" ;;
    *) return 1 ;;
  esac
  while [ -n "$rest" ]; do
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$c" in
      0|i|v) : ;;
      u|C|P)
        # getopt-standard short-option value attachment: `-uFOO` means
        # `-u FOO` in ONE token, same as `-C/tmp`/`-Pdir` (real env
        # genuinely accepts this form, verified live). Previously this
        # returned 1 ("not covered") whenever a value was attached,
        # which — since the caller's fallback on a non-match is to treat
        # the FLAG TOKEN ITSELF as exec_word — misresolved exec_base to
        # the flag token, bypassing every downstream check, up to a full
        # self-disarm (`env -uFOO rm <guard marker>`; PR #258 round-10
        # review finding, the attached-value sibling of round-9's
        # separated-value `-S` fix). An attached value has nothing
        # SEPARATE left to skip, so EFC_TAKES_VALUE stays 0 either way;
        # what changed is that this case no longer `return 1`s on it.
        if [ -n "$rest" ]; then EFC_TAKES_VALUE=0; else EFC_TAKES_VALUE=1; fi
        return 0
        ;;
      S)
        # -S/--split-string's value (attached `-Scmd` or separated `-S
        # cmd`) is not a plain path/name like -u/-C/-P's — it is a WHOLE
        # embedded command line that env itself re-splits and execs
        # (`env -S "HUSKY=0 git commit -m x"` really runs `HUSKY=0 git
        # commit -m x`, verified live on this platform). "Skip the value"
        # (what -u/-C/-P correctly do) would silently smuggle an unparsed
        # command past every exec_base-keyed check at once — the same
        # self-disarm-capable bug class rounds 3-5 already closed for
        # `\exec`/`command`/bundled flags. EFC_IS_SPLIT_STRING tells the
        # caller to deny outright regardless of which form this is (PR
        # #258 round-9 finding for the separated form; round-10 extended
        # the same deny to the attached form, which round 9 had left
        # falling through unrecognized exactly like -u/-C/-P's gap).
        if [ -n "$rest" ]; then EFC_TAKES_VALUE=0; else EFC_TAKES_VALUE=1; fi
        EFC_IS_SPLIT_STRING=1
        return 0
        ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# ===========================================================================
# Word tokenizer (bash 3.2 safe): splits a simple-command string into
# whitespace-delimited words, quote-aware (single/double quotes consumed and
# stripped — structural matching below never depends on quote-vs-bare
# distinction, only on WHICH token/position a value occupies, so stripping is
# safe and simplifies every check). `>` / `>>` are split into their own
# tokens even with no surrounding whitespace (bash allows `cmd>file`).
# ===========================================================================
tokenize_words() {
  local s="$1"
  local i=0 n=${#s} c buf="" in_sq=0 in_dq=0
  local -a out=()
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$in_sq" -eq 1 ]; then
      if [ "$c" = "'" ]; then in_sq=0; else buf+="$c"; fi
      i=$((i + 1)); continue
    fi
    if [ "$in_dq" -eq 1 ]; then
      if [ "$c" = '\' ]; then
        i=$((i + 1))
        [ "$i" -lt "$n" ] && buf+="${s:$i:1}"
      elif [ "$c" = '"' ]; then
        in_dq=0
      else
        buf+="$c"
      fi
      i=$((i + 1)); continue
    fi
    case "$c" in
      "'") in_sq=1 ;;
      '"') in_dq=1 ;;
      ' '|$'\t')
        [ -n "$buf" ] && out+=("$buf")
        buf=""
        ;;
      '>')
        [ -n "$buf" ] && out+=("$buf")
        buf=""
        if [ "${s:$((i + 1)):1}" = '>' ]; then
          out+=(">>"); i=$((i + 1))
        elif [ "${s:$((i + 1)):1}" = '|' ]; then
          # `>|` — the clobber-override redirect operator (PR #258
          # round-4 review finding); matched as its own token, same as
          # `>>`, so the redirect-target check below recognizes it.
          out+=(">|"); i=$((i + 1))
        else
          out+=(">")
        fi
        ;;
      *)
        buf+="$c" ;;
    esac
    i=$((i + 1))
  done
  [ -n "$buf" ] && out+=("$buf")
  printf '%s\n' "${out[@]}"
}

# ===========================================================================
# Simple-command splitter (bash 3.2 safe): splits the full `tool_input.command`
# string on top-level `;`, `&&`, `||`, `|`, newline — quote-aware, so a
# separator inside a quoted string is never treated as a boundary.
# ===========================================================================
split_simple_commands() {
  local s="$1"
  local i=0 n=${#s} c buf="" in_sq=0 in_dq=0
  local -a out=()
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$in_sq" -eq 1 ]; then
      buf+="$c"
      [ "$c" = "'" ] && in_sq=0
      i=$((i + 1)); continue
    fi
    if [ "$in_dq" -eq 1 ]; then
      buf+="$c"
      if [ "$c" = '\' ]; then
        i=$((i + 1))
        [ "$i" -lt "$n" ] && buf+="${s:$i:1}"
      elif [ "$c" = '"' ]; then
        in_dq=0
      fi
      i=$((i + 1)); continue
    fi
    case "$c" in
      "'") in_sq=1; buf+="$c" ;;
      '"') in_dq=1; buf+="$c" ;;
      ';'|$'\n')
        out+=("$buf"); buf="" ;;
      '&')
        if [ "${s:$((i + 1)):1}" = '&' ]; then
          out+=("$buf"); buf=""; i=$((i + 1))
        else
          buf+="$c"
        fi
        ;;
      '|')
        if [ "${buf: -1}" = '>' ]; then
          # `>|` is bash's clobber-override redirect operator (forces the
          # write even under `set -o noclobber`), not a pipe — treating
          # this `|` as a pipe boundary here splits "cmd >" and "target"
          # into two unrelated simple commands, hiding the write target
          # from the redirect-target check entirely (PR #258 round-4
          # review finding: `echo x >|jest.config.js` went undetected).
          buf+="$c"
        elif [ "${s:$((i + 1)):1}" = '|' ]; then
          out+=("$buf"); buf=""; i=$((i + 1))
        else
          out+=("$buf"); buf=""
        fi
        ;;
      *)
        buf+="$c" ;;
    esac
    i=$((i + 1))
  done
  out+=("$buf")
  printf '%s\n' "${out[@]}"
}

# ---------------------------------------------------------------------------
# Bash matcher
# ---------------------------------------------------------------------------
evaluate_bash_command() {
  local full_cmd="$1"
  local simple_cmd
  while IFS= read -r simple_cmd; do
    # trim leading/trailing whitespace
    simple_cmd="${simple_cmd#"${simple_cmd%%[![:space:]]*}"}"
    simple_cmd="${simple_cmd%"${simple_cmd##*[![:space:]]}"}"
    [ -n "$simple_cmd" ] || continue
    evaluate_one_simple_command "$simple_cmd"
  done < <(split_simple_commands "$full_cmd")
}

evaluate_one_simple_command() {
  local cmd="$1"
  local -a words=()
  while IFS= read -r w; do words+=("$w"); done < <(tokenize_words "$cmd")
  [ "${#words[@]}" -gt 0 ] || return 0

  # ---- env-var anchor check (checked FIRST, independent of invoked exec) --
  # Walk ALL leading VAR=val assignments (past an optional leading
  # export/env keyword), not just the first one — ordinary shell syntax
  # allows stacking any number of leading assignments (e.g.
  # `A=1 HUSKY=0 npm test`), and a single-token check would miss every
  # assignment after the first (PR #258 round-2 review finding). Mirrors
  # the assignment-walking loop below that locates exec_word — including
  # its backslash-strip and env-flag walk (PR #258 round-4 review
  # finding: `\env HUSKY=0 git commit -m x` and `env -i HUSKY=0 git
  # commit -m x` both reached this check unstripped/unwalked and slipped
  # past the anchor undetected).
  local anchor_i=0
  local w0="${words[0]:-}"
  case "$w0" in
    '\'?*) w0="${w0#\\}" ;;
  esac
  local anchor_after_env=0
  if [ "$w0" = "export" ]; then
    anchor_i=1
  elif [ "$w0" = "env" ]; then
    anchor_i=1
    anchor_after_env=1
  fi
  while [ "$anchor_i" -lt "${#words[@]}" ]; do
    local at="${words[$anchor_i]}"
    case "$at" in
      '\'?*) at="${at#\\}" ;;
    esac
    if [ "$anchor_after_env" -eq 1 ]; then
      if env_flag_cluster_consume "$at"; then
        if [ "$EFC_IS_SPLIT_STRING" -eq 1 ]; then
          deny_variant bash "env split-string wrapped command"
        elif [ "$EFC_TAKES_VALUE" -eq 1 ]; then
          anchor_i=$((anchor_i + 2)); continue
        else
          anchor_i=$((anchor_i + 1)); continue
        fi
      fi
      case "$at" in
        --split-string=*) deny_variant bash "env split-string wrapped command" ;;
        --unset=*|--chdir=*|--ignore-environment|--null|--debug)
          anchor_i=$((anchor_i + 1)); continue ;;
        *) anchor_after_env=0 ;;
      esac
    fi
    case "$at" in
      HUSKY=*|HUSKY_SKIP_HOOKS=*|SKIP=*|PRE_COMMIT_ALLOW_NO_CONFIG=*|GIT_CONFIG_PARAMETERS=*)
        deny_variant bash "commit/push-hook bypass env"
        ;;
      GIT_CONFIG_COUNT=*|GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*)
        # git >=2.31's env-var-only config channel (GIT_CONFIG_COUNT=<n>
        # + GIT_CONFIG_KEY_<i>=<key> + GIT_CONFIG_VALUE_<i>=<value>) is
        # functionally identical to `-c key=value` — including
        # `-c core.hooksPath=...`, already denied above — for setting
        # ANY git config from the command line. Live-verified against a
        # REAL executable git hook: `GIT_CONFIG_COUNT=1
        # GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
        # git commit -m x` genuinely skips the hook and commits (PR #258
        # round-10 review finding). Correlating a specific KEY_i/VALUE_i
        # pair across separate tokens to check for core.hooksPath
        # specifically would need extra cross-token bookkeeping this
        # scan doesn't otherwise do; deny the whole env-var family
        # outright instead — the same blanket-deny-on-presence treatment
        # GIT_CONFIG_PARAMETERS already gets above, for the identical
        # reason (its own value is a shell-quoted key=value list this
        # scan doesn't parse either).
        deny_variant bash "commit/push-hook bypass env"
        ;;
    esac
    case "$at" in
      [A-Za-z_]*=*)
        local av="${at%%=*}"
        case "$av" in
          *[!A-Za-z0-9_]*|"") break ;;
          *) anchor_i=$((anchor_i + 1)); continue ;;
        esac
        ;;
      *) break ;;
    esac
  done

  # ---- find invoked executable: skip leading VAR=val assignments,
  #      export/env keyword tokens, and command/builtin/exec — the
  #      standard shell-grammar ways to invoke a program while bypassing
  #      an alias/function of the same name. Without this, `command git
  #      ...`, `exec rm ...`, or `builtin ...` resolve exec_base to
  #      "command"/"exec"/"builtin" and silently skip EVERY
  #      exec_base-keyed check below — not just one pattern, the entire
  #      dispatch mechanism (PR #258 review round 3 finding; the widest
  #      instance yet of the recurring "only inspects the adjacent word"
  #      bug class). A leading backslash on ANY of these keyword tokens
  #      themselves (`\env`, `\exec`, ...) — the standard per-token
  #      alias-bypass escape — is stripped before matching, and `env`'s
  #      own flags/values (`env -i git ...`, `env -u FOO git ...`) are
  #      walked past the same way git's global options are (PR #258
  #      round-4 review finding: both forms previously resolved
  #      exec_base to the escaped keyword or the flag/value token
  #      itself, again defeating every downstream check at once —
  #      `\exec rm <guard marker>` was a full session self-disarm).
  #      ------------------------------------------------------------
  local idx=0
  local after_env=0
  while [ "$idx" -lt "${#words[@]}" ]; do
    local t="${words[$idx]}"
    case "$t" in
      '\'?*) t="${t#\\}" ;;
    esac
    if [ "$after_env" -eq 1 ]; then
      if env_flag_cluster_consume "$t"; then
        if [ "$EFC_IS_SPLIT_STRING" -eq 1 ]; then
          deny_variant bash "env split-string wrapped command"
        elif [ "$EFC_TAKES_VALUE" -eq 1 ]; then
          idx=$((idx + 2)); continue
        else
          idx=$((idx + 1)); continue
        fi
      fi
      case "$t" in
        --split-string=*) deny_variant bash "env split-string wrapped command" ;;
        --unset=*|--chdir=*|--ignore-environment|--null|--debug)
          idx=$((idx + 1)); continue ;;
        *) after_env=0 ;;
      esac
    fi
    case "$t" in
      export|command|builtin|exec) idx=$((idx + 1)); continue ;;
      env) after_env=1; idx=$((idx + 1)); continue ;;
      *=*)
        case "$t" in
          [A-Za-z_]*=*)
            # looks like VAR=value where VAR is a shell-identifier-shaped prefix
            local var_part="${t%%=*}"
            case "$var_part" in
              *[!A-Za-z0-9_]*) break ;;  # not a clean identifier, stop
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
  local exec_word="${words[$idx]:-}"
  case "$exec_word" in
    '\'?*) exec_word="${exec_word#\\}" ;;
  esac
  local exec_base
  exec_base="$(basename_of "$exec_word")"

  # ---- guard-arm.sh invocation rule (structural: exec is guard-arm.sh, or
  #      the word after bash/sh/source is a guard-arm.sh path — a bare
  #      `exec` prefix is already resolved past above) ------------------
  local ga_idx=-1
  case "$exec_base" in
    guard-arm.sh) ga_idx=$idx ;;
    bash|sh|source|.)
      local next="${words[$((idx + 1))]:-}"
      case "$(basename_of "$next")" in
        guard-arm.sh) ga_idx=$((idx + 1)) ;;
      esac
      ;;
  esac
  if [ "$ga_idx" -ge 0 ]; then
    local next_word="${words[$((ga_idx + 1))]:-}"
    if [ "$next_word" != "arm" ]; then
      deny_variant bash "internal control script invocation"
    fi
    # subcommand IS exactly "arm" -> normally allowed (harmless by
    # construction — see guard-arm.sh's own header) EXCEPT when a
    # --session-id token follows: that flag lets the caller name an
    # ARBITRARY session id instead of the tool call's own
    # CLAUDE_CODE_SESSION_ID, arming a session the calling agent does not
    # own. The only legitimate caller of --session-id is
    # dispatch-pr-review.sh, which invokes guard-arm.sh directly as a
    # subprocess, never through a tool call this matcher ever sees — so
    # denying it here costs no legitimate use (PR #258 review finding).
    local w2
    for w2 in "${words[@]:$((ga_idx + 2))}"; do
      case "$w2" in
        --session-id|--session-id=*)
          deny_variant bash "internal control script invocation"
          ;;
      esac
    done
    # subcommand is a bare "arm" with no --session-id -> allowed, fall
    # through to other checks. No further Bash-matcher checks apply to
    # this simple command since it is fully accounted for.
    return 0
  fi

  # ---- git-scoped patterns (only when the invoked executable is git) -----
  if [ "$exec_base" = "git" ]; then
    local w
    for w in "${words[@]:$((idx + 1))}"; do
      case "$w" in
        --no-ver*)
          # git accepts unambiguous long-option prefixes of --no-verify
          case "$w" in
            --no-ver[a-z]*|--no-verify) deny_variant bash "commit/push-hook bypass flag" ;;
          esac
          ;;
      esac
    done
    # Find the actual git subcommand, skipping past git's own GLOBAL
    # options — which may legitimately precede it (`git -c x=y commit -n`,
    # `git --no-pager clean -fdx`, `git -C . commit -n`). A fixed
    # words[idx+1] read missed the subcommand whenever ANY global flag came
    # first, silently skipping every subcommand-scoped check below
    # (self-audit follow-up to the PR #258 round-2 pre-commit/lefthook and
    # env-anchor findings — same "checks one adjacent word" bug class).
    local subcmd="" subcmd_idx=$((idx + 1))
    while [ "$subcmd_idx" -lt "${#words[@]}" ]; do
      local gw="${words[$subcmd_idx]}"
      case "$gw" in
        -c|-C)
          # value-taking short global options: skip the flag AND its value
          subcmd_idx=$((subcmd_idx + 2))
          continue
          ;;
        --*=*|-*)
          # any other flag (long --flag[=value], or a bare short flag) —
          # skip just this one token
          subcmd_idx=$((subcmd_idx + 1))
          continue
          ;;
        *)
          subcmd="$gw"
          break
          ;;
      esac
    done
    if [ "$subcmd" = "commit" ]; then
      local w2
      for w2 in "${words[@]:$((subcmd_idx + 1))}"; do
        case "$w2" in
          -[a-zA-Z]*)
            case "$w2" in
              --*) : ;;
              *n*) deny_variant bash "commit/push-hook bypass flag" ;;
            esac
            ;;
        esac
      done
    fi
    if [ "$subcmd" = "clean" ]; then
      local w3
      for w3 in "${words[@]:$((subcmd_idx + 1))}"; do
        case "$w3" in
          -[a-zA-Z]*)
            case "$w3" in
              --*) : ;;
              *[xX]*) deny_variant bash "destructive clean flag" ;;
            esac
            ;;
        esac
      done
    fi
    if [ "$subcmd" = "config" ]; then
      local has_hookspath=0 has_read_flag=0 has_value=0 argc=0
      local w4
      for w4 in "${words[@]:$((subcmd_idx + 1))}"; do
        case "$w4" in
          core.hooksPath) has_hookspath=1 ;;
          --get|--get-all|--list|-l) has_read_flag=1 ;;
          -*) : ;;
          *) argc=$((argc + 1)) ;;
        esac
      done
      if [ "$has_hookspath" -eq 1 ] && [ "$has_read_flag" -eq 0 ] && [ "$argc" -ge 1 ]; then
        deny_variant bash "git hooksPath override"
      fi
    fi
    # `git -c core.hooksPath=...`
    if [ "$idx" -ge 0 ]; then
      local w5
      for w5 in "${words[@]:$((idx + 1))}"; do
        case "$w5" in
          -c) : ;;
          core.hooksPath=*) deny_variant bash "git hooksPath override" ;;
        esac
      done
    fi
  fi

  # ---- pre-commit / lefthook uninstall ------------------------------------
  # Scan ALL remaining words for a bare "uninstall" token, not just the one
  # immediately after the executable — both tools' real CLIs (lefthook's
  # urfave/cli grammar in particular: `lefthook [global options] command
  # [command options]`) legitimately accept flags BEFORE the subcommand, so
  # `lefthook --no-colors uninstall` is a real invocation a next-word-only
  # check would miss entirely (PR #258 round-2 review finding).
  case "$exec_base" in
    pre-commit|lefthook)
      local w7
      for w7 in "${words[@]:$((idx + 1))}"; do
        [ "$w7" = "uninstall" ] && deny_variant bash "git-hook manager uninstall"
      done
      ;;
  esac

  # ---- rm/chmod/mv with an argument under a git-hook directory -----------
  # `.husky/` is equally in scope: Husky v9+ (the current default
  # `npx husky init` output) sets `core.hooksPath=.husky`, so
  # `.husky/pre-commit` IS the live git hook, not a convenience file next
  # to one — a `chmod -x` there disables the hook exactly like one under
  # `.git/hooks` would (PR #258 round-6 review finding). `chmod` stays a
  # dedicated case here (not folded into is_protected_path_arg below)
  # because a permission change doesn't rewrite CONTENT, so it's only a
  # meaningful "disable" for an executable-bit-sensitive hook path, not
  # for a protected basename or settings.json in general.
  case "$exec_base" in
    rm|chmod|mv)
      local w6
      for w6 in "${words[@]:$((idx + 1))}"; do
        case "$w6" in
          *.git/hooks*|*.husky*) deny_variant bash "git-hook directory write" ;;
        esac
      done
      ;;
  esac

  # ---- write verbs whose simple command names a protected path -----------
  local is_write_verb=0
  case "$exec_base" in
    tee|mv|cp|rm|truncate|install) is_write_verb=1 ;;
    sed)
      local w7
      for w7 in "${words[@]:$((idx + 1))}"; do
        case "$w7" in
          -i|-i*) is_write_verb=1 ;;
        esac
      done
      ;;
  esac
  if [ "$is_write_verb" -eq 1 ]; then
    local w8
    for w8 in "${words[@]:$((idx + 1))}"; do
      case "$w8" in
        -*) continue ;;
      esac
      if is_protected_path_arg "$w8"; then
        deny_variant bash "protected configuration write"
      fi
    done
  fi

  # ---- ln: symlink-clobber of the LINK NAME (the last non-flag argument
  #      in the `ln [-s] TARGET LINK_NAME` form), not every argument. `ln`
  #      only READS its TARGET argument(s) — treating them the same as the
  #      write verbs' all-argument scan above false-denies a legitimate
  #      `ln -s realfile.txt /tmp/dest` whenever realfile.txt happens to
  #      share a protected basename (PR #258 round-5 review finding; the
  #      round-4 fix that first added `ln` reused the all-argument scan
  #      verbatim without checking ln's own read-vs-write argument shape).
  if [ "$exec_base" = "ln" ]; then
    local w9 link_name=""
    for w9 in "${words[@]:$((idx + 1))}"; do
      case "$w9" in
        -*) continue ;;
      esac
      link_name="$w9"
    done
    if is_protected_path_arg "$link_name"; then
      deny_variant bash "protected configuration write"
    fi
  fi

  # ---- `>` / `>>` / `>|` redirect target -----------------------------------
  local wi
  for ((wi = 0; wi < ${#words[@]}; wi++)); do
    case "${words[$wi]}" in
      '>'|'>>'|'>|')
        local target="${words[$((wi + 1))]:-}"
        if is_protected_path_arg "$target"; then
          deny_variant bash "protected configuration write"
        fi
        ;;
    esac
  done

  return 0
}

# ---------------------------------------------------------------------------
# Write|Edit matcher
# ---------------------------------------------------------------------------
evaluate_write_edit() {
  local f="$1" base dirpart
  base="$(basename_of "$f")"

  case "$f" in
    */.supervisor/guard/*) deny_variant edit "protected configuration write" ;;
    */.husky/*) deny_variant edit "protected configuration path" ;;
    */.git/hooks/*) deny_variant edit "protected configuration path" ;;
  esac

  case "$f" in
    */.claude/settings.json|.claude/settings.json| \
    */.claude/settings.local.json|.claude/settings.local.json)
      deny_variant edit "protected configuration path"
      ;;
  esac

  if [ "$base" = "conftest.py" ]; then
    dirpart="$(dirname "$f")"
    local top
    top="$(git -C "$dirpart" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ]; then
      local dirpart_abs
      dirpart_abs="$(cd "$dirpart" 2>/dev/null && pwd -P || true)"
      if [ -n "$dirpart_abs" ] && [ "$dirpart_abs" = "$top" ]; then
        deny_variant edit "protected configuration path"
      fi
    fi
    # A failed toplevel lookup or a non-toplevel conftest.py means
    # "allow" for THIS rule specifically — deny_variant above already
    # exits on the deny path (deny() calls `exit 2`), so nothing below
    # is reached there. No early `return 0` here (PR #258 round-8 review
    # finding): an unconditional return made LOOMWRIGHT_GUARD_EXTRA_GLOBS
    # dead code for the one basename "conftest.py" — an admin extending
    # protection to non-toplevel conftest.py files via that env var was
    # silently ignored. Fall through so is_protected_basename (a no-op
    # for this basename, harmlessly) and EXTRA_GLOBS still both run.
  fi

  if is_protected_basename "$base"; then
    deny_variant edit "protected configuration path"
  fi

  # LOOMWRIGHT_GUARD_EXTRA_GLOBS — colon-separated, next-launch semantics
  # (process-env, same as the opt-out). `set -f` for the duration of the
  # split+match: `for glob in $extra` is intentionally unquoted (colon
  # splitting needs word splitting to happen), but bash ALSO performs
  # pathname expansion on an unquoted for-loop word, and there is no
  # `set -f` anywhere else in this script. Without it, a glob-shaped
  # pattern that happens to match files already present in the guard
  # PROCESS's own CWD (an ordinary, likely case — e.g. the documented
  # worked example `.github/workflows/*` run from a repo that already
  # has workflow files) silently expands to the literal list of
  # pre-existing filenames instead of staying a wildcard; a brand-new
  # file matching the intended pattern then fails the resulting literal
  # `case` comparison and is silently ALLOWED — the opposite of the
  # admin's intent, and non-deterministic (same payload+env, different
  # CWD contents, opposite verdict). Live-verified before this fix (PR
  # #258 round-8 review finding).
  local extra="${LOOMWRIGHT_GUARD_EXTRA_GLOBS:-}"
  if [ -n "$extra" ]; then
    local saved_ifs="$IFS" glob
    IFS=':'
    set -f
    for glob in $extra; do
      IFS="$saved_ifs"
      [ -n "$glob" ] || continue
      case "$f" in
        $glob) deny_variant edit "protected configuration path" ;;
      esac
      case "$base" in
        $glob) deny_variant edit "protected configuration path" ;;
      esac
    done
    set +f
    IFS="$saved_ifs"
  fi

  return 0
}

case "$TOOL_NAME" in
  Bash)
    COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -n "$COMMAND" ] || allow
    evaluate_bash_command "$COMMAND"
    ;;
  Write|Edit)
    FILE_PATH="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    [ -n "$FILE_PATH" ] || allow
    evaluate_write_edit "$FILE_PATH"
    ;;
esac

allow
