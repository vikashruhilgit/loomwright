---
name: ci-cd
description: CI/CD patterns for GitHub Actions. Covers pipeline stages, caching, deployment strategies, secrets management, and quality gates. Use when setting up or reviewing CI/CD workflows.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# CI/CD

GitHub Actions pipeline patterns for reliable builds, tests, and deployments.

---

## When to Use

- Setting up CI pipelines for new projects
- Adding deployment workflows
- Reviewing pipeline configuration for security and efficiency
- Optimizing build times with caching

## When NOT to Use

- Docker image building only — use `docker` skill
- Application-level testing patterns — use `unit-testing` or `playwright-e2e`
- Infrastructure provisioning (Terraform, Pulumi) — separate concern

## Core Patterns

### 1. Standard CI Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npm run test -- --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/lcov.info
```

### 2. Caching Strategy

```yaml
# Node modules cache (handled by setup-node cache: 'npm')
# Custom caches for other tools:
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/playwright
      node_modules/.cache
    key: ${{ runner.os }}-build-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-build-
```

### 3. Secrets Management

```yaml
# Use environment-scoped secrets for deployment
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Deploy
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          API_KEY: ${{ secrets.API_KEY }}
        run: npm run deploy
```

Rules:
- Never hardcode secrets in workflow files
- Use environment protection rules for production
- Rotate secrets regularly; use OIDC for cloud providers when possible
- Scope secrets to the narrowest environment

### 4. Deployment with Gates

```yaml
  deploy-staging:
    needs: [test, e2e]
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - run: npm run deploy:staging

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://app.example.com
    steps:
      - uses: actions/checkout@v4
      - run: npm run deploy:production
      - name: Smoke test
        run: curl -sf https://app.example.com/health || exit 1
```

### 5. Reusable Workflows

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
    secrets:
      DEPLOY_TOKEN:
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/deploy.sh
        env:
          TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

## Example Implementation

A reusable quality check workflow called from the main pipeline:

```yaml
# .github/workflows/quality.yml
name: Quality
on:
  workflow_call:

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test -- --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/lcov.info
      - name: Check coverage threshold
        run: |
          COVERAGE=$(npx coverage-summary --json | jq '.total.lines.pct')
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "Coverage $COVERAGE% is below 80% threshold"
            exit 1
          fi
```

## Testing Approach

- Validate workflow YAML with `actionlint` locally before pushing
- Use `act` (nektos/act) to run GitHub Actions workflows locally against the Docker runtime
- Test reusable workflows by calling them from a test workflow with known inputs and verifying outputs
- Verify concurrency groups by pushing two commits in quick succession and confirming the first run is cancelled

## Anti-Patterns

- **No concurrency control:** Parallel runs on the same branch waste resources. Always set `concurrency` with `cancel-in-progress`.
- **Installing dependencies in every job:** Use caching or share via artifacts.
- **Deploying without health checks:** Always verify the deployment succeeded with a smoke test.
- **Secrets in logs:** Never echo secrets. Use `::add-mask::` for dynamic values.
- **Monolithic workflows:** Split lint, test, build, deploy into separate jobs for parallelism and clarity.

## Example: Full Pipeline

```yaml
name: Pipeline
on:
  push:
    branches: [main]
  pull_request:

jobs:
  quality:
    uses: ./.github/workflows/quality.yml
  test:
    uses: ./.github/workflows/test.yml
  deploy:
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: [quality, test]
    uses: ./.github/workflows/deploy.yml
    with:
      environment: production
    secrets: inherit
```

## Related Skills

- `docker` — Container image builds in CI
- `unit-testing` — Test execution in pipelines
- `playwright-e2e` — E2E tests in CI with browser setup
- `monitoring-observability` — Post-deploy monitoring

## Quality Gates

- [ ] CI runs on every PR and push to main
- [ ] Concurrency groups prevent redundant runs
- [ ] Dependencies are cached (node_modules, Docker layers)
- [ ] Secrets use environment scoping, never hardcoded
- [ ] Production deploy requires prior staging success
- [ ] Post-deploy smoke test or health check exists
- [ ] Workflow files pass `actionlint` validation
