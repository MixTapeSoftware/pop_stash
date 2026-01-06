# Phase 2: Memory Foundation

Exact matching first. Embeddings later. Validate the abstractions before adding complexity.

---

## Dependency Chain

```
projects (done) → agents → stashes/insights → MCP tools → tests
```

Build in order. Breaking order causes compilation errors.

---

## Step 1: Agents

### Migration: `priv/repo/migrations/YYYYMMDDHHMMSS_create_agents.exs`

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
  end
end
```

### Schema: `lib/pop_stash/agents/agent.ex`

```elixir
defmodule PopStash.Agents.Agent do
  use PopStash.Schema

  @statuses ~w(active idle disconnected)

  schema "agents" do
    field :name, :string
    field :current_task, :string
    field :status, :string, default: "active"
    field :connected_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :project, PopStash.Projects.Project

    timestamps()
  end

  def statuses, do: @statuses
end
```

### Context: `lib/pop_stash/agents.ex`

```elixir
defmodule PopStash.Agents do
  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Repo
  alias PopStash.Agents.Agent

  def get(id), do: Repo.get(Agent, id) |> wrap_result()

  def list_active(project_id) do
    Agent
    |> where([a], a.project_id == ^project_id and a.status == "active")
    |> order_by(desc: :last_seen_at)
    |> Repo.all()
  end

  def connect(project_id, opts \\ []) do
    now = DateTime.utc_now()

    %Agent{}
    |> cast(%{
      project_id: project_id,
      name: Keyword.get(opts, :name, "Agent #{DateTime.to_unix(now)}"),
      status: "active",
      connected_at: now,
      last_seen_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
    }, [:project_id, :name, :status, :connected_at, :last_seen_at, :metadata])
    |> validate_required([:project_id, :status])
    |> validate_inclusion(:status, Agent.statuses())
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
  end

  def disconnect(agent_id) do
    with {:ok, agent} <- get(agent_id) do
      agent
      |> cast(%{status: "disconnected"}, [:status])
      |> Repo.update()
    end
  end

  def heartbeat(agent_id) do
    with {:ok, agent} <- get(agent_id) do
      agent
      |> cast(%{last_seen_at: DateTime.utc_now()}, [:last_seen_at])
      |> Repo.update()
    end
  end

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}
end
```

### Update Project schema

Add to `lib/pop_stash/projects/project.ex`:

```elixir
has_many :agents, PopStash.Agents.Agent
```

---

## Step 2: Stashes

### Migration: `priv/repo/migrations/YYYYMMDDHHMMSS_create_stashes.exs`

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
  end
end
```

### Schema: `lib/pop_stash/memory/stash.ex`

```elixir
defmodule PopStash.Memory.Stash do
  use PopStash.Schema

  schema "stashes" do
    field :name, :string
    field :summary, :string
    field :files, {:array, :string}, default: []
    field :metadata, :map, default: %{}
    field :expires_at, :utc_datetime_usec

    belongs_to :project, PopStash.Projects.Project
    belongs_to :agent, PopStash.Agents.Agent, foreign_key: :created_by

    timestamps()
  end
end
```

---

## Step 3: Insights

### Migration: `priv/repo/migrations/YYYYMMDDHHMMSS_create_insights.exs`

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
  end
end
```

### Schema: `lib/pop_stash/memory/insight.ex`

```elixir
defmodule PopStash.Memory.Insight do
  use PopStash.Schema

  schema "insights" do
    field :key, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :project, PopStash.Projects.Project
    belongs_to :agent, PopStash.Agents.Agent, foreign_key: :created_by

    timestamps()
  end
