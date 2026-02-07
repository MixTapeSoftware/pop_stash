# Phase 3: Decisions - Detailed Implementation Plan

## Overview

**Goal:** Add an immutable decision log so agents can record and query architectural decisions, technical choices, and project direction.

**Why This Matters:** Decisions are persistent knowledge - "We chose Guardian over Pow for auth because..." A single agent working across multiple sessions needs to remember what decisions were made and why.

---

## Design Principles

1. **Immutable Log**: Decisions are append-only. New decisions on the same topic create new entries (full history preserved). No updates.
2. **Topic Normalization**: Topics are lowercased and trimmed to prevent duplicates like "Authentication" vs "authentication"
3. **Simplified Schema**: Use `topic`, `decision`, `reasoning` fields
4. **Defer Embeddings**: Column added in Phase 4 when search infrastructure exists
5. **Defer Semantic Search**: Phase 3 uses exact topic matching; Phase 4 adds semantic search

---

## Step 1: Create Migration

**File:** `priv/repo/migrations/YYYYMMDDHHMMSS_create_decisions.exs`

**Command:** `mix ecto.gen.migration create_decisions`

```elixir
defmodule PopStash.Repo.Migrations.CreateDecisions do
  use Ecto.Migration

  def change do
    create table(:decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :topic, :string, null: false
      add :decision, :text, null: false
      add :reasoning, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Query by project
    create index(:decisions, [:project_id])
    # Query by topic within project (most common query)
    create index(:decisions, [:project_id, :topic])
    # Query recent decisions
    create index(:decisions, [:project_id, :inserted_at])
  end
end
```

**Why These Indexes:**
- `[:project_id]` - List all decisions for a project
- `[:project_id, :topic]` - Get decisions by topic (primary use case)
- `[:project_id, :inserted_at]` - List recent decisions efficiently

**Run:** `mix ecto.migrate`

---

## Step 2: Create Decision Schema

**File:** `lib/pop_stash/memory/decision.ex`

```elixir
defmodule PopStash.Memory.Decision do
  @moduledoc """
  Schema for decisions (immutable decision log).

  Decisions record architectural choices, technical decisions, and project direction.
  They are append-only - new decisions on the same topic create new entries,
  preserving full history.
  """

  use PopStash.Schema

  schema "decisions" do
    field :topic, :string
    field :decision, :string
    field :reasoning, :string
    field :metadata, :map, default: %{}

    belongs_to :project, PopStash.Projects.Project
    belongs_to :agent, PopStash.Agents.Agent, foreign_key: :created_by

    timestamps()
  end

  @doc """
  Normalizes a topic string for consistent matching.
  Trims whitespace and converts to lowercase.
  """
  def normalize_topic(topic) when is_binary(topic) do
    topic
    |> String.trim()
    |> String.downcase()
  end

  def normalize_topic(nil), do: nil
end
```

**Key Decisions:**
- Topic normalization function lives on the schema for reuse
- No changeset here - validation happens in context module (consistent with existing patterns)
- `reasoning` is optional (nullable in DB)

---

## Step 3: Add Context Functions to PopStash.Memory

**File:** `lib/pop_stash/memory.ex` (add to existing file)

Add alias at top:
```elixir
alias PopStash.Memory.Decision
```

Add new section for Decisions:

