<!-- bump: patch -->
Scrub-safe brief template: home-relative `Project:` line and no home-path examples
In branch mode a brief that followed the Supervisor-Ready Brief template made the lane's whole trail push fail, because its `- **Project:** {absolute path}` line put an absolute home path into the done brief and `meta-sync.sh push` fails CLOSED (exit 2) on the `home_path` scrub rule.
The template in `skills/supervisor-readiness/SKILL.md` now asks for the home-relative form (`~/...` under `$HOME`, else the repo directory name) and states the rule for the whole brief, because the scrub reads the whole file and not one field.
Launch Pad Phase 5 PACKAGE carries the same one-sentence rule as action 3b, so the brief author sees it at assembly time.
Every `/Users/<name>/...` example in the agent, command and skill prompts (launch-pad, orchestrator, supervisor, code-reviewer, product-owner, agent-output) is rewritten to a `~/...` form, so `grep -rn '/Users/name' loomwright/agents loomwright/commands loomwright/skills` returns nothing.
A brief rendered from the updated template was rehearsed through `meta-sync.sh push --root <scratch clone>` against a local bare remote and pushed with exit 0, while a control brief carrying the old absolute form was refused with exit 2.
