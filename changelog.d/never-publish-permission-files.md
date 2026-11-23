<!-- bump: minor -->
The publish guard refuses to push Claude Code permission files or a secret saved in one
Claude Code saves each "don't ask again" answer as an allow rule in `.claude/settings.local.json`, so a rule
for a command with a token in it stores the token. Until now a worker could force-add that file, commit it
and push it: the publish guard never looked at which files were going out, and CI had no check. The publish
guard (`guard-finalize-publish.sh`) now runs a new checker, `check-permission-files.sh`, on every
`git push` and `gh pr create` it detects, in every session, whether or not a Loomwright run is live. It
denies the publish when a commit that would go out, or a staged change, adds a `.claude/settings.local.json`
at any depth, or a `.claude/settings.json` holding a value shaped like a secret. When the same command also
commits before it pushes, it judges the files on disk too. The refusal names the commit, the path and the
secret's shape, never the secret. A missing checker denies, and there is no opt-out. CI runs the same
checker over the tracked tree. This is a permission-file check, not a general secret scanner.
