# Plan Tools - Practical Examples

This document provides real-world examples of using the plan MCP tools (`save_plan`, `get_plan`, `search_plans`).

## Table of Contents

- [Basic Usage](#basic-usage)
- [Real-World Scenarios](#real-world-scenarios)
- [Advanced Patterns](#advanced-patterns)
- [Integration with Other Tools](#integration-with-other-tools)
- [Common Workflows](#common-workflows)

## Basic Usage

### Creating Your First Plan

**Scenario:** Document a new feature roadmap

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "save_plan",
    "arguments": {
      "title": "Authentication Feature Roadmap",
      "version": "v1.0",
      "body": "# Authentication Feature Roadmap\n\n## Phase 1: Basic Auth\n- Email/password login\n- Session management\n- Password reset flow\n\n## Phase 2: OAuth\n- Google OAuth\n- GitHub OAuth\n\n## Phase 3: MFA\n- TOTP support\n- SMS backup codes",
      "tags": ["roadmap", "authentication", "security"]
    }
  }
}
```

**Response:**
```
✓ Saved plan "Authentication Feature Roadmap" (v1.0)

Use `get_plan` with title "Authentication Feature Roadmap" to retrieve it.
Use `search_plans` to find plans by content.
```

### Retrieving a Plan

**Scenario:** Get the latest version of a plan

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "get_plan",
    "arguments": {
      "title": "Authentication Feature Roadmap"
    }
  }
}
```

**Response:**
```markdown
# Authentication Feature Roadmap (v1.0)

# Authentication Feature Roadmap

## Phase 1: Basic Auth
- Email/password login
- Session management
- Password reset flow

## Phase 2: OAuth
- Google OAuth
- GitHub OAuth

## Phase 3: MFA
- TOTP support
- SMS backup codes

**Tags:** roadmap, authentication, security
*Created: 2024-01-15 14:30 UTC*
```

### Searching Plans

**Scenario:** Find plans related to security

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "search_plans",
    "arguments": {
      "query": "security best practices",
      "limit": 5
    }
  }
}
```

## Real-World Scenarios

### Scenario 1: API Architecture Planning

**Step 1: Create initial architecture plan**

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "REST API Architecture",
    "version": "draft-2024-01-15",
    "body": "# REST API Architecture\n\n## Design Principles\n- RESTful conventions\n- JSON responses\n- JWT authentication\n\n## Endpoints\n\n### Users\n- GET /api/v1/users\n- POST /api/v1/users\n- GET /api/v1/users/:id\n- PUT /api/v1/users/:id\n- DELETE /api/v1/users/:id\n\n### Posts\n- GET /api/v1/posts\n- POST /api/v1/posts\n- GET /api/v1/posts/:id\n\n## Error Handling\n- Standard HTTP status codes\n- Consistent error response format\n\n## Rate Limiting\n- 100 requests per minute per API key\n- 429 Too Many Requests on limit",
    "tags": ["architecture", "api", "design"]
  }
}
```

**Step 2: After team review, save updated version**

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "REST API Architecture",
    "version": "v1.0",
    "body": "# REST API Architecture\n\n## Design Principles\n- RESTful conventions\n- JSON:API specification\n- OAuth 2.0 + JWT\n- Versioned endpoints\n\n## Endpoints\n\n### Users Resource\n- GET /api/v1/users - List users (paginated)\n- POST /api/v1/users - Create user\n- GET /api/v1/users/:id - Get user details\n- PATCH /api/v1/users/:id - Update user\n- DELETE /api/v1/users/:id - Soft delete user\n\n### Posts Resource\n- GET /api/v1/posts - List posts (paginated, filterable)\n- POST /api/v1/posts - Create post\n- GET /api/v1/posts/:id - Get post with comments\n- PATCH /api/v1/posts/:id - Update post\n- DELETE /api/v1/posts/:id - Soft delete post\n\n## Authentication\n- OAuth 2.0 for user authorization\n- JWT for API authentication\n- Refresh token rotation\n\n## Error Handling\n- Standard HTTP status codes\n- JSON:API error format\n- Error tracking via Sentry\n\n## Rate Limiting\n- Tier-based: 100/1000/10000 req/min\n- Per API key + IP combination\n- 429 with Retry-After header\n\n## Response Format\n- JSON:API specification\n- HATEOAS links for pagination\n- Sparse fieldsets support",
    "tags": ["architecture", "api", "design", "approved"]
  }
}
```

**Step 3: View version history**

```json
{
  "name": "get_plan",
  "arguments": {
    "title": "REST API Architecture",
    "all_versions": true
  }
}
```

**Response:**
```
All versions of "REST API Architecture" (2, most recent first):

  • v1.0 - 2024-01-16 10:45 UTC
  • draft-2024-01-15 - 2024-01-15 14:20 UTC
