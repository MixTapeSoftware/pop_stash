defmodule PopStash.Memory do
  @moduledoc """
  Context for memory operations: stashes and insights.

  Handles saving and retrieving agent context across sessions.
  Phase 2 uses exact matching; Phase 4 adds semantic search.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias PopStash.Repo
  alias PopStash.Memory.{Stash, Insight}

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

  ## Helpers

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}
end
