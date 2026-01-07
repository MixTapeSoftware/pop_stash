# Phase 4: Discoverability with Typesense

## Overview

Implement semantic search for PopStash by adding:
1. Nx.Serving for embeddings (all-MiniLM-L6-v2, 384 dimensions)
2. Typesense for hybrid search (text + vector, built-in scoring)
3. pgvector columns for embedding persistence (enables reindexing)
4. Async embedding generation on create/update via PubSub
5. Upgraded `recall` and `pop` tools returning ranked result lists

## Key Decisions
- **Model**: all-MiniLM-L6-v2 (384 dimensions, fast)
- **Embedding generation**: Async (non-blocking writes)
- **Search engine**: Typesense handles both text and vector search with built-in hybrid scoring
- **Embedding storage**: pgvector in Postgres for persistence; Typesense for search
- **Reindexing**: Mix task rebuilds Typesense index from Postgres (source of truth)
- **Event-driven indexing**: PubSub decouples Memory context from Search
- **Results**: Always return a list (exact match = list of one)

---

## Step 1: Dependencies

**File:** `mix.exs`

Add to `deps`:
```elixir
# Embeddings
{:bumblebee, "~> 0.6"},
{:nx, "~> 0.9"},
{:exla, "~> 0.9"},

# Typesense
{:typesense_ex, git: "https://github.com/MixTapeSoftware/typesense_ex"},

# pgvector support
{:pgvector, "~> 0.3"}
```

Add to `application` extra_applications:
```elixir
extra_applications: [:logger, :runtime_tools, :exla]
```

---

## Step 2: Docker Compose - Add Typesense

**File:** `docker-compose.yml`

Add typesense service:
```yaml
typesense:
  image: typesense/typesense:27.1
  environment:
    TYPESENSE_API_KEY: pop_stash_dev_key
    TYPESENSE_DATA_DIR: /data
  ports:
    - "127.0.0.1:8108:8108"
  volumes:
    - pop_stash_typesense_data:/data
```

Add volume:
```yaml
volumes:
  pgdata:
  pop_stash_typesense_data:
```

---

## Step 3: Configuration

**File:** `config/config.exs`

```elixir
# TypesenseEx configuration
config :pop_stash, :typesense,
  api_key: "pop_stash_dev_key",
  nodes: [
    %{
      host: "localhost",
      port: 8108,
      protocol: "http"
    }
  ],
  enabled: true

config :pop_stash, PopStash.Embeddings,
  model: "sentence-transformers/all-MiniLM-L6-v2",
  dimensions: 384,
  enabled: true
```

**File:** `config/runtime.exs` (create if needed)

```elixir
import Config

if config_env() == :prod do
  typesense_url = System.get_env("TYPESENSE_URL") || raise("TYPESENSE_URL not set")
  typesense_api_key = System.get_env("TYPESENSE_API_KEY") || raise("TYPESENSE_API_KEY not set")
  
  # Parse URL to extract host, port, protocol
  uri = URI.parse(typesense_url)
  
  config :pop_stash, :typesense,
    api_key: typesense_api_key,
    nodes: [
      %{
        host: uri.host,
        port: uri.port || 8108,
        protocol: uri.scheme || "https"
      }
    ],
    enabled: true
end
```

**File:** `config/test.exs`

```elixir
config :pop_stash, PopStash.Embeddings, enabled: false
config :pop_stash, :typesense, enabled: false
```

---

## Step 4: Database Migration - Add Vector Columns

**File:** `priv/repo/migrations/TIMESTAMP_add_embedding_columns.exs`

```elixir
defmodule PopStash.Repo.Migrations.AddEmbeddingColumns do
  use Ecto.Migration

  def up do
    # Enable pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Stashes - embed name + summary
    alter table(:stashes) do
      add :embedding, :vector, size: 384
    end

    # Insights - embed key + content
    alter table(:insights) do
      add :embedding, :vector, size: 384
    end

    # Decisions - embed topic + decision + reasoning
    alter table(:decisions) do
      add :embedding, :vector, size: 384
    end

    # HNSW indexes for fast similarity search
    execute "CREATE INDEX stashes_embedding_idx ON stashes USING hnsw (embedding vector_cosine_ops)"
    execute "CREATE INDEX insights_embedding_idx ON insights USING hnsw (embedding vector_cosine_ops)"
    execute "CREATE INDEX decisions_embedding_idx ON decisions USING hnsw (embedding vector_cosine_ops)"
  end

  def down do
    drop index(:stashes, [:embedding])
    drop index(:insights, [:embedding])
    drop index(:decisions, [:embedding])

    alter table(:stashes) do
      remove :embedding
    end

    alter table(:insights) do
      remove :embedding
    end

    alter table(:decisions) do
      remove :embedding
    end

    execute "DROP EXTENSION IF EXISTS vector"
  end
end
```

