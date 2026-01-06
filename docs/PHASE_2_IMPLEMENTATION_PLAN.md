# Phase 2 Implementation Plan: Memory Foundation + Tools

Phase 2 focuses on **foundational memory primitives** without the complexity of embeddings. We build schemas, contexts, and tools that work with exact matches first. Semantic search comes in Phase 4 when we've validated the core abstractions.

---

## Prerequisites (Already Complete)

- [x] PostgreSQL with pgvector extension
- [x] `PopStash.Schema` base module (UUIDs, timestamps)
- [x] Projects schema, context, and migrations
- [x] MCP router with `/mcp/:project_id` routing
- [x] Project validation on every request

---

## Implementation Order

### Why This Order Matters

The dependency chain is:
```
projects (✓ done)
  ↓
agents (must come first — stashes/insights reference them)
  ↓
stashes, insights (depend on agents via created_by FK)
  ↓
MCP tools (depend on all schemas)
  ↓
Integration tests (validate end-to-end)
```

Breaking this order causes compilation errors or forces temporary workarounds.

---

## Step 1: Agents Schema & Context

**Goal**: Represent connected MCP clients with project isolation.

### 1.1 Create Migration

**File**: `priv/repo/migrations/20260106_create_agents.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string
      add :current_task, :text
      add :status, :string, default: "active", null: false
      add :connected_at, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agents, [:project_id])
    create index(:agents, [:project_id, :status])
    create index(:agents, [:project_id, :last_seen_at])
  end
end
```

**Design decisions**:
- `status`: `"active" | "idle" | "disconnected"` — simple string enum
- `connected_at` / `last_seen_at`: Separate fields for session tracking
- `metadata`: Extensibility without schema changes (agent capabilities, versions, etc.)
- Cascading delete: When project deleted, agents go too

### 1.2 Create Schema

**File**: `lib/pop_stash/agents/agent.ex`

```elixir
defmodule PopStash.Agents.Agent do
  @moduledoc """
  Schema for agents (connected MCP clients).

  An agent is a connected editor instance (Claude Code, Cursor, etc.) working
  within a specific project. Agents create stashes and insights, and their
  lifecycle is tracked for coordination and observability.
  """

  use PopStash.Schema

  alias PopStash.Projects.Project

  @statuses ~w(active idle disconnected)

  schema "agents" do
    field :name, :string
    field :current_task, :string
    field :status, :string, default: "active"
    field :connected_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :project, Project

    timestamps()
  end

  @doc false
  def statuses, do: @statuses
end
```

**Why no changesets in schemas?** Following the Elixir/Ecto guideline: schemas define structure, contexts define operations. Changesets are contextual (e.g., `connect_changeset` vs `disconnect_changeset`).

### 1.3 Create Context Module

**File**: `lib/pop_stash/agents.ex`

```elixir
defmodule PopStash.Agents do
  @moduledoc """
  Context for managing agents (connected MCP clients).

  Agents are scoped to projects and represent active editor sessions.
  This module handles agent lifecycle: connection, heartbeat, disconnection.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Repo
  alias PopStash.Agents.Agent

  ## Queries

  @doc """
  Gets an agent by ID.

  Returns `{:ok, agent}` or `{:error, :not_found}`.
  """
  def get(id) when is_binary(id) do
    case Repo.get(Agent, id) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end

  @doc """
  Gets an agent by ID, raising if not found.
  """
  def get!(id) when is_binary(id) do
    Repo.get!(Agent, id)
  end

  @doc """
  Lists all active agents for a project.
  """
  def list_active(project_id) when is_binary(project_id) do
    Agent
    |> where([a], a.project_id == ^project_id and a.status == "active")
    |> order_by([a], desc: a.last_seen_at)
    |> Repo.all()
  end

  @doc """
  Lists all agents for a project (any status).
  """
  def list_all(project_id) when is_binary(project_id) do
    Agent
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], desc: a.last_seen_at)
    |> Repo.all()
  end

  ## Mutations

  @doc """
  Connects an agent to a project.

  ## Options
    * `:name` - Optional agent name (defaults to "Agent {timestamp}")
    * `:metadata` - Optional metadata map

  Returns `{:ok, agent}` or `{:error, changeset}`.
  """
  def connect(project_id, opts \\ []) do
    now = DateTime.utc_now()
    default_name = "Agent #{DateTime.to_unix(now)}"

    attrs = %{
      project_id: project_id,
      name: Keyword.get(opts, :name, default_name),
      status: "active",
      connected_at: now,
      last_seen_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %Agent{}
    |> connect_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates agent heartbeat (last_seen_at).
  """
  def heartbeat(agent_id) when is_binary(agent_id) do
    case get(agent_id) do
      {:ok, agent} ->
        agent
        |> heartbeat_changeset(%{last_seen_at: DateTime.utc_now()})
        |> Repo.update()

      error ->
        error
    end
  end

  @doc """
  Marks an agent as disconnected.
  """
  def disconnect(agent_id) when is_binary(agent_id) do
    case get(agent_id) do
      {:ok, agent} ->
        agent
        |> disconnect_changeset(%{status: "disconnected"})
        |> Repo.update()

      error ->
        error
    end
  end

  @doc """
  Updates agent's current task.
  """
  def update_task(agent_id, task) when is_binary(agent_id) and is_binary(task) do
    case get(agent_id) do
      {:ok, agent} ->
        agent
        |> task_changeset(%{current_task: task, last_seen_at: DateTime.utc_now()})
        |> Repo.update()

      error ->
        error
    end
  end

  ## Changesets

  defp connect_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:project_id, :name, :status, :connected_at, :last_seen_at, :metadata])
    |> validate_required([:project_id, :status, :connected_at, :last_seen_at])
    |> validate_inclusion(:status, Agent.statuses())
    |> foreign_key_constraint(:project_id)
  end

  defp heartbeat_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:last_seen_at])
    |> validate_required([:last_seen_at])
  end

  defp disconnect_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, Agent.statuses())
  end

  defp task_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:current_task, :last_seen_at])
    |> validate_required([:last_seen_at])
  end
end
```

