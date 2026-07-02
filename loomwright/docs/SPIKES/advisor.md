# Spike B: Advisor Tool Capability Verification

> **Spike date:** 2026-05-10
> **Plugin version at spike:** v12.1.0 (target)
> **Status:** read-only research

## Question

Can the Anthropic **Advisor tool** (executor model + higher-intelligence advisor sub-inference, e.g. Sonnet/Haiku executor + Opus advisor) be invoked from plugin subagents that loomwright spawns via Claude Code's Task tool — or is it currently reachable only by calling `/v1/messages` directly with a beta header?

## Sources Consulted

All URLs fetched 2026-05-10 (HTTP 200, content extracted from server-rendered HTML / embedded payloads):

1. **Anthropic Advisor tool reference** — `https://docs.claude.com/en/docs/agents-and-tools/tool-use/advisor-tool`
   - Title: *"Advisor tool — Claude API Docs"*
   - Tagline (verbatim): *"Pair a faster executor model with a higher-intelligence advisor model that provides strategic guidance mid-generation."*
2. **Anthropic tool-use overview sidebar** — `https://docs.anthropic.com/en/docs/build-with-claude/tool-use/overview`
   - Sidebar lists "Advisor tool" alongside Web search, Web fetch, Code execution, Memory, Bash, Computer use, Text editor — i.e. it is grouped with **server-side tools**.
3. **Claude Code subagents** — `https://docs.claude.com/en/docs/claude-code/sub-agents`
   - "Available tools" section, frontmatter fields (`tools`, `disallowedTools`, MCP scoping, permission modes, hooks).
4. **Claude Code release notes** — `https://docs.claude.com/en/release-notes/claude-code`
   - Stripped text contains no "advisor" mention (the only `grep` hit was navigation chrome, not content).
5. **Agent SDK overview** — `https://docs.claude.com/en/docs/agent-sdk/overview`
   - No mention of `anthropic-beta`, `extra_headers`, `extraHeaders`, "advisor", or any path to inject the `advisor-tool-2026-03-01` beta header into a session.
6. **Claude Code settings reference** — `https://docs.claude.com/en/docs/claude-code/settings`
   - No `anthropic-beta` / `extra_headers` / advisor configuration knob documented.
7. **Claude Code best-practices** — `https://www.anthropic.com/engineering/claude-code-best-practices` (the only "advisor" hit was the word "advisory" describing CLAUDE.md, false positive — not the Advisor tool).

## Findings

### The Advisor tool exists and is documented in beta on the Claude API

Concrete facts captured from `docs.claude.com/.../advisor-tool`:

- **Beta header (verbatim):** *"The advisor tool is in beta. Include the beta header `advisor-tool-2026-03-01` in your requests."*
- **Tool type identifier:** `advisor_20260301` (the `type` field on the tool definition).
- **Mechanism (verbatim):** *"All of this happens inside a single `/v1/messages` request. No extra round trips on your side."* The advisor is a **server-side sub-inference** — the executor emits a `server_tool_use` block with `name: "advisor"`, the server runs a separate inference on the advisor model with the executor's full transcript, and an `advisor_tool_result` block returns to the executor.
- **Quick-start example uses `client.beta.messages.create(...)`** with executor `claude-sonnet-4-6`, beta `advisor-tool-2026-03-01`, advisor type `advisor_20260301`, advisor model `claude-opus-4-7`.
- **Valid pairs** (executor → permitted advisors; API slugs in parens):
  - Haiku 4.5 (`claude-haiku-4-5`) → Opus 4.7 (`claude-opus-4-7`)
  - Sonnet 4.6 (`claude-sonnet-4-6`) → Opus 4.7 (`claude-opus-4-7`) / Opus 4.6 (`claude-opus-4-6`)
  - Opus 4.6 (`claude-opus-4-6`) → Opus 4.7 (`claude-opus-4-7`)
  - Opus 4.7 (`claude-opus-4-7`) → Opus 4.7 (`claude-opus-4-7`)
  - Invalid pairs return `400 invalid_request_error`.
  - Note: model slugs are accurate as of 2026-05-10; verify against the current Anthropic models list (`https://docs.anthropic.com/en/docs/about-claude/models`) before building — slugs and pair eligibility may change as new model versions ship.
- **Platform availability (verbatim):** *"The advisor tool is available in beta on the Claude API (Anthropic)."* No mention of Bedrock / Vertex / Claude Code.
- **Billing:** advisor sub-inference billed at the advisor model's rates; usage reported in the response `usage` object.

### Claude Code subagents inherit the parent's tool surface — and there is no documented path to add the Advisor tool

From `docs.claude.com/en/docs/claude-code/sub-agents`, "Available tools" section (verbatim):

> *"Subagents can use any of Claude Code's internal tools. By default, subagents inherit all tools from the main conversation, including MCP tools."*

The frontmatter fields documented for plugin subagents — `tools` (allowlist), `disallowedTools` (denylist), `mcpServers`, `permissionMode`, `hooks`, `skills`, `memory`, `model` — control **which subset of the parent's tools** a subagent can use. None of them add new tools beyond Claude Code's built-in toolset + MCP tools.

