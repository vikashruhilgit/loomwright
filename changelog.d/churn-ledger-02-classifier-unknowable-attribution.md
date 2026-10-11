<!-- bump: patch -->
/pr-postmortem stops booking phantom and no-evidence rounds as flow_stage unknowable
Two classifier causes behind the 18 `convention_mismatch`/`unknowable` churn-ledger entries are fixed.
First, `pr-postmortem-gather.sh` no longer counts a PR's first commit as a review-fix round: `commits[0].is_review_fix`
is always `false`, because no review can precede the commit that opened the PR, so a feature commit whose subject
mentions self-heal no longer books a phantom round. The exclusion is by array position inside the existing single jq
build; `review_fix_re` and `agent_commit_re` are unchanged, so a later self-heal fix commit still counts.
Second, `skills/pr-postmortem/SKILL.md` Step 3 now attributes a residual round from a concrete review-fix headline
or omits it from `categories[]` and `flow_stages`. A round whose only evidence is a bot verify comment and "a push
followed" is never classified `unknowable` again; `unknowable` is reserved for a concrete finding whose stage cannot
be told. `categories[]` may now hold fewer entries than `review_rounds`, and on `/pr-postmortem` lines the
`flow_stages` values sum to its length. The four `flow_stages` keys and `schema_version: 1` are unchanged.
The command doc and the POSTMORTEM_RESULT schema doc restate the new rule, and `test-pr-postmortem-gather.sh` case 13
pins the first-commit exclusion. Existing ledger lines keep their old entries.
