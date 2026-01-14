defmodule PopStash.Memory do
  @moduledoc """
  Context for memory operations: stashes and insights.

  Handles saving and retrieving context across sessions.
  Supports both exact matching and semantic search via Typesense.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Memory.Context
  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.SearchLog
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  ## Contexts

  @doc """
  Creates a context.

  ## Options
    * `:files` - List of file paths
    * `:tags` - Optional list of tags
    * `:expires_at` - Optional expiration datetime
  """
  def create_context(project_id, name, summary, opts \\ []) do
    %Context{}
    |> cast(
      %{
        project_id: project_id,
        name: name,
        summary: summary,
        files: Keyword.get(opts, :files, []),
        tags: Keyword.get(opts, :tags, []),
        expires_at: Keyword.get(opts, :expires_at)
      },
      [:project_id, :name, :summary, :files, :tags, :expires_at]
    )
    |> validate_required([:project_id, :name, :summary])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:context_created, &1))
  end

  @doc """
  Updates a context.
  """
  def update_context(context, attrs) do
    context
    |> cast(attrs, [:name, :summary, :files, :tags, :expires_at])
    |> validate_required([:name, :summary])
    |> validate_length(:name, min: 1, max: 255)
    |> Repo.update()
    |> tap_ok(&broadcast(:context_updated, &1))
  end

  @doc """
  Retrieves a context by exact name match within a project.
  """
  def get_context_by_name(project_id, name) when is_binary(project_id) and is_binary(name) do
    Context
    |> where([s], s.project_id == ^project_id and s.name == ^name)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Lists all non-expired contexts for a project.
  """
  def list_contexts(project_id) when is_binary(project_id) do
    Context
    |> where([s], s.project_id == ^project_id)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes a context by ID.
  """
  def delete_context(context_id) when is_binary(context_id) do
    case Repo.get(Context, context_id) do
      nil ->
        {:error, :not_found}

      context ->
        case Repo.delete(context) do
          {:ok, _} ->
            broadcast(:context_deleted, context.id)
            :ok

          error ->
            error
        end
    end
  end

  ## Insights

  @doc """
  Creates an insight.

  ## Options
    * `:key` - Optional semantic key for exact retrieval
    * `:tags` - Optional list of tags
  """
  def create_insight(project_id, content, opts \\ []) do
    %Insight{}
    |> cast(
      %{
        project_id: project_id,
        content: content,
        key: Keyword.get(opts, :key),
        tags: Keyword.get(opts, :tags, [])
      },
      [:project_id, :content, :key, :tags]
    )
    |> validate_required([:project_id, :content])
    |> validate_length(:key, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:insight_created, &1))
  end

  @doc """
  Retrieves an insight by exact key match.
  """
  def get_insight_by_key(project_id, key) when is_binary(project_id) and is_binary(key) do
    Insight
    |> where([i], i.project_id == ^project_id and i.key == ^key)
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Lists all insights for a project, ordered by most recent.
  """
  def list_insights(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Insight
    |> where([i], i.project_id == ^project_id)
    |> order_by(desc: :updated_at)
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
        |> cast(%{content: content}, [:content])
        |> validate_required([:content])
        |> Repo.update()
        |> tap_ok(&broadcast(:insight_updated, &1))
    end
  end

  @doc """
  Deletes an insight by ID.
  """
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

  ## Decisions

  @doc """
  Creates an immutable decision record.

  Topics are automatically normalized (lowercased, trimmed) for consistent matching.

  ## Options
    * `:reasoning` - Why this decision was made (optional)
    * `:tags` - Optional list of tags
  """
  def create_decision(project_id, topic, decision, opts \\ []) do
    %Decision{}
    |> cast(
      %{
        project_id: project_id,
        topic: Decision.normalize_topic(topic),
        decision: decision,
        reasoning: Keyword.get(opts, :reasoning),
        tags: Keyword.get(opts, :tags, [])
      },
      [:project_id, :topic, :decision, :reasoning, :tags]
    )
    |> validate_required([:project_id, :topic, :decision])
    |> validate_length(:topic, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:decision_created, &1))
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

  ## Search

  @doc """
  Search contexts by semantic similarity.
  Returns ranked list of matching contexts.
  """
  def search_contexts(project_id, query, opts \\ []) do
    Typesense.search_contexts(project_id, query, opts)
  end

  @doc """
  Search insights by semantic similarity.
  Returns ranked list of matching insights.
  """
  def search_insights(project_id, query, opts \\ []) do
    Typesense.search_insights(project_id, query, opts)
  end

  @doc """
  Search decisions by semantic similarity.
  Returns ranked list of matching decisions.
  """
  def search_decisions(project_id, query, opts \\ []) do
    Typesense.search_decisions(project_id, query, opts)
  end

  ## Search Logging

  @doc false
  def log_search(project_id, query, collection, search_type, opts \\ []) do
    Task.start(fn ->
      result =
        %SearchLog{}
        |> cast(
          %{
            project_id: project_id,
            query: query,
            collection: to_string(collection),
            search_type: to_string(search_type),
            tool: Keyword.get(opts, :tool),
            result_count: Keyword.get(opts, :result_count, 0),
            found: Keyword.get(opts, :found, false),
            duration_ms: Keyword.get(opts, :duration_ms)
          },
          [
            :project_id,
            :query,
            :collection,
            :search_type,
            :tool,
            :result_count,
            :found,
            :duration_ms
          ]
        )
        |> validate_required([:project_id, :query, :collection, :search_type])
        |> Repo.insert()

      case result do
        {:ok, search_log} -> broadcast(:search_logged, search_log)
        _ -> :ok
      end
    end)

    :ok
  end

  @doc """
  Lists recent search logs for a project.

  ## Options
    * `:limit` - Maximum items to return (default: 20)
  """
  def list_search_logs(project_id, opts \\ []) when is_binary(project_id) do
    limit = Keyword.get(opts, :limit, 20)

    SearchLog
    |> where([s], s.project_id == ^project_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  @doc """
  Counts total searches for a project.
  """
  def count_searches(project_id) when is_binary(project_id) do
    SearchLog
    |> where([s], s.project_id == ^project_id)
    |> Repo.aggregate(:count, :id)
  end

  ## Helpers

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(PopStash.PubSub, "memory:events", {event, payload})
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(error, _fun), do: error
end
