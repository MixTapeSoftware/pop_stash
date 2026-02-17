# Step 4: Update Existing Contexts for Org Scoping

## Objective

Update `PopStash.Projects`, `PopStash.Memory`, and `PopStash.Activity` to accept `%Scope{}` for write operations and org_id validation. Preserve ALL existing functionality (thread_id, title normalization, search logging fields, Typesense integration, PubSub).

**Critical**: This step modifies public APIs that are called by LiveViews, MCP tools, and tests. Changes must be backward-compatible where possible or clearly documented.

## Prerequisites

- Step 1 completed (Repo.prepare_query enforces org_id on reads)
- Step 0 completed (org_id columns exist on all content tables)

## Design Principles

1. **Reads are auto-scoped**: `Repo.prepare_query` adds `WHERE org_id = ?` to all reads. Context functions do NOT need explicit org_id filtering on queries.
2. **Writes need explicit org_id**: `prepare_query` does not intercept inserts/updates/deletes. Context functions must set `org_id` on changesets.
3. **Scope for authorization**: Context functions accept `%Scope{}` to extract `org_id` for writes and validate access for cross-entity operations.
4. **Preserve existing features**: Thread IDs, title normalization, search log fields (query, collection, search_type, tool, result_count, found, duration_ms), Typesense calls -- all preserved.

## Implementation

### 1. Update Projects context

**File**: `/workspace/lib/pop_stash/projects.ex`

Add `%Scope{}` as first parameter to all public functions. Keep `get!/1` for backward compat (used by MCP).

```elixir
defmodule PopStash.Projects do
  import Ecto.Changeset
  import Ecto.Query
  alias PopStash.Projects.Project
  alias PopStash.Repo
  alias PopStash.Scope

  # --- Scoped API (used by LiveViews) ---

  def create(%Scope{org_id: org_id}, name, opts \\ []) when not is_nil(org_id) do
    attrs = %{
      name: name,
      description: Keyword.get(opts, :description),
      tags: Keyword.get(opts, :tags, []),
      org_id: org_id
    }

    %Project{}
    |> create_changeset(attrs)
    |> Repo.insert()
  end

  def get(%Scope{org_id: org_id}, id) when is_binary(id) and not is_nil(org_id) do
    # prepare_query auto-filters by org_id, so if project is in different org
    # it returns nil (same as not found -- no existence leak)
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  def list(%Scope{org_id: org_id}) when not is_nil(org_id) do
    # prepare_query auto-filters by org_id
    Project
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  def delete(%Scope{} = scope, id) when is_binary(id) do
    with {:ok, project} <- get(scope, id) do
      Repo.delete(project)
    end
  end

  def exists?(%Scope{}, id) when is_binary(id) do
    # prepare_query auto-filters
    Project
    |> where([p], p.id == ^id)
    |> Repo.exists?()
  end

  # --- Unscoped API (used by MCP -- localhost only) ---

  @doc """
  Gets a project by ID without scope. For system operations only (MCP).
  """
  def get_by_id(id) when is_binary(id) do
    case Repo.get(Project, id, skip_org_id: true) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  @doc """
  Gets a project by ID, raising if not found. For system operations only.
  """
  def get!(id) when is_binary(id) do
    Repo.get!(Project, id, skip_org_id: true)
  end

  ## Changesets

  defp create_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :tags, :org_id])
    |> validate_required([:name, :org_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:org_id)
  end
end
```

### 2. Update Memory context

**File**: `/workspace/lib/pop_stash/memory.ex`

Add `%Scope{}` as first parameter. Preserve thread_id, title normalization, search log fields, Typesense integration.

Key changes:
- `create_insight(scope, project_id, body, opts)` -- adds `org_id` from scope
- `create_decision(scope, project_id, title, body, opts)` -- adds `org_id` from scope
- `log_search(scope, project_id, query, collection, search_type, opts)` -- adds `org_id` from scope
- `list_insights(scope, project_id, opts)` -- prepare_query handles filtering
- Read functions like `get_insight_by_title`, `get_decision`, `get_decisions_by_title` -- prepare_query handles filtering
- `search_insights(scope, project_id, query, opts)` and `search_decisions` -- Typesense still filters by project_id
- PubSub topics change from `"memory:events"` to `"org:#{org_id}:memory:events"`

**Important preservations**:
- `thread_id` auto-generation with Thread.generate
- `Decision.normalize_title/1` call in create_decision
- All SearchLog fields: `:query, :collection, :search_type, :tool, :result_count, :found, :duration_ms`
- `list_all_search_logs/1` for cross-org admin view (add `skip_org_id: true`)
- Typesense indexing via `Search.Typesense.index_insight/2` and `index_decision/2`