**Design decisions**:
- **Contextual changesets**: Each operation has its own changeset with only the fields it can modify
- **Atomic updates**: `heartbeat` and `update_task` touch only what's needed
- **Simple status tracking**: No GenServer yet — just database records (GenServer comes in Phase 3 for `Agent.Connection`)

### 1.4 Add Association to Project Schema

**File**: `lib/pop_stash/projects/project.ex`

```elixir
defmodule PopStash.Projects.Project do
  @moduledoc """
  Schema for projects, the top-level isolation boundary in PopStash.

  Each project has its own agents, stashes, insights, decisions, and locks.
  """

  use PopStash.Schema

  schema "projects" do
    field :name, :string
    field :description, :string
    field :metadata, :map, default: %{}

    has_many :agents, PopStash.Agents.Agent  # ← Add this

    timestamps()
  end
end
```

### 1.5 Tests

**File**: `test/pop_stash/agents_test.exs`

```elixir
defmodule PopStash.AgentsTest do
  use PopStash.DataCase, async: true

  alias PopStash.{Projects, Agents}

  setup do
    {:ok, project} = Projects.create("Test Project")
    %{project: project}
  end

  describe "connect/2" do
    test "creates an active agent", %{project: project} do
      assert {:ok, agent} = Agents.connect(project.id)
      assert agent.project_id == project.id
      assert agent.status == "active"
      assert agent.connected_at
      assert agent.last_seen_at
    end

    test "accepts custom name and metadata", %{project: project} do
      assert {:ok, agent} = Agents.connect(project.id, name: "Claude", metadata: %{editor: "cursor"})
      assert agent.name == "Claude"
      assert agent.metadata == %{editor: "cursor"}
    end

    test "validates project exists" do
      assert {:error, changeset} = Agents.connect(Ecto.UUID.generate())
      assert "does not exist" in errors_on(changeset).project_id
    end
  end

  describe "heartbeat/1" do
    test "updates last_seen_at", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      old_time = agent.last_seen_at

      Process.sleep(10)
      assert {:ok, updated} = Agents.heartbeat(agent.id)
      assert DateTime.compare(updated.last_seen_at, old_time) == :gt
    end
  end

  describe "disconnect/1" do
    test "marks agent as disconnected", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      assert {:ok, updated} = Agents.disconnect(agent.id)
      assert updated.status == "disconnected"
    end
  end

  describe "update_task/2" do
    test "sets current task", %{project: project} do
      {:ok, agent} = Agents.connect(project.id)
      assert {:ok, updated} = Agents.update_task(agent.id, "Implementing auth")
      assert updated.current_task == "Implementing auth"
    end
  end

  describe "list_active/1" do
    test "returns only active agents", %{project: project} do
      {:ok, agent1} = Agents.connect(project.id)
      {:ok, agent2} = Agents.connect(project.id)
      {:ok, _} = Agents.disconnect(agent2.id)

      active = Agents.list_active(project.id)
      assert length(active) == 1
      assert hd(active).id == agent1.id
    end
  end
end
```

---

## Step 2: Stashes Schema & Context

**Goal**: Enable agents to save and restore context with exact name matching (no embeddings yet).

### 2.1 Create Migration