```elixir
## Decisions

@doc """
Creates an immutable decision record.

Topics are automatically normalized (lowercased, trimmed) for consistent matching.

## Options
  * `:reasoning` - Why this decision was made (optional)
  * `:metadata` - Optional metadata map
"""
def create_decision(project_id, agent_id, topic, decision, opts \\ []) do
  %Decision{}
  |> cast(
    %{
      project_id: project_id,
      created_by: agent_id,
      topic: Decision.normalize_topic(topic),
      decision: decision,
      reasoning: Keyword.get(opts, :reasoning),
      metadata: Keyword.get(opts, :metadata, %{})
    },
    [:project_id, :created_by, :topic, :decision, :reasoning, :metadata]
  )
  |> validate_required([:project_id, :topic, :decision])
  |> validate_length(:topic, min: 1, max: 255)
  |> foreign_key_constraint(:project_id)
  |> foreign_key_constraint(:created_by)
  |> Repo.insert()
end

@doc """
Retrieves a decision by ID.
"""
def get_decision(decision_id) when is_binary(decision_id) do
  Decision
  |> Repo.get(decision_id)
  |> wrap_result()
end

@doc """
Gets all decisions for a topic within a project.
Returns most recent first (full history for this topic).

Topic is automatically normalized for matching.
"""
def get_decisions_by_topic(project_id, topic) when is_binary(project_id) and is_binary(topic) do
  normalized_topic = Decision.normalize_topic(topic)

  Decision
  |> where([d], d.project_id == ^project_id and d.topic == ^normalized_topic)
  |> order_by(desc: :inserted_at)
  |> Repo.all()
end

@doc """
Lists decisions for a project.

## Options
  * `:limit` - Maximum number of decisions to return (default: 50)
  * `:since` - Only return decisions after this datetime
  * `:topic` - Filter by topic (exact match after normalization)
"""
def list_decisions(project_id, opts \\ []) when is_binary(project_id) do
  limit = Keyword.get(opts, :limit, 50)
  since = Keyword.get(opts, :since)
  topic = Keyword.get(opts, :topic)

  Decision
  |> where([d], d.project_id == ^project_id)
  |> maybe_filter_since(since)
  |> maybe_filter_topic(topic)
  |> order_by(desc: :inserted_at)
  |> limit(^limit)
  |> Repo.all()
end

defp maybe_filter_since(query, nil), do: query
defp maybe_filter_since(query, since) do
  where(query, [d], d.inserted_at > ^since)
end

defp maybe_filter_topic(query, nil), do: query
defp maybe_filter_topic(query, topic) do
  normalized = Decision.normalize_topic(topic)
  where(query, [d], d.topic == ^normalized)
end

@doc """
Deletes a decision by ID.
For admin use only - decisions are generally immutable.
"""
def delete_decision(decision_id) when is_binary(decision_id) do
  case Repo.get(Decision, decision_id) do
    nil -> {:error, :not_found}
    decision -> Repo.delete(decision)
  end
end

@doc """
Lists all unique topics for a project.
Useful for discovering what decisions exist.
"""
def list_decision_topics(project_id) when is_binary(project_id) do
  Decision
  |> where([d], d.project_id == ^project_id)
  |> select([d], d.topic)
  |> distinct(true)
  |> order_by(asc: :topic)
  |> Repo.all()
end
```

---

## Step 4: Create MCP Tool for Recording Decisions

**File:** `lib/pop_stash/mcp/tools/decide.ex`

```elixir
defmodule PopStash.MCP.Tools.Decide do
  @moduledoc """
  MCP tool for recording architectural decisions.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "decide",
        description: """
        Record an architectural or imoportant or key technical decision. Decisions are immutable - \
        recording a new decision on the same topic creates a new entry, preserving history. \
        Use this to document choices like "We chose Phoenix LiveView over React because..."
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            topic: %{
              type: "string",
              description: "What area this decision affects (e.g., 'authentication', 'database', 'api-design')"
            },
            decision: %{
              type: "string",
              description: "What was decided"
            },
            reasoning: %{
              type: "string",
              description: "Why this decision was made (optional but recommended)"
            }
          },
          required: ["topic", "decision"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(args, %{project_id: project_id, agent_id: agent_id}) do
    opts = if args["reasoning"], do: [reasoning: args["reasoning"]], else: []

    case Memory.create_decision(project_id, agent_id, args["topic"], args["decision"], opts) do
      {:ok, decision} ->
        {:ok, """
        Decision recorded for topic "#{decision.topic}".
        Use `get_decisions` to retrieve decisions by topic.
        """}

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

---

## Step 5: Create MCP Tool for Querying Decisions

**File:** `lib/pop_stash/mcp/tools/get_decisions.ex`

```elixir
defmodule PopStash.MCP.Tools.GetDecisions do
  @moduledoc """
  MCP tool for querying decisions.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "get_decisions",
        description: """
        Query recorded decisions. Provide a topic to get all decisions for that topic, \
        or omit topic to list recent decisions. Topics are matched case-insensitively.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            topic: %{
              type: "string",
              description: "Topic to query (optional - if omitted, lists recent decisions)"
            },
            limit: %{
              type: "integer",
              description: "Maximum number of decisions to return (default: 10)"
            },
            list_topics: %{
              type: "boolean",
              description: "If true, returns only the list of unique topics (ignores other params)"
            }
          },
          required: []
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"list_topics" => true}, %{project_id: project_id}) do
    topics = Memory.list_decision_topics(project_id)

    if Enum.empty?(topics) do
      {:ok, "No decisions recorded yet."}
    else
      topic_list = Enum.map_join(topics, "\n", &"  • #{&1}")
      {:ok, "Decision topics:\n#{topic_list}"}
    end
  end

  def execute(args, %{project_id: project_id}) do
    limit = Map.get(args, "limit", 10)

    decisions =
      if topic = args["topic"] do
        Memory.get_decisions_by_topic(project_id, topic)
        |> Enum.take(limit)
      else
        Memory.list_decisions(project_id, limit: limit)
      end

    format_decisions(decisions, args["topic"])
  end

  defp format_decisions([], nil) do
    {:ok, "No decisions recorded yet. Use `decide` to record architectural decisions."}
  end

  defp format_decisions([], topic) do
    {:ok, "No decisions found for topic \"#{topic}\". Use `get_decisions` with `list_topics: true` to see available topics."}
  end

  defp format_decisions(decisions, topic) do
    header = if topic do
      "Decisions for \"#{topic}\" (#{length(decisions)} found, most recent first):\n\n"
    else
      "Recent decisions (#{length(decisions)}):\n\n"
    end

    formatted = Enum.map_join(decisions, "\n---\n\n", &format_decision/1)
    {:ok, header <> formatted}
  end

  defp format_decision(decision) do
    base = """
    **Topic:** #{decision.topic}
    **Decision:** #{decision.decision}
    """

    with_reasoning = if decision.reasoning do
      base <> "**Reasoning:** #{decision.reasoning}\n"
    else
      base
    end

    timestamp = Calendar.strftime(decision.inserted_at, "%Y-%m-%d %H:%M UTC")
    with_reasoning <> "*Recorded: #{timestamp}*"
  end
