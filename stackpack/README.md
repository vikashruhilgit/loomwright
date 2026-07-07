# Stackpack

Generic tech-stack reference skills for Claude Code — Next.js, NestJS, API-gateway patterns, MySQL, PostgreSQL, Redis, and Docker. 18 skills, no agents, commands, or hooks.

These skills were part of the [Loomwright](../loomwright) plugin through v15.5.0 and were spun out so Loomwright can focus on its orchestration core. Install Stackpack alongside Loomwright to keep the same on-demand stack guidance available to workers and reviewers.

## Install

```
/plugin install stackpack@atelier
```

## The 18 Skills

**Next.js**
- `nextjs-routing` — App Router routing patterns
- `nextjs-components` — Server/client component patterns
- `nextjs-api-routes` — API route handlers
- `nextjs-data-fetching` — Data fetching and caching
- `nextjs-auth` — Authentication flows

**NestJS**
- `nestjs-controllers` — Controller patterns
- `nestjs-services` — Service/provider patterns
- `nestjs-guards` — Guards and auth
- `nestjs-typeorm` — TypeORM integration
- `nestjs-drizzle` — Drizzle ORM integration

**API Gateway**
- `gateway-auth-middleware` — Auth middleware patterns
- `gateway-correlation` — Correlation-ID propagation
- `gateway-proxy-patterns` — Proxying patterns
- `gateway-rate-limiting` — Rate-limiting strategies

**Database / Infrastructure**
- `mysql` — MySQL patterns
- `postgresql` — PostgreSQL patterns
- `redis-caching` — Redis caching strategies
- `docker` — Docker and docker-compose patterns

See `skills/SKILLS_INDEX.md` for versions and token estimates.

## Notes

- All skills are reference material, consumed on demand — nothing here is preloaded into agents.
- These snapshots capture stable patterns; for the freshest upstream documentation of any of these frameworks, Loomwright's `context7-lookup` skill serves current docs on demand via the Context7 MCP.

## License

MIT
