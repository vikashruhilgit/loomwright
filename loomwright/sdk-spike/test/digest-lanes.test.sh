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
# (5) Committed real-layout fixtures (loomwright/sdk-spike/test/fixtures/) — these give DURABLE
#     CI protection: `.supervisor/` is gitignored (absent in a fresh clone), so the heredoc
#     fixtures above and these committed files are the only regression protection this parser
#     has in CI. Each fixture is trimmed from a real archived brief that used to throw before the
#     fixes below landed.
# ---------------------------------------------------------------------------
FIXDIR="$SPIKE_DIR/test/fixtures"

# Per-subtask MARKDOWN heading anchor, no umbrella heading at all (trimmed from
# 2026-07-30-fix7-two-review-lenses.md).
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  const s1 = r.subtasks.find((s) => s.id === '1');
  const s2 = r.subtasks.find((s) => s.id === '2');
  const problems = [];
  if (!s1 || !s2) problems.push('subtask 1 or 2 missing');
  if (s1 && s1.provides.length !== 2) problems.push('subtask 1: expected 2 provides, got ' + (s1 && s1.provides.length));
  if (s2 && (s2.requires.length !== 1 || s2.requires[0].from !== '1')) problems.push('subtask 2: expected 1 requires item with from=1');
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$FIXDIR/brief-per-subtask-heading.md"; then
  pass "fixture brief-per-subtask-heading.md: per-subtask markdown heading anchor (no umbrella heading) parses"
else
  fail "fixture brief-per-subtask-heading.md did not parse as expected"
fi

# "Provides / Requires Schema" heading + inline flow-style arrays + S<N>: id keys + from: S<N>
# normalization (trimmed from 2026-06-19-automate-engine.md / 2026-07-07-script-test-gaps-and-
# roadmap-remainders.md).
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  const s1 = r.subtasks.find((s) => s.id === '1');
  const s2 = r.subtasks.find((s) => s.id === '2');
  const problems = [];
  if (!s1 || !s2) problems.push('subtask 1 or 2 missing (S<N>: id-key form did not resolve to plain numeric ids)');
  if (s1 && s1.provides.length !== 1) problems.push('subtask 1: expected 1 provides item (inline array), got ' + (s1 && s1.provides.length));
  if (s2 && (s2.requires.length !== 1 || s2.requires[0].from !== '1')) problems.push('subtask 2: expected 1 requires item with from=1 (normalized from \"S1\")');
  // INLINE lanes regression: lanes are plain strings, so the {...}-group scan used for
  // provides/requires finds nothing in them. An earlier cut silently left laneGlobs EMPTY here,
  // and workerPrompt emits lane-boundary text only when laneGlobs.length > 0 — so the worker got
  // no lane at all. Assert BOTH entries so a comma-splitting regression cannot pass on the first.
  if (s1 && (s1.laneGlobs.length !== 2
             || !s1.laneGlobs.includes('loomwright/scripts/produced.sh')
             || !s1.laneGlobs.includes('loomwright/scripts/produced-helper.sh'))) {
    problems.push('subtask 1: inline lanes: [\"a\", \"b\"] did not populate laneGlobs; got ' + JSON.stringify(s1.laneGlobs));
  }
  if (s2 && (s2.laneGlobs.length !== 1 || s2.laneGlobs[0] !== 'loomwright/scripts/consumed.sh')) {
    problems.push('subtask 2: single-entry inline lanes did not populate laneGlobs; got ' + JSON.stringify(s2.laneGlobs));
  }
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$FIXDIR/brief-inline-array-contracts.md"; then
  pass "fixture brief-inline-array-contracts.md: 'Provides / Requires Schema' heading + inline arrays + S<N>: ids + inline lanes parse"
else
  fail "fixture brief-inline-array-contracts.md did not parse as expected"
fi