end
```

---

## Step 6: Wire Tools to MCP Server

**File:** `lib/pop_stash/mcp/server.ex`

Update the `@tool_modules` list:

```elixir
@tool_modules [
  PopStash.MCP.Tools.Ping,
  PopStash.MCP.Tools.Stash,
  PopStash.MCP.Tools.Pop,
  PopStash.MCP.Tools.Insight,
  PopStash.MCP.Tools.Recall,
  PopStash.MCP.Tools.Decide,        # Add this
  PopStash.MCP.Tools.GetDecisions   # Add this
]
```

---

## Step 7: Unit Tests for Decision Schema and Context

**File:** `test/pop_stash/memory_test.exs` (add to existing file)

```elixir
describe "decisions" do
  test "create_decision/5 creates a decision", %{project: project, agent: agent} do
    assert {:ok, decision} =
             Memory.create_decision(project.id, agent.id, "Authentication", "Use Guardian for JWT auth")

    assert decision.topic == "authentication"  # normalized
    assert decision.decision == "Use Guardian for JWT auth"
    assert decision.project_id == project.id
    assert decision.created_by == agent.id
  end

  test "create_decision/5 accepts reasoning and metadata", %{project: project, agent: agent} do
    assert {:ok, decision} =
             Memory.create_decision(project.id, agent.id, "database", "Use PostgreSQL",
               reasoning: "Better JSON support than MySQL",
               metadata: %{alternatives_considered: ["MySQL", "SQLite"]}
             )

    assert decision.reasoning == "Better JSON support than MySQL"
    assert decision.metadata == %{alternatives_considered: ["MySQL", "SQLite"]}
  end

  test "create_decision/5 normalizes topic (lowercase, trim)", %{project: project, agent: agent} do
    assert {:ok, d1} = Memory.create_decision(project.id, agent.id, "  AUTH  ", "Decision 1")
    assert {:ok, d2} = Memory.create_decision(project.id, agent.id, "Auth", "Decision 2")
    assert {:ok, d3} = Memory.create_decision(project.id, agent.id, "auth", "Decision 3")

    assert d1.topic == "auth"
    assert d2.topic == "auth"
    assert d3.topic == "auth"
  end

  test "get_decision/1 retrieves decision by ID", %{project: project, agent: agent} do
    {:ok, decision} = Memory.create_decision(project.id, agent.id, "testing", "Use ExUnit")

    assert {:ok, found} = Memory.get_decision(decision.id)
    assert found.id == decision.id
    assert found.topic == "testing"
  end

  test "get_decision/1 returns error when not found" do
    assert {:error, :not_found} = Memory.get_decision(Ecto.UUID.generate())
  end

  test "get_decisions_by_topic/2 returns all decisions for topic (most recent first)", %{project: project, agent: agent} do
    {:ok, d1} = Memory.create_decision(project.id, agent.id, "auth", "First decision")
    Process.sleep(10)  # Ensure different timestamps
    {:ok, d2} = Memory.create_decision(project.id, agent.id, "AUTH", "Second decision")  # Different case
    {:ok, _other} = Memory.create_decision(project.id, agent.id, "database", "Other topic")

    decisions = Memory.get_decisions_by_topic(project.id, "Auth")  # Query with different case

    assert length(decisions) == 2
    assert hd(decisions).id == d2.id  # Most recent first
    assert List.last(decisions).id == d1.id
  end

  test "list_decisions/2 returns recent decisions", %{project: project, agent: agent} do
    {:ok, _} = Memory.create_decision(project.id, agent.id, "topic1", "Decision 1")
    {:ok, _} = Memory.create_decision(project.id, agent.id, "topic2", "Decision 2")

    decisions = Memory.list_decisions(project.id)
    assert length(decisions) == 2
  end

  test "list_decisions/2 respects limit", %{project: project, agent: agent} do
    for i <- 1..10 do
      Memory.create_decision(project.id, agent.id, "topic#{i}", "Decision #{i}")
    end

    assert length(Memory.list_decisions(project.id, limit: 3)) == 3
  end

  test "list_decisions/2 filters by topic", %{project: project, agent: agent} do
    {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Auth decision")
    {:ok, _} = Memory.create_decision(project.id, agent.id, "database", "DB decision")

    decisions = Memory.list_decisions(project.id, topic: "auth")
    assert length(decisions) == 1
    assert hd(decisions).topic == "auth"
  end

  test "list_decisions/2 filters by since datetime", %{project: project, agent: agent} do
    {:ok, _old} = Memory.create_decision(project.id, agent.id, "old", "Old decision")
    cutoff = DateTime.utc_now()
    Process.sleep(10)
    {:ok, new} = Memory.create_decision(project.id, agent.id, "new", "New decision")

    decisions = Memory.list_decisions(project.id, since: cutoff)
    assert length(decisions) == 1
    assert hd(decisions).id == new.id
  end

  test "delete_decision/1 removes a decision", %{project: project, agent: agent} do
    {:ok, decision} = Memory.create_decision(project.id, agent.id, "temp", "Temporary")

    assert {:ok, _} = Memory.delete_decision(decision.id)
    assert {:error, :not_found} = Memory.get_decision(decision.id)
  end

  test "delete_decision/1 returns error for nonexistent decision" do
    assert {:error, :not_found} = Memory.delete_decision(Ecto.UUID.generate())
  end

  test "list_decision_topics/1 returns unique topics", %{project: project, agent: agent} do
    {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Decision 1")
    {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Decision 2")
    {:ok, _} = Memory.create_decision(project.id, agent.id, "database", "Decision 3")
    {:ok, _} = Memory.create_decision(project.id, agent.id, "api", "Decision 4")

    topics = Memory.list_decision_topics(project.id)
    assert topics == ["api", "auth", "database"]  # Alphabetical order
  end
end

describe "decisions project isolation" do
  test "decisions are isolated by project", %{agent: agent} do
    {:ok, project1} = Projects.create("Project 1")
    {:ok, project2} = Projects.create("Project 2")

    {:ok, _} = Memory.create_decision(project1.id, agent.id, "auth", "P1 decision")
    {:ok, _} = Memory.create_decision(project2.id, agent.id, "auth", "P2 decision")

    p1_decisions = Memory.get_decisions_by_topic(project1.id, "auth")
    p2_decisions = Memory.get_decisions_by_topic(project2.id, "auth")

    assert length(p1_decisions) == 1
    assert length(p2_decisions) == 1
    assert hd(p1_decisions).decision == "P1 decision"
    assert hd(p2_decisions).decision == "P2 decision"
  end
end
```

---

## Step 8: Integration Tests for MCP Tools

**File:** `test/pop_stash/mcp/tools/decide_test.exs`

```elixir
defmodule PopStash.MCP.Tools.DecideTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.Decide
  alias PopStash.{Agents, Memory}

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, agent} = Agents.connect(project.id, name: "test-agent")
    context = %{project_id: project.id, agent_id: agent.id}
    {:ok, context: context, project: project}
  end

  describe "execute/2" do
    test "records a decision with topic and decision", %{context: context, project: project} do
      args = %{
        "topic" => "Authentication",
        "decision" => "Use Guardian for JWT"
      }

      assert {:ok, message} = Decide.execute(args, context)
      assert message =~ "Decision recorded"
      assert message =~ "authentication"  # normalized

      # Verify it was saved
      [decision] = Memory.get_decisions_by_topic(project.id, "authentication")
      assert decision.decision == "Use Guardian for JWT"
    end

    test "records a decision with reasoning", %{context: context, project: project} do
      args = %{
        "topic" => "database",
        "decision" => "Use PostgreSQL",
        "reasoning" => "Better JSON support"
      }

      assert {:ok, _} = Decide.execute(args, context)

      [decision] = Memory.get_decisions_by_topic(project.id, "database")
      assert decision.reasoning == "Better JSON support"
    end

    test "returns error for missing required fields", %{context: context} do
      args = %{"topic" => "auth"}  # missing decision

      assert {:error, message} = Decide.execute(args, context)
      assert message =~ "decision"
    end
  end
end
```

**File:** `test/pop_stash/mcp/tools/get_decisions_test.exs`

```elixir
defmodule PopStash.MCP.Tools.GetDecisionsTest do
  use PopStash.DataCase, async: true

  alias PopStash.MCP.Tools.GetDecisions
  alias PopStash.{Agents, Memory}

  import PopStash.Fixtures

  setup do
    project = project_fixture()
    {:ok, agent} = Agents.connect(project.id, name: "test-agent")
    context = %{project_id: project.id, agent_id: agent.id}
    {:ok, context: context, project: project, agent: agent}
  end

  describe "execute/2" do
    test "returns message when no decisions exist", %{context: context} do
      assert {:ok, message} = GetDecisions.execute(%{}, context)
      assert message =~ "No decisions recorded"
    end

    test "lists recent decisions when no topic provided", %{context: context, project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Use Guardian")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "db", "Use Postgres")

      assert {:ok, message} = GetDecisions.execute(%{}, context)
      assert message =~ "auth"
      assert message =~ "db"
      assert message =~ "Use Guardian"
    end

    test "filters by topic", %{context: context, project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Auth decision")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "database", "DB decision")

      assert {:ok, message} = GetDecisions.execute(%{"topic" => "auth"}, context)
      assert message =~ "Auth decision"
      refute message =~ "DB decision"
    end

    test "topic matching is case-insensitive", %{context: context, project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "Authentication", "Decision")

      assert {:ok, message} = GetDecisions.execute(%{"topic" => "AUTHENTICATION"}, context)
      assert message =~ "Decision"
    end

    test "respects limit parameter", %{context: context, project: project, agent: agent} do
      for i <- 1..5 do
        Memory.create_decision(project.id, agent.id, "topic", "Decision #{i}")
      end

      assert {:ok, message} = GetDecisions.execute(%{"limit" => 2}, context)
      assert message =~ "2"
    end

    test "lists topics when list_topics is true", %{context: context, project: project, agent: agent} do
      {:ok, _} = Memory.create_decision(project.id, agent.id, "auth", "Decision")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "database", "Decision")
      {:ok, _} = Memory.create_decision(project.id, agent.id, "api", "Decision")

      assert {:ok, message} = GetDecisions.execute(%{"list_topics" => true}, context)
      assert message =~ "Decision topics:"
      assert message =~ "auth"
      assert message =~ "database"
      assert message =~ "api"
    end

    test "returns helpful message when topic not found", %{context: context} do
      assert {:ok, message} = GetDecisions.execute(%{"topic" => "nonexistent"}, context)
      assert message =~ "No decisions found"
      assert message =~ "list_topics"
    end
  end
end
```

---

## Step 9: Add Server Test for New Tools

**File:** `test/pop_stash/mcp/server_test.exs` (add to existing file)

```elixir
describe "decision tools" do
  test "decide tool records a decision", %{context: context} do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "decide",
        "arguments" => %{
          "topic" => "testing",
          "decision" => "Use ExUnit",
          "reasoning" => "Built into Elixir"
        }
      }
    }

    assert {:ok, response} = Server.handle_message(message, context)
    assert [%{text: text}] = response.result.content
    assert text =~ "Decision recorded"
  end

  test "get_decisions tool queries decisions", %{context: context} do
    # First record a decision
    decide_msg = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "decide",
        "arguments" => %{"topic" => "auth", "decision" => "Use Guardian"}
      }
    }
    Server.handle_message(decide_msg, context)

    # Then query it
    query_msg = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_decisions",
        "arguments" => %{"topic" => "auth"}
      }
    }

    assert {:ok, response} = Server.handle_message(query_msg, context)
    assert [%{text: text}] = response.result.content
    assert text =~ "Use Guardian"
  end