**File**: `priv/repo/migrations/20260106_create_stashes.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateStashes do
  use Ecto.Migration

  def change do
    create table(:stashes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :summary, :text, null: false
      add :files, {:array, :string}, default: []
      add :metadata, :map, default: %{}
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stashes, [:project_id])
    create index(:stashes, [:project_id, :name])
    create index(:stashes, [:project_id, :created_by])
    create index(:stashes, [:expires_at])
  end
end
```

**Design decisions**:
- `name`: User-provided identifier for exact retrieval
- `summary`: Full context description (will get embeddings in Phase 4)
- `files`: Optional list of files involved (helps with context)
- `expires_at`: NULL means never expires (default behavior)
- `created_by`: Nullable FK — stash survives agent deletion (audit trail preserved)

### 2.2 Create Schema

**File**: `lib/pop_stash/memory/stash.ex`

```elixir
defmodule PopStash.Memory.Stash do
  @moduledoc """
  Schema for stashes (saved agent context).

  A stash is like `git stash` — it saves the current state of work for later
  retrieval. Stashes can be retrieved by exact name match (Phase 2) or semantic
  search (Phase 4).
  """

  use PopStash.Schema

  alias PopStash.Projects.Project
  alias PopStash.Agents.Agent

  schema "stashes" do
    field :name, :string
    field :summary, :string
    field :files, {:array, :string}, default: []
    field :metadata, :map, default: %{}
    field :expires_at, :utc_datetime_usec

    belongs_to :project, Project
    belongs_to :created_by, Agent, foreign_key: :created_by

    timestamps()
  end
end
```

### 2.3 Create Context Module

**File**: `lib/pop_stash/memory.ex`

```elixir
defmodule PopStash.Memory do
  @moduledoc """
  Context for memory operations: stashes and insights.

  This module handles saving and retrieving agent context across sessions.
  Phase 2 uses exact matching; Phase 4 adds semantic search.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Repo
  alias PopStash.Memory.Stash

  ## Stashes

  @doc """
  Creates a stash.

  ## Options
    * `:files` - List of file paths
    * `:metadata` - Optional metadata map
    * `:expires_at` - Optional expiration datetime

  Returns `{:ok, stash}` or `{:error, changeset}`.
  """
  def create_stash(project_id, agent_id, name, summary, opts \\ []) do
    attrs = %{
      project_id: project_id,
      created_by: agent_id,
      name: name,
      summary: summary,
      files: Keyword.get(opts, :files, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      expires_at: Keyword.get(opts, :expires_at)
    }

    %Stash{}
    |> create_stash_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves a stash by exact name match within a project.

  Returns `{:ok, stash}` or `{:error, :not_found}`.
  """
  def get_stash_by_name(project_id, name) when is_binary(project_id) and is_binary(name) do
    Stash
    |> where([s], s.project_id == ^project_id and s.name == ^name)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      stash -> {:ok, stash}
    end
  end

  @doc """
  Lists all non-expired stashes for a project.
  """
  def list_stashes(project_id) when is_binary(project_id) do
    Stash
    |> where([s], s.project_id == ^project_id)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes a stash by ID.
  """
  def delete_stash(stash_id) when is_binary(stash_id) do
    case Repo.get(Stash, stash_id) do
      nil -> {:error, :not_found}
      stash -> Repo.delete(stash)
    end
  end

  ## Changesets

  defp create_stash_changeset(stash, attrs) do
    stash
    |> cast(attrs, [:project_id, :created_by, :name, :summary, :files, :metadata, :expires_at])
    |> validate_required([:project_id, :name, :summary])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:summary, min: 1)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by)
  end
end
```

---

## Step 3: Insights Schema & Context

**Goal**: Persistent knowledge about the codebase, retrievable by exact key match.

### 3.1 Create Migration

**File**: `priv/repo/migrations/20260106_create_insights.exs`

```elixir
defmodule PopStash.Repo.Migrations.CreateInsights do
  use Ecto.Migration

  def change do
    create table(:insights, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :key, :string
      add :content, :text, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:insights, [:project_id])
    create index(:insights, [:project_id, :key])
    create index(:insights, [:project_id, :inserted_at])
  end
end
```

**Design decisions**:
- `key`: Optional semantic identifier ("auth-patterns", "db-schema", etc.)
- `content`: The actual insight text (will get embeddings in Phase 4)
- No expiration: Insights are permanent knowledge

### 3.2 Create Schema

**File**: `lib/pop_stash/memory/insight.ex`

