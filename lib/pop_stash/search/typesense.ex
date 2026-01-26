defmodule PopStash.Search.Typesense do
  @moduledoc """
  Typesense client for indexing and searching insights and decisions.
  Uses TypesenseEx for communication with Typesense server.
  """

  require Logger

  alias TypesenseEx.Collections
  alias TypesenseEx.Documents

  @insights_schema %{
    name: "insights",
    fields: [
      %{name: "id", type: "string"},
      %{name: "project_id", type: "string", facet: true},
      %{name: "title", type: "string", optional: true},
      %{name: "body", type: "string"},
      %{name: "embedding", type: "float[]", num_dim: 384},
      %{name: "created_at", type: "int64"}
    ]
  }

  @decisions_schema %{
    name: "decisions",
    fields: [
      %{name: "id", type: "string"},
      %{name: "project_id", type: "string", facet: true},
      %{name: "title", type: "string"},
      %{name: "body", type: "string"},
      %{name: "reasoning", type: "string", optional: true},
      %{name: "embedding", type: "float[]", num_dim: 384},
      %{name: "created_at", type: "int64"}
    ]
  }

  ## Collection management

  def ensure_collections do
    with :ok <- ensure_collection(@insights_schema) do
      ensure_collection(@decisions_schema)
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
    for collection <- ["insights", "decisions"] do
      Collections.delete(collection)
    end

    :ok
  end

  ## Indexing

  def index_insight(insight, embedding \\ nil) do
    document = %{
      id: insight.id,
      project_id: insight.project_id,
      title: insight.title,
      body: insight.body,
      embedding: embedding || insight.embedding || List.duplicate(0.0, 384),
      created_at: DateTime.to_unix(insight.inserted_at)
    }

    index_document("insights", document)
  end

  def index_decision(decision, embedding \\ nil) do
    document = %{
      id: decision.id,
      project_id: decision.project_id,
      title: decision.title,
      body: decision.body,
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

      {:ok, %{"message" => "Query string exceeds" <> _}} ->
        # Query string too long (vector search via GET), fall back to keyword search only
        search_params_no_vector = Map.delete(search_params, :vector_query)

        case Documents.search(collection, search_params_no_vector) do
          {:ok, %{"hits" => hits}} ->
            results = Enum.map(hits, &extract_document(&1, collection))
            {:ok, results}

          {:ok, %{"found" => 0}} ->
            {:ok, []}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_fields("insights"), do: "title,body"
  defp query_fields("decisions"), do: "title,body,reasoning"

  defp format_vector(embedding) when is_list(embedding) do
    "[" <> Enum.map_join(embedding, ",", &to_string/1) <> "]"
  end

  defp extract_document(%{"document" => doc}, collection) do
    base = %{id: doc["id"], inserted_at: DateTime.from_unix!(doc["created_at"])}

    case collection do
      "insights" ->
        Map.merge(base, %{title: doc["title"], body: doc["body"]})

      "decisions" ->
        Map.merge(base, %{title: doc["title"], body: doc["body"], reasoning: doc["reasoning"]})
    end
  end

  @doc """
  Check if Typesense is enabled in configuration.
  """
  def enabled? do
    config = Application.get_env(:pop_stash, :typesense, [])
    Keyword.get(config, :enabled, false)
  end
end
