<!-- bump: minor -->
classify-risk.sh treats instruction and config file changes as high risk and reads .agent/risk.json from the base ref
A PR that changed the rules it is judged by could pass the `/automate --auto-merge` gate. `CLAUDE.md`, `AGENTS.md`,
`.mcp.json`, `.claude/`, `.agent/rules/`, `.agent/risk.json`, `.agent/verify.json`, `REVIEW.md` and `CLAUDE.local.md`
had no branch in `classify-risk.sh`, so an edit to one of them alone was `high_risk: false`. The project extension
`.agent/risk.json` was also read from `--root`'s working tree, which on the merge path is the PR head, so a PR could
delete a `paths[]` entry and change the guarded path in the same diff. The script now has a `trusted-root` branch
built from one data list. `CLAUDE.md`, `AGENTS.md`, `REVIEW.md` and `CLAUDE.local.md` match by exact basename at any
depth. `.claude/`, `.mcp.json`, `.agent/rules/`, `.agent/risk.json` and `.agent/verify.json` match at the repo root
only. Both sides of a rename are checked, and a name is never matched as a substring. Each match adds a
`trusted-root: <path>` reason. `.agent/risk.json` is now read only from `<base_ref>` with `git show`. A blob that is
present but cannot be read gives `unclassifiable: git_failed` (`null`) and never drops the project's entries silently.
`--kind-table` and the committed risk table in `docs/result-schemas/supervisor-result.md` carry the new row.
`test-classify-risk.sh` adds one case per surface and per rule, commits each `risk.json` variant on its own base
branch, and has an in-suite mutation control for every pinned rule. Any PR that touches a `CLAUDE.md` now parks the
merge gate, this repo's own included.