```elixir
defmodule PopStash.Memory.Insight do
  @moduledoc """
  Schema for insights (persistent codebase knowledge).

  Insights are facts about the codebase that agents discover and share.
  They never expire and are searchable by key (Phase 2) or semantic
  similarity (Phase 4).
  """

  use PopStash.Schema

  alias PopStash.Projects.Project
  alias PopStash.Agents.Agent

  schema "insights" do
    field :key, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Project
    belongs_to :created_by, Agent, foreign_key: :created_by

    timestamps()
  end
end
```

### 3.3 Extend Context Module

**File**: `lib/pop_stash/memory.ex` (add to existing module)

```elixir
  alias PopStash.Memory.Insight  # Add to aliases at top

  ## Insights

  @doc """
  Creates an insight.

  ## Options
    * `:key` - Optional semantic key for exact retrieval
    * `:metadata` - Optional metadata map

  Returns `{:ok, insight}` or `{:error, changeset}`.
  """
  def create_insight(project_id, agent_id, content, opts \\ []) do
    attrs = %{
      project_id: project_id,
      created_by: agent_id,
      content: content,
      key: Keyword.get(opts, :key),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %Insight{}
    |> create_insight_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Retrieves an insight by exact key match.

  Returns `{:ok, insight}` or `{:error, :not_found}`.
  """
  def get_insight_by_key(project_id, key) when is_binary(project_id) and is_binary(key) do
    Insight
    |> where([i], i.project_id == ^project_id and i.key == ^key)
    |> order_by([i], desc: i.updated_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      insight -> {:ok, insight}
    end
  end

  @doc """
  Lists all insights for a project, ordered by most recent.
  """
  def list_insights(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Insight
    |> where([i], i.project_id == ^project_id)
    |> order_by([i], desc: i.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Updates an insight's content.
  """
  def update_insight(insight_id, content) when is_binary(insight_id) and is_binary(content) do
    case Repo.get(Insight, insight_id) do
      nil ->
        {:error, :not_found}

      insight ->
        insight
        |> update_insight_changeset(%{content: content})
        |> Repo.update()
    end
  end

  @doc """
  Deletes an insight by ID.
  """
  def delete_insight(insight_id) when is_binary(insight_id) do
    case Repo.get(Insight, insight_id) do
      nil -> {:error, :not_found}
      insight -> Repo.delete(insight)
    end
  end

  ## Changesets (add these)

  defp create_insight_changeset(insight, attrs) do
    insight
    |> cast(attrs, [:project_id, :created_by, :key, :content, :metadata])
    |> validate_required([:project_id, :content])
    |> validate_length(:content, min: 1)
    |> validate_length(:key, max: 255)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by)
  end

  defp update_insight_changeset(insight, attrs) do
    insight
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_length(:content, min: 1)
  end
```

### 3.4 Tests

**File**: `test/pop_stash/memory_test.exs`