---

## Step 5: Update Schemas

**File:** `lib/pop_stash/memory/stash.ex`

Add field:
```elixir
field :embedding, Pgvector.Ecto.Vector
```

**File:** `lib/pop_stash/memory/insight.ex`

Add field:
```elixir
field :embedding, Pgvector.Ecto.Vector
```

**File:** `lib/pop_stash/memory/decision.ex`

Add field:
```elixir
field :embedding, Pgvector.Ecto.Vector
```

---

## Step 6: Embeddings Module (Nx.Serving)

**File:** `lib/pop_stash/embeddings.ex`

Uses `Nx.Serving` directly for automatic request batching. No GenServer wrapper needed.

```elixir
defmodule PopStash.Embeddings do
  @moduledoc """
  Text embeddings using all-MiniLM-L6-v2 via Nx.Serving.

  Nx.Serving handles batching automatically - multiple concurrent
  embed/1 calls are batched together for efficient GPU/CPU usage.
  """

  require Logger

  @doc """
  Builds the Nx.Serving for text embeddings.
  Called by supervision tree at startup.
  """
  def serving do
    config = Application.get_env(:pop_stash, __MODULE__, [])
    model_name = Keyword.get(config, :model, "sentence-transformers/all-MiniLM-L6-v2")

    Logger.info("Loading embedding model: #{model_name}")

    {:ok, model} = Bumblebee.load_model({:hf, model_name})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name})

    Bumblebee.Text.text_embedding(model, tokenizer,
      defn_options: [compiler: EXLA],
      output_pool: :mean_pooling,
      output_attribute: :hidden_state
    )
  end

  @doc """
  Generate embedding for text. Blocks until model is ready.
  Returns {:ok, vector} or {:error, reason}.
  """
  def embed(text) when is_binary(text) do
    if enabled?() do
      %{embedding: embedding} = Nx.Serving.batched_run(__MODULE__, text)
      {:ok, Nx.to_list(embedding)}
    else
      {:error, :embeddings_disabled}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Check if the embedding service is enabled and ready.
  """
  def enabled? do
    config = Application.get_env(:pop_stash, __MODULE__, [])
    Keyword.get(config, :enabled, false)
  end

  @doc """
  Check if the embedding serving process is alive.
  """
  def ready? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
```

**Supervision tree** in `lib/pop_stash/application.ex`:
```elixir
def start(_type, _args) do
  typesense_enabled? = Application.get_env(:pop_stash, :typesense, [])[:enabled] || false
  embeddings_enabled? = Application.get_env(:pop_stash, PopStash.Embeddings, [])[:enabled] || false

  children =
    [
      PopStash.Repo,
      {Phoenix.PubSub, name: PopStash.PubSub},
      {Task.Supervisor, name: PopStash.TaskSupervisor, max_children: 50}
    ] ++
    maybe_child(typesense_enabled?, {TypesenseEx, Application.get_env(:pop_stash, :typesense)}) ++
    maybe_child(embeddings_enabled?, {Nx.Serving, serving: PopStash.Embeddings.serving(), name: PopStash.Embeddings, batch_timeout: 100}) ++
    maybe_child(typesense_enabled? and embeddings_enabled?, PopStash.Search.Indexer)

  Supervisor.start_link(children, strategy: :one_for_one, name: PopStash.Supervisor)
end

defp maybe_child(true, child), do: [child]
defp maybe_child(false, _child), do: []
```

**Note**: Indexer only starts when *both* Typesense and Embeddings are enabled.

**Boot behavior**: Requests to `embed/1` will queue and wait until model finishes loading (10-30s on cold start). The `ready?/0` function can be used for health checks.

---

## Step 7: Typesense Client Module

**File:** `lib/pop_stash/search/typesense.ex`