Example for `create_insight`:

```elixir
def create_insight(%Scope{org_id: org_id}, project_id, body, opts \\ [])
    when not is_nil(org_id) do
  thread_id = Keyword.get(opts, :thread_id) || Thread.generate(Insight.thread_prefix())

  %Insight{}
  |> cast(
    %{
      project_id: project_id,
      org_id: org_id,
      body: body,
      title: Keyword.get(opts, :title),
      files: Keyword.get(opts, :files, []),
      tags: Keyword.get(opts, :tags, []),
      thread_id: thread_id
    },
    [:project_id, :org_id, :body, :title, :files, :tags, :thread_id]
  )
  |> validate_required([:project_id, :org_id, :body, :thread_id])
  |> validate_length(:title, max: 255)
  |> foreign_key_constraint(:project_id)
  |> foreign_key_constraint(:org_id)
  |> Repo.insert()
  |> tap_ok(&broadcast(org_id, :insight_created, &1))
end
```

For broadcast, update to include org_id in topic:

```elixir
defp broadcast(org_id, event, payload) do
  Phoenix.PubSub.broadcast(PopStash.PubSub, "org:#{org_id}:memory:events", {event, payload})
end
```

### 3. Update Activity context

**File**: `/workspace/lib/pop_stash/activity.ex`

Add `%Scope{}` as first parameter to `list_recent/2`. The queries inside already go through `Repo.all` which calls `prepare_query` -- so they are auto-scoped. The `Activity.Item` struct remains unchanged (keep it nested, do not extract).

```elixir
def list_recent(%Scope{org_id: org_id} = _scope, opts \\ []) when not is_nil(org_id) do
  # Implementation stays the same -- prepare_query handles org_id filtering
  # Remove explicit org_id where clauses since prepare_query adds them
  limit = Keyword.get(opts, :limit, 20)
  project_id = Keyword.get(opts, :project_id)
  types = Keyword.get(opts, :types, [:decision, :insight, :search])

  # ... rest of implementation stays the same
end
```

**Important**: The `get_project_name/1` helper calls `Repo.get(Project, project_id)` which now requires org_id via prepare_query. This is fine because the Activity context is always called with org_id set.

### 4. Update MCP tool modules

MCP tools pass `context` map with `project_id`. They now need to also include `org_id` and create a `%Scope{}`. This is handled in Step 7 (MCP multi-tenancy), so for now the tool modules remain unchanged. The key is that `Memory.create_insight` now requires a `%Scope{}` first argument.

**Temporary bridge**: Create a `system_scope/1` helper in the MCP context that builds a scope from a project:

```elixir
defp system_scope(project) do
  %PopStash.Scope{org_id: project.org_id, user_id: nil, role: :owner}
end
```

## Verification

```bash
iex -S mix

# Setup
%{scope: scope, org: org} = PopStash.MultitenancyFixtures.setup_org_context()

# Projects
{:ok, project} = PopStash.Projects.create(scope, "Test Project")
assert project.org_id == org.id

projects = PopStash.Projects.list(scope)
assert length(projects) == 1

# Memory
{:ok, insight} = PopStash.Memory.create_insight(scope, project.id, "Test insight")
assert insight.org_id == org.id
assert insight.thread_id =~ "ithr_"

{:ok, decision} = PopStash.Memory.create_decision(scope, project.id, "Auth", "Use Guardian")
assert decision.org_id == org.id
assert decision.title == "auth"  # normalized

# Activity
items = PopStash.Activity.list_recent(scope, limit: 10)
assert length(items) >= 1
```

## Tests

Update existing test files to use scoped calls. The test setup uses `setup_org_context/0` from Step 1.

**File**: `test/pop_stash/projects_test.exs` -- update all calls:

