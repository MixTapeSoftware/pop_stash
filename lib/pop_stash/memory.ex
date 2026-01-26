defmodule PopStash.Memory do
  @moduledoc """
  Context for memory operations: insights and decisions.

  Handles saving and retrieving memory data across sessions.
  Supports both exact matching and semantic search via Typesense.

  ## Memory Types

  - **Insights** - Persistent knowledge about the codebase
  - **Decisions** - Immutable architectural decisions with history
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.SearchLog
  alias PopStash.Memory.Thread
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  ## Insights

  @doc """
  Creates an insight.

  ## Options
    * `:title` - Optional title for the insight
    * `:files` - Optional list of file paths
    * `:tags` - Optional list of tags
    * `:thread_id` - Optional thread ID to connect revisions (auto-generated if omitted)
  """
  def create_insight(project_id, body, opts \\ []) do
    thread_id = Keyword.get(opts, :thread_id) || Thread.generate(Insight.thread_prefix())

    %Insight{}
    |> cast(
      %{
        project_id: project_id,
        body: body,
        title: Keyword.get(opts, :title),
        files: Keyword.get(opts, :files, []),
        tags: Keyword.get(opts, :tags, []),
        thread_id: thread_id
      },
      [:project_id, :body, :title, :files, :tags, :thread_id]
    )
    |> validate_required([:project_id, :body, :thread_id])
    |> validate_length(:title, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:insight_created, &1))
  end

  @doc """
  Retrieves an insight by exact title match.
  """
  def get_insight_by_title(project_id, title) when is_binary(project_id) and is_binary(title) do
    Insight
    |> where([i], i.project_id == ^project_id and i.title == ^title)
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
  Updates an insight's body.
  """
  def update_insight(insight_id, body) when is_binary(insight_id) and is_binary(body) do
    case Repo.get(Insight, insight_id) do
      nil ->
        {:error, :not_found}

      insight ->
        insight
        |> cast(%{body: body}, [:body])
        |> validate_required([:body])
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

  Titles are automatically normalized (lowercased, trimmed) for consistent matching.

  ## Options
    * `:reasoning` - Why this decision was made (optional)
    * `:tags` - Optional list of tags
    * `:thread_id` - Optional thread ID to connect revisions (auto-generated if omitted)
  """
  def create_decision(project_id, title, body, opts \\ []) do
    thread_id = Keyword.get(opts, :thread_id) || Thread.generate(Decision.thread_prefix())

    %Decision{}
    |> cast(
      %{
        project_id: project_id,
        title: Decision.normalize_title(title),
        body: body,
        reasoning: Keyword.get(opts, :reasoning),
        tags: Keyword.get(opts, :tags, []),
        thread_id: thread_id
      },
      [:project_id, :title, :body, :reasoning, :tags, :thread_id]
    )
    |> validate_required([:project_id, :title, :body, :thread_id])
    |> validate_length(:title, min: 1, max: 255)
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
  Gets all decisions for a title within a project.
  Returns most recent first (full history for this title).

  Title is automatically normalized for matching.
  """
  def get_decisions_by_title(project_id, title) when is_binary(project_id) and is_binary(title) do
    normalized_title = Decision.normalize_title(title)

    Decision
    |> where([d], d.project_id == ^project_id and d.title == ^normalized_title)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists decisions for a project.

  ## Options
    * `:limit` - Maximum number of decisions to return (default: 50)
    * `:since` - Only return decisions after this datetime
    * `:title` - Filter by title (exact match after normalization)
  """
  def list_decisions(project_id, opts \\ []) when is_binary(project_id) do
    limit = Keyword.get(opts, :limit, 50)
    since = Keyword.get(opts, :since)
    title = Keyword.get(opts, :title)

    Decision
    |> where([d], d.project_id == ^project_id)
    |> maybe_filter_since(since)
    |> maybe_filter_title(title)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, since) do
    where(query, [d], d.inserted_at > ^since)
  end

  defp maybe_filter_title(query, nil), do: query

  defp maybe_filter_title(query, title) do
    normalized = Decision.normalize_title(title)
    where(query, [d], d.title == ^normalized)
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
  Lists all unique titles for a project.
  Useful for discovering what decisions exist.
  """
  def list_decision_titles(project_id) when is_binary(project_id) do
    Decision
    |> where([d], d.project_id == ^project_id)
    |> select([d], d.title)
    |> distinct(true)
    |> order_by(asc: :title)
    |> Repo.all()
  end

  ## Search

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
  Lists all recent search logs across all projects.

  ## Options
    * `:limit` - Maximum items to return (default: 50)
  """
  def list_all_search_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    SearchLog
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
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
