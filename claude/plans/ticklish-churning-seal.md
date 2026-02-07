# Multi-Tenancy Implementation Plan for PopStash

## Context

PopStash currently uses HTTP Basic Auth and project-level isolation. We're implementing **foreign-key multi-tenancy** where:

- Users can belong to multiple organizations
- Organizations contain projects and all associated data (insights, decisions, search logs)
- Every content table gets an `org_id` foreign key
- Users have a `selected_org_id` to indicate their current working context
- Access control enforced through a DAL (Data Access Layer) pattern with Scope validation

**Why this change:**
- Enable true multi-user collaboration with proper authentication
- Provide organization-level data isolation and access control
- Support passwordless authentication for better UX
- Scale to SaaS model with multiple tenants

**Key Design Decisions:**
- Use `mix phx.gen.auth` as foundation, customize for passwordless
- Implement Scope pattern (like Ecto.Multi.Scope) for access control
- Wrap existing contexts with DAL modules for org-scoped queries
- Keep MCP endpoint IP-protected (no breaking changes to API)
- Migrate existing data to a "Default Organization"

---

## Phase 1: Database Foundation

### Migrations (Run in order, no skipping)

**Migration 1-3: Core Tables**
```bash
mix ecto.gen.migration create_organizations
mix phx.gen.auth Accounts User users
mix ecto.gen.migration modify_users_for_passwordless
```

**Tables to create:**
1. **organizations**: `id, name, slug, settings, timestamps`
   - Unique index on `slug`
   - Slug format: `[a-z0-9-]+`

2. **users** (from phx.gen.auth): `id, email, confirmed_at, timestamps`
   - Remove `hashed_password` field
   - Add `selected_org_id` references organizations

3. **users_tokens** (from phx.gen.auth): `id, user_id, token, context, sent_to, inserted_at`
   - Context values: "login", "confirm_email"
   - Tokens expire in 1 hour for login

4. **org_members**: `id, org_id, user_id, role, timestamps`
   - Roles: "owner", "member" (enum)
   - Unique index on `[org_id, user_id]`

**Migration 4-7: Add org_id to content tables**
```elixir
# Add nullable org_id first
alter table(:projects) do
  add :org_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
end

# Repeat for: insights, decisions, search_logs
```

**Migration 8: Data Migration**
```elixir
# Create default org
# Assign all existing projects to default org
# Propagate org_id from projects to child records (insights, decisions, search_logs)
```

**Migration 9: Add NOT NULL constraints**
```elixir
alter table(:projects) do
  modify :org_id, :binary_id, null: false
end

# Repeat for: insights, decisions, search_logs
```

**Indexes to create:**
```sql
-- Organizations
CREATE INDEX idx_orgs_slug ON organizations(slug);

-- Projects
CREATE INDEX idx_projects_org_id ON projects(org_id);

-- Insights
CREATE INDEX idx_insights_org_project ON insights(org_id, project_id);
CREATE INDEX idx_insights_org_updated ON insights(org_id, updated_at DESC);

-- Decisions
CREATE INDEX idx_decisions_org_project ON decisions(org_id, project_id);
CREATE INDEX idx_decisions_org_inserted ON decisions(org_id, inserted_at DESC);

-- Search Logs
CREATE INDEX idx_search_logs_org_project ON search_logs(org_id, project_id);
```

---

## Phase 2: Schemas & Core Contexts

### New Schemas

**`lib/pop_stash/accounts/user.ex`** (modify from phx.gen.auth)
- Remove `hashed_password` field
- Add `belongs_to :selected_org, PopStash.Organizations.Organization`
- Add `has_many :org_members, PopStash.Organizations.OrgMember`
- Add `has_many :organizations, through: [:org_members, :organization]`
- Email validation only (no password)

**`lib/pop_stash/organizations/organization.ex`**
```elixir
schema "organizations" do
  field :name, :string
  field :slug, :string
  field :settings, :map, default: %{}

  has_many :projects, PopStash.Projects.Project
  has_many :insights, PopStash.Memory.Insight
  has_many :decisions, PopStash.Memory.Decision
  has_many :search_logs, PopStash.Memory.SearchLog
  has_many :org_members, PopStash.Organizations.OrgMember
  has_many :users, through: [:org_members, :user]

  timestamps()
end
```