```elixir
defmodule PopStash.Search.Typesense do
  @moduledoc """
  Typesense client for indexing and searching stashes/insights/decisions.
  Uses TypesenseEx for communication with Typesense server.
  """

  require Logger
  alias TypesenseEx.Collections
  alias TypesenseEx.Documents

  @stashes_schema %{
    name: "stashes",
    fields: [
      %{name: "id", type: "string"},
      %{name: "project_id", type: "string", facet: true},
      %{name: "name", type: "string"},
      %{name: "summary", type: "string"},
      %{name: "embedding", type: "float[]", num_dim: 384},
      %{name: "created_at", type: "int64"}
    ]
  }

  @insights_schema %{
    name: "insights",
    fields: [
      %{name: "id", type: "string"},
      %{name: "project_id", type: "string", facet: true},
      %{name: "key", type: "string", optional: true},
      %{name: "content", type: "string"},
      %{name: "embedding", type: "float[]", num_dim: 384},
      %{name: "created_at", type: "int64"}
    ]
  }

  @decisions_schema %{
    name: "decisions",
    fields: [
      %{name: "id", type: "string"},
      %{name: "project_id", type: "string", facet: true},
      %{name: "topic", type: "string"},
      %{name: "decision", type: "string"},
      %{name: "reasoning", type: "string", optional: true},
      %{name: "embedding", type: "float[]", num_dim: 384},
      %{name: "created_at", type: "int64"}
    ]
  }

  ## Collection management

  def ensure_collections do
    with :ok <- ensure_collection(@stashes_schema),
         :ok <- ensure_collection(@insights_schema),
         :ok <- ensure_collection(@decisions_schema) do
      :ok
    end
  end

  defp ensure_collection(schema) do
    case Collections.create(schema) do
      {:ok, _} ->
        Logger.info("Created Typesense collection: #{schema.name}")
        :ok

      {:error, %{"message" => "A collection with name `" <> _}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to create collection #{schema.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def drop_collections do
    for collection <- ["stashes", "insights", "decisions"] do
      Collections.delete(collection)
    end

    :ok
  end

  ## Indexing

  def index_stash(stash, embedding \\ nil) do
    document = %{
      id: stash.id,
      project_id: stash.project_id,
      name: stash.name,
      summary: stash.summary || "",
      embedding: embedding || stash.embedding || List.duplicate(0.0, 384),
      created_at: DateTime.to_unix(stash.inserted_at)
    }

    index_document("stashes", document)
  end

  def index_insight(insight, embedding \\ nil) do
    document = %{
      id: insight.id,
      project_id: insight.project_id,
      key: insight.key,
      content: insight.content,
      embedding: embedding || insight.embedding || List.duplicate(0.0, 384),
      created_at: DateTime.to_unix(insight.inserted_at)
    }

    index_document("insights", document)
  end

  def index_decision(decision, embedding \\ nil) do
    document = %{
      id: decision.id,
      project_id: decision.project_id,
      topic: decision.topic,
      decision: decision.decision,
      reasoning: decision.reasoning,
      embedding: embedding || decision.embedding || List.duplicate(0.0, 384),
      created_at: DateTime.to_unix(decision.inserted_at)
    }

    index_document("decisions", document)
  end

  defp index_document(collection, document) do
    # Use upsert to handle both create and update events
    case Documents.upsert(collection, document) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_document(collection, id) do
    case Documents.delete(collection, id) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  ## Search

  def search_stashes(project_id, query, opts \\ []) do
    with {:ok, embedding} <- PopStash.Embeddings.embed(query) do
      hybrid_search("stashes", project_id, query, embedding, opts)
    end
  end

  def search_insights(project_id, query, opts \\ []) do
    with {:ok, embedding} <- PopStash.Embeddings.embed(query) do
      hybrid_search("insights", project_id, query, embedding, opts)
    end
  end

  def search_decisions(project_id, query, opts \\ []) do
    with {:ok, embedding} <- PopStash.Embeddings.embed(query) do
      hybrid_search("decisions", project_id, query, embedding, opts)
    end
  end

  def hybrid_search(collection, project_id, query, embedding, opts) do
    limit = Keyword.get(opts, :limit, 10)

    search_params = %{
      q: query,
      query_by: query_fields(collection),
      filter_by: "project_id:=#{project_id}",
      vector_query: "embedding:(#{format_vector(embedding)}, k:#{limit})",
      limit: limit,
      per_page: limit
    }

    case Documents.search(collection, search_params) do
      {:ok, %{"hits" => hits}} ->
        results = Enum.map(hits, &extract_document(&1, collection))
        {:ok, results}

      {:ok, %{"found" => 0}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_fields("stashes"), do: "name,summary"
  defp query_fields("insights"), do: "key,content"
  defp query_fields("decisions"), do: "topic,decision,reasoning"

  defp format_vector(embedding) when is_list(embedding) do
    "[" <> Enum.map_join(embedding, ",", &to_string/1) <> "]"
  end

  defp extract_document(%{"document" => doc}, collection) do
    base = %{id: doc["id"], inserted_at: DateTime.from_unix!(doc["created_at"])}

    case collection do
      "stashes" -> Map.merge(base, %{name: doc["name"], summary: doc["summary"]})
      "insights" -> Map.merge(base, %{key: doc["key"], content: doc["content"]})
      "decisions" -> Map.merge(base, %{topic: doc["topic"], decision: doc["decision"]})
    end
  end
end
```

---

## Step 8: Search Indexer (PubSub-driven)

**File:** `lib/pop_stash/search/indexer.ex`

Subscribes to Memory events via PubSub. Decoupled from Memory context.

```elixir
defmodule PopStash.Search.Indexer do
  @moduledoc """
  Subscribes to Memory events and handles async embedding + Typesense indexing.
  Decoupled from Memory context via PubSub.
  """
  use GenServer
  require Logger

  alias PopStash.Embeddings
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    # Ensure Typesense collections exist (non-blocking, retry later if down)
    case Typesense.ensure_collections() do
      :ok ->
        {:ok, %{collections_ready: true}}
      {:error, reason} ->
        Logger.warning("Typesense not available at boot: #{inspect(reason)}. Will retry on first index.")
        {:ok, %{collections_ready: false}}
    end
  end

  # Handle PubSub events
  @impl true
  def handle_info({:stash_created, stash}, state) do
    index_async(stash, &index_stash/1)
    {:noreply, state}
  end

  def handle_info({:stash_updated, stash}, state) do
    index_async(stash, &index_stash/1)
    {:noreply, state}
  end

  def handle_info({:insight_created, insight}, state) do
    index_async(insight, &index_insight/1)
    {:noreply, state}
  end

  def handle_info({:insight_updated, insight}, state) do
    index_async(insight, &index_insight/1)
    {:noreply, state}
  end

  def handle_info({:decision_created, decision}, state) do
    index_async(decision, &index_decision/1)
    {:noreply, state}
  end

  def handle_info({:stash_deleted, stash_id}, state) do
    Typesense.delete_document("stashes", stash_id)
    {:noreply, state}
  end

  def handle_info({:insight_deleted, insight_id}, state) do
    Typesense.delete_document("insights", insight_id)
    {:noreply, state}
  end

  def handle_info({:decision_deleted, decision_id}, state) do
    Typesense.delete_document("decisions", decision_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private

  defp index_async(entity, index_fn) do
    Task.Supervisor.start_child(PopStash.TaskSupervisor, fn ->
      # Ensure collections exist (handles Typesense being down at boot)
      Typesense.ensure_collections()
      index_fn.(entity)
    end)
  end

  defp index_stash(stash) do
    text = "#{stash.name} #{stash.summary || ""}"

    with {:ok, embedding} <- Embeddings.embed(text),
         :ok <- update_embedding(stash, embedding),
         :ok <- Typesense.index_stash(stash, embedding) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to index stash #{stash.id}: #{inspect(reason)}")
        :error
    end
  end

  defp index_insight(insight) do
    text = "#{insight.key || ""} #{insight.content}"

    with {:ok, embedding} <- Embeddings.embed(text),
         :ok <- update_embedding(insight, embedding),
         :ok <- Typesense.index_insight(insight, embedding) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to index insight #{insight.id}: #{inspect(reason)}")
        :error
    end
  end

  defp index_decision(decision) do
    text = "#{decision.topic} #{decision.decision} #{decision.reasoning || ""}"

    with {:ok, embedding} <- Embeddings.embed(text),
         :ok <- update_embedding(decision, embedding),
         :ok <- Typesense.index_decision(decision, embedding) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to index decision #{decision.id}: #{inspect(reason)}")
        :error
    end
  end

  defp update_embedding(entity, embedding) do
    # Update pgvector column in Postgres
    entity
    |> Ecto.Changeset.change(embedding: embedding)
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
```

---

## Step 9: Update Memory Context

**File:** `lib/pop_stash/memory.ex`

Add PubSub broadcasts after create/update/delete. No direct Search dependency.

```elixir
# Add to create_stash/5
def create_stash(project_id, agent_id, name, summary, opts \\ []) do
  # ... existing changeset code ...
  case Repo.insert(changeset) do
    {:ok, stash} ->
      broadcast(:stash_created, stash)
      {:ok, stash}

    error ->
      error
  end
end

# Add to update_stash/2 (create this function if it doesn't exist)
def update_stash(stash, attrs) do
  stash
  |> cast(attrs, [:name, :summary, :files, :metadata, :expires_at])
  |> validate_required([:name, :summary])
  |> validate_length(:name, min: 1, max: 255)
  |> case do
    %{valid?: true} = changeset ->
      case Repo.update(changeset) do
        {:ok, stash} ->
          broadcast(:stash_updated, stash)
          {:ok, stash}

        error ->
          error
      end

    changeset ->
      {:error, changeset}
  end
end

# Update delete_stash/1
def delete_stash(stash_id) when is_binary(stash_id) do
  case Repo.get(Stash, stash_id) do
    nil ->
      {:error, :not_found}

    stash ->
      case Repo.delete(stash) do
        {:ok, _} ->
          broadcast(:stash_deleted, stash.id)
          :ok

        error ->
          error
      end
  end
end

# Update create_insight/4
def create_insight(project_id, agent_id, content, opts \\ []) do
  # ... existing changeset code ...
  case Repo.insert(changeset) do
    {:ok, insight} ->
      broadcast(:insight_created, insight)
      {:ok, insight}

    error ->
      error
  end
end

# Update update_insight/2
def update_insight(insight_id, content) when is_binary(insight_id) and is_binary(content) do
  case Repo.get(Insight, insight_id) do
    nil ->
      {:error, :not_found}

    insight ->
      insight
      |> cast(%{content: content}, [:content])
      |> validate_required([:content])
      |> case do
        %{valid?: true} = changeset ->
          case Repo.update(changeset) do
            {:ok, insight} ->
              broadcast(:insight_updated, insight)
              {:ok, insight}

            error ->
              error
          end

        changeset ->
          {:error, changeset}
      end
  end
end

# Update delete_insight/1
def delete_insight(insight_id) when is_binary(insight_id) do
  case Repo.get(Insight, insight_id) do
    nil ->
      {:error, :not_found}

    insight ->
      case Repo.delete(insight) do
        {:ok, _} ->
          broadcast(:insight_deleted, insight.id)
          :ok

        error ->
          error
      end
  end
end

# Update create_decision/5
def create_decision(project_id, agent_id, topic, decision, opts \\ []) do
  # ... existing changeset code ...
  case Repo.insert(changeset) do
    {:ok, decision} ->
      broadcast(:decision_created, decision)
      {:ok, decision}

    error ->
      error
  end
end

# Update delete_decision/1
def delete_decision(decision_id) when is_binary(decision_id) do
  case Repo.get(Decision, decision_id) do
    nil ->
      {:error, :not_found}

    decision ->
      case Repo.delete(decision) do
        {:ok, _} ->
          broadcast(:decision_deleted, decision.id)
          :ok

        error ->
          error
      end
  end
end

# Add broadcast helper
defp broadcast(event, payload) do
  Phoenix.PubSub.broadcast(PopStash.PubSub, "memory:events", {event, payload})
end

# Add new search functions (delegate to Typesense)
def search_stashes(project_id, query, opts \\ []) do
  PopStash.Search.Typesense.search_stashes(project_id, query, opts)
end

def search_insights(project_id, query, opts \\ []) do
  PopStash.Search.Typesense.search_insights(project_id, query, opts)
end

def search_decisions(project_id, query, opts \\ []) do
  PopStash.Search.Typesense.search_decisions(project_id, query, opts)
end
```

---

## Step 10: Upgrade recall Tool

**File:** `lib/pop_stash/mcp/tools/recall.ex`

Current behavior: exact key match, single result or error.

New behavior:
1. Try exact key match first
2. If no exact match, do semantic search with query embedding
3. Always return list of results (ranked by relevance)

```elixir
defmodule PopStash.MCP.Tools.Recall do
  @moduledoc """
  MCP tool for retrieving insights by exact key or semantic search.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "recall",
        description: """
        Retrieve insights by key (exact match) or semantic search.
        Returns a ranked list of matching insights.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            key: %{
              type: "string",
              description: "Insight key or search query"
            },
            limit: %{
              type: "number",
              description: "Maximum results to return (default: 5)",
              default: 5
            }
          },
          required: ["key"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"key" => query} = params, %{project_id: project_id}) do
    limit = Map.get(params, "limit", 5)

    # Try exact match first
    case Memory.get_insight_by_key(project_id, query) do
      {:ok, insight} ->
        {:ok, %{results: [format_insight(insight)], match_type: "exact"}}

      {:error, :not_found} ->
        # Fall back to semantic search
        case Memory.search_insights(project_id, query, limit: limit) do
          {:ok, []} ->
            recent = Memory.list_insights(project_id, limit: 5)
            hint = build_hint(recent)
            {:ok, %{results: [], message: "No insights found matching '#{query}'. #{hint}"}}

          {:ok, results} ->
            {:ok, %{results: Enum.map(results, &format_insight/1), match_type: "semantic"}}

          {:error, :embeddings_disabled} ->
            # Graceful degradation
            {:error, "Semantic search unavailable. Use exact key match."}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
    end
  end

  defp format_insight(insight) do
    %{
      id: insight.id,
      key: insight.key,
      content: insight.content,
      created_at: insight.inserted_at
    }
  end

  defp build_hint([]), do: "No insights yet."

  defp build_hint(recent) do
    keys =
      recent
      |> Enum.filter(& &1.key)
      |> Enum.map_join(", ", & &1.key)

    if keys == "", do: "No keyed insights.", else: "Recent keys: #{keys}"
  end
