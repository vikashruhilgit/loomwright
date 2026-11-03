# Validation gate accepts committed evidence with a declared verdict (Validation 4)

**What this proves:** `validation-gate` reads this file as the evidence for the item's Validation 4 (its one
"Running system" step) through the declared line below. It needs no PR-body evidence and no `--waive`, and its `ok`
line names this file. Without the declared line, the same file evidences nothing: the gate's `unrun` line names the
file as having no declared verdict and says what to add.

Verdict: PASS for Validation 4

**How it was run:** a hermetic replay of the branch's gate, before the PR existed. The item is this story's
requirement file (`.supervisor/requirements/2026-11-03-064334-validation-gate-accepts-committed-evidence-with-a-declared-verdict.md`),
whose `## Validation` section has four steps, V4 the Running system one. A stub `gh` stands in for the PR. Its body
has no V4 passage. Its changed-file list is the branch's diff against base `18f857b` plus untracked files. The
`docs/evidence/` listing and every raw read come from the worktree, so the gate reads this file's own bytes. PR
number `0` is a placeholder. The output was produced after this file was written; re-running the replay on the
committed file prints the same lines.

**Honest limit:** this is the replay, not the live READY park. The running-system proof is the gate on this item's
real PR at its `/automate` READY park: `validation-gate: ok` naming this file, with no `validation waived` line in
the run file's `## Progress`.

## Exact command

`bash replay-v4.sh <worktree> <requirement file> [drop-verdict]`:

```bash
#!/usr/bin/env bash
# replay-v4.sh <worktree> <requirement file> [drop-verdict] — validation-gate on this item, its PR served by a stub gh:
# the changed-file list is the branch's diff against its base (plus untracked files), the docs/evidence/ listing and
# every raw read come from the worktree. With `drop-verdict` the stub serves the evidence file minus its Verdict: line.
set -u
WT="$1"; REQ="$2"; DROP="${3:-}"; BASE=18f857b8816f4ce5d2e5aaef84fe8683249c6263
R="$(mktemp -d)"; trap 'rm -rf "$R"' EXIT
SHA="$(git -C "$WT" rev-parse HEAD)"; PR=https://github.com/vikashruhilgit/loomwright/pull/0
mkdir -p "$R/.supervisor/automate"; cp "$REQ" "$R/item.md"
printf '# Automate Run: replay\n## Progress\n- picked item.md\n' > "$R/.supervisor/automate/replay.md"
{ git -C "$WT" diff --name-only "$BASE"; git -C "$WT" ls-files --others --exclude-standard; } | sort -u > "$R/changed"
printf '## Summary\nThe validation gate reads declared evidence files.\n\n## Evidence\n- docs/evidence/validation-gate-declared-verdict.md\n' > "$R/body"
cat > "$R/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$R/calls"
case "\$*" in
  "pr view $PR --json body") jq -n --rawfile b "$R/body" '{body: \$b}' ;;
  "pr view $PR --json headRefOid,files") jq -n --rawfile c "$R/changed" --arg s "$SHA" '{headRefOid: \$s, files: [\$c | split("\n")[] | select(. != "") | {path: .}]}' ;;
  "api repos/vikashruhilgit/loomwright/contents/docs/evidence?ref=$SHA")
    for f in "$WT"/docs/evidence/*; do jq -n --arg n "\${f##*/}" '{name: \$n, path: ("docs/evidence/" + \$n), type: "file"}'; done | jq -s . ;;
  "api -H Accept: application/vnd.github.raw repos/vikashruhilgit/loomwright/contents/"*"?ref=$SHA")
    p="\${4#repos/vikashruhilgit/loomwright/contents/}"; p="\${p%%\?*}"
    if [ -n "$DROP" ]; then sed '/^Verdict: /d' "$WT/\$p"; else cat "$WT/\$p"; fi ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$R/gh"
LOOMWRIGHT_GH_BIN="$R/gh" bash "$WT/loomwright/scripts/automate-lanes.sh" validation-gate "$R/.supervisor/automate/replay.md" item.md "$PR"
echo "exit $?"
sed "s/$SHA/<head>/" "$R/calls"
```

## Output: this file as committed

```
$ bash replay-v4.sh <worktree> <requirement file>
validation-gate: ok — 1 running-system step(s) evidenced (V4 in docs/evidence/validation-gate-declared-verdict.md)
exit 0
gh pr view https://github.com/vikashruhilgit/loomwright/pull/0 --json body
gh pr view https://github.com/vikashruhilgit/loomwright/pull/0 --json headRefOid,files
gh api repos/vikashruhilgit/loomwright/contents/docs/evidence?ref=<head>
gh api -H Accept: application/vnd.github.raw repos/vikashruhilgit/loomwright/contents/docs/evidence/validation-gate-declared-verdict.md?ref=<head>
```

## Output: the same file with its Verdict: line removed (`drop-verdict`)

```
$ bash replay-v4.sh <worktree> <requirement file> drop-verdict
validation-gate: unrun — V4 Running system — a real READY park with no waiver: no evidence in the PR body; no changed docs/evidence/ file declares Validation 4 (docs/evidence/validation-gate-declared-verdict.md: no declared verdict line) — add `Verdict: PASS for Validation 4` and the fenced output to the step's docs/evidence/ file in this PR
exit 0
gh pr view https://github.com/vikashruhilgit/loomwright/pull/0 --json body
gh pr view https://github.com/vikashruhilgit/loomwright/pull/0 --json headRefOid,files
gh api repos/vikashruhilgit/loomwright/contents/docs/evidence?ref=<head>
gh api -H Accept: application/vnd.github.raw repos/vikashruhilgit/loomwright/contents/docs/evidence/validation-gate-declared-verdict.md?ref=<head>
```
