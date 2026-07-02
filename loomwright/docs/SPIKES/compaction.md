# Spike A: Compaction Capability Verification

## Question
Does Claude Code support `PreCompact` / `PostCompact` hook events with `type: command` handlers, and does their JSON output (`additionalContext` / `systemMessage` fields) inject context into the resumed session after a compaction operation? (Investigated 2026-05-10 against the upstream hooks reference.)

## Sources Consulted
- https://docs.claude.com/en/docs/claude-code/hooks (official Claude Code Hooks reference) — fetched 2026-05-10
- https://docs.claude.com/en/docs/claude-code/hooks-guide (official Hooks guide) — fetched 2026-05-10
- https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (Claude Code public changelog) — fetched 2026-05-10
- Local plugin file `loomwright/hooks/hooks.json` — read 2026-05-10 to confirm currently-used hook event types (`SubagentStop`, `Stop`, `TaskCompleted`, `WorktreeCreate`, `StopFailure`)

## Findings

The hooks reference documents both events as first-class:

- **`PreCompact`** — *"Runs before Claude Code is about to run a compact operation."* Matchers: `manual` (from `/compact`) and `auto` (auto-compact when the context window is full). Input includes `trigger` and `custom_instructions`. **Supports decision control**: exit code 2 or `{"decision": "block", "reason": "..."}` can block the compaction (the decision-control table lists `PreCompact` in the *"Top-level decision"* group alongside `UserPromptSubmit`, `Stop`, `SubagentStop`, etc.).
- **`PostCompact`** — *"Runs after Claude Code completes a compact operation. Use this event to react to the new compacted state, for example to log the generated summary or update external state."* Same `manual` / `auto` matchers. Input includes `trigger` and `compact_summary` (the conversation summary the compaction produced).

**Critical caveat — PostCompact has no decision control.** The hooks reference states verbatim: *"PostCompact hooks have no decision control. They cannot affect the compaction result but can perform follow-up tasks."* The decision-control summary table groups `PostCompact` with `WorktreeRemove`, `Notification`, `SessionEnd`, `InstructionsLoaded`, `StopFailure`, `CwdChanged`, and `FileChanged` under: *"None — No decision control. Used for side effects like logging or cleanup."*

**Critical caveat — `additionalContext` is NOT delivered for compaction events.** The reference enumerates the events that deliver `additionalContext` / `systemMessage` into Claude's context:
> *"Where the reminder appears depends on the event:*
> - *SessionStart, Setup, and SubagentStart: at the start of the conversation, before the first prompt*
> - *UserPromptSubmit and UserPromptExpansion: alongside the submitted prompt*
> - *PreToolUse, PostToolUse, PostToolUseFailure, and PostToolBatch: next to the tool result"*

`PreCompact` and `PostCompact` are **absent** from this delivery list. There is no documented schema by which a `PostCompact` hook returning `{"hookSpecificOutput": {"hookEventName": "PostCompact", "additionalContext": "..."}}` would land that text in the resumed (post-compaction) session. The async-hook delivery channel does mention `additionalContext` / `systemMessage` for *background* completion notifications, but it too names no compaction event among the supported parents.

**`type: command` handlers** are supported generically — the plugin's existing `hooks.json` already uses `type: command` handlers for `WorktreeCreate`, `StopFailure`, and the `send-telemetry.sh` SubagentStop wrappers, so the handler-type axis is not a blocker. The blocker is the event semantics: the hook fires, but its output cannot be used to inject context into the post-compaction session.

**Recap of what is and isn't possible (per docs as of 2026-05-10):**

| Capability | Supported? |
|---|---|
| Register a `PreCompact` hook with `type: command` | Yes |
| Register a `PostCompact` hook with `type: command` | Yes |
| Block a compaction from `PreCompact` (exit 2 / `decision: block`) | Yes |
| Read `compact_summary` from `PostCompact` input and log/persist it externally | Yes |
| Inject text into the resumed-session context via `additionalContext` from `PostCompact` | **No** (event not in `additionalContext` delivery list; PostCompact "has no decision control") |
| Inject text into the resumed-session context via `systemMessage` from `PostCompact` | **No** (same reason) |
| Inject text into the next prompt via `additionalContext` from `PreCompact` | **No** (PreCompact's documented JSON output is `decision`/`reason` for blocking; not in the `additionalContext` delivery list) |

The original spike target — using a `PostCompact` hook to seed the post-compaction session with restored agent state, supervisor invariants, or a contract-recap so that a long-running orchestration survives compaction — is therefore **not currently expressible** through the documented hooks API. The event hands the host script `compact_summary` for *external* persistence, but offers no return channel back into the live conversation.

## Recommendation
NO-GO

## Implementation Notes
Deferral reason: PostCompact is documented as having no decision control and no `additionalContext` delivery path, so a hook cannot re-inject restored context into the resumed session — which is the entire premise of the proposed work; what would unblock a future re-spike is either (a) Anthropic adding `PostCompact` (or PreCompact's `additionalContext`) to the delivery list in a future release, observable in `https://docs.claude.com/en/docs/claude-code/hooks` and the public changelog, or (b) a confirmed undocumented behavior verified by an empirical test in a live Claude Code session that survives a `/compact`-then-resume cycle.