# Positional fallback: no id marker of any kind, id implied by table row order (trimmed from
# 2026-06-14-requirement-closeout-loop.md).
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  const s1 = r.subtasks.find((s) => s.id === '1');
  const s2 = r.subtasks.find((s) => s.id === '2');
  const problems = [];
  if (!s1 || !s2) problems.push('subtask 1 or 2 missing (positional fallback did not bind ids)');
  if (s1 && s1.provides.length !== 1) problems.push('subtask 1: expected 1 provides item, got ' + (s1 && s1.provides.length));
  if (s2 && (s2.requires.length !== 1 || s2.requires[0].from !== '1')) problems.push('subtask 2: expected 1 requires item with from=1');
  if (problems.length) { console.error(problems.join('; ')); process.exit(1); }
" "$DIST" "$FIXDIR/brief-positional-no-id.md"; then
  pass "fixture brief-positional-no-id.md: positional (id-less) contracts fallback binds ids in table order"
else
  fail "fixture brief-positional-no-id.md did not parse as expected"
fi

# Digest section-shape fixture also parses cleanly as a brief (shared with test-context-digest.sh).
if node -e "
  const { parseBrief } = require(process.argv[1]);
  const fs = require('fs');
  const r = parseBrief(fs.readFileSync(process.argv[2], 'utf8'));
  process.exit(r.subtasks.length === 2 ? 0 : 1);
" "$DIST" "$FIXDIR/brief-digest-sections.md"; then
  pass "fixture brief-digest-sections.md: parses as a 2-subtask brief (shared digest/parser fixture)"
else
  fail "fixture brief-digest-sections.md did not parse as a 2-subtask brief"
fi

# ---------------------------------------------------------------------------
# (6) OPT-IN local corpus sweep: `.supervisor/jobs/{done,in-progress}/*.md` is gitignored and
#     absent in a fresh clone/CI checkout — this section runs ONLY when that directory exists
#     locally, and ANNOUNCES the skip (never silently no-ops) when it does not. This is
#     ADDITIONAL, opportunistic protection on top of the committed fixtures above (5), which are
#     the durable CI-covered regression guard; this sweep is what an operator sees when running
#     the suite locally against the real, gitignored job corpus.
# ---------------------------------------------------------------------------
REPO_ROOT_FOR_CORPUS="$(cd "$SPIKE_DIR/../.." && pwd)"
CORPUS_DIRS="$REPO_ROOT_FOR_CORPUS/.supervisor/jobs/done $REPO_ROOT_FOR_CORPUS/.supervisor/jobs/in-progress"
CORPUS_FOUND=0
for d in $CORPUS_DIRS; do [ -d "$d" ] && CORPUS_FOUND=1; done

if [ "$CORPUS_FOUND" != 1 ]; then
  skip "local corpus sweep: .supervisor/jobs/{done,in-progress}/ not present (gitignored, expected absent in CI/fresh clone) — skipping, not a failure"