end
```

---

## Step 11: Upgrade pop Tool

**File:** `lib/pop_stash/mcp/tools/pop.ex`

Same pattern as recall:
1. Try exact name match
2. Semantic fallback
3. Return list of results

```elixir
defmodule PopStash.MCP.Tools.Pop do
  @moduledoc """
  MCP tool for retrieving stashes by exact name or semantic search.
  """

  @behaviour PopStash.MCP.ToolBehaviour

  alias PopStash.Memory

  @impl true
  def tools do
    [
      %{
        name: "pop",
        description: """
        Retrieve stashes by name (exact match) or semantic search.
        Returns a ranked list of matching stashes.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "Stash name or search query"
            },
            limit: %{
              type: "number",
              description: "Maximum results to return (default: 5)",
              default: 5
            }
          },
          required: ["name"]
        },
        callback: &__MODULE__.execute/2
      }
    ]
  end

  def execute(%{"name" => query} = params, %{project_id: project_id}) do
    limit = Map.get(params, "limit", 5)

    # Try exact match first
    case Memory.get_stash_by_name(project_id, query) do
      {:ok, stash} ->
        {:ok, %{results: [format_stash(stash)], match_type: "exact"}}

      {:error, :not_found} ->
        # Fall back to semantic search
        case Memory.search_stashes(project_id, query, limit: limit) do
          {:ok, []} ->
            recent = Memory.list_stashes(project_id) |> Enum.take(5)
            hint = build_hint(recent)
            {:ok, %{results: [], message: "No stashes found matching '#{query}'. #{hint}"}}

          {:ok, results} ->
            {:ok, %{results: Enum.map(results, &format_stash/1), match_type: "semantic"}}

          {:error, :embeddings_disabled} ->
            {:error, "Semantic search unavailable. Use exact name match."}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
    end
  end

  defp format_stash(stash) do
    %{
      id: stash.id,
      name: stash.name,
      summary: stash.summary,
      files: stash.files || [],
      created_at: stash.inserted_at
    }
  end

  defp build_hint([]), do: "No stashes yet."

  defp build_hint(recent) do
    "Recent stashes: " <> Enum.map_join(recent, ", ", & &1.name)
  end
end
```

---

## Step 12: Testing Strategy

**Unit Tests:**

- `test/pop_stash/embeddings_test.exs` - Test enabled/disabled behavior, mock Nx.Serving
- `test/pop_stash/search/typesense_test.exs` - Mock ExTypesense functions
- `test/pop_stash/search/indexer_test.exs` - Test PubSub subscription and async indexing

**Integration Tests:**

- `test/pop_stash/search/integration_test.exs` - Full flow with real Typesense (tagged @moduletag :integration)
- Update `test/pop_stash/mcp/tools/recall_test.exs` - Test new list-based response
- Update `test/pop_stash/mcp/tools/pop_test.exs` - Test new list-based response

**Mocking Approach:**

Use Mimic (already in deps) to mock:
- `PopStash.Embeddings.embed/1` - return fake vectors
- `TypesenseEx.Collections` and `TypesenseEx.Documents` functions - return canned search results

**Test Configuration:**

Ensure embeddings and Typesense are disabled in test environment to prevent loading models during test suite:

```elixir
# config/test.exs
config :pop_stash, PopStash.Embeddings, enabled: false
config :pop_stash, PopStash.Search.Typesense, enabled: false
```

---

## Step 13: Error Handling & Graceful Degradation

**When embeddings unavailable:**
- Index documents without embedding field (zeros as placeholder)
- Search falls back to text-only Typesense search
- Tools return helpful error message

**When Typesense unavailable:**
- Create/update operations still succeed (database is source of truth)
- PubSub events are emitted but indexing tasks fail silently with logs
- Search returns `{:error, :search_unavailable}`
- Tools return: "Semantic search temporarily unavailable, use exact key/name"

**Error Recovery:**
- Indexer logs warnings but doesn't crash
- Failed indexing tasks don't affect Memory operations
- Reindex mix task can recover from any state

---

## Step 14: Reindex Mix Task

**File:** `lib/mix/tasks/pop_stash.reindex_search.ex`

Rebuilds Typesense index from Postgres (source of truth). Uses pgvector embeddings when available, regenerates missing ones.

```elixir
defmodule Mix.Tasks.PopStash.ReindexSearch do
  @moduledoc """
  Rebuilds Typesense search index from database.

  ## Usage

      # Reindex all collections
      mix pop_stash.reindex_search

      # Reindex specific collection
      mix pop_stash.reindex_search stashes

      # Regenerate all embeddings
      mix pop_stash.reindex_search --regenerate-embeddings

      # Reindex specific collection and regenerate embeddings
      mix pop_stash.reindex_search insights --regenerate-embeddings

  ## Options

    * `--regenerate-embeddings` - Regenerate embeddings even if they exist
  """
  use Mix.Task

  alias PopStash.Embeddings
  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.Stash
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  import Ecto.Query

  @shortdoc "Rebuild Typesense search index from database"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, collections, _} =
      OptionParser.parse(args,
        switches: [regenerate_embeddings: :boolean]
      )

    collections = if collections === [], do: ~w(stashes insights decisions), else: collections

    Mix.shell().info("Starting reindex...")
    Typesense.ensure_collections()

    collections
    |> Task.async_stream(&reindex_collection(&1, opts), timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Reindex complete.")
  end

  defp reindex_collection("stashes", opts) do
    Mix.shell().info("Reindexing stashes...")

    Stash
    |> Repo.all()
    |> Task.async_stream(&index_stash(&1, opts), max_concurrency: 10, timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Stashes reindexed.")
  end

  defp reindex_collection("insights", opts) do
    Mix.shell().info("Reindexing insights...")

    Insight
    |> Repo.all()
    |> Task.async_stream(&index_insight(&1, opts), max_concurrency: 10, timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Insights reindexed.")
  end

  defp reindex_collection("decisions", opts) do
    Mix.shell().info("Reindexing decisions...")

    Decision
    |> Repo.all()
    |> Task.async_stream(&index_decision(&1, opts), max_concurrency: 10, timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Decisions reindexed.")
  end

  defp index_stash(stash, opts) do
    embedding =
      get_or_generate_embedding(stash, opts, fn s ->
        "#{s.name} #{s.summary || ""}"
      end)

    Typesense.index_stash(stash, embedding)
  end

  defp index_insight(insight, opts) do
    embedding =
      get_or_generate_embedding(insight, opts, fn i ->
        "#{i.key || ""} #{i.content}"
      end)

    Typesense.index_insight(insight, embedding)
  end

  defp index_decision(decision, opts) do
    embedding =
      get_or_generate_embedding(decision, opts, fn d ->
        "#{d.topic} #{d.decision} #{d.reasoning || ""}"
      end)

    Typesense.index_decision(decision, embedding)
  end

  defp get_or_generate_embedding(entity, opts, text_fn) do
    cond do
      opts[:regenerate_embeddings] ->
        generate_and_save_embedding(entity, text_fn)

      entity.embedding != nil ->
        entity.embedding

      true ->
        generate_and_save_embedding(entity, text_fn)
    end
  end

  defp generate_and_save_embedding(entity, text_fn) do
    {:ok, embedding} = Embeddings.embed(text_fn.(entity))
    save_embedding(entity, embedding)
    embedding
  end

  defp save_embedding(entity, embedding) do
    entity
    |> Ecto.Changeset.change(embedding: embedding)
    |> Repo.update!()
  end
end
```

---

## Files to Create

1. `lib/pop_stash/embeddings.ex` - Nx.Serving builder + embed/1 helper
2. `lib/pop_stash/search/typesense.ex` - Typesense client
3. `lib/pop_stash/search/indexer.ex` - PubSub subscriber, async indexing
4. `lib/mix/tasks/pop_stash.reindex_search.ex` - Reindex mix task
5. `priv/repo/migrations/TIMESTAMP_add_embedding_columns.exs`
6. `config/runtime.exs` (if doesn't exist)
7. `test/pop_stash/embeddings_test.exs`
8. `test/pop_stash/search/typesense_test.exs`
9. `test/pop_stash/search/indexer_test.exs`
10. `test/pop_stash/search/integration_test.exs`

## Files to Modify

1. `mix.exs` - Add dependencies
2. `docker-compose.yml` - Add Typesense service
3. `config/config.exs` - Add Typesense and Embeddings config
4. `config/test.exs` - Disable embeddings/Typesense in tests
5. `lib/pop_stash/application.ex` - Add PubSub, TaskSupervisor, Nx.Serving, and Indexer to supervision tree
6. `lib/pop_stash/memory/stash.ex` - Add embedding field
7. `lib/pop_stash/memory/insight.ex` - Add embedding field
8. `lib/pop_stash/memory/decision.ex` - Add embedding field
9. `lib/pop_stash/memory.ex` - Add PubSub broadcasts, add search functions, add update_stash/2
10. `lib/pop_stash/mcp/tools/recall.ex` - Hybrid search, return list
11. `lib/pop_stash/mcp/tools/pop.ex` - Hybrid search, return list
12. `test/pop_stash/mcp/tools/recall_test.exs` - Update for new response format
13. `test/pop_stash/mcp/tools/pop_test.exs` - Update for new response format

---

## Implementation Order

1. **Infrastructure**: Dependencies, Docker, config
2. **PubSub**: Add Phoenix.PubSub to supervision tree
3. **Database**: Migration for vector columns, update schemas
4. **Embeddings**: Nx.Serving module with serving/0 and embed/1, add to supervision tree
5. **Typesense**: Client module, collection schemas
6. **Indexer**: PubSub subscriber GenServer, add to supervision tree
7. **Memory context**: Add PubSub broadcasts on create/update/delete, add search functions
8. **Tools**: Upgrade recall and pop
9. **Reindex task**: Mix task for rebuilding index from Postgres
10. **Tests**: Unit and integration tests
11. **Manual testing**: Verify with Claude Code workflow

---

## Performance Considerations

**Embedding Generation:**
- Initial model load: 10-30s on CPU (one-time at startup)
- Per-embedding latency: ~10-50ms depending on batch size
- Batch processing: Nx.Serving automatically batches concurrent requests

**Typesense:**
- Sub-100ms query latency for hybrid search
- HNSW indexes provide efficient vector similarity search
- Text search uses BM25 ranking

**Scaling:**
- Task.Supervisor limits concurrency to 50 background indexing tasks
- Failed indexing tasks don't block Memory operations
- Postgres is always the source of truth for recovery

---

## Security Considerations

1. **API Keys**: Use environment variables in production, never commit keys
2. **Port Binding**: Typesense bound to localhost only (127.0.0.1:8108)
3. **Project Isolation**: All search queries filter by `project_id`
4. **Input Validation**: Query strings sanitized by Typesense client
5. **Resource Limits**: Task.Supervisor prevents unbounded concurrent tasks

---

## Success Criteria

Phase 4 is complete when all of the following pass:

### Automated

- [ ] `mix test` — all tests pass
- [ ] `mix lint` — no lint errors (credo, dialyzer if configured)

### Manual Verification

Agent should manually verify the full indexing and search flow:

1. **Start services**: `docker compose up -d` (Typesense running)
2. **Start app**: `iex -S mix` with embeddings and Typesense enabled
3. **Create test data**:
   ```elixir
   {:ok, stash} = PopStash.Memory.create_stash(project_id, agent_id, "auth-flow", "User authentication implementation with JWT tokens")
   {:ok, insight} = PopStash.Memory.create_insight(project_id, agent_id, "Always validate JWT expiration before trusting claims", key: "jwt-validation")
   ```
4. **Wait for async indexing** (~1-2 seconds for embedding generation)
5. **Verify semantic search works**:
   ```elixir
   # Should find "auth-flow" stash even with different wording
   {:ok, results} = PopStash.Memory.search_stashes(project_id, "login system")
   assert length(results) > 0
   assert hd(results).name == "auth-flow"

   # Should find "jwt-validation" insight
   {:ok, results} = PopStash.Memory.search_insights(project_id, "token security")
   assert length(results) > 0
   ```
6. **Verify exact match still works**:
   ```elixir
   {:ok, insight} = PopStash.Memory.get_insight_by_key(project_id, "jwt-validation")
   ```
7. **Verify reindex task**:
   ```bash
   mix pop_stash.reindex_search
   ```
8. **Verify graceful degradation**: Stop Typesense, confirm Memory operations still succeed