**`lib/pop_stash/organizations/org_member.ex`**
```elixir
schema "org_members" do
  field :role, :string, default: "member"

  belongs_to :organization, PopStash.Organizations.Organization
  belongs_to :user, PopStash.Accounts.User

  timestamps()
end
```

### Update Existing Schemas

**All content schemas** (Project, Insight, Decision, SearchLog):
```elixir
# Add to each schema
belongs_to :organization, PopStash.Organizations.Organization, foreign_key: :org_id
```

### New Contexts

**`lib/pop_stash/organizations.ex`**
- `create(name, creator_user_id, opts)` - Creates org + owner membership
- `get(id)` - Get by ID
- `get_by_slug(slug)` - Get by slug
- `list_for_user(user_id)` - List user's orgs
- `update(org_id, attrs)` - Update org
- `delete(org_id)` - Delete org (cascades)

**`lib/pop_stash/memberships.ex`**
- `add_member(org_id, user_id, role)` - Add member
- `remove_member(scope, user_id)` - Remove (owner only)
- `update_member_role(scope, user_id, new_role)` - Change role (owner only)
- `list_members(org_id)` - List org members
- `has_role?(org_id, user_id, role)` - Check role
- `get_role(org_id, user_id)` - Get user's role

---

## Phase 3: Access Control Architecture

### Scope Module

**`lib/pop_stash/scope.ex`**
```elixir
defmodule PopStash.Scope do
  defstruct [:org_id, :user_id, :role]

  @type t :: %__MODULE__{
    org_id: binary() | nil,
    user_id: binary() | nil,
    role: :owner | :member | nil
  }

  def from_user(%User{selected_org_id: nil}), do: {:error, :no_org_selected}
  def from_user(%User{selected_org_id: org_id, id: user_id} = user) do
    # Verify membership, get role, return scope
  end

  def owner?(%__MODULE__{role: :owner}), do: true
  def owner?(_), do: false

  def validate_org_access(%__MODULE__{org_id: org_id}, %{org_id: record_org_id}) do
    if org_id == record_org_id, do: :ok, else: {:error, :unauthorized}
  end
end
```

### Repo Extension

**`lib/pop_stash/repo.ex`** (add to existing)
```elixir
def transact(fun) when is_function(fun, 0) do
  transaction(fn ->
    case fun.() do
      {:ok, result} -> result
      {:error, reason} -> rollback(reason)
    end
  end)
end
```

### DAL Pattern (Wrap Existing Contexts)

**Key Pattern:**
```elixir
defmodule PopStash.ProjectsDAL do
  alias PopStash.Projects
  alias PopStash.Projects.Project
  alias PopStash.Repo
  alias PopStash.Scope

  def validate_selected_org(%Scope{org_id: nil}), do: {:error, :no_org_selected}
  def validate_selected_org(%Scope{org_id: _}), do: :ok

  def create(%Scope{} = scope, name, opts \\ []) do
    with :ok <- validate_selected_org(scope) do
      attrs = %{name: name, org_id: scope.org_id} |> Map.merge(Map.new(opts))
      %Project{} |> Project.changeset(attrs) |> Repo.insert()
    end
  end

  def get(%Scope{} = scope, id) do
    with :ok <- validate_selected_org(scope) do
      case Repo.get(Project, id) do
        nil -> {:error, :not_found}
        %Project{org_id: org_id} = p when org_id == scope.org_id -> {:ok, p}
        _ -> {:error, :unauthorized}
      end
    end
  end

  def list(%Scope{} = scope) do
    with :ok <- validate_selected_org(scope) do
      Project
      |> where([p], p.org_id == ^scope.org_id)
      |> order_by([p], desc: :inserted_at)
      |> Repo.all()
    end
  end
end
```

**DAL Modules to Create:**
- `lib/pop_stash/projects_dal.ex` - Wraps `PopStash.Projects`
- `lib/pop_stash/memory_dal.ex` - Wraps `PopStash.Memory`
- `lib/pop_stash/activity_dal.ex` - Wraps `PopStash.Activity`

**Note:** Keep original contexts unchanged. DAL adds org scoping layer.

---

## Phase 4: Passwordless Authentication

### Token Flow

1. User enters email → System generates magic link token
2. Send email with link containing token
3. User clicks link → Validate token → Create session
4. Redirect to org selection if no `selected_org_id`

### Key Files

**`lib/pop_stash/accounts/user_token.ex`** (from phx.gen.auth)
- Build login tokens with 1-hour expiry
- Hash tokens with SHA256
- Store hashed version in DB

