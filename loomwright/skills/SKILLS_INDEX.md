# Skills Index

Comprehensive index of all skills available in the Loomwright plugin.

---

## Workflow / Orchestration

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Supervisor Readiness | `supervisor-readiness/` | Launch Pad (preload), Supervisor (preload) | ~800 | 1.1.2 | 2026-06-14 |
| Workflow Management | `workflow-management/` | Supervisor (preload) | ~1,200 | 1.0.0 | 2026-03 |
| Async Orchestration | `async-orchestration/` | Supervisor (preload) | ~1,000 | 1.0.0 | 2026-05-09 |
| State Management | `state-management/` | Supervisor (preload) | ~900 | 1.1.0 | 2026-05 |
| Context Summarization | `context-summarization/` | Supervisor (preload) | ~600 | 1.0.0 | 2026-03 |
| Context Setup | `context-setup/` | Launch Pad (preload) | ~500 | 1.0.0 | 2026-03 |
| Claude MD Validation | `claude-md-validation/` | Launch Pad (preload) | ~400 | 1.0.0 | 2026-03 |
| Agent Teams | `agent-teams/` | — (reference) | ~800 | 1.1.0 | 2026-05-10 |
| Agent Output | `agent-output/` | — (reference) | ~400 | 1.0.0 | 2026-03 |
| Beads Workflow | `beads-workflow/` | Orchestrator (reference), Product Owner (reference) | ~600 | 1.0.0 | 2026-03 |
| Telemetry | `telemetry/` | — (reference, shell-script-driven) | ~600 | 1.0.0 | 2026-04 |
| Memory Tool | `memory-tool/` | — (reference) | ~500 | 1.0.0 | 2026-05-10 |
| Autonomous Loop | `autonomous-loop/` | `/autonomous` (slash command, reference) | ~2,800 [^al-tokens] | 1.4.0 | 2026-07-06 |
| Automate Loop | `automate-loop/` | `/automate` (slash command, reference) | ~3,200 | 1.2.0 | 2026-07-06 |
| Review Heal | `review-heal/` | `review-pr-runner` (preload), `/review-pr` + Supervisor + `/autonomous` (reference) | ~3,000 | 1.4.0 | 2026-06-22 |
| Self-Heal Advisory | `self-heal-advisory/` | Supervisor (on-demand Read at Phase 4.5 entry — deliberately NOT preloaded) | ~2,000 | 1.0.0 | 2026-06-10 |
| PR Postmortem | `pr-postmortem/` | `/pr-postmortem` (slash command, reference) | ~1,400 | 1.3.0 | 2026-06-13 |
| Setup | `setup/` | `/setup` (slash command, read at Step 0) | ~1,200 | 1.0.0 | 2026-06-13 |
| Brain Context | `brain-context/` | Launch Pad / Code Reviewer / Supervisor (on-demand Read — deliberately NOT preloaded) | ~1,500–2,000 | 1.0.0 | 2026-06-16 |
| Rules | `rules/` | `/rules` (slash command, reference) | ~1,300 | 1.1.0 | 2026-07-03 |

[^al-tokens]: The `autonomous-loop` skill is intentionally larger than the other reference-category skills (~500–600 tokens). It encodes the full `/autonomous` orchestration protocol (loop phases, EVALUATE branching, signal-extraction algorithms, refined-requirement templates, `AUTONOMOUS_RUN` summary format, failure-modes table) — comprehensive by design because it is the single source of truth for the loop's behavior, read at runtime by the main thread via Step 0. Splitting it across smaller files would fragment the protocol and risk drift; the trade-off is the higher token cost on the one slash command that loads it.