end
```

---

## Step 4: Memory Context

### `lib/pop_stash/memory.ex`

```elixir
defmodule PopStash.Memory do
  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Repo
  alias PopStash.Memory.{Stash, Insight}

  ## Stashes

  def create_stash(project_id, agent_id, name, summary, opts \\ []) do
    %Stash{}
    |> cast(%{
      project_id: project_id,
      created_by: agent_id,
      name: name,
      summary: summary,
      files: Keyword.get(opts, :files, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      expires_at: Keyword.get(opts, :expires_at)
    }, [:project_id, :created_by, :name, :summary, :files, :metadata, :expires_at])
    |> validate_required([:project_id, :name, :summary])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by)
    |> Repo.insert()
  end

  def get_stash_by_name(project_id, name) do
    Stash
    |> where([s], s.project_id == ^project_id and s.name == ^name)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  def list_stashes(project_id) do
    Stash
    |> where([s], s.project_id == ^project_id)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  ## Insights

  def create_insight(project_id, agent_id, content, opts \\ []) do
    %Insight{}
    |> cast(%{
      project_id: project_id,
      created_by: agent_id,
      content: content,
      key: Keyword.get(opts, :key),
      metadata: Keyword.get(opts, :metadata, %{})
    }, [:project_id, :created_by, :content, :key, :metadata])
    |> validate_required([:project_id, :content])
    |> validate_length(:key, max: 255)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by)
    |> Repo.insert()
  end

  def get_insight_by_key(project_id, key) do
    Insight
    |> where([i], i.project_id == ^project_id and i.key == ^key)
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  def list_insights(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Insight
    |> where([i], i.project_id == ^project_id)
    |> order_by(desc: :updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}
end
```

---

## Step 5: MCP Tools

### Tool Behaviour: `lib/pop_stash/mcp/tool_behaviour.ex`

```elixir
defmodule PopStash.MCP.ToolBehaviour do
  @callback tools() :: [map()]
end
```

### Stash Tool: `lib/pop_stash/mcp/tools/stash.ex`

```elixir
defmodule PopStash.MCP.Tools.Stash do
  @behaviour PopStash.MCP.ToolBehaviour
  alias PopStash.Memory

  @impl true
  def tools do
    [%{
      name: "stash",
      description: "Save context for later. Use when switching tasks or context is long.",
      inputSchema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Short name (e.g., 'auth-wip')"},
          summary: %{type: "string", description: "What you're working on"},
          files: %{type: "array", items: %{type: "string"}}
        },
        required: ["name", "summary"]
      },
      callback: &__MODULE__.execute/2
    }]
  end

  def execute(args, %{project_id: project_id, agent_id: agent_id}) do
    case Memory.create_stash(
      project_id,
      agent_id,
      args["name"],
      args["summary"],
      files: Map.get(args, "files", [])
    ) do
      {:ok, stash} ->
        {:ok, "Stashed '#{stash.name}'. Use `pop` with name '#{stash.name}' to restore."}
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
```

### Pop Tool: `lib/pop_stash/mcp/tools/pop.ex`

```elixir
defmodule PopStash.MCP.Tools.Pop do
  @behaviour PopStash.MCP.ToolBehaviour
  alias PopStash.Memory

  @impl true
  def tools do
    [%{
      name: "pop",
      description: "Retrieve a stash by exact name.",
      inputSchema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Exact stash name"}
        },
        required: ["name"]
      },
      callback: &__MODULE__.execute/2
    }]
  end

  def execute(%{"name" => name}, %{project_id: project_id}) do
    case Memory.get_stash_by_name(project_id, name) do
      {:ok, stash} ->
        files = if stash.files == [], do: "", else: "\n\nFiles: #{Enum.join(stash.files, ", ")}"
        {:ok, "#{stash.summary}#{files}"}
      {:error, :not_found} ->
        recent = Memory.list_stashes(project_id) |> Enum.take(5)
        hint = if recent == [] do
          "No stashes yet."
        else
          "Available: " <> Enum.map_join(recent, ", ", & &1.name)
        end
        {:error, "Stash '#{name}' not found. #{hint}"}
    end
  end
end
```

### Insight Tool: `lib/pop_stash/mcp/tools/insight.ex`

```elixir
defmodule PopStash.MCP.Tools.Insight do
  @behaviour PopStash.MCP.ToolBehaviour
  alias PopStash.Memory

  @impl true
  def tools do
    [%{
      name: "insight",
      description: "Save a persistent insight about the codebase.",
      inputSchema: %{
        type: "object",
        properties: %{
          key: %{type: "string", description: "Optional key for retrieval"},
          content: %{type: "string", description: "The insight"}
        },
        required: ["content"]
      },
      callback: &__MODULE__.execute/2
    }]
  end

  def execute(args, %{project_id: project_id, agent_id: agent_id}) do
    opts = if args["key"], do: [key: args["key"]], else: []

    case Memory.create_insight(project_id, agent_id, args["content"], opts) do
      {:ok, insight} ->
        key_text = if insight.key, do: " (key: #{insight.key})", else: ""
        {:ok, "Insight saved#{key_text}. Use `recall` to retrieve."}
      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
  end
end
```

### Recall Tool: `lib/pop_stash/mcp/tools/recall.ex`

```elixir
defmodule PopStash.MCP.Tools.Recall do
  @behaviour PopStash.MCP.ToolBehaviour
  alias PopStash.Memory

  @impl true
  def tools do
    [%{
      name: "recall",
      description: "Retrieve an insight by exact key.",
      inputSchema: %{
        type: "object",
        properties: %{
          key: %{type: "string", description: "Exact insight key"}
        },
        required: ["key"]
      },
      callback: &__MODULE__.execute/2
    }]
  end

  def execute(%{"key" => key}, %{project_id: project_id}) do
    case Memory.get_insight_by_key(project_id, key) do
      {:ok, insight} ->
        {:ok, insight.content}
      {:error, :not_found} ->
        recent = Memory.list_insights(project_id, limit: 5)
        hint = if recent == [] do
          "No insights yet."
        else
          keys = recent |> Enum.filter(& &1.key) |> Enum.map(& &1.key) |> Enum.join(", ")
          if keys == "", do: "No keyed insights.", else: "Keys: #{keys}"
        end
        {:error, "Insight '#{key}' not found. #{hint}"}
    end
  end
