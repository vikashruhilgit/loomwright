# Architecture Diagram

> Visual topology of the 12-agent system. For contracts and rules, see `ARCHITECTURE_CONTRACTS.md`.

---

## Full Agent Topology

```
                            ┌─────────────┐
                            │  User Goal  │
                            └──────┬──────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
              ┌─────▼─────┐ ┌─────▼─────┐ ┌─────▼─────┐
              │ /launch-  │ │/supervisor│ │  Manual   │
              │   pad     │ │  (direct) │ │ Workflow  │
              └─────┬─────┘ └─────┬─────┘ └─────┬─────┘
                    │              │              │
         ┌──────────▼──────────┐  │    ┌─────────▼──────────┐
         │ Plan Reviewer       │  │    │ /product-owner     │
         │ #48D1CC (Phase 5.5) │  │    │ /orchestrator      │
         │ mandatory gate      │  │    │ /code-reviewer     │
         └──────────┬──────────┘  │    │ /commit            │
                    │              │    └────────────────────┘
         ┌──────────▼──────────┐  │
         │ .supervisor/jobs/   │  │
         │ pending/{brief}.md  │  │
         └──────────┬──────────┘  │
                    │              │
                    └──────┬───────┘
                           │
                    ┌──────▼──────────────────────────────────┐
                    │           SUPERVISOR v4                   │
                    │  model: inherit  color: #1E90FF           │
                    │  Budget: 30 tool calls                    │
                    │                                           │
                    │  INIT → ACQUIRE → PLAN → EXECUTE →        │
                    │  FINALIZE → SELF_HEAL → LOOP              │
                    └──┬────────┬────────┬────────────────────┘
                       │        │        │
              ┌────────▼──┐  ┌──▼─────┐  │
              │ Context-  │  │Orchest-│  │
              │ Keeper    │  │rator   │  │
              │ #708090   │  │#9370DB │  │
              │ haiku     │  │inherit │  │
              │ maxT: 3   │  │maxT:40 │  │
              └────┬──────┘  └────────┘  │
                   │                      │
            ┌──────▼──────┐               │
            │ .supervisor/│        ┌──────▼──────────────────────────┐
            │ state.md    │        │      EXECUTE MANAGER             │
            └─────────────┘        │  model: inherit  color: #4169E1  │
                                   │  Budget: 60 tool calls           │
                                   │  maxTurns: 80                    │
                                   └──┬──────────────┬───────────────┘
                                      │              │
                              ┌───────▼──────┐ ┌─────▼────────────┐
                              │  Worker A    │ │  Worker B        │
                              │  #32CD32     │ │  #32CD32         │
                              │  maxT: 40    │ │  maxT: 40        │
                              │  (worktree)  │ │  (worktree)      │
                              └───────┬──────┘ └──────┬───────────┘
                                      │               │
                              ┌───────▼──────┐ ┌──────▼───────────┐
                              │ Code Review  │ │ Code Review      │
                              │ A  #20B2AA   │ │ B  #20B2AA       │
                              │ maxT: 40     │ │ maxT: 40         │
                              └──────────────┘ └──────────────────┘

                    ┌──────────────────────────────────────────┐
                    │           POST-EXECUTION                  │
                    └──┬──────────────────────┬───────────────┘
                       │                      │
              ┌────────▼──────────┐  ┌────────▼──────────────┐
              │  QA Strategist   │  │  Red Team Reviewer    │
              │  #FF6347         │  │  #DC143C              │
              │  maxT: 40        │  │  maxT: 60             │
              │  Risk strategy   │  │  Adversarial audit    │
              └────────┬─────────┘  └───────────────────────┘
                       │
              ┌────────▼─────────┐
              │  QA Executor    │
              │  #FF4500         │
              │  maxT: 80        │
              │  Discovery +     │
              │  Tests + Debate  │
              └──────────────────┘
```

---

## Workflow Paths

### Plan-First Autonomous (Recommended for Complex Tasks)

```
/launch-pad goal: "..."
    ↓
.supervisor/jobs/pending/{date}-{slug}.md
    ↓ (fresh session)
/supervisor job: .supervisor/jobs/pending/{file}.md
    ↓
INIT → ACQUIRE (move brief to in-progress/) → PLAN → EXECUTE → FINALIZE → SELF_HEAL (integration review + bounded fix loop; move brief to done/ in completion tail) → LOOP
    ↓
PR created (task completion recorded in SELF_HEAL tail, not FINALIZE)
```

### Direct Autonomous

```
/supervisor task: "..."
    ↓
INIT → ACQUIRE → PLAN → EXECUTE → FINALIZE → SELF_HEAL → LOOP
    ↓
PR created
```

### Manual Workflow

```
/product-owner → User Stories
    ↓
/orchestrator → Tasks with Review Gates
    ↓
Implement → /code-reviewer → PASS/FAIL/NEEDS_HUMAN
    ↓
/commit → Conventional Commits
```

### QA Pipeline

```
/qa-strategist src/ → Risk Classification + Coverage Targets
    ↓
/qa-executor → Discovery → Test Generation → Execution → Coverage
    ↓
/qa-strategist --audit .qa-summary.md → STRATEGIST_VERDICT
```

### Pre-Launch Audit

```
/red-team-reviewer --focus security
    ↓
Fix FATAL/CRITICAL findings
    ↓
/red-team-reviewer (re-audit)
```

---

## State Flow

```
.supervisor/
├── state.md              ← Context-Keeper (sole writer)
├── history/              ← Supervisor (LOOP phase)
├── jobs/
│   ├── pending/          ← Launch Pad (Phase 6 SAVE)
│   ├── in-progress/      ← Supervisor (ACQUIRE phase)
│   ├── done/             ← Supervisor (FINALIZE success)
│   └── failed/           ← Supervisor (on failure/abort)
├── logs/                 ← Supervisor, Execute Manager, Worker (JSONL)
└── worker-summaries/     ← Worker (inline mode)
```

---

## Key References

- Agent prompts: `agents/*.md`
- Result schemas: `docs/RESULT_SCHEMAS.md`
- Failure escalation: `docs/FAILURE_ESCALATION.md`
- Architecture contracts: `docs/ARCHITECTURE_CONTRACTS.md`
- QA system blueprint: `docs/QA_SYSTEM_BLUEPRINT.md`
