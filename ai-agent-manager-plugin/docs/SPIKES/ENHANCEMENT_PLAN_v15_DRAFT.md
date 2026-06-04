# Enhancement Plan v15 (REVISED post-red-team) — Less-Babysitting, Not More-Autonomy

> Status: **DRAFT for review, hardened by an independent red-team pass.** Not wired.
> Authored from research + adversarial review of v14.0.0 (`491bddb`). `file:line` grounded; verified
> facts tagged ✅; unverified/secondary tagged ⚠️.
>
> **⚠️ Hook-count note (added v14.9.0):** the `14 → 16` pinned hook figures throughout this draft
> (§0 Executive Summary, §2.4, and the §6 roadmap table) reflect the hook count *at time of writing*,
> when `main` was around v14.0.0–v14.2.x. The **current** count is **19** (authoritative: `plugin.json`
> / `CLAUDE.md`) — the §6 P1 notification additions described here were never landed as written
> (§0a: PR #13 was closed/conflicting — its notification surface never merged, so `main` kept only the
> v14.0.0 inline webhook). Treat **all** hook counts and notification-architecture figures in this draft
> (including §2's hook approach) as historical planning context that predates v14.1.0–v14.2.x, not
> current state — the scripts it references (`notify-desktop.sh`, `session-resume.sh`,
> `validate-launch-pad-result.py`) did subsequently land.
>
> **Guiding principle (changed after red-team):** the plugin's only real asset is its **gated,
> reviewable, human-in-the-loop** workflow. The goal is **"make the gated workflow require less
> babysitting without weakening a single gate"** — *not* "make it autonomous." Anything that lets the
> system **trust its own writes** is the thing to be most suspicious of.

---

## 0a. ⚠️ MOST OF P0+P1 ALREADY EXISTS ON A **CLOSED** PR (#13 / `release/v13.1.0`)

A prior session already built — and self-red-teamed — the notification surface **and** the
concurrency/resume fix this plan proposes. Verified on-branch:
- `scripts/notify-desktop.sh` (osascript/notify-send banner, opt-out, scope-gated, stderr-logged).
- `hooks.json`: `PreToolUse[AskUserQuestion]` → desktop+webhook, `Notification` → desktop,
  `SessionStart` → `session-resume.sh`, `launch-pad-runner` SubagentStop → `validate-launch-pad-result.py`.
- `send-webhook.sh`: new stdin-driven **paused-event** branch.
- **`LAUNCH_PAD_RESULT` schema + Python validator** → `saved_brief_path` becomes the primary brief-detect
  signal; the fragile `ls`-diff is demoted to fallback. **This closes the concurrent-session footgun (my P0).**
- `session-resume.sh` SessionStart rehydration, bounded to 10k-char cap, **silent on `startup`** (already
  solves my C3 "don't tax every session" concern).

**Why the maintainer "sees no notifications": PR #13 is `CLOSED` + `CONFLICTING`, never merged. `main`
moved to v14.0.0 without it.** v14 has only the env-gated `--event-type gate` webhook (inline, not a
hook) — no desktop banner, no `Notification`/`PreToolUse` hook. So the running v14 has no local
notification path at all, and the webhook half is defeated by the `.zshrc` env-propagation bug (§2.1).

**Revised top priority: RECONCILE & LAND PR #13 onto v14**, not build P0/P1 from scratch. The only true
conflict is `send-webhook.sh` (both sides insert at the post-`JQ_BIN` region): v13.1.0's *stdin/hook-driven*
paused branch vs v14's *flag-driven* `--event-type gate` branch — resolvable by **interleaving both
branches** (check `--event-type gate` first; else read stdin; if `PreToolUse`+`AskUserQuestion` →
paused; else `supervisor_result`). `hooks.json` merges clean (v14 never touched it). Then: **dedup the
double-fire** (for `/autonomous` gates both the inline gate webhook AND the PreToolUse paused webhook
POST), bump versions v13.1.0→v14.x in the branch's docs, apply the §0c fixes.

## 0c. Fixes to apply WHILE landing PR #13 (net-new on top of it)
1. **`timeout 3` around `osascript`/`notify-send`** (W4) — branch lacks it; macOS first-run notification
   permission dialog or a hung daemon can block the hook.
2. **Matcher on the `Notification` hook** → exclude `auth_success` (fires a banner every session = noise).
3. **ntfy-aware webhook payload** — plain-text body + `Title:`/`Priority:`/`Tags:` headers; the current
   JSON POST to an ntfy topic renders as a raw blob (§2.1 secondary).
4. **File-based webhook config** `.supervisor/notify-config.json` (§2.1 fix) so the `.zshrc`
   env-propagation bug can't silently disable the webhook half.
5. **Bidirectional reply leg** (§8.1): the branch is OUTBOUND-only. Phone push + remote reply needs
   **Claude Code Remote Control** (+ optional `PushNotification` inline at `/autonomous` gates). Net-new.

---

## 0d. THE ACTUAL GOAL — The Compounding Flywheel ("the more I use it, the smarter it gets")

The maintainer's north star: **every run improves the next run; the system proactively suggests the
best way forward; it compounds with use.** Memory, notifications, self-evolution are *parts* — this is
the *loop* that connects them. A system only gets **better** (not just bigger / drifting) if the loop
is **closed by an outcome signal**. Five stages:

```
        ┌────────────────────────────────────────────────────────────────┐
        │                                                                  │
   ① OBSERVE ──▶ ② DISTILL ──▶ ③ PROMOTE(human) ──▶ ④ APPLY ──▶ ⑤ MEASURE ─┘
   every run     candidate       quality ratchet     inject at    did it help?
   emits         knowledge       (per-item OK)        the right    reinforce / demote
   signals       (scored)        provenance-tagged    moment       → feeds next DISTILL
```

| Stage | What it does | Built on (exists ✅ / new ➕) | The "gets smarter" mechanism |
|---|---|---|---|
| **① OBSERVE** | Capture every run's signals | ✅ JSONL logs, `SUPERVISOR_/CODE_REVIEW_/QA_/RUBRIC` result blocks, telemetry scoring | The raw episodic substrate already exists — nothing to build |
| **② DISTILL** | Turn raw signals → *candidate* knowledge, scored by (recall-freq × outcome × diversity) | ➕ extend `/dreaming` to read logs + `failed/` briefs → candidate LESSONS / CLAUDE.md edits / playbooks | Reflection is where "understanding" is manufactured from experience |
| **③ PROMOTE** | Human-gated quality ratchet: per-item approval; only promoted items become authoritative; provenance-tagged | ✅ `/dreaming` per-item approval model — keep, **minimize** (batch, rare, "approve-safe" defaults) | **This is the anti-drift valve** the red-team demanded — knowledge can't self-trust |
| **④ APPLY** | Inject the *right* knowledge at the *right* moment | ➕ Launch Pad consults `playbooks/` before planning; Workers/Reviewer get scoped topic-memory + relevant LESSONS (lazy, not blanket) | **This is "understands more"** — past knowledge present at decision time |
| **⑤ MEASURE** | Did applied knowledge improve the outcome? Reinforce what helps, demote what doesn't | ➕ track `rubric_score` trend, Plan-Review retry count, self-heal iterations, QA pass-rate **per playbook/lesson** | **This is what makes it BETTER not just bigger** — the missing ingredient in naïve memory systems |

**The proactive advisory layer** (the maintainer's "suggest way forward / best practice" ask) is stage
④ made *visible*: a **pre-flight briefing** at the start of work (integrated into Launch Pad, or a thin
`/advise`):
> *"For a goal like this, past runs suggest approach X (playbook P — succeeded 3/3, avg rubric 5/5).
> Heads-up: 2 similar features hit Y (lesson L). Recommended now: [best practice from skills + current
> Claude Code capabilities via `/capability-check`]. Known risks: Z."*

This turns silent memory into spoken guidance — the user *feels* it getting smarter.

**Why this won't drift into garbage (red-team's central fear, answered):**
- ⑤ MEASURE auto-demotes knowledge that correlates with worse outcomes — bad lessons decay instead of
  compounding.
- ③ PROMOTE keeps a human ratchet, but **minimized** (rare/actionable/batched) so it doesn't rot into a
  rubber stamp (W3).
- Everything bounded (§3.0 caps), provenance-tagged (§3.2 read-side gate), advisory-subordinate-to-human
  `CLAUDE.md` (§3 inverted precedence), and the system **never** self-edits its own gates/agents/hooks.

**Way-forward sequencing for the flywheel (after PR #13 lands P0+P1):**
1. **APPLY-first with what already exists.** The 6 `memory: project` agents already capture; wire Launch
   Pad to *read* successful briefs as playbooks → instant ④ with zero new capture. (Smallest loop that
   visibly compounds.)
2. **Project `PROJECT_MEMORY.md`** (§3, correctly homed under `.supervisor/memory/`) — the shared,
   cross-agent knowledge layer the per-agent memories can't be.
3. **MEASURE** — add per-playbook/lesson outcome tracking keyed on existing result-block scores. Without
   this the flywheel is open-loop; with it, it self-corrects.
4. **DISTILL+PROMOTE** — extend `/dreaming` (reflection → candidates) + the pre-flight `/advise`
   briefing. Now the user *sees* it suggesting the way forward.
5. **`/capability-check`** — the outer loop: keeps best-practices/capabilities current (on-demand first).

**One-line test of whether a proposed addition belongs:** *does it move knowledge around the
OBSERVE→…→MEASURE loop?* If yes, build it. If it only adds capture (no apply) or apply (no measure),
it will bloat, not compound — defer it.

---

## 0. Executive Summary

1. **Notifications are the real, confirmed bug** — and the fix is narrower than it first looks.
   Root cause: webhook-only, env-gated, no native hook, no local fallback. Fix = wire the **native
   `Notification` hook** ✅ but **matched + debounced + channel-detected**, scoped honestly to the
   *interactive* user. The **webhook remains the only headless channel** — desktop toasts do not fire
   in CI/SSH/Docker, and the `Notification` hook itself **may not fire headless** (docs-unconfirmed).
2. **Agent-writable project memory is the highest-value AND highest-risk idea.** The naïve design
   (`.agent-manager/`) is **architecturally broken**: it diverges across git worktrees and pollutes
   the user's repo (not gitignored). Corrected design: home it under **`.supervisor/memory/`**
   (already gitignored, already has a sole-writer via Context-Keeper), single-writer in a
   **pinned absolute CWD**, **advisory-only / subordinate to human CLAUDE.md**, with a **read-side
   provenance gate** before anything is trusted.
3. **Self-evolution should be on-demand-first.** Ship a manual **`/capability-check`** (the
   productized version of *this session's* research pass) before any cron. A scheduled scanner is a
   silent-death risk (7-day cron expiry) and a cost leak unless durability + budget + circuit-breaker
   + heartbeat are designed in from day one.
4. **The actual prerequisite for everything is concurrency/resume hardening** (`LAUNCH_PAD_RESULT` +
   killing the `ls`-diff). Ship it **first** — notifications that encourage unattended use on top of a
   known concurrency footgun increase the blast radius.

All changes additive and reversible. **Pinned final hook count: 14 → 16** (only `Notification` +
`SessionEnd`; `PreCompact`/`SessionStart`/`FileChanged` are *evaluated*, not auto-adopted — see §6).

---

## 1. Built-in Claude Code Capabilities to Leverage (stop reinventing)

Verified against `code.claude.com/docs/en/hooks` + the live tool surface.

| Need | Today | Native capability | Verdict |
|---|---|---|---|
| Notify when agent needs attention | Webhook-only, env-gated; **zero `Notification` hooks** in `hooks.json` | **`Notification` hook** ✅ (matchers: `permission_prompt`, `idle_prompt`, `elicitation_dialog`…) + `Stop`/`SessionEnd` | **Adopt — matched/debounced (§2)** |
| Push to phone/desktop | None | **`PushNotification` tool** ✅ (model-turn only) | **Adopt for `/autonomous` gates, main-thread** |
| Headless / CI notification | Webhook (works) | Webhook is **the only headless channel** — desktop toasts/bell do NOT fire headless | **Keep webhook as the headless path** |
| Unattended scheduling | Manual re-invoke | **`/schedule`+`CronCreate`** ✅ (`durable:true` survives restarts; **7-day auto-expiry otherwise** ⚠️), **`/loop`**, **`RemoteTrigger`** (cloud routines) | **On-demand first; cron behind guardrails (§4)** |
| Agent-written learnings | Per-agent `memory:` dirs only | **Auto-memory** ✅ (`~/.claude/projects/<proj>/memory/MEMORY.md`, on-demand topic files), `/memory`, `consolidate-memory` skill | **Adopt the on-demand model, not front-loading (§3)** |
| Don't lose context at compaction | Nothing on a compaction trigger | **`PreCompact`/`PostCompact`** ✅ (PreCompact can block) | **Evaluate (§3.3) — not auto-adopt** |
| Rehydrate state at session start | Skills preload only | **`SessionStart`** ✅ (`additionalContext`, `watchPaths`, `reloadSkills`, `CLAUDE_ENV_FILE`) | **Adopt lazily/scoped (§3.4)** |
| Read-only review/research fan-out | Supervisor + worktrees (for edits) | **`Workflow`/`/workflows`** ✅ (schema-validated fan-out) | **Adopt for read-only phases** |

**Hard constraints designed around (verified):** subagents can't spawn subagents ✅ (new autonomy
stays main-thread / `-runner`); plugin agents ignore frontmatter `hooks`/`mcpServers`/`permissionMode`
✅ (all hooks → `hooks.json`); `Notification` hooks **cannot block**, side-effect only ✅;
`PushNotification` is a tool, not shell-callable ✅.

---

## 2. Notification System — Root Cause + Corrected Architecture

### 2.1 Confirmed root causes (ranked, evidenced)
1. **PRIMARY — env-var propagation, not "never set."** Verified on the maintainer's machine: the var
   **is** set (`~/.zshrc:50` → `AI_AGENT_MANAGER_WEBHOOK_URL=https://ntfy.sh/my-claude-agent-…`) yet is
   **absent from the running Claude Code process** (live check: `[<UNSET>]`). `.zshrc` is sourced only
   by *interactive zsh*; Claude Code `type: command` hooks run under **non-interactive bash** (sources
   `.bashrc`/`.profile`, never `.zshrc`), and the var only reaches a hook if the **launching process**
   already had it exported. If `claude` was started from a GUI/IDE, a login shell that sources
   `.zprofile`/`.zshenv`, or a shell predating the `.zshrc` edit, the var never propagates →
   `send-webhook.sh:82-84` exits 0 silently. **This is fragile by design.**
   **FIX (architectural):** stop depending on env-var inheritance. Read the webhook target from a
   **config file** the hook always reads — e.g. `.supervisor/notify-config.json` (mirrors the existing
   `.supervisor/telemetry-consent.json` pattern), with the env var as an *override*. A file in the repo
   resolves regardless of how `claude` was launched. Document `~/.zshenv` (sourced by all zsh) as the
   env-var fallback for users who prefer env config.
   **SECONDARY (ntfy payload shape):** even when it fires, `send-webhook.sh` POSTs
   `{agent,status,pr_url,summary,timestamp}` as `application/json` to `https://ntfy.sh/<topic>`. ntfy
   treats the body of a topic-path POST as the **raw message text**, so the user gets a JSON blob, not
   a readable alert, and ntfy niceties (`Title`/`Priority`/`Tags` headers, or `X-Title`) are unused.
   Add an ntfy-aware event-type that sends a plain-text body + `Title:`/`Priority:`/`Tags:` headers.
2. **SECONDARY** — `hooks.json` (125 lines) has **zero** `Notification`/notify-`Stop`/`SessionEnd`
   entries. Interactive user gets **nothing** — no bell, no toast.
3. **TERTIARY** — silent exit-0 on missing `curl`/`jq`/empty payload (`send-webhook.sh:154-157`,
   `:172-175`, `:300-303`, `:347-351`).

### 2.2 The honest channel matrix (red-team correction)
| Channel | Interactive desktop | Interactive SSH/TTY | Headless / CI / Docker |
|---|---|---|---|
| Terminal bell `printf '\a'` | ✅ | ⚠️ (goes to controlling TTY; raw `0x07` into logs if none) | ❌ no TTY |
| Desktop toast (osascript / notify-send) | ✅ macOS/Linux-with-session-bus | ❌ no display | ❌ |
| Webhook (Slack/Discord/email relay) | ✅ | ✅ | ✅ **only headless channel** |
| `PushNotification` tool | ✅ if Remote Control connected | ✅ | ❌ (needs a model turn; blocked at gate) |

**Consequence:** desktop notifications are an **interactive-only** win. The "wake up to finished work"
story for *unattended* runs rests on the **webhook + `--non-interactive-fallback`** (already exists),
NOT on desktop toasts and NOT on the `Notification` hook (which the docs say may not fire headless ⚠️).

### 2.3 `notify.sh` dispatcher (corrected)
- **Matched** `Notification` hook — `matcher: "permission_prompt|idle_prompt|elicitation_dialog"`.
  **Never `auth_success`** (fires every session = pure noise).
- **Channel-detect before attempting:** `[ -t 2 ]` for bell; `$DISPLAY`/`$XDG_RUNTIME_DIR` (Linux) or
  Aqua/macOS for toast; skip cleanly otherwise.
- **`timeout 3` around every external call** (W4: `osascript` can block on the macOS first-run
  "wants to send notifications" permission dialog; `notify-send` can hang on a dead daemon). Background
  the toast call. Always exit 0 — but never *block* reaching the exit.
- **Debounce:** coalesce events within a short window via a timestamp file in a **gitignored tmp dir**
  (`.supervisor/logs/.notify-debounce`), suppressing toast storms from parallel fires.
- **Fail-loud-on-misconfig** only when an interactive channel was *expected*: if `/autonomous --notify`
  is passed, no webhook URL, and no interactive channel detected → one visible warning. Main-thread
  check, not a hook.
- **WSL/Windows:** documented as webhook-only (or `powershell.exe -c` toast as a follow-up).

### 2.4 `hooks.json` additions (pinned: +2 → 16 total) `[historical — current count is 19; see the top-of-file Hook-count note]`
```jsonc
"Notification": [
  { "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
    "hooks": [ { "type": "command",
      "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh\" --source notification" } ] }
],
"SessionEnd": [
  { "matcher": "logout|prompt_input_exit|other",
    "hooks": [ { "type": "command",
      "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh\" --source session-end" } ] }
]
```
- **Do NOT** route notifications through `SubagentStop` (spam during normal parallel execution). Keep
  the existing `SubagentStop → send-webhook.sh` scoped to `supervisor-runner` only (`hooks.json:54-69`).
- Add a `notify.sh` self-test mirroring the existing hook self-tests (X3: no untested hook surface).

### 2.5 `PushNotification` at `/autonomous` gates (main-thread, honest)
The loop already pauses at gates with `AskUserQuestion`. Emit `PushNotification` **immediately before**
the gate. This helps the **away-but-attended** user (walked away during a run) — it does **not** help a
fully unattended run (which is blocked at the gate anyway; for that, the gate decision should fire the
**webhook** and then honor `--non-interactive-fallback`). Document next to the `--notify` webhook calls
in `autonomous-loop/SKILL.md`.

### 2.6 Effort: ~1 day (`notify.sh` ~100 lines w/ detection+timeout+debounce, 2 hooks + self-test, 1
warning line, README "Enabling notifications" with the channel matrix).

---

## 3. Memory Architecture — 9 Concepts, Corrected Design

### 3.0 Memory Core Principle (proposed canonical text for `AGENT_GUIDELINES.md`)

> **Rule 0 — Memory is a liability until proven an asset.** Every stored line is paid for on every
> future load. The default is *don't store it*.

**Asset test — store a fact only if it passes ALL four:**
1. **Durable** — true across sessions (not transient run state).
2. **Reusable** — will apply to a future task, not a one-off.
3. **Decision-changing** — an agent would act *differently* knowing it. If it wouldn't change a
   decision, it's trivia — drop it.
4. **Non-duplicative** — not already in `CLAUDE.md`, the code, or another memory layer.

**Never store:** session/run state (→ `.supervisor/`), secrets/PII/tokens, transient debug notes,
anything derivable by reading code or `CLAUDE.md`, speculation/guesses.

**Hard limits (enforced at WRITE time — never silent truncation):**
| File | Cap | At cap |
|---|---|---|
| `PROJECT_MEMORY.md` (index only) | ≤ 200 lines / 25 KB (= Claude Code auto-memory load cap) | evict lowest-value (oldest-unreferenced / lowest-recall), log eviction to provenance |
| `topics/<topic>.md` | ≤ 400 lines | split or summarize |
| `LESSONS.md` | ≤ 3 active entries **per category** (Reflexion sliding window) | retire oldest |

**Freshness mandate:** every entry is **dated + provenance-tagged**; a periodic freshness sweep
(extend `/dreaming`) re-validates entries against current code and prunes/flags stale ones; memory is
**advisory and subordinate to human `CLAUDE.md`** — on any conflict, the human layer wins.

**Retrieval tooling — no RAG / no vector DB.** The filesystem + `grep`/`Glob` + the bounded
`PROJECT_MEMORY.md` index *is* the retrieval system. A codebase is already greppable; semantic recall
is not the bottleneck, and a vector store adds infra, opacity, and the #1 poisoning attack surface
(MINJA/MemoryGraft). **Decision rule to ever add vectors:** only if (a) memory corpus > ~1k entries
AND (b) keyword/path retrieval demonstrably misses relevant entries in practice — and then reach for
**embedded `sqlite-vec`**, not a server. Until both are true, files win.

### 3.0b CLAUDE.md Currency Mandate (proposed)

`CLAUDE.md` is the canonical, human-authoritative project memory. Keeping it current is **mandatory,
not optional.** You cannot *safely auto-rewrite* it (drift/poisoning), so enforce currency in layers:
1. **Mechanical staleness gate (automatable).** When a run touches structure — `agents/`, `commands/`,
   `skills/`, `docs/`, `hooks.json`, plugin metadata, or introduces a pattern used 3+ times — the
   Supervisor completion tail (or Launch Pad) must require **either** a `CLAUDE.md` diff **or** an
   explicit "no update needed" acknowledgement before the run is marked complete. Code Reviewer's
   existing auto-consistency-audit already triggers on exactly these paths — extend it to emit a
   `CLAUDE.md`-staleness flag.
2. **Freshness sweep.** Run `claude-md-validation` periodically (via `/dreaming` or `/capability-check`)
   to confirm documented patterns still match code; flag drift.
3. **Human-gated apply.** Proposals surface to the maintainer; never auto-applied.

Research base unchanged (Anthropic context-engineering, Claude Code auto-memory, OpenClaw file-memory,
Letta tiers, OpenHands condenser, Devin human-gated playbooks, Voyager verification gate, Reflexion
bounded reflection, MINJA/MemoryGraft poisoning). ⚠️ "OpenClaw" real (`github.com/openclaw`); **"Hermes
Agent" unverified** (marketing only; ≠ Nous *Hermes LLMs*); **`SOUL.md` is a community SoulSpec layer**,
not an OpenClaw core primitive.

| Concept | Verdict | How (corrected) |
|---|---|---|
| **Soul files** | **SKIP** | Identity already in 13 agent prompts. Fold a short "operating values" stanza into `AGENT_GUIDELINES.md`; no new file. |
| **User memory** | **ADOPT (native)** | Use `~/.claude/CLAUDE.md` (user scope). Document; don't reinvent. |
| **Workspace/project memory** | **ADOPT — but homed correctly** | `.supervisor/memory/PROJECT_MEMORY.md` (✅ gitignored at `.gitignore:34`, ✅ sole-writer via Context-Keeper). **Advisory-only, subordinate to human CLAUDE.md.** Not a new `.agent-manager/` dir (broken — see §3.1). |
| **Memory hierarchy** | **ADOPT inverted precedence** | Human layers (`~/.claude/CLAUDE.md`, project `CLAUDE.md`) **always win**. Agent memory consulted **only when human layers are silent** (W2). Add agent memory to the `claude-md-validation` freshness sweep. |
| **Reflection** | **ADOPT, bounded** | `/dreaming` extension proposes `LESSONS.md` entries, **max 3 active per category** (Reflexion sliding window). Per-item human approval (existing contract). |
| **Planning memory** | **ADOPT** | Launch Pad briefs already are this. Add Devin-style postconditions + prior-correction advice. **Playbooks must be STRUCTURAL** (`provides`/`requires` skeletons, prose stripped — X1 injection vector). |
| **Long-term** | **File-based; DEFER vector** | Files + grep/Glob. No vector DB (poisoning surface + infra). |
| **Compressed** | **EVALUATE PreCompact (§3.3)** | "Memory-flush before compaction" — but see the read-team caveat below; don't auto-adopt a `PreCompact` hook without testing. |
| **Execution history** | **KEEP + rotate** | `.supervisor/logs/{session}.jsonl` already exists. Add size-cap rotation so it never loads whole. |

### 3.1 Why NOT `.agent-manager/` — the fatal homing bug (red-team F1)
- **Worktree divergence:** workers run in **separate git worktrees** (`worker.md:27,39,52,57`).
  A relative `.agent-manager/memory/…` resolves against **the worktree CWD**, not the main checkout.
  Git shares only `.git` across worktrees, **not untracked working-tree files** → N divergent memory
  copies, all destroyed on `git worktree remove`. Total loss of exactly the learnings the feature
  exists to persist.
- **Repo pollution:** `.gitignore:34` ignores **only `.supervisor/`**. `.agent-manager/` would surface
  in the **user's** `git status` and get committed into their application repo.
- **Corrected discipline:** **workers NEVER write memory.** They emit candidate learnings in
  `WORKER_RESULT`; the **main thread / Context-Keeper persists them once, to `.supervisor/memory/`,
  using the repo root CWD resolved at session start** (never a worktree path). This *is* the
  Context-Keeper sole-writer pattern — reuse it instead of inventing a contract-free dir.

### 3.2 Memory-poisoning defense — read-side, not write-side (red-team W1)
Write-side provenance alone is theater. Required:
- **Read-side gate:** SessionStart injection injects a `PROJECT_MEMORY.md` line **only if** it has a
  matching, valid provenance entry; un-provenanced lines are dropped, not trusted.
- **Tamper-evidence:** hash-chain `.provenance.jsonl` (each entry references prior hash) so an attacker
  can't append a matching fake entry. If hash-chaining isn't feasible, **drop the provenance claim** —
  don't ship a non-control labeled as a control.
- **Subordinate:** agent memory can never override a human CLAUDE.md fact or a hook gate (memory is
  never enforcement — Anthropic guidance; existing plugin stance).

### 3.3 PreCompact "memory flush" — EVALUATE, don't auto-adopt
The OpenClaw pattern (persist unsaved facts before the window resets) is attractive but adds a hook on
a hot path. **Gate it behind a test** that it fires reliably for plugin-distributed hooks and doesn't
stall compaction. If it doesn't, fall back to a **main-thread checkpoint step** in the Supervisor
completion tail (already a natural persistence point).

### 3.4 SessionStart injection — lazy & scoped (red-team C3)
Do **not** inject 200 lines on every session (taxes `/telemetry status`, `/agent-help`, one-shot
reviews). Inject memory **only for planning/execution agents** (Launch Pad, Supervisor) and as a
**pointer** ("memory exists; topic files in `.supervisor/memory/topics/` — load on demand"), mirroring
native auto-memory's on-demand topic-file model. **200-line cap enforced at write time** with a
deterministic eviction policy (oldest / lowest-recall), eviction logged to provenance (X2 — never
silent truncation).

### 3.5 File layout (corrected)
```
.supervisor/memory/                 # gitignored ✅, sole-writer (Context-Keeper), repo-root CWD
├── PROJECT_MEMORY.md               # advisory index, ≤200 lines (write-time eviction), provenance-gated
├── topics/<topic>.md               # loaded on demand
├── LESSONS.md                      # bounded reflection (≤3 per category)
└── .provenance.jsonl               # hash-chained {entry_id, prev_hash, session_id, source, ts}
.supervisor/playbooks/<slug>.md     # STRUCTURAL reusable briefs (prose stripped)
```

---

## 4. Self-Evolution — On-Demand First, Cron Behind Guardrails

### 4.1 `/capability-check` (NEW, manual) — ship this first
A bounded, on-demand command that does what *this session* did: WebFetch the Claude Code changelog/docs
+ Context7 for pinned deps, diff against `.supervisor/memory/CAPABILITY_BASELINE.json`, emit a
`CAPABILITY_REPORT.md` of **candidate** adoptions. **Never self-applies.** Bounded tool-call/WebFetch
budget per run. This is abandonment-resilient: the maintainer runs it when a session surfaces a gap,
instead of being trained to ignore a weekly cron (W3).

### 4.2 Scheduled scanner — only with all four guardrails (red-team F2)
If cron is added later: **(1)** `durable:true` **and cadence < 7-day expiry** (e.g. run every ≤5 days,
or re-arm on each run) — else it silently dies after a week while the maintainer trusts it; **(2)**
explicit per-run tool-call + dollar budget (the existing Supervisor/Execute-Manager budgets do NOT
apply to a new agent); **(3)** circuit breaker — 3 consecutive scan failures → disable + notify, never
retry-forever; **(4)** heartbeat — if no report in >N days, the next interactive session warns "scanner
appears dead."

### 4.3 Reflection → advisory memory — extend `/dreaming` only
`/dreaming` already: read-only, proposes memory/CLAUDE.md updates, per-item approval. Extend it to
consume `.supervisor/logs/*.jsonl` + `failed/` briefs → propose **bounded** `LESSONS.md` entries,
scored (OpenClaw dreaming gate: score × recall-freq × diversity). **No new write path** — reuse the
existing approval contract.

### 4.4 Guardrails (non-negotiable)
Human-in-the-loop promotion (existing `/dreaming`); verification gate before adoption (reuse Plan
Reviewer / Rubric Grader); bounded everything (reflections ≤3, memory ≤200 lines write-time-evicted,
scanner budgeted); read-side provenance (§3.2); **the system may propose but never apply changes to its
own gates/agents/hooks** — a human applies them. Accept that the human gate **decays into a rubber
stamp** (W3): design reports to be **rare + actionable**, suppress no-change output.

### 4.5 Voyager-style skill auto-authoring — DEFER (P5)
Only behind Plan-Review/Rubric verification gate; playbooks structural-only + read-side-gated.

---

## 5. "Less-Babysitting" Additions (the honest version of "autonomous")

1. **Concurrency/resume hardening = the real prerequisite.** `LAUNCH_PAD_RESULT` schema with
   `saved_brief_path` (CLAUDE.md: "single biggest leverage point") replaces the fragile `ls`-diff brief
   detection (`autonomous-loop/SKILL.md`). **Ship before notifications** — notifications encourage
   unattended/concurrent use, which is unsafe until this lands.
2. **Resume contract.** Persist enough to `.supervisor/autonomous/<session>/` to re-enter at the last
   completed iteration; pair with scoped `SessionStart` rehydration (§3.4).
3. **Gate notification, not autonomy.** Better/faster notification of gates (so the human shows up
   sooner) + `--non-interactive-fallback` (exists) is the safe "wake up to finished work." Webhook is
   the headless channel.
4. **Cross-run learning via structural playbooks** (§3, §4.3) — Launch Pad consults `playbooks/` before
   planning similar goals → fewer Plan-Review retries over time. Measurable "gets better with use."

---

## 6. Corrected Phased Roadmap (post-red-team reorder)

| Phase | Scope | Effort | Risk | Gate before next |
|---|---|---|---|---|
| **P0** | **Concurrency/resume:** `LAUNCH_PAD_RESULT` + `saved_brief_path`; kill `ls`-diff | 1–2 d | Low | — |
| **P1** | **Notifications (interactive-scoped, honest):** matched+debounced `Notification` hook, channel-detected `notify.sh` w/ per-tier `timeout`, webhook = headless channel, fail-loud-on-misconfig, self-test | 1 d | Low | — |
| **P2** | **Advisory memory, correctly homed:** `.supervisor/memory/`, single-writer/pinned-CWD, write-time eviction, read-side provenance gate, lazy/scoped SessionStart injection. **Worktree concurrency test = merge blocker.** | 2–3 d | Med (poisoning — mitigated by read-side gate) | read-side gate must pass |
| **P3** | **`/capability-check` (on-demand)** — bounded, manual | 1–2 d | Low | — |
| **P4** | `/dreaming` reflection extension → bounded `LESSONS.md`; structural playbook templates | 2–3 d | Med (drift — human gate + rarity) | — |
| **P5 (defer)** | Scheduled scanner (4 guardrails); Voyager skill auto-authoring behind gates; vector recall iff file search fails at scale | — | High | — |

**Pinned hook count: 16** `[historical — now 19]` after P1 (`Notification` + `SessionEnd`). `PreCompact`/`SessionStart`/
`FileChanged` are evaluated in P2 and adopted only if they pass the §3.3 fire/no-stall test — each new
hook ships with a self-test.

---

## 7. The Single Most Dangerous Idea (keep visible)
**Agent-writable memory that is auto-injected and later trusted.** It is the one place the design lets
the system act on its own writes, guarded only by a human who will eventually stop looking (W3) and a
provenance scheme that must actually be *read* and *tamper-evident* to mean anything (W1). Every other
finding is a bug; this one can quietly corrupt behavior and survive across sessions. Mitigations
(advisory-only, subordinate to human CLAUDE.md, read-side provenance gate, bounded, rare-report human
review) are mandatory, not optional — and if any can't be built properly, **ship the memory feature
read-only (propose-only, like `/dreaming`) rather than self-trusting.**

---

## 8. Bidirectional Async Gates + Context Hygiene (maintainer-requested refinements)

### 8.1 "Gated" and "autonomous" are NOT opposites — make gates ASYNC, not blocking stops
The maintainer's reframe is correct and supersedes §0's framing tension: a gate that **notifies the
human and resumes the same session on their reply** keeps the safety property *and* the autonomy.
Treat the human as an **async tool the agent calls**, not a full stop.
- **The pause already exists and is already same-session.** `AskUserQuestion` (the `/autonomous`
  adjudication/rubric gates) and the native `idle_prompt`/`permission_prompt` are **blocking waits
  within the live session** — they do not kill it. On reply, the same session continues. So "doesn't
  stop, keeps working after I answer" is the *current* behavior; the only missing piece is the
  human-knows-to-come-back signal (= P1 notifications).
- **Remote bidirectional (answer from your phone).** Enable **Claude Code Remote Control**; then
  `PushNotification` pushes the gate to your phone (its own description: "If Remote Control is
  connected, it also pushes to their phone"), and you reply from the claude.ai app → same session
  resumes. That is the full out-and-back loop, built-in, no plumbing to build.
- **Invariant preserved:** the gate is *relocated to async*, never *removed*. No gate is auto-answered;
  `--non-interactive-fallback` remains the fail-closed path when genuinely unattended.
- **Net:** P1 (notifications) + Remote Control already deliver the maintainer's "still autonomous,
  bidirectional, same session" vision. No new agent required for it.

### 8.2 Context hygiene — an honest design (a subagent CANNOT clean its parent's context)
**Hard truth:** separate agents have separate context windows; **no agent can prune another session's
context.** A "context-janitor agent" is architecturally impossible. What actually keeps the orchestrator
small (and the plugin already does most of it):
1. **Delegate to disposable subagent contexts; keep only compressed summaries** (Context-Keeper,
   Execute Manager, `context-summarization` skill). The heavy reading happens in contexts that are
   thrown away — the orchestrator never holds it. This is THE context-management system; lean on it.
2. **Externalize state to files, hold only pointers** (just-in-time retrieval): `.supervisor/state.md`,
   the `PROJECT_MEMORY.md` index, JSONL logs. The main thread carries identifiers, not content.
3. **`PreCompact` "memory-flush"** so Claude Code's native auto-compaction is *lossless* — persist
   durable facts before the window resets (§3.3, gated on the fire/no-stall test).
4. **A `context-hygiene` SKILL (not an agent)** encoding the discipline: thresholds for when to
   checkpoint+`/compact`, what must be flushed first, what stays a pointer. Optionally a lightweight
   watchdog (a periodic main-thread self-check or a `PostToolUse` heuristic) that *warns* "context
   getting large — checkpoint now," but the actual compaction is Claude Code's, made safe by step 3.
- **Deliverable shape:** `skills/context-hygiene/SKILL.md` + the `PreCompact` flush hook. No new agent.

### 8.3 Self-evolution delivery — a SKILL + command, not a new heavyweight agent
`/capability-check` is **a slash command + skill on the main thread** (it needs WebFetch/Context7 + log
reads + to drive the human approval interaction — all main-thread work; a subagent's isolated context
fights this). Extend the existing `/dreaming` **skill** for the reflection→`LESSONS.md` half. Reserve a
thin agent only if you later want a *scheduled headless* scan in an isolated context (P5). **Skill-first
because skills compose and stay cheap; agents are for isolated delegation, which this isn't.**

---

## Appendix — Red-Team Findings Folded In
F1 (worktree divergence + gitignore pollution) → §3.1 rehoming. F2 (scanner durability/cost/kill-switch)
→ §4.2 four guardrails + §4.1 on-demand-first. C1 (Notification spam + headless-absent) → §2.2 channel
matrix + §2.3 matched/debounced. C2 (portability) → §2.2/§2.3 channel detection + WSL note. C3
(SessionStart tax) → §3.4 lazy/scoped. C4 (roadmap order) → §6 reorder (P0=concurrency). W1 (write-side
provenance theater) → §3.2 read-side + hash-chain. W2 (4-layer staleness) → §3 inverted precedence +
validation sweep. W3 (human-gate decay) → §4.1 on-demand + §4.4 rare/actionable. W4 (notify.sh blocking)
→ §2.3 per-tier timeout. X1 (playbook injection) → §3 structural-only. X2 (200-line truncation) → §3.4
write-time eviction. X3 (hook count "~") → §0/§6 pinned 16 + self-tests.
