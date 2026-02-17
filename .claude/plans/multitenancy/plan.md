# Multi-Tenancy Implementation Plan

## Overview
Transform PopStash from single-user HTTP Basic Auth to multi-tenant SaaS with passwordless authentication. Users can belong to multiple organizations, with data isolated by org_id foreign keys.

## Motivation
- **Multi-user collaboration**: Enable teams to work together in shared organizations
- **Data isolation**: Each organization has complete data separation
- **Better UX**: Passwordless email authentication instead of shared HTTP Basic Auth
- **SaaS readiness**: Scale to multiple tenants with proper access control

## Design Philosophy
- Use Phoenix/Elixir best practices (mix phx.gen.auth, contexts, LiveView patterns)
- Follow foreign-key multi-tenancy pattern (org_id on every content table)
- Enforce org_id at the Repo level via `prepare_query` callback — impossible to forget
- Accept `%Scope{}` in context function heads as the access control mechanism
- Zero breaking changes to MCP endpoint

## Architecture

### Core Concepts
- **Organization**: Top-level tenant boundary (has projects, insights, decisions)
- **User**: Can belong to multiple organizations with role-based membership
- **OrgMember**: Join table with roles (owner, member)
- **Scope**: Access control struct containing org_id, user_id, role
- **Repo.prepare_query**: Automatic org_id filtering on ALL read queries (except excluded tables)

### Data Model
```
organizations (tenant boundary, excluded from prepare_query)
├── projects (add org_id FK)
│   ├── insights (add org_id FK)
│   ├── decisions (add org_id FK)
│   └── search_logs (add org_id FK)
└── org_members (join table, excluded from prepare_query)
    └── users (excluded from prepare_query)
        └── users_tokens (excluded from prepare_query)
```

### Access Control Flow
1. User logs in via magic link (passwordless)
2. User selects organization (sets selected_org_id)
3. Scope created from user + selected org
4. `Repo.put_org_id(scope.org_id)` called — sets org_id in process dictionary
5. `prepare_query` automatically filters ALL reads by org_id
6. Contexts validate org access before mutations (writes)
7. Tables without org_id (users, organizations, org_members, users_tokens) are excluded

### Excluded Tables (`@skip_org_id_tables`)
These tables are listed in `Repo.@skip_org_id_tables` and are automatically skipped
by `prepare_query` — no `skip_org_id: true` needed on individual calls:
- `organizations` — queried during org selection/creation
- `users` — queried during authentication
- `users_tokens` — queried during token verification
- `org_members` — queried during scope creation (before org_id is known)

## Implementation Steps

### Step 0: Database Foundation
- Create organizations table
- Create org_members join table
- Run mix phx.gen.auth for users/authentication
- Modify users table (remove password, add selected_org_id)
- **Orthogonal**: Pure database changes, no application logic

### Step 1: Add org_id to Content Tables
- Add nullable org_id to projects, insights, decisions, search_logs
- Migrate existing data to "Default Organization"
- Add NOT NULL constraints
- Update schema files
- **Orthogonal**: Database changes + schema updates only

### Step 2: Passwordless Authentication
- Remove password from phx.gen.auth generated code
- Implement magic link token generation
- Create email delivery (UserNotifier)
- Update Accounts context for passwordless flow
- Create login LiveViews
- **Orthogonal**: Complete auth system, testable independently

### Step 3: Core Access Control & Repo Enforcement
- Create Scope module
- Create Organizations context
- Create Memberships context
- Add `Repo.transact` helper
- Add `Repo.prepare_query` — enforces org_id on every query
- Add `Repo.default_options` — auto-injects org_id from process dictionary
- Add `Repo.put_org_id/1` and `Repo.get_org_id/0` — process dictionary helpers
- **Orthogonal**: Access control primitives, no UI changes

### Step 4: Update Contexts for Org Scoping
- Update Projects context to accept Scope parameter
- Update Memory context to accept Scope parameter
- Update Activity context to accept Scope parameter
- Reads are auto-filtered by `prepare_query`, contexts add Scope for writes
- **Orthogonal**: Context changes only, no UI or routing changes

### Step 5: Router & OrgPlug
- Create OrgPlug for LiveView on_mount
- Call `Repo.put_org_id` when scope is established
- Update router pipelines (remove BasicAuth, add UserAuth)
- Create org selection LiveViews
- **Orthogonal**: Routing layer, connects auth to access control

### Step 6: Update LiveViews
- Update all dashboard LiveViews to use scoped context calls
- Add current_scope assigns
- Update PubSub subscriptions to org-scoped topics
- **Orthogonal**: UI updates, uses scoped contexts from Step 4

### Step 7: MCP Multi-Tenancy
- Update MCP controller to derive org_id from project
- Call `Repo.put_org_id` for MCP requests
- Add `Projects.get_by_id` (non-scoped, system operation)
- **Orthogonal**: MCP is localhost-only, independent of Steps 5/6

### Step 8: Testing & Polish
- Unit tests for contexts and Repo enforcement
- Integration tests for auth flow
- Cross-org isolation tests (verify prepare_query blocks leaks)
- LiveView tests
- **Orthogonal**: Quality assurance

## Success Criteria
- Passwordless authentication working
- Multi-organization support
- Complete data isolation by org_id (enforced at Repo level)
- `prepare_query` raises on missing org_id (cannot forget)
- Zero breaking changes to MCP endpoint
- All tests passing
- No N+1 queries
- Dashboard performance maintained
