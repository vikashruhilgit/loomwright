#!/usr/bin/env bash
# Drift guard for command-wrapper files.
#
# Ensures ai-agent-manager-plugin/commands/code-reviewer.md stays a thin wrapper:
#   - must carry the thin-wrapper sentinel comment
#   - must not re-embed canonical prompt sections (unambiguous headings only)
#   - must not reference the non-existent .claude-plugin/agents/utils.md path
#   - must not show flat-layout paths inside fenced sample blocks (post-marketplace migration)
#
# Exits 0 when clean, 1 when drift detected.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
targets=(
  "${repo_root}/ai-agent-manager-plugin/commands/code-reviewer.md"
)

sentinel='<!-- thin-wrapper: canonical prompt lives in ai-agent-manager-plugin/agents/code-reviewer.md -->'

# Unambiguous canonical-prompt-only markers. Avoid `### Output Format` / `## Example Output`
# because those are legitimate in a user-facing wrapper.
canonical_markers=(
  '^# Code Reviewer Agent Prompt$'
  '^## Role: Code Reviewer'
  '^### Review Decision Matrix'
  '^### Pre-Review Checklist'
  '^### Close Review Task'
)

stale_ref='.claude-plugin/agents/utils.md'

fail=0

for file in "${targets[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "check-command-sync: missing target file: $file" >&2
    fail=1
    continue
  fi

  if ! grep -qF "$sentinel" "$file"; then
    echo "FAIL: $file is missing the thin-wrapper sentinel:" >&2
    echo "      $sentinel" >&2
    fail=1
  fi

  for marker in "${canonical_markers[@]}"; do
    if grep -nE "$marker" "$file" >/dev/null; then
      echo "FAIL: $file re-embeds a canonical-prompt section matching: $marker" >&2
      grep -nE "$marker" "$file" >&2 || true
      fail=1
    fi
  done

  if grep -nF "$stale_ref" "$file" >/dev/null; then
    echo "FAIL: $file references stale path: $stale_ref" >&2
    grep -nF "$stale_ref" "$file" >&2 || true
    fail=1
  fi

  # Flat-layout drift inside fenced code blocks (``` ... ```).
  # Post-marketplace migration: plugin content lives under ai-agent-manager-plugin/.
  # Sample YAML blocks that list paths must carry the ai-agent-manager-plugin/ prefix
  # (except for root-level .claude-plugin/marketplace.json and CLAUDE.md / README.md).
  flat_hits=$(awk '
    /^```/ { in_block = !in_block; next }
    in_block && /^[[:space:]]*-[[:space:]]+(agents|commands|skills|docs)\// { print NR ": " $0; hit=1 }
    in_block && /^[[:space:]]*-[[:space:]]+\.claude-plugin\/plugin\.json[[:space:]]*$/ { print NR ": " $0; hit=1 }
    in_block && /^Triggers:[[:space:]]+(agents|commands|skills|docs)\// { print NR ": " $0; hit=1 }
    in_block && /^Scope expanded:.*(^|[[:space:],])(agents|commands|skills|docs)\// { print NR ": " $0; hit=1 }
    in_block && /^Scope expanded:.*(^|[[:space:],])\.claude-plugin\/plugin\.json/ { print NR ": " $0; hit=1 }
    END { exit hit ? 1 : 0 }
  ' "$file") && flat_rc=0 || flat_rc=$?

  if [[ $flat_rc -ne 0 ]]; then
    echo "FAIL: $file contains flat-layout paths inside fenced sample blocks (expected ai-agent-manager-plugin/ prefix):" >&2
    echo "$flat_hits" >&2
    fail=1
  fi

  # Prose-level flat-layout drift: backtick-wrapped path references that point at
  # canonical source locations (e.g. `agents/code-reviewer.md`, `commands/foo.md`,
  # `hooks/hooks.json`, `.claude-plugin/plugin.json`) must carry the
  # ai-agent-manager-plugin/ prefix post-migration.
  #
  # Deliberately EXCLUDED from prose enforcement:
  #   - `skills/{slug}/SKILL.md` — skill refs are resolved from plugin root at runtime,
  #     short-form is the idiomatic convention in both agents and wrappers.
  #   - `docs/*.md` — similar runtime-relative doc pointers.
  # These stay caught in fenced sample blocks (YAML lists of repo-relative paths) via the
  # fenced-block check above, where short-form IS wrong because those blocks encode
  # concrete git-diff-style paths.
  prose_hits=$(awk '
    /^```/ { in_block = !in_block; next }
    !in_block {
      line = $0
      # Strip already-prefixed occurrences so the bare-path search is unambiguous.
      gsub(/`ai-agent-manager-plugin\/[^`]*`/, "", line)
      if (match(line, /`(agents|commands|hooks)\/[^`]+\.(md|json)`/)) {
        print NR ": " $0; hit=1
      } else if (match(line, /`\.claude-plugin\/plugin\.json`/)) {
        print NR ": " $0; hit=1
      }
    }
    END { exit hit ? 1 : 0 }
  ' "$file") && prose_rc=0 || prose_rc=$?

  if [[ $prose_rc -ne 0 ]]; then
    echo "FAIL: $file contains flat-layout backtick paths in prose (expected ai-agent-manager-plugin/ prefix or root .claude-plugin/marketplace.json):" >&2
    echo "$prose_hits" >&2
    fail=1
  fi
done

if [[ $fail -eq 0 ]]; then
  echo "check-command-sync: OK"
fi

exit $fail
