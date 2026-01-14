defmodule PopStash.Memory do
  @moduledoc """
  Context for memory operations: contexts, insights, decisions, and plans.

  Handles saving and retrieving memory data across sessions.
  Supports both exact matching and semantic search via Typesense.

  ## Memory Types

  - **Contexts** - Temporary working context for tasks (formerly stashes)
  - **Insights** - Persistent knowledge about the codebase
  - **Decisions** - Immutable architectural decisions with history
  - **Plans** - Versioned project documentation and roadmaps
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Memory.Context
  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.Plan
  alias PopStash.Memory.SearchLog
  alias PopStash.Memory.Thread
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  ## Contexts

  @doc """
  Creates a context.

  ## Options
    * `:files` - List of file paths
    * `:tags` - Optional list of tags
    * `:thread_id` - Optional thread ID to connect revisions (auto-generated if omitted)
    * `:expires_at` - Optional expiration datetime
  """
  def create_context(project_id, title, body, opts \\ []) do
    thread_id = Keyword.get(opts, :thread_id) || Thread.generate(Context.thread_prefix())

    %Context{}
    |> cast(
      %{
        project_id: project_id,
        title: title,
        body: body,
        files: Keyword.get(opts, :files, []),
        tags: Keyword.get(opts, :tags, []),
        thread_id: thread_id,
        expires_at: Keyword.get(opts, :expires_at)
      },
      [:project_id, :title, :body, :files, :tags, :thread_id, :expires_at]
    )
    |> validate_required([:project_id, :title, :body, :thread_id])
    |> validate_length(:title, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:context_created, &1))
  end

  @doc """
  Updates a context.
  """
  def update_context(context, attrs) do
    context
    |> cast(attrs, [:title, :body, :files, :tags, :expires_at])
    |> validate_required([:title, :body])
    |> validate_length(:title, min: 1, max: 255)
    |> Repo.update()
    |> tap_ok(&broadcast(:context_updated, &1))
  end

  @doc """
  Retrieves a context by exact title match within a project.
  """
  def get_context_by_title(project_id, title) when is_binary(project_id) and is_binary(title) do
    Context
    |> where([s], s.project_id == ^project_id and s.title == ^title)
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

  ## Plans

  @doc """
  Creates a plan with a title and body content.

  Plans use threads for versioning - pass the same thread_id to create
  new revisions of an existing plan.

  ## Options
    * `:tags` - Optional list of tags
    * `:thread_id` - Optional thread ID to connect revisions (auto-generated if omitted)
  """
  def create_plan(project_id, title, body, opts \\ []) do
    thread_id = Keyword.get(opts, :thread_id) || Thread.generate(Plan.thread_prefix())

    %Plan{}
    |> cast(
      %{
        project_id: project_id,
        title: title,
        body: body,
        tags: Keyword.get(opts, :tags, []),
        thread_id: thread_id
      },
      [:project_id, :title, :body, :tags, :thread_id]
    )
    |> validate_required([:project_id, :title, :body, :thread_id])
    |> validate_length(:title, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
    |> tap_ok(&broadcast(:plan_created, &1))
  end

  @doc """
  Gets the latest plan by title.
  Returns the most recent revision based on inserted_at.
  """
  def get_plan(project_id, title) when is_binary(project_id) and is_binary(title) do
    Plan
    |> where([p], p.project_id == ^project_id and p.title == ^title)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Gets a plan by its thread_id.
  Returns the most recent revision in that thread.
  """
  def get_plan_by_thread(project_id, thread_id)
      when is_binary(project_id) and is_binary(thread_id) do
    Plan
    |> where([p], p.project_id == ^project_id and p.thread_id == ^thread_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Lists all plans for a project.

  ## Options
    * `:limit` - Maximum number of plans to return (default: 50)
    * `:title` - Filter by title (exact match)
  """
  def list_plans(project_id, opts \\ []) when is_binary(project_id) do
    limit = Keyword.get(opts, :limit, 50)
    title = Keyword.get(opts, :title)

    Plan
    |> where([p], p.project_id == ^project_id)
    |> maybe_filter_plan_title(title)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_plan_title(query, nil), do: query

  defp maybe_filter_plan_title(query, title) do
    where(query, [p], p.title == ^title)
  end

  @doc """
  Lists all revisions of a plan by title.
  Returns most recent revision first.
  """
  def list_plan_revisions(project_id, title) when is_binary(project_id) and is_binary(title) do
    Plan
    |> where([p], p.project_id == ^project_id and p.title == ^title)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all revisions in a thread.
  Returns most recent revision first.
  """
  def list_plan_thread(project_id, thread_id)
      when is_binary(project_id) and is_binary(thread_id) do
    Plan
    |> where([p], p.project_id == ^project_id and p.thread_id == ^thread_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates the body content of a plan.
  """
  def update_plan(plan_id, body) when is_binary(plan_id) and is_binary(body) do
    case Repo.get(Plan, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        plan
        |> cast(%{body: body}, [:body])
        |> validate_required([:body])
        |> Repo.update()
        |> tap_ok(&broadcast(:plan_updated, &1))
    end
  end

  @doc """
  Deletes a plan by ID.
  """
  def delete_plan(plan_id) when is_binary(plan_id) do
    case Repo.get(Plan, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        case Repo.delete(plan) do
          {:ok, _} ->
            broadcast(:plan_deleted, plan.id)
            :ok

          error ->
            error
        end
    end
  end

  @doc """
  Lists all unique plan titles for a project.
  """
  def list_plan_titles(project_id) when is_binary(project_id) do
    Plan
    |> where([p], p.project_id == ^project_id)
    |> select([p], p.title)
    |> distinct(true)
    |> order_by(asc: :title)
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

  @doc """
  Search plans by semantic similarity.
  Returns ranked list of matching plans.
  """
  def search_plans(project_id, query, opts \\ []) do
    Typesense.search_plans(project_id, query, opts)
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