end
```

---

## Step 10: Manual Testing with Claude Code

After implementation, test the full workflow:

### 1. Start the server
```bash
mix pop_stash.server
```

### 2. Configure Claude Code
Add to `.claude/mcp_servers.json`:
```json
{
  "pop_stash": {
    "url": "http://localhost:4001/mcp/YOUR_PROJECT_ID"
  }
}
```

### 3. Test scenarios in Claude Code

**Record a decision:**
```
Use the decide tool to record that we chose PostgreSQL over MySQL for the database because of better JSON support and the pgvector extension for embeddings.
```

**Query decisions:**
```
Use get_decisions to see what we decided about the database.
```

**List all topics:**
```
Use get_decisions with list_topics to see all decision areas.
```

**Test case normalization:**
```
Use decide to record a decision for "API Design" about using REST.
Then use get_decisions to query for "api design" (lowercase).
```

---

## Implementation Checklist

### Migration & Schema
- [ ] Generate migration with `mix ecto.gen.migration create_decisions`
- [ ] Implement migration with proper indexes
- [ ] Run `mix ecto.migrate`
- [ ] Create `lib/pop_stash/memory/decision.ex` schema

### Context Functions
- [ ] Add `alias PopStash.Memory.Decision` to memory.ex
- [ ] Implement `create_decision/5`
- [ ] Implement `get_decision/1`
- [ ] Implement `get_decisions_by_topic/2`
- [ ] Implement `list_decisions/2` with options
- [ ] Implement `delete_decision/1`
- [ ] Implement `list_decision_topics/1`
- [ ] Add helper functions `maybe_filter_since/2` and `maybe_filter_topic/2`

### MCP Tools
- [ ] Create `lib/pop_stash/mcp/tools/decide.ex`
- [ ] Create `lib/pop_stash/mcp/tools/get_decisions.ex`
- [ ] Add both modules to `@tool_modules` in server.ex

### Testing
- [ ] Add decision tests to `test/pop_stash/memory_test.exs`
- [ ] Create `test/pop_stash/mcp/tools/decide_test.exs`
- [ ] Create `test/pop_stash/mcp/tools/get_decisions_test.exs`
- [ ] Add server integration tests
- [ ] Run full test suite: `mix test`

### Manual Verification
- [ ] Start server with `mix pop_stash.server`
- [ ] Configure Claude Code with project ID
- [ ] Test `decide` tool with various topics
- [ ] Test `get_decisions` with topic filter
- [ ] Test `get_decisions` with `list_topics: true`
- [ ] Verify topic normalization (case-insensitive matching)

---

## Files Changed Summary

| File | Action | Description |
|------|--------|-------------|
| `priv/repo/migrations/*_create_decisions.exs` | Create | Migration for decisions table |
| `lib/pop_stash/memory/decision.ex` | Create | Decision schema with topic normalization |
| `lib/pop_stash/memory.ex` | Modify | Add decision context functions |
| `lib/pop_stash/mcp/tools/decide.ex` | Create | MCP tool for recording decisions |
| `lib/pop_stash/mcp/tools/get_decisions.ex` | Create | MCP tool for querying decisions |
| `lib/pop_stash/mcp/server.ex` | Modify | Register new tool modules |
| `test/pop_stash/memory_test.exs` | Modify | Add decision unit tests |
| `test/pop_stash/mcp/tools/decide_test.exs` | Create | Integration tests for decide tool |
| `test/pop_stash/mcp/tools/get_decisions_test.exs` | Create | Integration tests for get_decisions tool |
| `test/pop_stash/mcp/server_test.exs` | Modify | Add decision tool server tests |

---

## Estimated Time

- Migration & Schema: 15 minutes
- Context Functions: 30 minutes
- MCP Tools: 30 minutes
- Unit Tests: 45 minutes
- Integration Tests: 30 minutes
- Manual Testing: 15 minutes

**Total: ~2.5 hours**

---

## Future Considerations (Phase 4+)

1. **Embeddings Column**: Add `embedding vector(1536)` column for semantic search
2. **Semantic Search**: Query decisions by meaning, not just exact topic match
3. **Decision Superseding**: Optionally link new decisions to ones they replace
4. **Decision Categories**: Add tags/categories for cross-cutting concerns
5. **Decision Export**: Export decisions as ADR (Architecture Decision Records) markdown files
