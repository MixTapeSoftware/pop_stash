# Multi-Tenancy Implementation Plan

## Overview

Transform PopStash from single-user HTTP Basic Auth to multi-tenant SaaS with passwordless authentication. Users can belong to multiple organizations, with data isolated by org_id foreign keys enforced at the Repo level.

## Current Architecture

- **Auth**: HTTP Basic Auth via `PopStashWeb.Plugs.BasicAuth` (skipped in dev/test)
- **Router**: Single scope at "/" with `pop_stash_dashboard` macro, MCP at "/mcp"
- **Contexts**: `PopStash.Projects`, `PopStash.Memory`, `PopStash.Activity` -- no user/org awareness
- **Schemas**: `Project`, `Insight`, `Decision`, `SearchLog` -- all have `project_id`, no `org_id`
- **MCP**: JSON-RPC 2.0 via `PopStash.MCP.Server` with tool modules, localhost-only
- **Dashboard**: Uses `PopStashWeb.Dashboard` module with own layouts, live_session `:pop_stash_dashboard`
- **Repo**: Plain `Ecto.Repo` at `/workspace/lib/pop_stash/repo.ex`, no `transact` or `prepare_query`
- **Tests**: No factories, direct context calls in setup blocks

## Design Decisions

1. **Foreign-key multi-tenancy** (not schema-per-tenant) -- org_id column on content tables
2. **`Repo.prepare_query`** auto-injects `WHERE org_id = ?` on all reads for content tables
3. **`Repo.put_org_id/1`** stores org_id in process dictionary, consumed by `prepare_query`
4. **Scope struct** carries `org_id`, `user_id`, `role` -- passed to context functions for writes
5. **Passwordless auth** via magic link tokens (no passwords)
6. **Registration creates org atomically** -- `Repo.transact` wraps org + user + membership creation
7. **Org slug uniqueness only on submit** -- no `unsafe_validate_unique` (prevents enumeration)
8. **MCP derives org_id from project** -- no auth changes needed for localhost MCP

## Data Model

```
organizations (excluded from prepare_query)
  |-- id, name, slug, settings, timestamps

users (excluded from prepare_query)
  |-- id, email, confirmed_at, selected_org_id -> organizations, timestamps

users_tokens (excluded from prepare_query)
  |-- id, user_id, token, context, sent_to, timestamps

org_members (excluded from prepare_query)
  |-- id, org_id -> organizations, user_id -> users, role, timestamps

projects (ADD org_id -> organizations)
insights (ADD org_id -> organizations)
decisions (ADD org_id -> organizations)
search_logs (ADD org_id -> organizations)
```

## Skip Tables for prepare_query

`@skip_org_id_tables ~w(organizations users users_tokens org_members schema_migrations)`

These are detected by source table name in `prepare_query` -- no `skip_org_id: true` needed.

## Implementation Steps

| Step | Scope | Orthogonal? | Dependencies |
|------|-------|-------------|--------------|
| 0 | Database foundation + schemas (orgs, users, org_members, org_id on content) | Yes | None |
| 1 | Repo.transact + Repo.prepare_query + Scope struct + fix broken tests | Yes | Step 0 (tables exist) |
| 2 | Passwordless auth (phx.gen.auth, remove passwords, magic links, registration with org) | Yes | Step 0 (users table) |
| 3 | Organizations + Memberships contexts | Yes | Step 0, Step 1 |
| 4 | Update existing contexts (Projects, Memory, Activity) for Scope + fix broken tests | Partial | Step 1 (Repo enforcement) |
| 5 | Router, OrgPlug, org switcher -- wire auth to dashboard | Partial | Steps 2, 3, 4 |
| 6 | Update dashboard LiveViews for scoped context calls + fix broken LiveView tests | No | Step 4, 5 |
| 7 | MCP multi-tenancy + Typesense org_id | Yes | Step 1, 4 |
| 8 | Team invitation flow (invite by email, accept, manage members UI) | Partial | Steps 2, 3, 5 |

## Key Files to Modify