```elixir
defmodule PopStash.MemoryTest do
  use PopStash.DataCase, async: true

  alias PopStash.{Projects, Agents, Memory}

  setup do
    {:ok, project} = Projects.create("Test Project")
    {:ok, agent} = Agents.connect(project.id, name: "TestAgent")
    %{project: project, agent: agent}
  end

  describe "stashes" do
    test "create_stash/5 creates a stash", %{project: project, agent: agent} do
      assert {:ok, stash} = Memory.create_stash(project.id, agent.id, "my-work", "Working on auth")
      assert stash.name == "my-work"
      assert stash.summary == "Working on auth"
      assert stash.project_id == project.id
      assert stash.created_by == agent.id
    end

    test "create_stash/5 accepts files and metadata", %{project: project, agent: agent} do
      assert {:ok, stash} =
               Memory.create_stash(project.id, agent.id, "test", "summary",
                 files: ["lib/auth.ex"],
                 metadata: %{priority: "high"}
               )

      assert stash.files == ["lib/auth.ex"]
      assert stash.metadata == %{priority: "high"}
    end

    test "get_stash_by_name/2 retrieves stash by exact name", %{project: project, agent: agent} do
      {:ok, stash} = Memory.create_stash(project.id, agent.id, "my-work", "Summary")
      assert {:ok, found} = Memory.get_stash_by_name(project.id, "my-work")
      assert found.id == stash.id
    end

    test "get_stash_by_name/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_stash_by_name(project.id, "nonexistent")
    end

    test "get_stash_by_name/2 ignores expired stashes", %{project: project, agent: agent} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, _} = Memory.create_stash(project.id, agent.id, "expired", "Old", expires_at: past)
      assert {:error, :not_found} = Memory.get_stash_by_name(project.id, "expired")
    end

    test "list_stashes/1 returns all non-expired stashes", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_stash(project.id, agent.id, "stash1", "First")
      {:ok, _} = Memory.create_stash(project.id, agent.id, "stash2", "Second")
      stashes = Memory.list_stashes(project.id)
      assert length(stashes) == 2
    end

    test "delete_stash/1 removes a stash", %{project: project, agent: agent} do
      {:ok, stash} = Memory.create_stash(project.id, agent.id, "temp", "Temp")
      assert {:ok, _} = Memory.delete_stash(stash.id)
      assert {:error, :not_found} = Memory.get_stash_by_name(project.id, "temp")
    end
  end

  describe "insights" do
    test "create_insight/4 creates an insight", %{project: project, agent: agent} do
      assert {:ok, insight} = Memory.create_insight(project.id, agent.id, "Auth uses Guardian")
      assert insight.content == "Auth uses Guardian"
      assert insight.project_id == project.id
      assert insight.created_by == agent.id
    end

    test "create_insight/4 accepts key and metadata", %{project: project, agent: agent} do
      assert {:ok, insight} =
               Memory.create_insight(project.id, agent.id, "Content", key: "auth", metadata: %{verified: true})

      assert insight.key == "auth"
      assert insight.metadata == %{verified: true}
    end

    test "get_insight_by_key/2 retrieves insight by key", %{project: project, agent: agent} do
      {:ok, insight} = Memory.create_insight(project.id, agent.id, "JWT patterns", key: "auth-jwt")
      assert {:ok, found} = Memory.get_insight_by_key(project.id, "auth-jwt")
      assert found.id == insight.id
    end

    test "get_insight_by_key/2 returns error when not found", %{project: project} do
      assert {:error, :not_found} = Memory.get_insight_by_key(project.id, "nonexistent")
    end

    test "list_insights/2 returns recent insights", %{project: project, agent: agent} do
      {:ok, _} = Memory.create_insight(project.id, agent.id, "First")
      {:ok, _} = Memory.create_insight(project.id, agent.id, "Second")
      insights = Memory.list_insights(project.id, limit: 10)
      assert length(insights) == 2
    end

    test "update_insight/2 updates content", %{project: project, agent: agent} do
      {:ok, insight} = Memory.create_insight(project.id, agent.id, "Old content")
      assert {:ok, updated} = Memory.update_insight(insight.id, "New content")
      assert updated.content == "New content"
    end

    test "delete_insight/1 removes an insight", %{project: project, agent: agent} do
      {:ok, insight} = Memory.create_insight(project.id, agent.id, "Temp", key: "temp")
      assert {:ok, _} = Memory.delete_insight(insight.id)
      assert {:error, :not_found} = Memory.get_insight_by_key(project.id, "temp")
    end
  end
end
```

---

## Step 4: MCP Tools

**Goal**: Expose memory operations via MCP protocol with helpful errors and examples.

### 4.1 Tool: `stash`

**File**: `lib/pop_stash/mcp/tools/stash.ex`

```elixir
defmodule PopStash.MCP.Tools.Stash do
  @moduledoc """
  MCP tool for creating stashes.
  """

  alias PopStash.Memory

  @behaviour PopStash.MCP.ToolBehaviour

  @impl true
  def tools do
    [
      %{
        name: "stash",
        description: "Save current context with a name for later retrieval. Use when context is getting long or switching tasks.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Short name for this stash (e.g., 'auth-wip')"},
            summary: %{type: "string", description: "What you were working on and current state"},
            files: %{type: "array", items: %{type: "string"}, description: "Optional list of file paths"}
          },
          required: ["name", "summary"]
        },
        callback: &execute/2
      }
    ]
  end

  defp execute(args, context) do
    # context includes: %{project_id: id, agent_id: id} (set by router in future step)
    project_id = Map.fetch!(context, :project_id)
    agent_id = Map.fetch!(context, :agent_id)

    name = Map.fetch!(args, "name")
    summary = Map.fetch!(args, "summary")
    files = Map.get(args, "files", [])

    case Memory.create_stash(project_id, agent_id, name, summary, files: files) do
      {:ok, stash} ->
        {:ok, """
        ✓ Stashed: #{stash.name}

        Created at: #{format_datetime(stash.inserted_at)}

        To restore this stash later, use:
          `pop` with query: "#{name}"
        """}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:error, "Failed to create stash:\n#{errors}"}
    end
  end

  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map_join("\n", fn {field, errors} -> "  #{field}: #{Enum.join(errors, ", ")}" end)
  end
end
```

### 4.2 Tool: `pop`

**File**: `lib/pop_stash/mcp/tools/pop.ex`

