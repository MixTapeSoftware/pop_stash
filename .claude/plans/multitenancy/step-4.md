# Step 4: Update Contexts for Org Scoping

## Overview
Modify existing contexts (Projects, Memory, Activity) to accept Scope parameter for write operations and authorization. Add composable query modules per project guidelines.

## Context
With `prepare_query` in place (Step 3), all read queries are automatically scoped by org_id via the process dictionary. Contexts still need the Scope parameter for:
- **Write operations**: Setting org_id on inserts (prepare_query doesn't intercept writes)
- **Authorization**: Role-based access checks (e.g., owner-only operations)
- **Cross-entity validation**: Ensuring a project belongs to the org before creating child records

Read queries (list, get) benefit from automatic `prepare_query` filtering but contexts still accept Scope to extract `org_id` for writes and for the `get` pattern that returns `:not_found` for wrong-org records.

## Implementation

### 1. Update Projects Context

**File**: `lib/pop_stash/projects.ex`

Add Scope parameter to all functions and use composable query module:

```elixir
defmodule PopStash.Projects do
  @moduledoc """
  Context for managing projects.
  """

  import Ecto.Query

  alias PopStash.Projects.Project
  alias PopStash.Repo
  alias PopStash.Scope

  ## Query Module

  defmodule Query do
    @moduledoc false
    import Ecto.Query
    alias PopStash.Projects.Project

    def for_org(query \\ Project, org_id) do
      where(query, [p], p.org_id == ^org_id)
    end

    def ordered_by_inserted_at(query, direction \\ :desc) do
      order_by(query, [p], [{^direction, p.inserted_at}])
    end

    def with_tags(query, tags) when is_list(tags) do
      where(query, [p], fragment("? && ?", p.tags, ^tags))
    end
  end

  ## Public API

  @doc """
  Creates a project within the scoped organization.
  """
  def create(%Scope{org_id: org_id} = _scope, name, opts \\ []) when not is_nil(org_id) do
    attrs = %{
      name: name,
      description: Keyword.get(opts, :description),
      tags: Keyword.get(opts, :tags, []),
      org_id: org_id
    }

    %Project{}
    |> create_changeset(attrs)
    |> Repo.insert()
    |> maybe_broadcast_created()
  end

  @doc """
  Gets a project by ID, ensuring it belongs to the scoped org.
  Returns {:error, :not_found} for both missing and unauthorized to avoid leaking existence.
  """
  def get(%Scope{org_id: org_id} = _scope, id) when not is_nil(org_id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      %Project{org_id: ^org_id} = project -> {:ok, project}
      _ -> {:error, :not_found}  # Don't leak existence of other org's projects
    end
  end

  @doc """
  Lists all projects for the scoped organization.
  """
  def list(%Scope{org_id: org_id} = _scope, opts \\ []) when not is_nil(org_id) do
    Query.for_org(org_id)
    |> Query.ordered_by_inserted_at()
    |> maybe_filter_tags(opts[:tags])
    |> Repo.all()
  end

  @doc """
  Updates a project, ensuring it belongs to the scoped org.
  """
  def update(%Scope{} = scope, id, attrs) do
    with {:ok, project} <- get(scope, id) do
      project
      |> update_changeset(attrs)
      |> Repo.update()
      |> maybe_broadcast_updated()
    end
  end

  @doc """
  Deletes a project, ensuring it belongs to the scoped org.
  """
  def delete(%Scope{} = scope, id) do
    with {:ok, project} <- get(scope, id) do
      Repo.delete(project)
      |> maybe_broadcast_deleted()
    end
  end

  ## Changesets (in context per project guidelines)

  defp create_changeset(project, attrs) do
    project
    |> Ecto.Changeset.cast(attrs, [:name, :description, :tags, :org_id])
    |> Ecto.Changeset.validate_required([:name, :org_id])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)
  end

  defp update_changeset(project, attrs) do
    project
    |> Ecto.Changeset.cast(attrs, [:name, :description, :tags])
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 255)
  end

  ## Helpers

  defp maybe_filter_tags(query, nil), do: query
  defp maybe_filter_tags(query, tags), do: Query.with_tags(query, tags)

  defp maybe_broadcast_created({:ok, project} = result) do
    Phoenix.PubSub.broadcast(
      PopStash.PubSub,
      "org:#{project.org_id}:projects:events",
      {:project_created, project}
    )
    result
  end
  defp maybe_broadcast_created(error), do: error

  defp maybe_broadcast_updated({:ok, project} = result) do
    Phoenix.PubSub.broadcast(
      PopStash.PubSub,
      "org:#{project.org_id}:projects:events",
      {:project_updated, project}
    )
    result
  end
  defp maybe_broadcast_updated(error), do: error

  defp maybe_broadcast_deleted({:ok, project} = result) do
    Phoenix.PubSub.broadcast(
      PopStash.PubSub,
      "org:#{project.org_id}:projects:events",
      {:project_deleted, project}
    )
    result
  end
  defp maybe_broadcast_deleted(error), do: error
end
```

### 2. Update Memory Context

**File**: `lib/pop_stash/memory.ex`

Add Scope parameter and validate project access:

```elixir
defmodule PopStash.Memory do
  @moduledoc """
  Context for managing insights, decisions, and search logs.
  """

  import Ecto.Query

  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.SearchLog
  alias PopStash.Repo
  alias PopStash.Scope

  ## Query Module

  defmodule Query do
    @moduledoc false
    import Ecto.Query

    def for_org(query, org_id) do
      where(query, [r], r.org_id == ^org_id)
    end

    def for_project(query, project_id) do
      where(query, [r], r.project_id == ^project_id)
    end

    def limit(query, count) do
      Ecto.Query.limit(query, ^count)
    end
  end

  ## Insights

  @doc """
  Creates an insight within the scoped organization.
  Validates that the project belongs to the org.
  """
  def create_insight(%Scope{org_id: org_id} = scope, project_id, body, opts \\ [])
      when not is_nil(org_id) do
    # Validate project access first
    with :ok <- validate_project_access(scope, project_id) do
      attrs = %{
        project_id: project_id,
        org_id: org_id,
        body: body,
        tags: Keyword.get(opts, :tags, []),
        embedding: Keyword.get(opts, :embedding)
      }

      %Insight{}
      |> insight_changeset(attrs)
      |> Repo.insert()
      |> maybe_index_insight()
      |> maybe_broadcast_insight(:created)
    end
  end

  @doc """
  Lists insights for the scoped organization and project.
  """
  def list_insights(%Scope{org_id: org_id} = scope, project_id, opts \\ [])
      when not is_nil(org_id) do
    with :ok <- validate_project_access(scope, project_id) do
      limit = Keyword.get(opts, :limit, 50)

      Insight
      |> Query.for_org(org_id)
      |> Query.for_project(project_id)
      |> order_by(desc: :updated_at)
      |> Query.limit(limit)
      |> Repo.all()
    end
  end

  @doc """
  Gets an insight by ID, ensuring org access.
  """
  def get_insight(%Scope{org_id: org_id} = _scope, id) when not is_nil(org_id) do
    case Repo.get(Insight, id) do
      nil -> {:error, :not_found}
      %Insight{org_id: ^org_id} = insight -> {:ok, insight}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Updates an insight, ensuring org access.
  """
  def update_insight(%Scope{} = scope, id, attrs) do
    with {:ok, insight} <- get_insight(scope, id) do
      insight
      |> insight_update_changeset(attrs)
      |> Repo.update()
      |> maybe_index_insight()
      |> maybe_broadcast_insight(:updated)
    end
  end

  @doc """
  Deletes an insight, ensuring org access.
  """
  def delete_insight(%Scope{} = scope, id) do
    with {:ok, insight} <- get_insight(scope, id) do
      Repo.delete(insight)
      |> maybe_deindex_insight()
      |> maybe_broadcast_insight(:deleted)
    end
  end

  ## Decisions

  @doc """
  Creates a decision within the scoped organization.
  """
  def create_decision(%Scope{org_id: org_id} = scope, project_id, title, body, opts \\ [])
      when not is_nil(org_id) do
    with :ok <- validate_project_access(scope, project_id) do
      attrs = %{
        project_id: project_id,
        org_id: org_id,
        title: title,
        body: body,
        status: Keyword.get(opts, :status, "active"),
        tags: Keyword.get(opts, :tags, [])
      }

      %Decision{}
      |> decision_changeset(attrs)
      |> Repo.insert()
      |> maybe_broadcast_decision(:created)
    end
  end

  @doc """
  Lists decisions for the scoped organization and project.
  """
  def list_decisions(%Scope{org_id: org_id} = scope, project_id, opts \\ [])
      when not is_nil(org_id) do
    with :ok <- validate_project_access(scope, project_id) do
      limit = Keyword.get(opts, :limit, 50)

      Decision
      |> Query.for_org(org_id)
      |> Query.for_project(project_id)
      |> order_by(desc: :inserted_at)
      |> Query.limit(limit)
      |> Repo.all()
    end
  end

  @doc """
  Logs a search query within the scoped organization.
  """
  def log_search(%Scope{org_id: org_id} = scope, project_id, query_text, opts \\ [])
      when not is_nil(org_id) do
    with :ok <- validate_project_access(scope, project_id) do
      attrs = %{
        project_id: project_id,
        org_id: org_id,
        query_text: query_text,
        results_count: Keyword.get(opts, :results_count, 0)
      }

      # Fire and forget - unsupervised task
      Task.start(fn ->
        %SearchLog{}
        |> search_log_changeset(attrs)
        |> Repo.insert()
      end)

      :ok
    end
  end

  ## Changesets

  defp insight_changeset(insight, attrs) do
    insight
    |> Ecto.Changeset.cast(attrs, [:project_id, :org_id, :body, :tags, :embedding])
    |> Ecto.Changeset.validate_required([:project_id, :org_id, :body])
  end

  defp insight_update_changeset(insight, attrs) do
    insight
    |> Ecto.Changeset.cast(attrs, [:body, :tags, :embedding])
  end

  defp decision_changeset(decision, attrs) do
    decision
    |> Ecto.Changeset.cast(attrs, [:project_id, :org_id, :title, :body, :status, :tags])
    |> Ecto.Changeset.validate_required([:project_id, :org_id, :title, :body])
    |> Ecto.Changeset.validate_inclusion(:status, ~w(active archived))
  end

  defp search_log_changeset(search_log, attrs) do
    search_log
    |> Ecto.Changeset.cast(attrs, [:project_id, :org_id, :query_text, :results_count])
    |> Ecto.Changeset.validate_required([:project_id, :org_id, :query_text])
  end

  ## Helpers

  defp validate_project_access(%Scope{org_id: org_id}, project_id) do
    case Repo.get(PopStash.Projects.Project, project_id) do
      nil -> {:error, :project_not_found}
      %{org_id: ^org_id} -> :ok
      _ -> {:error, :not_found}  # Don't leak existence
    end
  end

  defp maybe_index_insight({:ok, insight} = result) do
    # TODO: Add Typesense indexing with org_id
    result
  end
  defp maybe_index_insight(error), do: error

  defp maybe_deindex_insight({:ok, insight} = result) do
    # TODO: Remove from Typesense
    result
  end
  defp maybe_deindex_insight(error), do: error

  defp maybe_broadcast_insight({:ok, insight} = result, event) do
    Phoenix.PubSub.broadcast(
      PopStash.PubSub,
      "org:#{insight.org_id}:memory:events",
      {:"insight_#{event}", insight}
    )
    result
  end
  defp maybe_broadcast_insight(error, _event), do: error

  defp maybe_broadcast_decision({:ok, decision} = result, event) do
    Phoenix.PubSub.broadcast(
      PopStash.PubSub,
      "org:#{decision.org_id}:memory:events",
      {:"decision_#{event}", decision}
    )
    result
  end
  defp maybe_broadcast_decision(error, _event), do: error
end
```

### 3. Update Activity Context

**File**: `lib/pop_stash/activity.ex`

Extract nested `Activity.Item` to separate file and update for org scoping:

**File**: `lib/pop_stash/activity/item.ex`

```elixir
defmodule PopStash.Activity.Item do
  @moduledoc """
  Represents an activity item in the feed.
  """

  @type t :: %__MODULE__{
    id: binary(),
    type: :insight | :decision | :search,
    title: String.t(),
    body: String.t() | nil,
    project: map() | nil,
    inserted_at: DateTime.t()
  }

  defstruct [:id, :type, :title, :body, :project, :inserted_at]

  def from_insight(%PopStash.Memory.Insight{} = insight) do
    %__MODULE__{
      id: insight.id,
      type: :insight,
      title: String.slice(insight.body, 0..100),
      body: insight.body,
      project: insight.project,
      inserted_at: insight.inserted_at
    }
  end

  def from_decision(%PopStash.Memory.Decision{} = decision) do
    %__MODULE__{
      id: decision.id,
      type: :decision,
      title: decision.title,
      body: decision.body,
      project: decision.project,
      inserted_at: decision.inserted_at
    }
  end

  def from_search_log(%PopStash.Memory.SearchLog{} = search) do
    %__MODULE__{
      id: search.id,
      type: :search,
      title: search.query_text,
      body: nil,
      project: search.project,
      inserted_at: search.inserted_at
    }
  end
end
```

**File**: `lib/pop_stash/activity.ex`

```elixir
defmodule PopStash.Activity do
  @moduledoc """
  Context for managing activity feeds.
  """

  import Ecto.Query

  alias PopStash.Activity.Item
  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.SearchLog
  alias PopStash.Repo
  alias PopStash.Scope

  @doc """
  Lists recent activity for the scoped organization.
  """
  def list_recent(%Scope{org_id: org_id} = _scope, opts \\ []) when not is_nil(org_id) do
    limit = Keyword.get(opts, :limit, 20)
    project_id = Keyword.get(opts, :project_id)
    types = Keyword.get(opts, :types, [:decision, :insight, :search])

    items = []

    items = if :decision in types,
      do: items ++ fetch_decisions(org_id, project_id, limit),
      else: items

    items = if :insight in types,
      do: items ++ fetch_insights(org_id, project_id, limit),
      else: items

    items = if :search in types,
      do: items ++ fetch_searches(org_id, project_id, limit),
      else: items

    items
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&to_activity_item/1)
  end

  ## Private

  defp fetch_decisions(org_id, nil, limit) do
    Decision
    |> where([d], d.org_id == ^org_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  defp fetch_decisions(org_id, project_id, limit) do
    Decision
    |> where([d], d.org_id == ^org_id and d.project_id == ^project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  defp fetch_insights(org_id, nil, limit) do
    Insight
    |> where([i], i.org_id == ^org_id)
    |> order_by(desc: :updated_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  defp fetch_insights(org_id, project_id, limit) do
    Insight
    |> where([i], i.org_id == ^org_id and i.project_id == ^project_id)
    |> order_by(desc: :updated_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  defp fetch_searches(org_id, nil, limit) do
    SearchLog
    |> where([s], s.org_id == ^org_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  defp fetch_searches(org_id, project_id, limit) do
    SearchLog
    |> where([s], s.org_id == ^org_id and s.project_id == ^project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  defp to_activity_item(%Decision{} = decision), do: Item.from_decision(decision)
  defp to_activity_item(%Insight{} = insight), do: Item.from_insight(insight)
  defp to_activity_item(%SearchLog{} = search), do: Item.from_search_log(search)
end
```

## Verification

```bash
# Test in IEx
iex -S mix

# Setup: create user, org, project
{:ok, user} = PopStash.Accounts.register_user(%{email: "test@example.com"})
{:ok, org} = PopStash.Organizations.create("My Org", user.id)
{:ok, user} = PopStash.Accounts.select_org(user, org.id)
{:ok, scope} = PopStash.Scope.from_user(user)

# Test Projects
{:ok, project} = PopStash.Projects.create(scope, "Test Project")
assert project.org_id == org.id

projects = PopStash.Projects.list(scope)
assert length(projects) == 1

# Test cross-org isolation
{:ok, other_org} = PopStash.Organizations.create("Other Org", user.id)
other_scope = %PopStash.Scope{org_id: other_org.id, user_id: user.id, role: :owner}
{:ok, other_project} = PopStash.Projects.create(other_scope, "Other Project")

# Should fail - wrong org (returns :not_found to avoid leaking existence)
assert {:error, :not_found} = PopStash.Projects.get(scope, other_project.id)

# Test Memory
{:ok, insight} = PopStash.Memory.create_insight(scope, project.id, "Test insight")
assert insight.org_id == org.id

# Test Activity
items = PopStash.Activity.list_recent(scope)
assert length(items) >= 1
```

## Tests

**File**: `test/pop_stash/projects_test.exs`

```elixir
defmodule PopStash.ProjectsTest do
  use PopStash.DataCase

  alias PopStash.Projects
  alias PopStash.Scope

  setup do
    org1 = insert(:organization)
    org2 = insert(:organization)
    user = insert(:user, selected_org_id: org1.id)

    insert(:org_member, org_id: org1.id, user_id: user.id)

    scope1 = %Scope{org_id: org1.id, user_id: user.id, role: :member}
    scope2 = %Scope{org_id: org2.id, user_id: user.id, role: :member}

    {:ok, scope1: scope1, scope2: scope2, org1: org1, org2: org2}
  end

  describe "create/3" do
    test "creates project in scoped org", %{scope1: scope1, org1: org1} do
      assert {:ok, project} = Projects.create(scope1, "Test")
      assert project.org_id == org1.id
      assert project.name == "Test"
    end
  end

  describe "get/2" do
    test "returns project when in same org", %{scope1: scope1, org1: org1} do
      project = insert(:project, org_id: org1.id)
      assert {:ok, found} = Projects.get(scope1, project.id)
      assert found.id == project.id
    end

    test "returns :not_found when in different org", %{scope1: scope1, org2: org2} do
      other_project = insert(:project, org_id: org2.id)
      assert {:error, :not_found} = Projects.get(scope1, other_project.id)
    end

    test "returns :not_found when project doesn't exist", %{scope1: scope1} do
      assert {:error, :not_found} = Projects.get(scope1, Ecto.UUID.generate())
    end
  end

  describe "list/2" do
    test "lists only scoped org projects", %{scope1: scope1, org1: org1, org2: org2} do
      insert(:project, org_id: org1.id, name: "Org1 Project")
      insert(:project, org_id: org2.id, name: "Org2 Project")

      projects = Projects.list(scope1)

      assert length(projects) == 1
      assert hd(projects).name == "Org1 Project"
    end
  end

  describe "update/3" do
    test "updates project in same org", %{scope1: scope1, org1: org1} do
      project = insert(:project, org_id: org1.id, name: "Old")
      assert {:ok, updated} = Projects.update(scope1, project.id, %{name: "New"})
      assert updated.name == "New"
    end

    test "returns :not_found for different org", %{scope1: scope1, org2: org2} do
      other_project = insert(:project, org_id: org2.id)
      assert {:error, :not_found} = Projects.update(scope1, other_project.id, %{name: "Hacked"})
    end
  end

  describe "delete/2" do
    test "deletes project in same org", %{scope1: scope1, org1: org1} do
      project = insert(:project, org_id: org1.id)
      assert {:ok, _} = Projects.delete(scope1, project.id)
      assert {:error, :not_found} = Projects.get(scope1, project.id)
    end

    test "returns :not_found for different org", %{scope1: scope1, org2: org2} do
      other_project = insert(:project, org_id: org2.id)
      assert {:error, :not_found} = Projects.delete(scope1, other_project.id)
    end
  end
end
```

## Dependencies
- Step 3 completed (Scope, Organizations, Memberships exist)
- Step 1 completed (org_id columns exist on all tables)

## Next Step
Step 5 will create OrgPlug and update router to use authentication and org scoping.

## Notes
- **prepare_query handles reads**: `Repo.prepare_query` auto-filters all reads by org_id from process dictionary
- **Scope needed for writes**: Contexts still accept Scope to set org_id on inserts
- **Composable queries**: Using Query modules per project Ecto guidelines
- **Return :not_found**: Instead of :unauthorized to avoid leaking existence
- **PubSub scoped**: Topics now include org_id: `"org:#{org_id}:projects:events"`
- **Changesets in contexts**: Moved from schema files per project guidelines
- **Activity.Item extracted**: No longer nested module