**`lib/pop_stash/accounts/user_notifier.ex`**
```elixir
def deliver_login_instructions(user, url) do
  deliver(user.email, "Your PopStash login link", """
  Click the link below to sign in:

  #{url}

  This link will expire in 1 hour.
  """)
end
```

**`lib/pop_stash/accounts.ex`** (add to generated context)
```elixir
def deliver_user_login_instructions(user, login_url_fun) do
  {encoded_token, user_token} = UserToken.build_email_token(user, "login")
  Repo.insert!(user_token)
  UserNotifier.deliver_login_instructions(user, login_url_fun.(encoded_token))
end

def get_user_by_login_token(token) do
  with {:ok, query} <- UserToken.verify_email_token_query(token, "login"),
       %User{} = user <- Repo.one(query) do
    Repo.delete_all(UserToken.token_and_context_query(token, "login"))
    {:ok, user}
  else
    _ -> :error
  end
end
```

### LiveViews to Create

- `lib/pop_stash_web/live/user_registration_live.ex` - Email registration
- `lib/pop_stash_web/live/user_login_live.ex` - Email login (no password field)
- `lib/pop_stash_web/live/user_settings_live.ex` - User settings
- `lib/pop_stash_web/live/org_selection_live.ex` - Choose/create org
- `lib/pop_stash_web/live/org_form_live.ex` - New org form

---

## Phase 5: Router & Plugs

### OrgPlug

**`lib/pop_stash_web/plugs/org_plug.ex`**
```elixir
defmodule PopStashWeb.OrgPlug do
  import Phoenix.Component
  import Phoenix.LiveView

  alias PopStash.Scope

  # For routes that work with or without org
  def on_mount(:assign_current_org, _params, _session, socket) do
    socket =
      case socket.assigns[:current_user] do
        nil -> socket
        user -> assign_current_scope(socket, user)
      end

    {:cont, socket}
  end

  # For routes that REQUIRE org selection
  def on_mount(:ensure_org_selected, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil -> {:halt, redirect(socket, to: "/users/log-in")}
      user ->
        socket = assign_current_scope(socket, user)
        case socket.assigns[:current_scope] do
          %Scope{org_id: nil} -> {:halt, redirect(socket, to: "/orgs/select")}
          %Scope{} -> {:cont, socket}
        end
    end
  end

  defp assign_current_scope(socket, user) do
    case Scope.from_user(user) do
      {:ok, scope} -> assign(socket, :current_scope, scope)
      _ -> assign(socket, current_scope: nil)
    end
  end
end
```

### Router Configuration

**`lib/pop_stash_web/router.ex`**
```elixir
defmodule PopStashWeb.Router do
  use PopStashWeb, :router
  import PopStashWeb.Dashboard.Router
  import PopStashWeb.UserAuth

  # Remove BasicAuth, add UserAuth
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PopStashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{...}
    plug :fetch_current_user  # From UserAuth
  end

  # Public auth routes
  scope "/", PopStashWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PopStashWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log-in", UserLoginLive, :new
      live "/users/log-in/:token", UserLoginLive, :verify
    end

    post "/users/log-in", UserSessionController, :create
  end

  # Authenticated routes (no org required)
  scope "/", PopStashWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {PopStashWeb.UserAuth, :ensure_authenticated},
        {PopStashWeb.OrgPlug, :assign_current_org}
      ] do
      live "/users/settings", UserSettingsLive, :edit
      live "/orgs/select", OrgSelectionLive, :index
      live "/orgs/new", OrgFormLive, :new
    end

    delete "/users/log-out", UserSessionController, :delete
  end

  # Org-scoped routes (requires org selection)
  scope "/", PopStashWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :org_scoped,
      on_mount: [
        {PopStashWeb.UserAuth, :ensure_authenticated},
        {PopStashWeb.OrgPlug, :ensure_org_selected}
      ] do
      pop_stash_dashboard("/")
    end
  end

  # MCP stays IP-protected (no changes)
  scope "/mcp", PopStashWeb do
    pipe_through :mcp
    get "/", MCPController, :index
    get "/:project_id", MCPController, :show
    post "/:project_id", MCPController, :handle
  end
end
```