```elixir
defmodule PopStash.MCP.Tools.Pop do
  @moduledoc """
  MCP tool for retrieving stashes by exact name match.
  Phase 4 will add semantic search.
  """

  alias PopStash.Memory

  @behaviour PopStash.MCP.ToolBehaviour

  @impl true
  def tools do
    [
      %{
        name: "pop",
        description: "Retrieve a stash by exact name match. (Semantic search coming in Phase 4)",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Exact name of the stash to retrieve"}
          },
          required: ["name"]
        },
        callback: &execute/2
      }
    ]
  end

  defp execute(args, context) do
    project_id = Map.fetch!(context, :project_id)
    name = Map.fetch!(args, "name")

    case Memory.get_stash_by_name(project_id, name) do
      {:ok, stash} ->
        files_text = if Enum.empty?(stash.files) do
          ""
        else
          "\n\nFiles:\n" <> Enum.map_join(stash.files, "\n", &"  - #{&1}")
        end

        {:ok, """
        ✓ Popped stash: #{stash.name}

        #{stash.summary}#{files_text}

        Created: #{format_datetime(stash.inserted_at)}
        """}

      {:error, :not_found} ->
        {:error, "Stash not found: '#{name}'\n\nTip: Use exact name match. Semantic search coming in Phase 4."}
    end
  end

  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
end
```

### 4.3 Tool: `insight`

**File**: `lib/pop_stash/mcp/tools/insight.ex`

```elixir
defmodule PopStash.MCP.Tools.Insight do
  @moduledoc """
  MCP tool for creating insights.
  """

  alias PopStash.Memory

  @behaviour PopStash.MCP.ToolBehaviour

  @impl true
  def tools do
    [
      %{
        name: "insight",
        description: "Save a persistent insight about the codebase. Insights never expire and are searchable.",
        inputSchema: %{
          type: "object",
          properties: %{
            key: %{type: "string", description: "Optional semantic key (e.g., 'auth-patterns')"},
            content: %{type: "string", description: "The insight content"}
          },
          required: ["content"]
        },
        callback: &execute/2
      }
    ]
  end

  defp execute(args, context) do
    project_id = Map.fetch!(context, :project_id)
    agent_id = Map.fetch!(context, :agent_id)

    content = Map.fetch!(args, "content")
    key = Map.get(args, "key")

    opts = if key, do: [key: key], else: []

    case Memory.create_insight(project_id, agent_id, content, opts) do
      {:ok, insight} ->
        key_text = if insight.key, do: " (#{insight.key})", else: ""

        {:ok, """
        ✓ Insight saved#{key_text}

        #{String.slice(content, 0, 100)}#{if String.length(content) > 100, do: "...", else: ""}

        Created: #{format_datetime(insight.inserted_at)}

        Other agents can find this via `recall`.
        """}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:error, "Failed to save insight:\n#{errors}"}
    end
  end

  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map_join("\n", fn {field, errors} -> "  #{field}: #{Enum.join(errors, ", ")}" end)
  end
end
```

### 4.4 Tool: `recall`

**File**: `lib/pop_stash/mcp/tools/recall.ex`

```elixir
defmodule PopStash.MCP.Tools.Recall do
  @moduledoc """
  MCP tool for retrieving insights by exact key match.
  Phase 4 will add semantic search.
  """

  alias PopStash.Memory

  @behaviour PopStash.MCP.ToolBehaviour

  @impl true
  def tools do
    [
      %{
        name: "recall",
        description: "Retrieve insights by exact key match. (Semantic search coming in Phase 4)",
        inputSchema: %{
          type: "object",
          properties: %{
            key: %{type: "string", description: "Exact key of the insight to retrieve"},
            limit: %{type: "integer", description: "Max results (default: 5)", default: 5}
          },
          required: ["key"]
        },
        callback: &execute/2
      }
    ]
  end

  defp execute(args, context) do
    project_id = Map.fetch!(context, :project_id)
    key = Map.fetch!(args, "key")

    case Memory.get_insight_by_key(project_id, key) do
      {:ok, insight} ->
        {:ok, """
        ✓ Insight: #{insight.key || "(no key)"}

        #{insight.content}

        Created: #{format_datetime(insight.inserted_at)}
        Updated: #{format_datetime(insight.updated_at)}
        """}

      {:error, :not_found} ->
        # Fallback: show recent insights as hint
        recent = Memory.list_insights(project_id, limit: 5)

        hint =
          if Enum.empty?(recent) do
            "No insights saved yet."
          else
            "Recent insights:\n" <>
              Enum.map_join(recent, "\n", fn i ->
                "  - #{i.key || "(no key)"}: #{String.slice(i.content, 0, 60)}..."
              end)
          end

        {:error, "Insight not found: '#{key}'\n\nTip: Use exact key match. Semantic search coming in Phase 4.\n\n#{hint}"}
    end
  end

  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
end
```

