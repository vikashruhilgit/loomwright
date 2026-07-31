#!/usr/bin/env bash
# digest-lanes.test.sh — offline-safe regression test for D6 subtask 3 (AC5 + AC12):
#   - the SDK-runner carrier of the context-digest pointer (contextDigestPointer) reaches the
#     composed worker prompt, alongside the subtask's own lane text (laneGlobs)
#   - the brief parser's contracts-heading fix, fail-closed empty-contracts guard, and the
#     `lanes:` list-header reset (no leak into `requires`)
#
# bash-3.2-safe (macOS stock bash): no associative arrays, no mapfile, no ${var,,}.
# Exits non-zero on any FAIL. Degrades gracefully offline: everything here needs a compiled
# dist/runner.js (this test exercises the exported parseBrief / contextDigestPointer /
# workerPrompt directly, not the CLI) — SKIP, not FAIL, when node or the build is unavailable.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SPIKE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$SPIKE_DIR" || { echo "FATAL: cannot cd to spike dir"; exit 1; }

FAILURES=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; }

HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1
DIST="$SPIKE_DIR/dist/runner.js"

if [ "$HAVE_NODE" != 1 ] || [ ! -f "$DIST" ]; then
  skip "digest-lanes.test.sh: all checks skipped — node or dist/runner.js unavailable (run npm run build first)"
  printf '\n%s\n' "digest-lanes.test.sh: 0 failure(s) (fully skipped)"
  exit 0
fi

TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t digest-lanes)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixture briefs — built as temp files rather than test/fixtures/*.md so this
# test stays inside its declared lane (test/digest-lanes.test.sh only).
# ---------------------------------------------------------------------------

BRIEF_OLD_HEADING="$TMP_DIR/old-heading-brief.md"
cat > "$BRIEF_OLD_HEADING" <<'EOF'
# Supervisor Job: digest-lanes test (old heading)

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | Producer | 1 | LAUNCHABLE |
| 2 | Consumer | 1 | BLOCKED (by #1) |

### Subtask contracts

```yaml
# Subtask 1 — Producer (LAUNCHABLE)
provides:
  - {kind: "file", path: "src/producer.ts"}
requires: []

# Subtask 2 — Consumer (BLOCKED by #1)
provides:
  - {kind: "file", path: "src/consumer.ts"}
requires:
  - {from: "1", kind: "file", path: "src/producer.ts"}
```

Suggested branch: feature/digest-lanes-old-heading
EOF

BRIEF_NEW_HEADING="$TMP_DIR/new-heading-brief.md"
cat > "$BRIEF_NEW_HEADING" <<'EOF'
# Supervisor Job: digest-lanes test (new heading)

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | Producer | 1 | LAUNCHABLE |
| 2 | Consumer | 1 | BLOCKED (by #1) |

### Provides / Requires Contracts

```yaml
# Subtask 1 — Producer (LAUNCHABLE)
provides:
  - {kind: "file", path: "src/producer.ts"}
requires: []

# Subtask 2 — Consumer (BLOCKED by #1)
provides:
  - {kind: "file", path: "src/consumer.ts"}
requires:
  - {from: "1", kind: "file", path: "src/producer.ts"}
```

Suggested branch: feature/digest-lanes-new-heading
EOF

BRIEF_ZERO_CONTRACTS="$TMP_DIR/zero-contracts-brief.md"
cat > "$BRIEF_ZERO_CONTRACTS" <<'EOF'
# Supervisor Job: zero-contracts fail-closed test

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | Producer | 1 | LAUNCHABLE |
| 2 | Consumer | 1 | BLOCKED (by #1) |

Suggested branch: feature/zero-contracts-test
EOF

BRIEF_LANE_LEAK="$TMP_DIR/lane-leak-brief.md"
cat > "$BRIEF_LANE_LEAK" <<'EOF'
# Supervisor Job: lanes-does-not-leak-into-requires test

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | Producer | 1 | LAUNCHABLE |

### Subtask contracts

```yaml
# Subtask 1 — Producer (LAUNCHABLE)
provides:
  - {kind: "file", path: "src/producer.ts"}
requires:
  - {from: "0", kind: "file", path: "src/base.ts"}
lanes:
  - "src/producer.ts"
  - {kind: "file", path: "should/not/leak.ts"}
external_requires: []
```

Suggested branch: feature/lane-leak-test
EOF

# ---------------------------------------------------------------------------
# (1) Both contracts headings parse
# ---------------------------------------------------------------------------
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  const s1 = r.subtasks.find((s) => s.id === '1');
  const s2 = r.subtasks.find((s) => s.id === '2');
  const problems = [];
  if (!s1 || !s2) problems.push('subtask 1 or 2 missing');
  if (s1 && s1.provides.length !== 1) problems.push('subtask 1: expected 1 provides item, got ' + (s1 && s1.provides.length));
  if (s2 && s2.requires.length !== 1) problems.push('subtask 2: expected 1 requires item, got ' + (s2 && s2.requires.length));
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$BRIEF_OLD_HEADING"; then
  pass "parseBrief: '### Subtask contracts' heading parses provides/requires"
else
  fail "parseBrief: '### Subtask contracts' heading did not parse provides/requires"
fi

if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  const s1 = r.subtasks.find((s) => s.id === '1');
  const s2 = r.subtasks.find((s) => s.id === '2');
  const problems = [];
  if (!s1 || !s2) problems.push('subtask 1 or 2 missing');
  if (s1 && s1.provides.length !== 1) problems.push('subtask 1: expected 1 provides item, got ' + (s1 && s1.provides.length));
  if (s2 && s2.requires.length !== 1) problems.push('subtask 2: expected 1 requires item, got ' + (s2 && s2.requires.length));
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$BRIEF_NEW_HEADING"; then
  pass "parseBrief: '### Provides / Requires Contracts' heading ALSO parses provides/requires"
else
  fail "parseBrief: '### Provides / Requires Contracts' heading did not parse provides/requires"
fi

# ---------------------------------------------------------------------------
# (2) Zero-contract parse FAILS CLOSED (not an all-LAUNCHABLE wave)
# ---------------------------------------------------------------------------
ZERO_ERR=$(node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  try {
    parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
    console.error('parseBrief did NOT throw on a zero-contract multi-subtask brief');
    process.exit(1);
  } catch (e) {
    if (!/all-LAUNCHABLE/.test(e.message)) {
      console.error('threw, but wrong message: ' + e.message);
      process.exit(1);
    }
    process.exit(0);
  }
" "$DIST" "$BRIEF_ZERO_CONTRACTS" 2>&1)
if [ $? = 0 ]; then
  pass "parseBrief: Subtask Structure table with zero parsed contracts fails closed (explicit error, not all-LAUNCHABLE)"
else
  fail "parseBrief: zero-contract fail-closed check did not behave as expected: $ZERO_ERR"
fi

# Single-subtask exemption: no sibling to sequence against, so a lone LAUNCHABLE subtask with
# no contracts section must NOT trip the fail-closed guard (it would be a false positive).
SINGLE_BRIEF="$TMP_DIR/single-subtask-no-contracts.md"
cat > "$SINGLE_BRIEF" <<'EOF'
# Supervisor Job: single-subtask exemption

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | Only subtask | 1 | LAUNCHABLE |

Suggested branch: feature/single-subtask-exemption
EOF
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  process.exit(r.subtasks.length === 1 ? 0 : 1);
" "$DIST" "$SINGLE_BRIEF"; then
  pass "parseBrief: single-subtask brief with no contracts section is exempt from the fail-closed guard"
else
  fail "parseBrief: single-subtask exemption regressed (false-positive fail-closed, or subtask count wrong)"
fi

# ---------------------------------------------------------------------------
# (3) `lanes:` items do not leak into `requires`
# ---------------------------------------------------------------------------
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  const s1 = r.subtasks.find((s) => s.id === '1');
  const problems = [];
  if (!s1) problems.push('subtask 1 missing');
  else {
    if (s1.requires.length !== 1) problems.push('expected exactly 1 requires item, got ' + s1.requires.length);
    if (s1.requires.some((r) => r.path === 'should/not/leak.ts')) problems.push('a lanes: entry leaked into requires');
    if (!s1.laneGlobs.includes('src/producer.ts')) problems.push('laneGlobs missing the quoted-string lane entry');
  }
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$BRIEF_LANE_LEAK"; then
  pass "parseBrief: 'lanes:' resets listKey — a brace-form lane entry does not leak into requires"
else
  fail "parseBrief: a 'lanes:' entry leaked into requires (listKey not reset)"
fi

# ---------------------------------------------------------------------------
# (4) Context digest pointer appears in a composed worker prompt
# ---------------------------------------------------------------------------
DIGEST_REPO_ROOT="$TMP_DIR/repo"
mkdir -p "$DIGEST_REPO_ROOT/.supervisor/jobs/context-digests"
DIGEST_BASENAME="2026-07-31-digest-lanes-fixture.md"
printf '## File Impact Map\n_(none found)_\n' > "$DIGEST_REPO_ROOT/.supervisor/jobs/context-digests/$DIGEST_BASENAME"
# briefPath need not exist itself — contextDigestPointer only needs its basename.
FAKE_BRIEF_PATH="$TMP_DIR/jobs/in-progress/$DIGEST_BASENAME"

if node -e "
  const { contextDigestPointer, workerPrompt } = require(process.argv[1]);
  const repoRoot = process.argv[2];
  const briefPath = process.argv[3];
  const pointer = contextDigestPointer(repoRoot, briefPath);
  const problems = [];
  if (!pointer) problems.push('contextDigestPointer returned undefined for an EXISTING digest file');
  else {
    if (!pointer.includes('Read only the sections you need')) problems.push('pointer missing \"Read only the sections you need\"');
    if (!pointer.includes('MAIN-CHECKOUT ABSOLUTE')) problems.push('pointer missing MAIN-CHECKOUT ABSOLUTE wording');
    if (pointer.length - pointer.indexOf('Summary:') > 260) problems.push('bounded summary looks unbounded');
  }
  const subtask = { id: '1', title: 'demo', tableStatus: '', provides: [], requires: [], laneGlobs: ['src/producer.ts'] };
  const prompt = workerPrompt(subtask, '/tmp/wt-demo', pointer);
  if (pointer && !prompt.includes(pointer)) problems.push('composed worker prompt is missing the digest pointer verbatim');
  if (!prompt.includes('src/producer.ts')) problems.push('composed worker prompt is missing the laneGlobs lane text');
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$DIGEST_REPO_ROOT" "$FAKE_BRIEF_PATH"; then
  pass "contextDigestPointer + laneGlobs: both reach the composed worker prompt when the digest file exists"
else
  fail "contextDigestPointer / laneGlobs did not reach the composed worker prompt as expected"
fi

# Advisory fail-safe: no digest file on disk -> undefined, never a placeholder pointing at nothing.
if node -e "
  const { contextDigestPointer } = require(process.argv[1]);
  const pointer = contextDigestPointer(process.argv[2], 'brief-with-no-digest.md');
  process.exit(pointer === undefined ? 0 : 1);
" "$DIST" "$DIGEST_REPO_ROOT"; then
  pass "contextDigestPointer: returns undefined (never a placeholder) when the digest file is absent"
else
  fail "contextDigestPointer: did not return undefined for a missing digest file"
fi

# ---------------------------------------------------------------------------
printf '\n%s\n' "digest-lanes.test.sh: $FAILURES failure(s)"
[ "$FAILURES" = 0 ] || exit 1
exit 0
