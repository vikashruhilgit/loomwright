# Evidence — code-review telemetry counts every severity and category (af/15)

Real output from this repository, captured 2026-10-24 on branch `feature/af15-telemetry-count-pins` (base
`237adab`). Nothing below is hand-written except the prose and the headings. The run is sandboxed: a
`mktemp -d` scratch dir holds a fake `HOME` (user-scope `egress.json` only), a scratch git repo used as the
working directory, and a recording `gh` stub first on `PATH`. The core runs with `--dry-run`, so it never
calls `gh`, and the stub's call count proves it. Every finding in the fixture carries placeholder text only.

## Command (run from the repo root)

```bash
bash <<'SH'
set -u
CORE="$PWD/loomwright/scripts/send-telemetry-core.sh"
T="$(mktemp -d)"; mkdir -p "$T/home/.claude/loomwright" "$T/repo" "$T/bin"; : > "$T/gh.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/gh.log"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
printf '{"schema_version":1,"repos":{"x/y":{"telemetry":"always_allow","telemetry_repo":"example/sink"}}}' \
  > "$T/home/.claude/loomwright/egress.json"
git -C "$T/repo" init -q; git -C "$T/repo" remote add origin https://github.com/x/y.git
git -C "$T/repo" -c user.email=t@e.invalid -c user.name=t commit -q --allow-empty -m init
python3 - "$T/mixed.json" <<'PY'
import json, sys
L = ["Review done.", "", "```yaml", "CODE_REVIEW_RESULT:", "  schema_version: 3",
     "  review_mode: diff_review", "  audit_focus: []", "  trigger_paths_detected: []",
     "  scope_expanded: []", "  files_checked: [placeholder]", "  decision: FAIL", "  issues:"]
for sev, cat in (("HIGH", "new"), ("MEDIUM", "new"), ("LOW", "new"), ("LOW", "nit")):
    L += ["    - severity: %s" % sev, "      category: %s" % cat,
          "      file: placeholder", "      description: placeholder finding"]
L += ["  summary: review", "```"]
json.dump({"session_id": "s", "agent_id": "a", "agent_type": "loomwright:loomwright:code-reviewer",
           "result_block": "\n".join(L)}, open(sys.argv[1], "w"))
PY
( cd "$T/repo" && HOME="$T/home" PATH="$T/bin:$PATH" bash "$CORE" --dry-run < "$T/mixed.json" 2>&1 ) \
  | sed -n '/"issues": {/,/^  },$/p; /"issues_by_category": {/,/^  },$/p; /^WOULD_EXIT=/p'
echo "gh_stub_calls=$(wc -l < "$T/gh.log" | tr -d ' ')"
rm -rf "$T"
SH
```

## Output

```text
  "issues": {
    "blocking": 0,
    "high": 1,
    "low": 2,
    "medium": 1,
    "unspecified": 0
  },
  "issues_by_category": {
    "drift": 0,
    "new": 3,
    "nit": 1,
    "other": 0,
    "pre_existing": 0
  },
WOULD_EXIT=0
gh_stub_calls=0
```

The `"issues"` object is the core's `issues_by_severity`. Raw Data ships it under that key. The fixture holds
HIGH `new`, MEDIUM `new`, LOW `new` and LOW `nit` findings, and each one is counted under both its severity and
its category. The stub recorded no call.

## The pins catch the regression

`test-telemetry-threads.sh` T2 asserts the same five counts on the same fixture shape. T8 mutant (e) swaps the
`count-from-parsed-findings` block for one that counts only BLOCKING/HIGH severities. That was the effective
behaviour from 5d9f7a2 until ee5b1e7: the count read the rendered `## Issues Detected` lines, and only
BLOCKING/HIGH findings are rendered there (the `mixed` run renders just `- [HIGH] new finding`). Under that mutant the dry-run still exits `0` and keeps `"high": 1`, but `"medium": 1` and
`"low": 2` are gone, so the `assert_not_match` controls pass. Each one-line mutation in the brief's Pin
mutations table was also applied to a scratch copy of the core, and each one turned red the T2 `mixed` pin it
targets:

```text
issues_by_severity[sev] += int(sev not in ("blocking", "high"))
FAIL  T2_mixed_high_counted  needle='"high": 1' not found
issues_by_severity[sev] += int(sev in ("blocking", "high"))
FAIL  T2_mixed_medium_counted  needle='"medium": 1' not found
FAIL  T2_mixed_low_counted  needle='"low": 2' not found
(issues_by_category[cat] += 1 deleted)
FAIL  T2_mixed_new_category_counted  needle='"new": 3' not found
FAIL  T2_mixed_nit_category_counted  needle='"nit": 1' not found
```

## The deleted Rubric B branch was unreachable

The same sandbox ran a `PASS` review with two `new` MEDIUM findings (the input of TELEMETRY.md's old Rubric B
worked example) once through the base core (`237adab`, dead `elif` still present) and once through the branch
core. Both printed the same line:

```text
filter_skipped reason=interest_filter score=9 status=pass
```

So the `base = 7.0` branch never ran, and the doc's old "base `7`, bucket `medium`" was wrong before this
change. The branch keeps the score and corrects the doc. The test-telemetry.sh goldens are byte-identical
(`git diff --stat loomwright/scripts/telemetry-fixtures/` is empty).