end
```

---

## Step 6: Wire Tools to Server

Update `@tool_modules` in `lib/pop_stash/mcp/server.ex`:

```elixir
@tool_modules [
  PopStash.MCP.Tools.Ping,
  PopStash.MCP.Tools.Stash,
  PopStash.MCP.Tools.Pop,
  PopStash.MCP.Tools.Insight,
  PopStash.MCP.Tools.Recall
]
```

Update `handle_message/2` signature and `execute_tool` to pass context:

```elixir
# Change: handle_message now takes context map instead of Project struct
def handle_message(message, %{project_id: _, agent_id: _} = context) do
  # ... existing logic, pass context to route/2
end
```

---

## Step 7: Agent Context in Router

Update `lib/pop_stash/mcp/router.ex`:

```elixir
post "/mcp/:project_id" do
  project_id = conn.path_params["project_id"]

  case PopStash.Projects.get(project_id) do
    {:ok, project} ->
      {:ok, agent} = get_or_create_agent(project.id)
      context = %{project_id: project.id, agent_id: agent.id}

      case PopStash.MCP.Server.handle_message(conn.body_params, context) do
        {:ok, :notification} -> send_resp(conn, 204, "")
        {:ok, response} -> json(conn, 200, response)
        {:error, response} -> json(conn, 200, response)
      end

    {:error, :not_found} ->
      # existing error handling
  end
end

# Temporary - Phase 3 replaces with session-based tracking
defp get_or_create_agent(project_id) do
  PopStash.Agents.connect(project_id, name: "mcp-client")
end
```

**Note**: Creates new agent per request. Phase 3 adds proper session management.

---

## Step 8: Tests

### `test/pop_stash/agents_test.exs`

```elixir
defmodule PopStash.AgentsTest do
  use PopStash.DataCase, async: true
  alias PopStash.{Projects, Agents}

  setup do
    {:ok, project} = Projects.create("Test")
    %{project: project}
  end

  test "connect/2 creates active agent", %{project: p} do
    assert {:ok, agent} = Agents.connect(p.id)
    assert agent.status == "active"
    assert agent.project_id == p.id
  end

  test "disconnect/1 sets status", %{project: p} do
    {:ok, agent} = Agents.connect(p.id)
    assert {:ok, updated} = Agents.disconnect(agent.id)
    assert updated.status == "disconnected"
  end

  test "list_active/1 filters by status", %{project: p} do
    {:ok, a1} = Agents.connect(p.id)
    {:ok, a2} = Agents.connect(p.id)
    Agents.disconnect(a2.id)

    active = Agents.list_active(p.id)
    assert length(active) == 1
    assert hd(active).id == a1.id
  end
end
```

### `test/pop_stash/memory_test.exs`

```elixir
defmodule PopStash.MemoryTest do
  use PopStash.DataCase, async: true
  alias PopStash.{Projects, Agents, Memory}

  setup do
    {:ok, project} = Projects.create("Test")
    {:ok, agent} = Agents.connect(project.id)
    %{project: project, agent: agent}
  end

  describe "stashes" do
    test "create and retrieve by name", %{project: p, agent: a} do
      {:ok, _} = Memory.create_stash(p.id, a.id, "my-work", "summary")
      assert {:ok, stash} = Memory.get_stash_by_name(p.id, "my-work")
      assert stash.summary == "summary"
    end

    test "expired stashes not returned", %{project: p, agent: a} do
      past = DateTime.add(DateTime.utc_now(), -3600)
      {:ok, _} = Memory.create_stash(p.id, a.id, "old", "x", expires_at: past)
      assert {:error, :not_found} = Memory.get_stash_by_name(p.id, "old")
    end
  end

  describe "insights" do
    test "create and retrieve by key", %{project: p, agent: a} do
      {:ok, _} = Memory.create_insight(p.id, a.id, "content", key: "auth")
      assert {:ok, insight} = Memory.get_insight_by_key(p.id, "auth")
      assert insight.content == "content"
    end

    test "list_insights respects limit", %{project: p, agent: a} do
      for i <- 1..10, do: Memory.create_insight(p.id, a.id, "insight #{i}")
      assert length(Memory.list_insights(p.id, limit: 3)) == 3
    end
  end
end
```

---

## Checklist

- [ ] Run migrations: `mix ecto.migrate`
- [ ] Tests pass: `mix test`
- [ ] Manual test with Claude Code:
  - [ ] `stash` creates record
  - [ ] `pop` retrieves by exact name
  - [ ] `insight` saves with optional key
  - [ ] `recall` retrieves by exact key
  - [ ] Errors show helpful hints
  - [ ] Different projects are isolated

---

## What's NOT in Phase 2

- Embeddings / semantic search (Phase 4)
- Agent.Connection GenServer (Phase 3)
- Locks / coordination (Phase 3)
- `start_task` / `end_task` (Phase 3)
- Telemetry (Phase 5)

---

## Technical Debt

1. **Agent per request**: Router creates new agent each request. Phase 3 fixes with sessions.
2. **No cleanup**: Stale agents accumulate. Phase 3 adds lifecycle management.

Both are acceptable for validating the core abstractions.
