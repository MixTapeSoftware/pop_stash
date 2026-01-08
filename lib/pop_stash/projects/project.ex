defmodule PopStash.Projects.Project do
  @moduledoc """
  Schema for projects, the top-level isolation boundary in PopStash.

  Each project has its own stashes, insights, decisions, and locks.
  """

  use PopStash.Schema

  schema "projects" do
    field(:name, :string)
    field(:description, :string)
    field(:tags, {:array, :string}, default: [])

    timestamps()
  end
end
