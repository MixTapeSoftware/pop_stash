defmodule PopStash.Projects do
  @moduledoc """
  Context for managing projects.

  Projects are the top-level isolation boundary. Each project has its own
  stashes, insights, decisions, and locks.
  """

  import Ecto.Changeset
  import Ecto.Query
  alias PopStash.Projects.Project
  alias PopStash.Repo

  @doc """
  Gets a project by ID.

  Returns `{:ok, project}` or `{:error, :not_found}`.
  """
  def get(id) when is_binary(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  @doc """
  Gets a project by ID, raising if not found.
  """
  def get!(id) when is_binary(id) do
    Repo.get!(Project, id)
  end

  @doc """
  Creates a new project.

  ## Options

    * `:description` - Optional description
    * `:tags` - Optional list of tags
  """
  def create(name, opts \\ []) do
    attrs = %{
      name: name,
      description: Keyword.get(opts, :description),
      tags: Keyword.get(opts, :tags, [])
    }

    %Project{}
    |> create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all projects, ordered by creation date (newest first).
  """
  def list do
    Project
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes a project and all associated data.

  Returns `{:ok, project}` or `{:error, :not_found}`.
  """
  def delete(id) when is_binary(id) do
    case get(id) do
      {:ok, project} -> Repo.delete(project)
      error -> error
    end
  end

  @doc """
  Checks if a project exists.
  """
  def exists?(id) when is_binary(id) do
    Project
    |> where([p], p.id == ^id)
    |> Repo.exists?()
  end

  ## Changesets

  defp create_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :tags])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