### 4.5 Create Tool Behaviour

**File**: `lib/pop_stash/mcp/tool_behaviour.ex`

```elixir
defmodule PopStash.MCP.ToolBehaviour do
  @moduledoc """
  Behaviour for MCP tool modules.
  """

  @callback tools() :: [map()]
end
```

### 4.6 Update Server to Register Tools

**File**: `lib/pop_stash/mcp/server.ex`

```elixir
  @tool_modules [
    PopStash.MCP.Tools.Ping,
    PopStash.MCP.Tools.Stash,  # ← Add
    PopStash.MCP.Tools.Pop,    # ← Add
    PopStash.MCP.Tools.Insight,# ← Add
    PopStash.MCP.Tools.Recall  # ← Add
  ]
```

### 4.7 Agent Context Injection

**Important**: Tools need access to `agent_id`. Since we don't have `start_task` yet, we'll create a temporary agent on first tool use.

**File**: `lib/pop_stash/mcp/router.ex` (update POST handler)

```elixir
  post "/mcp/:project_id" do
    project_id = conn.path_params["project_id"]

    case PopStash.Projects.get(project_id) do
      {:ok, project} ->
        # Get or create agent for this connection
        # In Phase 3, this becomes session-based
        agent_id = get_or_create_agent(project_id, conn)

        context = %{project_id: project.id, agent_id: agent_id}

        case PopStash.MCP.Server.handle_message(conn.body_params, context) do
          {:ok, :notification} -> send_resp(conn, 204, "")
          {:ok, response} -> json(conn, 200, response)
          {:error, response} -> json(conn, 200, response)
        end

      {:error, :not_found} ->
        # ... existing error handling
    end
  end

  # Temporary: Phase 3 will replace this with proper session management
  defp get_or_create_agent(project_id, conn) do
    # Use a deterministic agent ID based on connection (naive, but works for Phase 2)
    # In Phase 3, this becomes proper session tracking
    agent_name = "#{conn.remote_ip |> :inet.ntoa() |> to_string()}"

    case PopStash.Agents.connect(project_id, name: agent_name) do
      {:ok, agent} -> agent.id
      {:error, _} -> raise "Failed to create agent"
    end
  end
```

**Note**: This is a temporary solution. Phase 3 adds proper `start_task`/`end_task` with session-based agent management.

---

## Step 5: Integration Testing

### 5.1 MCP Integration Test

**File**: `test/pop_stash/mcp_integration_test.exs`

```elixir
defmodule PopStash.MCPIntegrationTest do
  use PopStash.DataCase, async: true

  alias PopStash.{Projects, MCP.Router}
  alias Plug.Test

  setup do
    {:ok, project} = Projects.create("Integration Test Project")
    %{project: project}
  end

  defp call_mcp(project_id, method, params \\ %{}) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => params
    }

    conn =
      Test.conn(:post, "/mcp/#{project_id}", Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Router.call([])

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  test "full stash → pop workflow", %{project: project} do
    # 1. Create stash
    {200, response} =
      call_mcp(project.id, "tools/call", %{
        "name" => "stash",
        "arguments" => %{
          "name" => "auth-work",
          "summary" => "Implementing JWT. Done: token gen. TODO: refresh logic.",
          "files" => ["lib/auth.ex"]
        }
      })

    assert response["result"]["content"]
    assert String.contains?(hd(response["result"]["content"])["text"], "✓ Stashed")

    # 2. Pop it back
    {200, response} =
      call_mcp(project.id, "tools/call", %{
        "name" => "pop",
        "arguments" => %{"name" => "auth-work"}
      })

    text = hd(response["result"]["content"])["text"]
    assert String.contains?(text, "✓ Popped stash: auth-work")
    assert String.contains?(text, "Implementing JWT")
    assert String.contains?(text, "lib/auth.ex")
  end

  test "full insight → recall workflow", %{project: project} do
    # 1. Save insight
    {200, response} =
      call_mcp(project.id, "tools/call", %{
        "name" => "insight",
        "arguments" => %{
          "key" => "auth-patterns",
          "content" => "All auth uses Guardian. Tokens expire in 24h. Errors return 401."
        }
      })

    assert String.contains?(hd(response["result"]["content"])["text"], "✓ Insight saved")

    # 2. Recall it
    {200, response} =
      call_mcp(project.id, "tools/call", %{
        "name" => "recall",
        "arguments" => %{"key" => "auth-patterns"}
      })

    text = hd(response["result"]["content"])["text"]
    assert String.contains?(text, "All auth uses Guardian")
  end

  test "pop returns helpful error when stash not found", %{project: project} do
    {200, response} =
      call_mcp(project.id, "tools/call", %{
        "name" => "pop",
        "arguments" => %{"name" => "nonexistent"}
      })

    assert response["result"]["isError"] == true
    text = hd(response["result"]["content"])["text"]
    assert String.contains?(text, "Stash not found")
    assert String.contains?(text, "Tip:")
  end

  test "recall returns helpful error with recent insights hint", %{project: project} do
    # Create some insights first
    call_mcp(project.id, "tools/call", %{
      "name" => "insight",
      "arguments" => %{"key" => "db", "content" => "Uses PostgreSQL"}
    })

    # Try to recall nonexistent
    {200, response} =
      call_mcp(project.id, "tools/call", %{
        "name" => "recall",
        "arguments" => %{"key" => "nonexistent"}
      })

    assert response["result"]["isError"] == true
    text = hd(response["result"]["content"])["text"]
    assert String.contains?(text, "Insight not found")
    assert String.contains?(text, "Recent insights:")
    assert String.contains?(text, "db:")
  end
end
```

