defmodule PopStash.Memory do
  @moduledoc """
  Context for memory operations: stashes and insights.

  Handles saving and retrieving agent context across sessions.
  Phase 2 uses exact matching; Phase 4 adds semantic search.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Memory.Stash
  alias PopStash.Repo

  ## Stashes

  @doc """
  Creates a stash.

  ## Options
    * `:files` - List of file paths
    * `:metadata` - Optional metadata map
    * `:expires_at` - Optional expiration datetime
  """
  def create_stash(project_id, agent_id, name, summary, opts \\ []) do
    %Stash{}
    |> cast(
      %{
        project_id: project_id,
        created_by: agent_id,
        name: name,
        summary: summary,
        files: Keyword.get(opts, :files, []),
        metadata: Keyword.get(opts, :metadata, %{}),
        expires_at: Keyword.get(opts, :expires_at)
      },
      [:project_id, :created_by, :name, :summary, :files, :metadata, :expires_at]
    )
    |> validate_required([:project_id, :name, :summary])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by)
    |> Repo.insert()
  end

  @doc """
  Retrieves a stash by exact name match within a project.
  """
  def get_stash_by_name(project_id, name) when is_binary(project_id) and is_binary(name) do
    Stash
    |> where([s], s.project_id == ^project_id and s.name == ^name)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Lists all non-expired stashes for a project.
  """
  def list_stashes(project_id) when is_binary(project_id) do
    Stash
    |> where([s], s.project_id == ^project_id)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
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

  ## Insights

  @doc """
  Creates an insight.

  ## Options
    * `:key` - Optional semantic key for exact retrieval
    * `:metadata` - Optional metadata map
  """
  def create_insight(project_id, agent_id, content, opts \\ []) do
    %Insight{}
    |> cast(
      %{
        project_id: project_id,
        created_by: agent_id,
        content: content,
        key: Keyword.get(opts, :key),
        metadata: Keyword.get(opts, :metadata, %{})
      },
      [:project_id, :created_by, :content, :key, :metadata]
    )
    |> validate_required([:project_id, :content])
    |> validate_length(:key, max: 255)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by)
    |> Repo.insert()
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

  ## Helpers

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}
end
