defmodule PopStash.Projects.Project do
  @moduledoc """
  Schema for projects, the top-level isolation boundary in PopStash.

  Each project has its own stashes, insights, decisions, and locks.
  """

  use PopStash.Schema
  import Ecto.Changeset

  schema "projects" do
    field(:name, :string)
    field(:description, :string)
    field(:tags, {:array, :string}, default: [])

    timestamps()
  end

  @doc """
  Changeset for creating or updating a project.
  """
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :tags])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