**Key Changes:**
- Remove `PopStashWeb.Plugs.BasicAuth` from browser pipeline
- Add `PopStashWeb.UserAuth` plugs
- Create 3 live_session groups: public, authenticated, org-scoped
- MCP endpoint unchanged (IP check only)

---

## Phase 6: Update LiveViews

### Dashboard LiveViews to Update

**All dashboard LiveViews** need these changes:

1. **Change context calls to DAL:**
   ```elixir
   # Before
   PopStash.Projects.list_projects()

   # After
   PopStash.ProjectsDAL.list(socket.assigns.current_scope)
   ```

2. **Use `current_scope` from assigns:**
   ```elixir
   def mount(_params, _session, socket) do
     scope = socket.assigns.current_scope
     projects = PopStash.ProjectsDAL.list(scope)
     {:ok, assign(socket, projects: projects)}
   end
   ```

3. **Pass org_id when creating:**
   ```elixir
   def handle_event("create_project", %{"name" => name}, socket) do
     case PopStash.ProjectsDAL.create(socket.assigns.current_scope, name) do
       {:ok, project} -> ...
       {:error, _} -> ...
     end
   end
   ```

**Files to update:**
- `lib/pop_stash_web/live/dashboard/projects_live.ex`
- `lib/pop_stash_web/live/dashboard/insights_live.ex`
- `lib/pop_stash_web/live/dashboard/decisions_live.ex`
- `lib/pop_stash_web/live/dashboard/activity_live.ex`
- Any other dashboard LiveViews

---

## Phase 7: Testing & Verification

### Test Strategy

**Unit Tests:**
- Organizations context (create, get, update, delete)
- Memberships context (add, remove, role checks)
- Scope module (from_user, validation)
- DAL modules (access control, org isolation)

**Integration Tests:**
- Passwordless login flow (email → token → session)
- Org selection flow (login → select org → dashboard)
- Org switching (change selected_org_id)
- Access denial (cross-org access attempts)

**Critical Test Cases:**
```elixir
# User cannot access other org's data
test "ProjectsDAL denies cross-org access" do
  org1 = insert(:organization)
  org2 = insert(:organization)
  user = insert(:user, selected_org_id: org1.id)
  scope = %Scope{org_id: org1.id, user_id: user.id, role: :member}

  other_project = insert(:project, org_id: org2.id)

  assert {:error, :unauthorized} = PopStash.ProjectsDAL.get(scope, other_project.id)
end

# Passwordless login works
test "user receives magic link and can log in" do
  user = insert(:user, email: "test@example.com")

  {:ok, lv, _html} = live(conn, ~p"/users/log-in")
  lv |> form("#login_form", user: %{email: "test@example.com"}) |> render_submit()

  assert_email_sent(subject: "Your PopStash login link")
  # Extract token, visit link, verify session
end
```

### Manual Verification Steps

1. **Run migrations:**
   ```bash
   mix ecto.migrate
   ```

2. **Create first user and org:**
   ```bash
   iex -S mix
   {:ok, user} = PopStash.Accounts.register_user(%{email: "admin@example.com"})
   {:ok, org} = PopStash.Organizations.create("My Org", user.id)
   {:ok, _} = PopStash.Accounts.update_selected_org(user, org.id)
   ```

3. **Test login flow:**
   - Visit `/users/log-in`
   - Enter email
   - Check mailbox at `/dev/mailbox` (dev env)
   - Click magic link
   - Verify redirect to dashboard

4. **Test org isolation:**
   - Create second org and user
   - Try to access first org's projects
   - Verify access denied

5. **Test MCP endpoint still works:**
   ```bash
   curl http://localhost:4000/mcp/PROJECT_ID -d '{...}'
   ```

---

## Implementation Order (6-Week Timeline)

### Week 1: Database & Schemas
- [ ] Create migrations 1-9
- [ ] Run migrations in dev
- [ ] Create Organization, OrgMember schemas
- [ ] Modify User schema
- [ ] Update Project, Insight, Decision, SearchLog schemas
- [ ] Write schema unit tests

### Week 2: Authentication
- [ ] Run `mix phx.gen.auth`
- [ ] Remove password fields
- [ ] Implement magic link tokens
- [ ] Create UserNotifier
- [ ] Update Accounts context
- [ ] Write auth integration tests

### Week 3: Access Control
- [ ] Create Scope module
- [ ] Create Memberships context
- [ ] Create Organizations context
- [ ] Add Repo.transact
- [ ] Create OrgPlug
- [ ] Write access control unit tests

