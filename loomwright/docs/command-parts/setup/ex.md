## Examples

```
$ /setup
## /setup — module status
| Module        | Status                          | Configure with       |
| observability | not configured                  | /setup observability |
| telemetry     | enabled (target=acme/agents)    | /setup telemetry     |
...
[AskUserQuestion multi-select] → observability
[... full local init flow runs, smoke test passes ...]
Setup: observability configured (local Langfuse, 7/7 healthy, smoke trace landed). Restart Claude Code sessions to start emitting.
```

```
$ /setup observability status
[mode: local stack · env block: 8/8 keys · containers: 7/7 healthy · Langfuse health: OK]
Setup: observability healthy (local stack); dashboard at http://localhost:3000.
```