In particular:

- The `tools:` field in subagent frontmatter is an **allowlist over Claude Code's internal tools**, not a list of Anthropic API server-tools. The names are Claude Code names (`Read`, `Grep`, `Glob`, `Bash`, `Task`, etc.), not API tool types like `advisor_20260301`.
- The `Task` tool's documented contract (spawning subagents) likewise doesn't expose an Anthropic server-tool array or a mechanism to set the per-call `tools` array on the underlying `/v1/messages` invocation.
- **No `anthropic-beta` header is configurable** from any documented settings location — not in `settings.json`, not in subagent frontmatter, not in the Agent SDK overview's documented options. The Advisor tool's required `advisor-tool-2026-03-01` header therefore cannot be injected from a plugin.
- No release-note or changelog entry surfaces "advisor" support for Claude Code or the Agent SDK as of 2026-05-10.

### What this means for loomwright

The Advisor tool's executor/advisor split happens **inside one `/v1/messages` call** and is selected by the SDK call site that owns the request — the developer's code calling `client.beta.messages.create(...)`. Plugin subagents in loomwright are spawned as Claude Code subagents via Task; they do **not** own a direct `/v1/messages` request and have **no documented surface** to:
1. set the `anthropic-beta: advisor-tool-2026-03-01` header,
2. add `{ "type": "advisor_20260301", "advisor_model": "claude-opus-4-7" }` to the request `tools` array, or
3. observe / round-trip `advisor_tool_result` blocks.

Conversely, an out-of-band integration that calls the Anthropic SDK directly (TypeScript / Python `client.beta.messages.create(...)`) with the beta header and the advisor tool definition is straightforwardly supported today — but that is **outside** the Claude Code subagent runtime, not a `--advisor` flag wired through Supervisor / Execute Manager / Worker.

## Recommendation

SDK-ONLY

The Advisor tool is real, shipping in beta on the Anthropic Claude API as of 2026-05-10, and well documented. However, no documented Claude Code surface (subagent frontmatter, settings, hooks, the Task tool, or the Agent SDK overview) lets a plugin subagent inject the `advisor-tool-2026-03-01` beta header or attach the `advisor_20260301` server-tool to its underlying `/v1/messages` call. Until Claude Code or the Agent SDK exposes a beta-header / server-tool pass-through, the Advisor pattern is reachable only by code that calls `client.beta.messages.create(...)` directly — i.e. not from inside a Task-spawned plugin subagent.

## Implementation Notes

### Why not GO

Wiring a `/supervisor --advisor` flag that **claims** to run Sonnet/Haiku workers under an Opus advisor would be misleading: workers are Claude Code Task-spawned subagents with no beta-header injection, so the Advisor tool can't be attached at the underlying request level. Effort tiering (`xhigh` / `high` / `medium`) and the `--cheap` cost profile (already shipping in v11) remain the correct levers for cost/quality trade-offs across plugin agents.

### Why not NO-GO

The tool exists and is callable today via the SDK — a plugin **author** (not the running plugin) can absolutely use it in companion CLIs, scripts, or future helpers that bypass the Claude Code Task layer.

### What "SDK-ONLY" means concretely for this plugin

1. **Do not add `--advisor` to `/supervisor` in v12.1.0.** The flag would have no plumbing path through Task-spawned workers.
2. **Document the SDK escape hatch** for users who want the pattern outside the plugin, e.g. an external script:
   ```typescript
   import Anthropic from "@anthropic-ai/sdk";
   const client = new Anthropic();
   const resp = await client.beta.messages.create({
     model: "claude-sonnet-4-6",                 // executor
     betas: ["advisor-tool-2026-03-01"],
     max_tokens: 4096,
     tools: [
       { type: "advisor_20260301", advisor_model: "claude-opus-4-7" }
     ],
     messages: [{ role: "user", content: "..." }],
   });
   ```
   Equivalent Python: `client.beta.messages.create(model="claude-sonnet-4-6", betas=["advisor-tool-2026-03-01"], tools=[{"type": "advisor_20260301", "advisor_model": "claude-opus-4-7"}], ...)`.
3. **Trigger conditions for a re-spike (promote SDK-ONLY → GO):**
   - Claude Code release notes, subagent docs, or Agent SDK reference document a way to set `anthropic-beta` headers on subagent inference (e.g., a frontmatter `betas:` field, a settings.json `anthropic.betas` array, or a Task-tool parameter).
   - **OR** Claude Code adds an `Advisor` internal tool (analogous to `WebFetch`) that subagents can list in `tools:`.
   - **OR** the Advisor tool exits beta and Anthropic publishes a Claude Code integration note.
4. **Effort tiering remains the canonical knob** for cost/quality in v12.x: `xhigh` / `high` / `medium` per `ARCHITECTURE_CONTRACTS.md` §"Effort Tiers", plus `/supervisor --cheap` for opt-in Sonnet overrides on execution-shaped roles.
5. **Re-check cadence:** revisit when Claude Code ships a release note mentioning "advisor" or "anthropic-beta", or at the next minor (v12.2.0) — whichever is sooner.
