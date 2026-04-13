#!/usr/bin/env bash
# Drift guard for command-wrapper files.
#
# Ensures commands/code-reviewer.md stays a thin wrapper:
#   - must carry the thin-wrapper sentinel comment
#   - must not re-embed canonical prompt sections (unambiguous headings only)
#   - must not reference the non-existent .claude-plugin/agents/utils.md path
#
# Exits 0 when clean, 1 when drift detected.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
targets=(
  "${repo_root}/commands/code-reviewer.md"
)

sentinel='<!-- thin-wrapper: canonical prompt lives in agents/code-reviewer.md -->'

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
done

if [[ $fail -eq 0 ]]; then
  echo "check-command-sync: OK"
fi

exit $fail
