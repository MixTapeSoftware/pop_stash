defmodule PopStash.Projects.Project do
  @moduledoc """
  Schema for projects, the top-level isolation boundary in PopStash.

  Each project has its own agents, stashes, insights, decisions, and locks.
  """

  use PopStash.Schema

  schema "projects" do
    field(:name, :string)
    field(:description, :string)
    field(:metadata, :map, default: %{})

    has_many(:agents, PopStash.Agents.Agent)

    timestamps()
  end
end