---

## Step 6: Manual Testing with Claude Code

### 6.1 Setup Test Workspace

```bash
# 1. Create test project
mix pop_stash.project.new "Phase 2 Test"
# Note the project ID: proj_abc123

# 2. Add to .claude/mcp_servers.json
{
  "pop_stash": {
    "url": "http://localhost:4001/mcp/proj_abc123"
  }
}

# 3. Restart Claude Code
```

### 6.2 Test Scenarios

**Scenario 1: Stash & Pop**
```
User: Use the stash tool to save this: "Working on user auth. Created User schema and basic CRUD. Next: add password hashing"

[Agent uses stash tool]

User: Now pop that stash back

[Agent uses pop tool and retrieves exact content]
```

**Scenario 2: Insight & Recall**
```
User: Save an insight with key "database" saying "We use PostgreSQL 16 with pgvector for embeddings"

[Agent uses insight tool]

User: Recall the "database" insight

[Agent uses recall tool]
```

**Scenario 3: Error Handling**
```
User: Pop a stash named "doesnt-exist"

[Agent should get helpful error with tip about exact matching]
```

### 6.3 Validation Checklist

- [ ] `stash` tool creates records visible in database
- [ ] `pop` tool retrieves exact stash by name
- [ ] `insight` tool saves with optional key
- [ ] `recall` tool retrieves by exact key
- [ ] Error messages are helpful (include tips)
- [ ] All operations scoped to project (try with multiple projects)
- [ ] Files array in stash preserved correctly
- [ ] Timestamps accurate
- [ ] Agent ID captured in created_by

---

## Migration Execution Order

```bash
# Run migrations in dependency order
mix ecto.migrate
```

Ecto will execute in filename order:
1. `20260106_create_agents.exs`
2. `20260106_create_stashes.exs`
3. `20260106_create_insights.exs`

---

## Success Criteria

**Phase 2 is complete when:**

1. ✅ Agents schema, context, and tests passing
2. ✅ Stashes schema, context, and tests passing
3. ✅ Insights schema, context, and tests passing
4. ✅ All four MCP tools (`stash`, `pop`, `insight`, `recall`) working
5. ✅ Integration test passes
6. ✅ Manual testing with Claude Code successful
7. ✅ All queries properly scoped by `project_id`
8. ✅ Error messages include remediation hints
9. ✅ Documentation in each module explains purpose

**What we're NOT doing in Phase 2:**
- ❌ Embeddings / semantic search (Phase 4)
- ❌ Agent.Connection GenServer (Phase 3)
- ❌ Locks / coordination (Phase 3)
- ❌ `start_task` / `end_task` (Phase 3)
- ❌ Observability / telemetry (Phase 5)

---

## Post-Phase 2 Cleanup

Once validated, document learnings:

**File**: `docs/PHASE_2_INSIGHTS.md`

```markdown
# Phase 2 Insights

## What Went Well
- [Record successes]

## What Didn't Work
- [Record issues]

## Changes from Plan
- [Record deviations]

## Technical Debt Incurred
- [Temporary agent creation in router — replace in Phase 3]

## Recommendations for Phase 3
- [Insights for next phase]
```

---

## Principles Applied

1. **Start Simple**: Exact matching before semantic search
2. **Test Everything**: Every context function has tests
3. **Documentation as Feature**: Error messages teach users
4. **Composability**: Each piece works independently
5. **No Premature Optimization**: Phase 4 adds complexity when we've validated Phase 2

This plan builds a solid foundation. Phase 3 will add coordination, and Phase 4 will add the "magic" of semantic search — but only after we know the basics work.

---