## Development Practices

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Quality Checklist | `quality-checklist/` | Orchestrator (preload), Code Reviewer (preload), QA Strategist (preload), QA Executor (preload) | ~500 | 1.2.0 | 2026-06-27 |
| Commit | `commit/` | — (reference) | ~600 | 1.1.0 | 2026-06 |
| Pattern Detector | `pattern-detector/` | Code Reviewer (reference) | ~500 | 1.0.0 | 2026-03 |
| Context7 Lookup | `context7-lookup/` | Launch Pad (preload), Code Reviewer (preload), Red Team Reviewer (preload) | ~300 | 1.0.0 | 2026-03 |
| Unit Testing | `unit-testing/` | Worker (reference), Code Reviewer (preload) | ~800 | 1.0.0 | 2026-03 |
| Error Handling | `error-handling/` | Worker (reference), Code Reviewer (preload) | ~900 | 1.0.0 | 2026-03 |
| CI/CD | `ci-cd/` | Orchestrator (reference), Worker (reference) | ~900 | 1.0.0 | 2026-03 |
| Docker | `docker/` | Worker (reference) | ~800 | 1.0.0 | 2026-03 |
| Monitoring & Observability | `monitoring-observability/` | Red Team Reviewer (reference), Code Reviewer (preload) | ~900 | 1.0.0 | 2026-03 |

## Product / Discovery

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Product Discovery | `product-discovery/` | Launch Pad (preload) | ~600 | 1.0.0 | 2026-03 |
| MVP Scoping | `mvp-scoping/` | Launch Pad (preload) | ~500 | 1.0.0 | 2026-03 |
| User Story Writing | `user-story-writing/` | Product Owner (reference) | ~500 | 1.0.0 | 2026-03 |
| Domain Knowledge | `domain-knowledge/` | Product Owner (reference) | ~400 | 1.0.0 | 2026-03 |
| Brainstorming | `brainstorming/` | Product Owner (preload) | ~1,000 | 1.0.0 | 2026-04 |

## Framework — NestJS

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| NestJS Controllers | `nestjs-controllers/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |
| NestJS Services | `nestjs-services/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |
| NestJS Guards | `nestjs-guards/` | Worker (reference) | ~600 | 1.0.0 | 2026-03 |
| NestJS TypeORM | `nestjs-typeorm/` | Worker (reference) | ~800 | 1.0.0 | 2026-03 |
| NestJS Drizzle | `nestjs-drizzle/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |

## Framework — Next.js

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Next.js Routing | `nextjs-routing/` | Worker (reference) | ~600 | 1.0.0 | 2026-03 |
| Next.js Components | `nextjs-components/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |
| Next.js API Routes | `nextjs-api-routes/` | Worker (reference) | ~600 | 1.0.0 | 2026-03 |
| Next.js Data Fetching | `nextjs-data-fetching/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |
| Next.js Auth | `nextjs-auth/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |
| Frontend UI | `frontend-ui/` | Worker (reference) | ~600 | 1.0.0 | 2026-03 |

## Framework — API Gateway

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Gateway Auth Middleware | `gateway-auth-middleware/` | Worker (reference) | ~600 | 1.0.0 | 2026-03 |
| Gateway Correlation | `gateway-correlation/` | Worker (reference) | ~500 | 1.0.0 | 2026-03 |
| Gateway Proxy Patterns | `gateway-proxy-patterns/` | Worker (reference) | ~600 | 1.0.0 | 2026-03 |
| Gateway Rate Limiting | `gateway-rate-limiting/` | Worker (reference) | ~500 | 1.0.0 | 2026-03 |

## Testing / QA

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| Playwright E2E | `playwright-e2e/` | QA Executor (preload) | ~1,500 | 1.0.0 | 2026-03 |
| QA Strategy | `qa-strategy/` | QA Strategist (preload), QA Executor (preload) | ~1,100 | 1.0.0 | 2026-03 |
| QA Gates | `qa-gates/` | QA Executor (preload), QA Strategist (preload) | ~1,400 | 1.0.0 | 2026-06-10 |
| QA Test Patterns | `qa-test-patterns/` | QA Executor (preload) | ~1,800 | 1.0.0 | 2026-06-10 |
| QA Orchestration | `qa-orchestration/` | QA Executor (reference) | ~900 | 1.0.0 | 2026-03 |

## Database

| Skill Name | Directory | Agent Consumers | Token Est. | Version | Last Updated |
|------------|-----------|-----------------|------------|---------|--------------|
| MySQL | `mysql/` | Worker (reference) | ~700 | 1.0.0 | 2026-03 |
| PostgreSQL | `postgresql/` | Worker (reference) | ~800 | 1.0.0 | 2026-03 |
| Redis Caching | `redis-caching/` | Worker (reference) | ~800 | 1.0.0 | 2026-03 |

---

**Total: 57 skills**

_Last updated: 2026-07-06_
