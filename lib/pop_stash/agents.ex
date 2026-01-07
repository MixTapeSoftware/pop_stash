defmodule PopStash.Agents do
  @moduledoc """
  Context for managing agents (connected MCP clients).

  Agents are scoped to projects and represent active editor sessions.
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
    Agent
    |> Repo.get(id)
    |> wrap_result()
  end

  @doc """
  Lists all active agents for a project.
  """
  def list_active(project_id) when is_binary(project_id) do
    Agent
    |> where([a], a.project_id == ^project_id and a.status == "active")
    |> order_by(desc: :last_seen_at)
    |> Repo.all()
  end

  @doc """
  Lists all agents for a project (any status).
  """
  def list_all(project_id) when is_binary(project_id) do
    Agent
    |> where([a], a.project_id == ^project_id)
    |> order_by(desc: :last_seen_at)
    |> Repo.all()
  end

  ## Mutations

  @doc """
  Connects an agent to a project.

  ## Options
    * `:name` - Optional agent name
    * `:metadata` - Optional metadata map
  """
  def connect(project_id, opts \\ []) do
    now = DateTime.utc_now()

    %Agent{}
    |> cast(
      %{
        project_id: project_id,
        name: Keyword.get(opts, :name, "Agent #{DateTime.to_unix(now)}"),
        status: "active",
        connected_at: now,
        last_seen_at: now,
        metadata: Keyword.get(opts, :metadata, %{})
      },
      [:project_id, :name, :status, :connected_at, :last_seen_at, :metadata]
    )
    |> validate_required([:project_id, :status])
    |> validate_inclusion(:status, Agent.statuses())
    |> foreign_key_constraint(:project_id)
    |> Repo.insert()
  end

  @doc """
  Marks an agent as disconnected.
  """
  def disconnect(agent_id) when is_binary(agent_id) do
    with {:ok, agent} <- get(agent_id) do
      agent
      |> cast(%{status: "disconnected"}, [:status])
      |> Repo.update()
    end
  end

  @doc """
  Updates agent heartbeat (last_seen_at).
  """
  def heartbeat(agent_id) when is_binary(agent_id) do
    with {:ok, agent} <- get(agent_id) do
      agent
      |> cast(%{last_seen_at: DateTime.utc_now()}, [:last_seen_at])
      |> Repo.update()
    end
  end

  @doc """
  Updates agent's current task.
  """
  def update_task(agent_id, task) when is_binary(agent_id) do
    with {:ok, agent} <- get(agent_id) do
      agent
      |> cast(%{current_task: task, last_seen_at: DateTime.utc_now()}, [
        :current_task,
        :last_seen_at
      ])
      |> Repo.update()
    end
  end

  ## Helpers

  defp wrap_result(nil), do: {:error, :not_found}
  defp wrap_result(record), do: {:ok, record}
end
