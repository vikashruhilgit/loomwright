<!-- bump: patch -->
Detached review drain: close the GraphQL merge path and make its pinned allowlist actually work
A live `claude -p --permission-mode dontAsk` probe of the drain's pinned `--allowedTools` (dispatch-pr-review.sh
`build_allowed_tools`) found it never worked. `Bash(gh api repos/*:*)` matched nothing, because a `*` before the legacy
trailing `:*` is a literal character, so the drain could not read issue comments or check annotations. There was no
Write/Edit entry, so the fix worker could not change a file and every drain ended ESCALATED. No plugin script
was admitted, and the push rule (`git push origin <ref>:*`) never matched the `git push origin HEAD:<ref>` that
review-heal prescribes. `Bash(gh api graphql:*)` did match, and it admits a `mergePullRequest` mutation, which a
prompt injection in a PR comment could have used to merge around the single sanctioned merge executor. The drain
now gets no raw `gh api` at all. Its GitHub reads go through the new `drain-gh-read.sh`, whose four operations are
read-only by construction (fixed GET endpoints, a fixed GraphQL query, validated identifiers, gh's own exit status).
Write/Edit are scoped to the drain worktree, with `.git`, `.claude/` and `.mcp.json` denied. The push rule is exact,
so no extra refspec and no `--force` can ride along. Each drain script gets its own absolute-path rule, and
`automate-helpers.sh` is admitted only for `escalation-cause`, never `gate-eval`. The rule shapes are the ones the
probe showed the CLI honours (`scripts/fixtures/drain-allowlist-probe.json`). The test that used to pin the broken
string now checks those shapes and fails when the drain prose names a script the allowlist does not admit.