```

### Scenario 2: Database Migration Planning

**Create migration plan with phases**

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "PostgreSQL to TimescaleDB Migration",
    "version": "v1.0",
    "body": "# PostgreSQL to TimescaleDB Migration Plan\n\n## Overview\nMigrate time-series metrics data from PostgreSQL to TimescaleDB for better performance.\n\n## Current State\n- 500GB of metrics data in PostgreSQL\n- 10M+ rows per day\n- Queries taking 30+ seconds\n\n## Target State\n- TimescaleDB for metrics tables\n- <1s query performance\n- Automatic data retention policies\n\n## Migration Phases\n\n### Phase 1: Setup (Week 1)\n- [ ] Provision TimescaleDB instance\n- [ ] Configure replication from PostgreSQL\n- [ ] Test data consistency\n\n### Phase 2: Dual-Write (Week 2-3)\n- [ ] Update application to write to both DBs\n- [ ] Monitor for write failures\n- [ ] Verify data parity\n\n### Phase 3: Backfill (Week 4)\n- [ ] Backfill historical data\n- [ ] Validate data integrity\n- [ ] Set up monitoring\n\n### Phase 4: Cutover (Week 5)\n- [ ] Switch reads to TimescaleDB\n- [ ] Monitor performance\n- [ ] Stop writes to PostgreSQL\n- [ ] Archive old data\n\n## Rollback Plan\n- Keep PostgreSQL data for 30 days\n- Feature flag for quick rollback\n- Documented rollback procedure\n\n## Success Metrics\n- Query latency < 1s (P95)\n- Zero data loss\n- <5min downtime during cutover",
    "tags": ["database", "migration", "timescaledb", "operations"]
  }
}
```

### Scenario 3: Security Audit Action Plan

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "Q1 2024 Security Audit Remediation",
    "version": "v1.0",
    "body": "# Q1 2024 Security Audit Remediation Plan\n\n## Critical Issues (Fix by: Feb 1)\n\n### 1. SQL Injection Vulnerability in Search\n- **Location:** `app/controllers/search_controller.rb:42`\n- **Fix:** Use parameterized queries\n- **Owner:** @alice\n- **Status:** In Progress\n\n### 2. Missing Rate Limiting on Auth Endpoints\n- **Location:** `/api/auth/*`\n- **Fix:** Implement Rack::Attack rules\n- **Owner:** @bob\n- **Status:** Not Started\n\n## High Priority (Fix by: Feb 15)\n\n### 3. Outdated Dependencies with Known CVEs\n- **Packages:** Rails 6.0.3, Nokogiri 1.10.4\n- **Fix:** Update to latest stable versions\n- **Owner:** @charlie\n- **Status:** Testing\n\n### 4. Weak Password Policy\n- **Current:** Min 6 chars\n- **New:** Min 12 chars, complexity requirements\n- **Owner:** @alice\n- **Status:** Not Started\n\n## Medium Priority (Fix by: Mar 1)\n\n### 5. Missing CSRF Tokens on API Endpoints\n### 6. Insufficient Logging for Security Events\n### 7. No MFA Option for Admin Accounts\n\n## Process Improvements\n- Implement automated dependency scanning (Dependabot)\n- Add security headers to all responses\n- Set up quarterly penetration testing\n- Create security incident response runbook",
    "tags": ["security", "audit", "remediation", "critical"]
  }
}
```

## Advanced Patterns

### Pattern 1: Versioned Roadmaps with Dates

Use date-based versions for time-based planning:

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "Product Roadmap",
    "version": "2024-Q1",
    "body": "# Q1 2024 Product Roadmap\n\n## January\n- User authentication\n- Profile management\n\n## February\n- Social login integration\n- Email notifications\n\n## March\n- Admin dashboard\n- Analytics integration",
    "tags": ["roadmap", "2024", "q1"]
  }
}
```

