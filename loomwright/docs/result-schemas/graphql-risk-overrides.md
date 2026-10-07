## GRAPHQL_RISK_OVERRIDES

Produced by QA Strategist in Strategy Mode **only when `api_style` is `graphql` or `mixed`**.
Consumed by QA Executor in Phase 7 write-back to persist per-operation risk into `discovery/api-calls.json`.

This is a markdown-table contract (not YAML) because it appears inline in the Strategist's textual output. The Executor parses it by header row match.

### Format

```markdown
### GraphQL Risk Overrides

| Operation | Method | Risk | Reason |
|---|---|---|---|
| createUser | MUTATION | HIGH | auth + data mutation |
| getUsers | QUERY | MEDIUM | (default) |
| deleteOrg | MUTATION | HIGH | destructive, admin-only |
| healthCheck | QUERY | LOW | no side effects |
```

### Validation Rules

- Heading must contain the literal text `GraphQL Risk Overrides` (case-insensitive)
- Table columns MUST be `Operation | Method | Risk | Reason` in this order
- Match key into `api-calls.json` is `Operation` + `Method` together (a query and mutation can share the same name — method disambiguates)
- `Method` values: `QUERY` | `MUTATION` (uppercase)
- `Risk` values: `HIGH` | `MEDIUM` | `LOW`
- `Reason` is free-form human-readable text (not parsed by machines)
- Block is **omitted entirely** when `api_style` is not `graphql`/`mixed` — absence is not an error
- If block is absent for a graphql app: Phase 5B default risks stand (no write-back performed)

### Write-back Behavior (Executor)

For each row in the table:
1. Match by `Operation` + `Method` against entries in `discovery/api-calls.json`
2. If row's `Risk` differs from entry's current `risk`: update the entry's `risk` field via Edit
3. If row has no matching entry: log warning, skip (Strategist may have hallucinated an operation)
4. Operations in `api-calls.json` not listed in the override table: keep existing Phase 5B default

Executor updates `api-calls.json` in-place; no separate overrides file is persisted.

---