else
  CORPUS_OUT=$(node -e "
    const fs = require('fs');
    const path = require('path');
    const { parseBrief } = require(process.argv[1]);
    const dirs = process.argv.slice(2);
    let total = 0, thrown = 0;
    const throwList = [];
    for (const dir of dirs) {
      if (!fs.existsSync(dir)) continue;
      for (const f of fs.readdirSync(dir)) {
        if (!f.endsWith('.md')) continue;
        const p = path.join(dir, f);
        const text = fs.readFileSync(p, 'utf8');
        if (!/^\s*(provides|requires):/m.test(text)) continue;
        total++;
        try {
          parseBrief(text);
        } catch (e) {
          thrown++;
          throwList.push(f + ' :: ' + e.message.split('\n')[0].slice(0, 140));
        }
      }
    }
    console.log('CORPUS_TOTAL=' + total);
    console.log('CORPUS_THROWN=' + thrown);
    throwList.forEach((l) => console.log('CORPUS_THROW_DETAIL: ' + l));
  " "$DIST" $CORPUS_DIRS 2>&1)
  echo "$CORPUS_OUT" | grep -v '^CORPUS_TOTAL=\|^CORPUS_THROWN=' | while IFS= read -r line; do [ -n "$line" ] && echo "  $line"; done
  CORPUS_TOTAL=$(echo "$CORPUS_OUT" | grep '^CORPUS_TOTAL=' | cut -d= -f2)
  CORPUS_THROWN=$(echo "$CORPUS_OUT" | grep '^CORPUS_THROWN=' | cut -d= -f2)
  if [ -n "$CORPUS_THROWN" ] && [ "$CORPUS_THROWN" = 0 ]; then
    pass "local corpus sweep: parseBrief threw on 0/$CORPUS_TOTAL contract-bearing briefs in .supervisor/jobs/"
  else
    # NOT a hard failure of this committed suite: a genuinely malformed brief in the local,
    # uncommitted job corpus (e.g. free-text provides/requires values with no {kind,path}
    # structure — a real authoring defect, not a parser bug) is expected to keep throwing, and
    # this sweep has no way to distinguish that from a real regression. Reported loudly as a
    # named exception rather than silently passed or hard-failed.
    echo "NOTE: local corpus sweep found $CORPUS_THROWN/$CORPUS_TOTAL contract-bearing briefs still throwing (see CORPUS_THROW_DETAIL lines above) — investigate each by name before assuming regression; a known one is 2026-07-18-sdk-runner-token-levers.md (free-text provides/requires values, not {kind,path} items — a genuine brief defect)."
  fi
fi

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# `from:` reference forms. A dropped edge is INVISIBLE to the contractless guard
# (provides/lanes parse fine, so nothing throws) while the wave scheduler reads an
# undefined `from` as NO dependency and launches every dependent in wave 1. Prefix
# drift has bitten this parser repeatedly, so both arms are pinned: every accepted
# spelling must RESOLVE, and an unrecognised one must THROW rather than drop.
# ---------------------------------------------------------------------------
_mk_from_brief() {  # $1 = the from: value, verbatim
  cat <<EOF
## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | A | 1 | x | LAUNCHABLE |
| 2 | B | 1 | x | BLOCKED (by #1) |

### Subtask contracts

\`\`\`yaml
subtask_1:
  provides:
    - {kind: file, path: a.ts}
  requires: []
  lanes: ["a.ts"]
subtask_2:
  provides:
    - {kind: file, path: b.ts}
  requires:
    - {from: $1, kind: file, path: a.ts}
  lanes: ["b.ts"]
\`\`\`
EOF
}

for _form in '"subtask_1"' 'subtask_1' '"1"' '1' 'S1' '"ST1"'; do
  _brief="$(_mk_from_brief "$_form")"
  if printf '%s' "$_brief" | node -e "
    const { parseBrief } = require(process.argv[1]);
    let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
      const r = parseBrief(t);
      const dep = r.subtasks.find(s => s.id === '2');
      const from = dep && dep.requires[0] && dep.requires[0].from;
      if (from !== '1') { console.error('from resolved to ' + JSON.stringify(from) + ', wanted \"1\"'); process.exit(1); }
    });
  " "$SPIKE_DIR/dist/runner.js" 2>/dev/null; then
    pass "parseBrief: from: $_form resolves to subtask id 1 (edge NOT dropped)"
  else
    fail "parseBrief: from: $_form did NOT resolve to id 1 — a silently dropped edge schedules the dependent into wave 1"
  fi
done

# An unrecognised `from:` spelling must FAIL CLOSED, never silently drop the edge.
_brief_bad="$(_mk_from_brief '"totally_unknown_form"')"
if printf '%s' "$_brief_bad" | node -e "
  const { parseBrief } = require(process.argv[1]);
  let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
    try { parseBrief(t); process.exit(1); } catch (e) { process.exit(0); }
  });
" "$SPIKE_DIR/dist/runner.js" 2>/dev/null; then
  pass "parseBrief: an unparseable from: value throws (fails closed, never a dropped edge)"
else
  fail "parseBrief: an unparseable from: value did NOT throw — the edge would be silently dropped"
fi

# ---------------------------------------------------------------------------
# CONTRACT-VALUE SHAPE MATRIX. Every shape a contract value can take, asserted in ONE
# table so a branch cannot be hardened in isolation.
#
# WHY A MATRIX: the fail-closed guard was first written inside the bracketed-inline branch
# only, so `requires: [free text]` threw while the non-bracketed twin `requires: free text`
# silently dropped the edge and scheduled the dependent into wave 1 -- the exact failure the
# guard exists to stop. A single-shape test passed. Coverage asymmetry across branches is
# invisible unless the shapes are enumerated together, so they are.
#
# Columns: <label> | <yaml body for subtask_2> | throw|nothrow
# ---------------------------------------------------------------------------
_shape_brief() {  # $1 = subtask_2 body
  cat <<EOF
## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | A | 1 | x | LAUNCHABLE |
| 2 | B | 1 | x | LAUNCHABLE |

### Subtask contracts

\`\`\`yaml
subtask_1:
  provides:
    - {kind: file, path: a.ts}
  requires: []
  lanes: ["a.ts"]
subtask_2:
$1
\`\`\`
EOF
}

_shape_case() {  # $1 label  $2 body  $3 expect(throw|nothrow)
  _sc_out=0
  printf '%s' "$(_shape_brief "$2")" | node -e "
    const { parseBrief } = require(process.argv[1]);
    let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
      try { parseBrief(t); process.exit(0); } catch (e) { process.exit(3); }
    });
  " "$SPIKE_DIR/dist/runner.js" 2>/dev/null || _sc_out=$?
  if [ "$3" = "throw" ]; then
    if [ "$_sc_out" -eq 3 ]; then pass "shape matrix: $1 -> throws (fail-closed)"
    else fail "shape matrix: $1 -> did NOT throw; an unverifiable contract silently schedules the subtask into wave 1"; fi
  else
    if [ "$_sc_out" -eq 0 ]; then pass "shape matrix: $1 -> parses (legitimate shape, not flagged)"
    else fail "shape matrix: $1 -> threw on a LEGITIMATE shape (false positive aborts a valid brief)"; fi
  fi
}

# --- unverifiable values: MUST fail closed, in EVERY shape ---
_shape_case "non-bracketed prose" \
  '  provides: updated docs
  requires: the output of subtask 1' throw
_shape_case "bracketed prose" \
  '  provides: [updated docs]
  requires: [the output of subtask 1]' throw
_shape_case "prose on provides only" \
  '  provides: some description
  requires: []
  lanes: ["b.ts"]' throw

# --- legitimate values: MUST parse ---
_shape_case "multi-line brace items" \
  '  provides:
    - {kind: file, path: b.ts}
  requires: []
  lanes: ["b.ts"]' nothrow
_shape_case "inline brace items" \
  '  provides: [{kind: file, path: b.ts}]
  requires: []
  lanes: ["b.ts"]' nothrow
_shape_case "explicit all-empty (coordination-only)" \
  '  provides: []
  requires: []
  lanes: []' nothrow
_shape_case "block-form lanes" \
  '  provides:
    - {kind: file, path: b.ts}
  requires: []
  lanes:
    - "b.ts"' nothrow

# ---------------------------------------------------------------------------
# PINNED LIMITATION: the `# Subtask N` id-anchor is FENCE-ONLY.
#
# The generic un-fenced heading-terminator in parseBrief (`!inYaml && /^#{1,4}\s+/`)
# matches a single `#` too, so an un-fenced `# Subtask N` line always hits that
# terminator and `continue`s before reaching the id-anchor match below it. That is
# BY CONSTRUCTION, not by intent, and it is harmless today: Launch Pad only ever
# writes this form inside a ```yaml fence, and a brief authored the un-fenced way
# fails CLOSED on the contractless guard (throws) rather than silently scheduling
# every subtask into wave 1.
#
# Pinned rather than left implied because reordering those two checks would silently
# change the behavior in EITHER direction, and neither direction is self-announcing:
# a future editor who makes the un-fenced form parse should see this assertion flip
# and update the parser comment deliberately, not discover it by accident.
# ---------------------------------------------------------------------------
_unfenced_anchor_brief() {
  cat <<'EOF'
## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | A | 1 | x | LAUNCHABLE |
| 2 | B | 1 | x | LAUNCHABLE |

### Subtask contracts

# Subtask 1
provides:
  - {kind: file, path: a.ts}
lanes:
  - "a.ts"

# Subtask 2
provides:
  - {kind: file, path: b.ts}
requires:
  - {from: "1", kind: file, path: a.ts}
lanes:
  - "b.ts"
EOF
}

_ufa_out=0
printf '%s' "$(_unfenced_anchor_brief)" | node -e "
  const { parseBrief } = require(process.argv[1]);
  let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
    try { parseBrief(t); process.exit(0); } catch (e) { process.exit(3); }
  });
" "$SPIKE_DIR/dist/runner.js" 2>/dev/null || _ufa_out=$?
if [ "$_ufa_out" -eq 3 ]; then
  pass "un-fenced \`# Subtask N\` is fence-only — fails CLOSED (throws), never a silent all-wave-1 schedule"
else
  fail "un-fenced \`# Subtask N\` no longer fails closed (rc=$_ufa_out) — parseBrief's id-anchor comment says this form is fence-only; if that changed deliberately, update the comment AND this assertion together"
fi

# ---------------------------------------------------------------------------
# LEGACY-BRIEF CARVE-OUT (v15.20.0 review round 2).
#
# `agents/plan-reviewer.md` Criterion 12 exempts a brief carrying an explicit top-level
# `legacy_brief: true` marker from the provides:/requires: mandate, and Criterion 16
# "shares that same gate". The fail-closed guard shipped without that carve-out and hard-
# threw on the archived `2026-07-07-stackpack-mysql-mcp-spinoff.md` — a shape this repo's
# own plan gate had declared legal — while telling the operator to fix a contracts anchor
# that legitimately does not exist. Both directions are asserted: the marker must exempt,
# and its ABSENCE must still fail closed (the carve-out must not become a blanket bypass).
# The `- **legacy_brief:** true` spelling is the one real briefs actually use; the bare
# `legacy_brief: true` form is what the Criterion 12 prose documents.
_legacy_brief() {
  cat <<EOF
# Legacy Brief

## Environment
$1

## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | A | 1 | x | LAUNCHABLE |
| 2 | B | 1 | x | LAUNCHABLE |
EOF
}

_parses() {
  printf '%s' "$1" | node -e "
    const { parseBrief } = require(process.argv[1]);
    let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
      try { parseBrief(t); process.exit(0); } catch (e) { process.exit(3); }
    });
  " "$SPIKE_DIR/dist/runner.js" 2>/dev/null
}