Then update quarterly:

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "Product Roadmap",
    "version": "2024-Q2",
    "body": "# Q2 2024 Product Roadmap\n\n## April\n- Mobile app MVP\n- Push notifications\n\n## May\n- In-app messaging\n- File uploads\n\n## June\n- Search functionality\n- API v2 launch",
    "tags": ["roadmap", "2024", "q2"]
  }
}
```

### Pattern 2: Architecture Decision Records (ADRs) as Plans

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "ADR-001: Database Choice",
    "version": "accepted",
    "body": "# ADR-001: Use PostgreSQL as Primary Database\n\n## Status\nAccepted\n\n## Context\nWe need to choose a primary database for the application.\n\n## Decision\nUse PostgreSQL 15+\n\n## Consequences\n\n### Positive\n- Strong ACID guarantees\n- Rich ecosystem and tooling\n- JSON support for flexible schemas\n- Full-text search capabilities\n- Mature pgvector for embeddings\n\n### Negative\n- Scaling horizontally requires careful planning\n- May need separate solution for time-series data\n\n## Alternatives Considered\n- MySQL: Less feature-rich\n- MongoDB: Eventual consistency concerns\n- CockroachDB: Added complexity for our scale",
    "tags": ["adr", "architecture", "database", "accepted"]
  }
}
```

### Pattern 3: Discovery and Exploration

**List all available plans:**

```json
{
  "name": "get_plan",
  "arguments": {
    "list_titles": true
  }
}
```

**Response:**
```
Plan titles:
  • ADR-001: Database Choice
  • Authentication Feature Roadmap
  • PostgreSQL to TimescaleDB Migration
  • Product Roadmap
  • Q1 2024 Security Audit Remediation
  • REST API Architecture
```

**Explore plans about a topic:**

```json
{
  "name": "search_plans",
  "arguments": {
    "query": "how do we handle authentication"
  }
}
```

## Integration with Other Tools

### Workflow: Plan → Decide → Context

**Step 1: Create a plan**

```json
{
  "name": "save_plan",
  "arguments": {
    "title": "Cache Strategy",
    "version": "v1.0",
    "body": "# Cache Strategy\n\n## Layers\n1. Browser cache (static assets)\n2. CDN cache (public content)\n3. Redis cache (API responses)\n4. Database query cache\n\n## TTL Policy\n- Static assets: 1 year\n- Public content: 1 hour\n- API responses: 5 minutes\n- Invalidation on updates"
  }
}
```

**Step 2: Record implementation decision**

```json
{
  "name": "decide",
  "arguments": {
    "topic": "caching",
    "decision": "Use Redis for API response caching with 5-minute TTL",
    "reasoning": "Following the Cache Strategy v1.0 plan. Redis provides fast lookups and easy invalidation. 5-minute TTL balances freshness and cache hit rate."
  }
}
```

**Step 3: Save working context during implementation**