- `/workspace/lib/pop_stash/repo.ex` -- add transact, prepare_query, put_org_id
- `/workspace/lib/pop_stash/projects.ex` -- add Scope parameter
- `/workspace/lib/pop_stash/projects/project.ex` -- add org_id belongs_to
- `/workspace/lib/pop_stash/memory.ex` -- add Scope parameter
- `/workspace/lib/pop_stash/memory/insight.ex` -- add org_id belongs_to
- `/workspace/lib/pop_stash/memory/decision.ex` -- add org_id belongs_to
- `/workspace/lib/pop_stash/memory/search_log.ex` -- add org_id belongs_to
- `/workspace/lib/pop_stash/activity.ex` -- add Scope parameter
- `/workspace/lib/pop_stash_web/router.ex` -- remove BasicAuth, add UserAuth pipelines
- `/workspace/lib/pop_stash_web/dashboard/router.ex` -- add on_mount hooks
- `/workspace/lib/pop_stash_web/dashboard/components/layouts/dashboard.html.heex` -- org switcher
- `/workspace/lib/pop_stash_web/dashboard/live/home_live.ex` -- use scoped calls
- `/workspace/lib/pop_stash_web/dashboard/live/project_live/index.ex` -- use scoped calls
- `/workspace/lib/pop_stash_web/controllers/mcp_controller.ex` -- set org_id from project

## New Files to Create

- `/workspace/lib/pop_stash/scope.ex`
- `/workspace/lib/pop_stash/organizations.ex`
- `/workspace/lib/pop_stash/organizations/organization.ex`
- `/workspace/lib/pop_stash/organizations/org_member.ex`
- `/workspace/lib/pop_stash/organizations/invitation.ex`
- `/workspace/lib/pop_stash/memberships.ex`
- `/workspace/lib/pop_stash/accounts.ex` (generated by phx.gen.auth, modified)
- `/workspace/lib/pop_stash/accounts/user.ex` (generated, modified)
- `/workspace/lib/pop_stash/accounts/user_token.ex` (generated, modified)
- `/workspace/lib/pop_stash/accounts/user_notifier.ex`
- `/workspace/lib/pop_stash_web/plugs/org_plug.ex`
- `/workspace/lib/pop_stash_web/dashboard/hooks/org_switcher_hook.ex`
- `/workspace/lib/pop_stash_web/live/user_login_live.ex`
- `/workspace/lib/pop_stash_web/live/user_registration_live.ex`
- `/workspace/lib/pop_stash_web/live/org_selection_live.ex`
- `/workspace/lib/pop_stash_web/live/accept_invitation_live.ex`
- `/workspace/lib/pop_stash_web/dashboard/live/team_live/index.ex`
- `/workspace/lib/pop_stash_web/dashboard/live/team_live/invite_form_component.ex`
- `/workspace/test/support/fixtures/accounts_fixtures.ex`

## Success Criteria

- Passwordless authentication working end-to-end
- Multi-organization support with org switching
- Complete data isolation by org_id (enforced at Repo level via prepare_query)
- prepare_query raises on missing org_id for content tables
- Zero breaking changes to MCP endpoint (JSON-RPC 2.0 contract unchanged)
- Typesense search includes org_id filtering for defense-in-depth
- Invite-to-team flow working (send invite email, accept, join org)
- Team management UI for viewing members, sending invites, removing members
- All existing tests updated and passing (fixed incrementally per step)
- Cross-org isolation verified in tests
- No N+1 queries introduced

## Resolved Decisions

1. **Typesense org_id**: YES -- add `org_id` to `@insights_schema` and `@decisions_schema` in `/workspace/lib/pop_stash/search/typesense.ex`. Handled in Step 7 alongside MCP changes.
2. **Invitation flow**: YES -- invite-to-team by email. New Step 8 covers creating invitations, sending invite emails, accepting invitations, and team member management UI.
3. **Test breakage**: Fix incrementally -- each step fixes any tests it breaks, not batched.

## Open Questions

1. Should MCP support org-scoped API keys for remote access in the future?
