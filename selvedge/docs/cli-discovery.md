# CLI discovery: does a plugin's `bin/` reach `PATH`?

Measured 2026-11-13 on macOS with Claude Code `2.1.319`, from the qa-split/01 worktree
(`/Users/vikashruhil/Documents/work/AI/ai-agent-manager-qa-split-01-1`).

## Answer

| Load mechanism | `selvedge/bin` on the Bash tool's `PATH`? |
|---|---|
| Desktop app — explicit `--plugin-dir <path>` on the session's command line | **yes** (measured below) |
| Installed CLI — implicit load from user-scope `enabledPlugins` | **unverified** (the scratch config could not log in; owner-runnable command below) |

**`install-cli` is REQUIRED**, not optional: it is optional only when both cases are measured
`yes`, and the installed-CLI case is not measured. The README says so.

The `install-cli` link points at one installed copy's real path, in a per-release folder of the
plugin cache, so it must be re-run after every plugin update: otherwise it keeps running the old
CLI and breaks once that folder is cleaned up. Because `~/.local/bin` usually comes before the
plugin's own `bin/` on `PATH` (Case 1 below), a stale link also shadows the updated plugin's CLI.
`install-cli` prints this reminder each time it runs, and the README says so.

Background (project memory `desktop-vs-cli-plugin-install-location`): the desktop app loads a
plugin by passing an explicit `--plugin-dir <cache path>` on its own command line, while a bare CLI
session loads installed plugins implicitly from user-scope `enabledPlugins`. They are different
code paths, so one measurement does not stand in for the other.

Precondition for both probes: no other `selvedge` on `PATH`. Checked before probing:

```
$ ls -la ~/.local/bin/selvedge
ls: /Users/vikashruhil/.local/bin/selvedge: No such file or directory
```

## Case 1 — desktop app mechanism (`--plugin-dir`): yes

The desktop app itself was not driven (a worker cannot operate it); its load mechanism, an
explicit `--plugin-dir`, was. The prompt goes on stdin because `--plugin-dir` is variadic and
swallows a trailing prompt argument (`Error: Input must be provided either through stdin or as a
prompt argument when using --print`). The measuring command writes its own output to a file, so
the result below is the shell's output read back from disk, not text relayed by the model.

Command (run from the worktree root; `S` is the session scratch dir
`/private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager/6d16f45f-036c-4434-9abd-1bed7dbf1cc8/scratchpad/spike`):

```
printf '%s\n' "Run exactly this one Bash command, then reply only with the word done: { command -v selvedge; echo \"rc=\$?\"; selvedge --version; echo \"\$PATH\" | tr ':' '\\n' | grep -n selvedge; } > $S/desktop-raw.txt 2>&1" > "$S/prompt2.txt"
claude -p --plugin-dir "$PWD/selvedge" --allowedTools Bash < "$S/prompt2.txt"; echo "exit=$?"
cat "$S/desktop-raw.txt"
```

Full output:

```
done
exit=0
/Users/vikashruhil/Documents/work/AI/ai-agent-manager-qa-split-01-1/selvedge/bin/selvedge
rc=0
selvedge 0.1.0
46:/Users/vikashruhil/Documents/work/AI/ai-agent-manager-qa-split-01-1/selvedge/bin
```

`selvedge/bin` is appended as the LAST `PATH` entry (entry 46 of 46 in an earlier, model-relayed
run of the same probe that printed the whole `PATH`), so an earlier `selvedge` on `PATH` — for
example an `install-cli` link in `~/.local/bin` — wins over it.

## Case 2 — installed CLI (`enabledPlugins`): unverified

Probed only in an isolated scratch config (`CLAUDE_CONFIG_DIR`), never the real one. Install
succeeded; the session could not start because the scratch config has no login and no
environment credential was available (`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and
`ANTHROPIC_AUTH_TOKEN` all unset). Copying the real credentials into the scratch config was
deliberately not done.

Commands (`SC="$S/scratch-config"`, an empty dir; `W` the worktree root):

```
CLAUDE_CONFIG_DIR="$SC" claude plugin marketplace add "$W"
CLAUDE_CONFIG_DIR="$SC" claude plugin install selvedge@atelier --scope user
CLAUDE_CONFIG_DIR="$SC" claude plugin list
cd "$S" && CLAUDE_CONFIG_DIR="$SC" claude -p --allowedTools Bash < "$S/prompt3.txt"; echo "exit=$?"
```

(`prompt3.txt` is `prompt2.txt` with the output file renamed to `installed-raw.txt`.)

Full output:

```
Adding marketplace…✔ Successfully added marketplace: atelier (declared in user settings)
exit=0
Installing plugin "selvedge@atelier"...✔ Successfully installed plugin: selvedge@atelier (scope: user)
exit=0
Installed plugins:

  ❯ selvedge@atelier
    Version: 0.1.0
    Read from: /Users/vikashruhil/Documents/work/AI/ai-agent-manager-qa-split-01-1/selvedge
    Scope: user
    Status: ✔ enabled

exit=0
Not logged in · Please run /login
exit=1
```

The real config was checked unchanged afterwards: the `shasum` of
`~/.claude/plugins/installed_plugins.json`, `~/.claude/plugins/known_marketplaces.json` and
`~/.claude/settings.json`, and the listing of `~/.claude/plugins/cache/`, were identical before
and after.

No plugin already installed in the real config ships a `bin/` directory (`ls
~/.claude/plugins/cache/*/*/*/bin` matched nothing), so the mechanism could not be observed
read-only through another plugin either.

### Owner-runnable check

Pre-merge, isolated (one interactive `/login` in the scratch config):

```
SC="$(mktemp -d)/claude-config"; mkdir -p "$SC"
CLAUDE_CONFIG_DIR="$SC" claude plugin marketplace add "$PWD"          # from the repo root
CLAUDE_CONFIG_DIR="$SC" claude plugin install selvedge@atelier --scope user
CLAUDE_CONFIG_DIR="$SC" claude                                        # run /login, then exit
OUT="$(mktemp)"
printf '%s\n' "Run exactly this one Bash command, then reply only with the word done: { command -v selvedge; echo \"rc=\$?\"; selvedge --version; echo \"\$PATH\" | tr ':' '\\n' | grep -n selvedge; } > $OUT 2>&1" \
  | CLAUDE_CONFIG_DIR="$SC" claude -p --allowedTools Bash
cat "$OUT"
```

Post-merge, in the real config: `/plugin install selvedge@atelier`, then the last three lines
without `CLAUDE_CONFIG_DIR`. Either way, first confirm `command -v selvedge` prints nothing in your
shell (no `install-cli` link yet). A `.../selvedge/bin/selvedge` line with `rc=0` means **yes**;
`rc=1` means **no**. If both cases are `yes`, `install-cli` can be documented as optional (update
this file and the README together).