```elixir
defmodule PopStash.ProjectsTest do
  use PopStash.DataCase, async: true

  alias PopStash.Projects

  setup do
    %{scope: scope, org: org} = setup_org_context()
    %{scope: scope, org: org}
  end

  describe "create/3" do
    test "creates a project with org_id", %{scope: scope, org: org} do
      assert {:ok, project} = Projects.create(scope, "My Project")
      assert project.name == "My Project"
      assert project.org_id == org.id
    end

    test "creates a project with description", %{scope: scope} do
      assert {:ok, project} = Projects.create(scope, "My Project", description: "A test")
      assert project.description == "A test"
    end
  end

  describe "get/2" do
    test "returns project when it exists in same org", %{scope: scope} do
      {:ok, created} = Projects.create(scope, "Test Project")
      assert {:ok, found} = Projects.get(scope, created.id)
      assert found.id == created.id
    end

    test "returns not_found for project in different org", %{scope: scope} do
      # Create project in different org
      other_org = organization_fixture()
      Repo.insert_all("projects", [
        %{id: Ecto.UUID.generate(), name: "Other", org_id: other_org.id,
          tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ], skip_org_id: true)

      other_id = Repo.one!(from p in "projects", where: p.org_id == ^other_org.id, select: p.id)
      assert {:error, :not_found} = Projects.get(scope, other_id)
    end

    test "returns error when project doesn't exist", %{scope: scope} do
      assert {:error, :not_found} = Projects.get(scope, Ecto.UUID.generate())
    end
  end

  describe "list/1" do
    test "returns only projects for scoped org", %{scope: scope, org: org} do
      {:ok, _} = Projects.create(scope, "My Project")

      # Create project in different org
      other_org = organization_fixture()
      Repo.insert_all("projects", [
        %{id: Ecto.UUID.generate(), name: "Other", org_id: other_org.id,
          tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
      ], skip_org_id: true)

      projects = Projects.list(scope)
      assert length(projects) == 1
      assert hd(projects).org_id == org.id
    end
  end

  describe "delete/2" do
    test "deletes project in same org", %{scope: scope} do
      {:ok, project} = Projects.create(scope, "To Delete")
      assert {:ok, _} = Projects.delete(scope, project.id)
      assert {:error, :not_found} = Projects.get(scope, project.id)
    end
  end
end
```

**File**: `test/pop_stash/memory_test.exs` -- update all calls similarly:

```elixir
setup do
  %{scope: scope} = setup_org_context()
  {:ok, project} = PopStash.Projects.create(scope, "Test Project")
  %{scope: scope, project: project}
end

# Then update all Memory calls to pass scope as first arg:
# Memory.create_insight(scope, project.id, body, opts)
# Memory.list_insights(scope, project.id, opts)
# etc.
```

**File**: `test/pop_stash/cross_org_isolation_test.exs` (new)

```elixir
defmodule PopStash.CrossOrgIsolationTest do
  use PopStash.DataCase

  alias PopStash.Memory
  alias PopStash.Projects
  alias PopStash.Repo

  test "user cannot see projects from other org" do
    %{scope: scope1, org: org1} = setup_org_context()
    {:ok, _} = Projects.create(scope1, "Org1 Project")

    # Create project in org2
    org2 = organization_fixture()
    Repo.insert_all("projects", [
      %{id: Ecto.UUID.generate(), name: "Org2 Project", org_id: org2.id,
        tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
    ], skip_org_id: true)

    projects = Projects.list(scope1)
    assert length(projects) == 1
    assert hd(projects).name == "Org1 Project"
  end

  test "prepare_query prevents direct Repo access to other org data" do
    %{org: org1} = setup_org_context()
    org2 = organization_fixture()

    Repo.insert_all("projects", [
      %{id: Ecto.UUID.generate(), name: "Org1", org_id: org1.id,
        tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
      %{id: Ecto.UUID.generate(), name: "Org2", org_id: org2.id,
        tags: [], inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
    ], skip_org_id: true)

    # Even direct Repo.all is scoped
    projects = Repo.all(PopStash.Projects.Project)
    assert length(projects) == 1
    assert hd(projects).name == "Org1"
  end

  test "prepare_query raises when no org_id set" do
    Repo.put_org_id(nil)

    assert_raise RuntimeError, ~r/expected org_id/, fn ->
      Repo.all(PopStash.Projects.Project)
    end
  end
end
```

## Dependencies

- Step 0 completed (org_id columns exist)
- Step 1 completed (Repo.prepare_query, Scope struct, test fixtures)

## Important Notes

- **Do NOT rewrite the Memory context from scratch.** Modify the existing functions to accept `%Scope{}` and add `org_id` to changesets. Preserve all existing fields, thread_id logic, title normalization, and Typesense calls.
- **PubSub topics change**: From `"memory:events"` to `"org:#{org_id}:memory:events"`. This will require updating LiveView subscriptions in Step 6.
- **MCP tools will break** until Step 7 updates them to pass `%Scope{}`. This is expected and acceptable since steps are done sequentially.
- The `list_all_search_logs/1` function should use `skip_org_id: true` since it queries across orgs (admin use).