### Week 4: DAL Layer
- [ ] Create ProjectsDAL
- [ ] Create MemoryDAL
- [ ] Create ActivityDAL
- [ ] Write DAL unit tests
- [ ] Test cross-org isolation

### Week 5: Router & LiveViews
- [ ] Update router with new pipelines
- [ ] Create org selection LiveViews
- [ ] Update dashboard LiveViews to use DAL
- [ ] Add current_scope to all LiveViews
- [ ] Write LiveView integration tests

### Week 6: Polish & Testing
- [ ] Add org switcher UI
- [ ] Create org settings page
- [ ] Member management UI
- [ ] E2E testing
- [ ] Performance testing
- [ ] Documentation

---

## Critical Files Reference

**New Files:**
- `lib/pop_stash/scope.ex`
- `lib/pop_stash/organizations.ex`
- `lib/pop_stash/organizations/organization.ex`
- `lib/pop_stash/organizations/org_member.ex`
- `lib/pop_stash/memberships.ex`
- `lib/pop_stash/projects_dal.ex`
- `lib/pop_stash/memory_dal.ex`
- `lib/pop_stash/activity_dal.ex`
- `lib/pop_stash_web/plugs/org_plug.ex`
- `lib/pop_stash_web/live/org_selection_live.ex`
- `lib/pop_stash_web/live/org_form_live.ex`

**Modified Files:**
- `lib/pop_stash/repo.ex` - Add transact/1
- `lib/pop_stash/accounts/user.ex` - Remove password, add selected_org_id
- `lib/pop_stash/projects/project.ex` - Add org_id
- `lib/pop_stash/memory/insight.ex` - Add org_id
- `lib/pop_stash/memory/decision.ex` - Add org_id
- `lib/pop_stash/memory/search_log.ex` - Add org_id
- `lib/pop_stash_web/router.ex` - Replace BasicAuth with UserAuth
- All dashboard LiveViews - Use DAL instead of direct contexts

**Generated by phx.gen.auth:**
- `lib/pop_stash/accounts.ex`
- `lib/pop_stash/accounts/user_token.ex`
- `lib/pop_stash/accounts/user_notifier.ex`
- `lib/pop_stash_web/user_auth.ex`
- `lib/pop_stash_web/controllers/user_session_controller.ex`
- `lib/pop_stash_web/live/user_registration_live.ex`
- `lib/pop_stash_web/live/user_login_live.ex`
- `lib/pop_stash_web/live/user_settings_live.ex`

---

## Rollback Plan

If issues arise, migrations can be rolled back in reverse order:

```bash
mix ecto.rollback --step 9  # Rolls back all 9 migrations
```

Each migration includes a `down/0` function that:
- Removes NOT NULL constraints first
- Removes foreign keys
- Removes columns
- Drops tables
- Database handles cascade deletes

**Critical:** Test rollback in dev before prod deployment.

---

## Notes & Considerations

### Typesense Collection Isolation

Current Typesense collections are project-scoped. Consider namespacing by org:
- `insights_#{org_id}` instead of global `insights` collection
- Update `PopStash.Search.Typesense` to accept org_id parameter
- Migrate existing collections to default org namespace

### Embeddings

Embeddings are already project-scoped. No changes needed unless we want org-level semantic search across all projects.

### MCP Endpoint Strategy

**Phase 1:** Keep IP-protected (no breaking changes)
**Phase 2 (Future):** Add optional org-based API keys for remote access

### Performance

All org-scoped queries use composite indexes `(org_id, project_id)` for optimal performance. Monitor query plans in production.

### Security

- Always use DAL layer in LiveViews (never bypass to direct contexts)
- Validate org access on every mutation
- Use `Scope.validate_org_access/2` before updates/deletes
- Never trust client-side org_id params

---

## Success Criteria

✅ Users can register with email only (no password)
✅ Users receive magic link emails and can log in
✅ Users can create and switch between organizations
✅ Users can only access data in their selected org
✅ Existing projects migrate to default org without data loss
✅ MCP endpoint continues to work unchanged
✅ All tests pass (unit, integration, E2E)
✅ No N+1 queries (verify with query logging)
✅ Dashboard loads in <500ms
✅ Cross-org access attempts are blocked

---

This plan implements multi-tenancy following Elixir/Phoenix best practices with clear org boundaries, robust access control, and a smooth migration path for existing data.
