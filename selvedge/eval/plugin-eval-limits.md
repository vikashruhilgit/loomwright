# `claude plugin eval` — the two reported limits, re-checked

Checked on 2026-11-21 with **Claude Code 2.1.329** (`claude --version` → `2.1.329 (Claude Code)`),
macOS, against a throwaway probe plugin (`{"name": "pe-probe", "version": "0.0.1"}`) in a scratch
directory, never against Selvedge itself. Every command below was run from inside that probe
plugin's directory (`.` is the target). Home-directory paths in outputs are shown as `~`.

| Limit | Result |
|---|---|
| 1. No custom-code graders (a grader cannot run your own script) | **confirmed** |
| 2. The run's sandbox cannot read the browser cache under `~` | **confirmed** |

## 1. No custom-code graders — confirmed

A case whose grader asks for a script type, `evals/codegrader/graders/code.md`:

```markdown
---
type: script
weight: 1
command: node check.mjs
---

exit 0 means pass
```

Command:

```bash
claude plugin eval . --case codegrader --runs 1 --ablation none --no-publish --max-cost-usd 0.05 --trust-plugin
```

Output (the case is refused at load, before any model run):

```
✗ <scratch>/p/evals/codegrader: invalid case.yaml:   graders.0.type: Invalid discriminator value. Expected 'regex' | 'tool_order' | 'tool_used' | 'file_exists' | 'llm' | 'baseline'

CASE  SCORE PASS% RUNS COST    NOTES

0 case(s) · 0s · $0.00

Couldn't load 1 case file — see above.
```

The grader types are a closed list of six, none of which runs author code. The only author code a
suite can run is a case's `scaffold_script`, which sets a case up (off unless `--scaffold`) and
does not score it.

## 2. The sandbox cannot read the browser cache under `~` — confirmed

On the host, `~/Library/Caches/ms-playwright/` exists and holds `chromium-1255`,
`chromium_headless_shell-1255`, `ffmpeg-1013` (and more).

Case `evals/cache/prompt.md` (front matter `max_turns: 4`, `allowed_tools: [Bash]`) asks the model
to run one command and echo its output; the grader is `type: regex`, `pattern: "chromium-1255"`.

**a. Through `$HOME`.** Prompt command: `ls -la "$HOME/Library/Caches/ms-playwright/" ; echo "exit=$?"`.

```bash
claude plugin eval . --case cache --runs 1 --ablation none --no-publish --max-cost-usd 0.25 --trust-plugin --allow-tools Bash --model haiku --keep-temp --json <scratch>/cache-result.json
```

The run gets its own temporary `HOME`, so the real cache is not where `~` points (tool result from
the kept trace, `out/trace.jsonl`):

```
ls: /private/tmp/e-thdjGH/home/Library/Caches/ms-playwright/: No such file or directory
exit=1
```

**b. By absolute path.** Same command line; the prompt names the real home directory's cache by
its absolute path: `ls -la "~/Library/Caches/ms-playwright/" ; echo "exit=$?"` (with `~` written
out in full). Tool result:

```
ls: ~/Library/Caches/ms-playwright/: Operation not permitted
total 0
exit=1
```

Both runs scored 0 (`pattern not found in last_message`), cost under $0.01 each, and exited 1. The
`--keep-temp` notice also states the shape of the sandbox: `home/ and tmp/ in it were written by
the plugin under test and are sealed`.

## For item 08

Item 08 may **not** use `claude plugin eval` for its optional with/without-plugin comparison as
things stand: Selvedge's runs need the Playwright browsers in the home-directory cache, which the
eval sandbox refuses (limit 2), and scoring a verdict against a known answer needs a code grader
the eval does not offer (limit 1) — re-check both on a newer CLI before planning on it.
