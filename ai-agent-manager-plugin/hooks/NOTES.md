# Hooks NOTES

## SubagentStart Hook (deferred from v12.0.0)

v12.0.0 S4 spike: SubagentStart hooks for worker / execute-manager are deferred. The Claude Code changelog confirms the SubagentStart hook event exists, and prompt-type hooks are documented to accept it, but `type: command` support could not be positively verified in available docs/source for v12.0.0 — only a changelog entry ('Added the SubagentStart hook event') was found, with no JSON schema reference. When implementing, the JSON output emitted by the command must follow the format `{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}` and the additionalContext should reference the v12 outputs_verified contract (worker) or the toolset_gap / adjudication invariants (execute-manager). Track follow-up: positively verify type:command support against Claude Code source before adding.

When implementing, the JSON output must follow the format
`{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}`.