for _marker in '- **legacy_brief:** true' 'legacy_brief: true'; do
  _lb_out=0
  _parses "$(_legacy_brief "$_marker")" || _lb_out=$?
  if [ "$_lb_out" -eq 0 ]; then
    pass "legacy_brief carve-out: contract-free brief marked \`$_marker\` parses (Criterion 12's sanctioned shape is not aborted)"
  else
    fail "legacy_brief carve-out: \`$_marker\` still throws (rc=$_lb_out) — the fail-closed guard must exempt the marker Plan Reviewer Criterion 12 exempts"
  fi
done

_lb_neg=0
_parses "$(_legacy_brief '- **legacy_brief:** false')" || _lb_neg=$?
if [ "$_lb_neg" -eq 3 ]; then
  pass "legacy_brief carve-out is NOT a blanket bypass — \`false\` (and any unmarked brief) still fails closed"
else
  fail "legacy_brief carve-out leaked: a brief marked \`false\` with no contracts parsed (rc=$_lb_neg) — the guard must still throw on a genuine parse miss"
fi

# ---------------------------------------------------------------------------
# BARE KEY + PROSE, and BARE SUBTASK REFERENCES (bot-review round 3).
#
# Two shapes the fail-closed guard did not cover, both the same silent-empty-graph class this
# parser already fails closed on four other ways:
#   (a) `requires:` as a BARE key followed by unstructured PROSE lines. Only an inline value was
#       recorded as "claimed to declare something", so nothing ever marked it unparseable —
#       `sawContractKey` said "declared", `requires` stayed `[]`, and the wave scheduler read the
#       dependency as vacuously satisfied. MUST THROW.
#   (b) `requires:` followed by BARE dash references (`- subtask_1`, `- 1`, `- S2`). Only the
#       `- {...}` brace form was parsed, so these produced `requires: []` SILENTLY — measured on
#       two archived briefs (`2026-06-02-preflight-sync-gate.md`,
#       `2026-06-06-auto-pr-review-heal.md`), which at the time parsed to ZERO dependency edges
#       and scheduled every subtask into wave 1. MUST PARSE, with the edges recovered — throwing
#       here would be wrong; the brief did declare an ordering, the parser just could not read it.
# ---------------------------------------------------------------------------
_bare_brief() {   # $1 = the requires: block body, verbatim
  cat <<EOF
# Bare Key Fixture

## Subtask Structure

| # | Title | Est. Files | Skills | Status |
|---|-------|-----------|--------|--------|
| 1 | A | 1 | x | LAUNCHABLE |
| 2 | B | 1 | x | BLOCKED |

### Subtask contracts

\`\`\`yaml
subtask_1:
  provides:
    - {kind: file, path: a.ts}
  requires: []
  lanes:
    - "a.ts"
subtask_2:
  provides:
    - {kind: file, path: b.ts}
$1
  lanes:
    - "b.ts"
\`\`\`
EOF
}

# (a) bare key + prose -> must FAIL CLOSED
_bk_rc=0
printf '%s' "$(_bare_brief '  requires:
    the output of subtask 1, described in prose
    across multiple lines with no dash-brace syntax')" | node -e "
  const { parseBrief } = require(process.argv[1]);
  let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
    try { parseBrief(t); process.exit(0); } catch (e) { process.exit(3); }
  });
" "$SPIKE_DIR/dist/runner.js" 2>/dev/null || _bk_rc=$?
if [ "$_bk_rc" -eq 3 ]; then
  pass "bare \`requires:\` key followed by PROSE fails CLOSED (a bare key claims items; yielding none is unparseable, not 'declared nothing')"
else
  fail "bare-key+prose did NOT fail closed (rc=$_bk_rc) — \`requires\` stays [] and the wave scheduler reads the dependency as vacuously satisfied, scheduling a BLOCKED subtask into wave 1"
fi

# (b) bare dash references -> must PARSE, and the edge must be RECOVERED
_br_out="$(printf '%s' "$(_bare_brief '  requires:
    - subtask_1   # gate semantics')" | node -e "
  const { parseBrief } = require(process.argv[1]);
  let t=''; process.stdin.on('data',d=>t+=d).on('end',()=>{
    try {
      const r = parseBrief(t);
      const st2 = r.subtasks.find(s => s.id === '2');
      console.log(JSON.stringify({edges: st2.requires.length, from: st2.requires[0] && st2.requires[0].from}));
    } catch (e) { console.log('THREW'); }
  });
" "$SPIKE_DIR/dist/runner.js" 2>/dev/null)"
if [ "$_br_out" = '{"edges":1,"from":"1"}' ]; then
  pass "bare \`- subtask_1\` reference under \`requires:\` parses into a real dependency edge (from=1) — the shape two archived briefs use, previously dropped silently"
else
  fail "bare subtask reference not recovered: got [$_br_out], expected {\"edges\":1,\"from\":\"1\"} — an unparsed edge here is a silently-wrong SCHEDULE, not a visible error"
fi

printf '\n%s\n' "digest-lanes.test.sh: $FAILURES failure(s)"
[ "$FAILURES" = 0 ] || exit 1
exit 0