```json
{
  "name": "save_context",
  "arguments": {
    "name": "redis-cache-impl",
    "summary": "Implementing Redis cache layer per Cache Strategy v1.0. Set up cache client, implementing cache-aside pattern for API endpoints.",
    "files": ["lib/cache.ex", "lib/api/users.ex"]
  }
}
```

### Workflow: Search Plans → Save Insight

**Search for relevant context:**

```json
{
  "name": "search_plans",
  "arguments": {
    "query": "error handling patterns"
  }
}
```

**After reading and understanding, save insight:**

```json
{
  "name": "insight",
  "arguments": {
    "content": "According to REST API Architecture v1.0, we use JSON:API error format with standard HTTP status codes. All errors are tracked in Sentry.",
    "key": "api/error-handling"
  }
}
```

## Common Workflows

### Workflow 1: Project Kickoff

1. **Document the plan:**
```json
{"name": "save_plan", "arguments": {"title": "Project Phoenix", "version": "v1.0", "body": "..."}}
```

2. **List what's there:**
```json
{"name": "get_plan", "arguments": {"list_titles": true}}
```

3. **Search for related work:**
```json
{"name": "search_plans", "arguments": {"query": "similar to phoenix goals"}}
```

### Workflow 2: Iteration and Updates

1. **Get current version:**
```json
{"name": "get_plan", "arguments": {"title": "Feature X"}}
```

2. **Save updated version:**
```json
{"name": "save_plan", "arguments": {"title": "Feature X", "version": "v1.1", "body": "updated..."}}
```

3. **View history:**
```json
{"name": "get_plan", "arguments": {"title": "Feature X", "all_versions": true}}
```

### Workflow 3: Knowledge Discovery

1. **Search broadly:**
```json
{"name": "search_plans", "arguments": {"query": "performance optimization"}}
```

2. **Get specific plan:**
```json
{"name": "get_plan", "arguments": {"title": "Database Performance Plan", "version": "v2.0"}}
```

3. **Check related decisions:**
```json
{"name": "get_decisions", "arguments": {"topic": "performance"}}
```

## Tips and Best Practices

### Versioning Strategies

**Semantic Versioning:**
- `v1.0` - Initial approved version
- `v1.1` - Minor updates
- `v2.0` - Major revision

**Date-Based:**
- `2024-01-15` - Daily snapshots
- `2024-Q1` - Quarterly plans
- `jan-2024` - Monthly releases

**Status-Based:**
- `draft` - Work in progress
- `review` - Under review
- `approved` - Finalized
- `implemented` - Completed

### Tagging Conventions

Organize plans with consistent tags:

```json
{
  "tags": [
    "architecture",      // Domain
    "q1-2024",          // Time period
    "high-priority",    // Priority
    "approved"          // Status
  ]
}
```

### Search Optimization

**Good search queries:**
- "how do we handle user authentication"
- "database scaling strategy"
- "deployment process -docker" (exclude docker)

**Less effective:**
- "db" (too generic)
- Single words like "plan" or "roadmap"

### Plan Content Structure

Use consistent markdown structure:

```markdown
# [Title]

## Overview
Brief summary of what this plan covers

## Current State
Where we are now

## Goals
What we want to achieve

## Approach
How we'll do it

## Timeline
When things will happen

## Success Metrics
How we'll know we succeeded

## Risks & Mitigation
What could go wrong and how we'll handle it
```

## Troubleshooting

### Issue: "A plan with this title and version already exists"

**Solution:** Use a different version number or check existing versions first:

```json
{"name": "get_plan", "arguments": {"title": "My Plan", "all_versions": true}}
```

### Issue: Can't find a plan I just created

**Solution:** Search by content or list all titles:

```json
{"name": "search_plans", "arguments": {"query": "keywords from your plan"}}
```

or

```json
{"name": "get_plan", "arguments": {"list_titles": true}}
```

### Issue: Too many results from search

**Solution:** Use more specific queries or reduce limit:

```json
{"name": "search_plans", "arguments": {"query": "very specific phrase", "limit": 3}}
```
