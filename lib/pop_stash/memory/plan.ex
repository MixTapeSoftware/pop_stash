defmodule PopStash.Memory.Plan do
  @moduledoc """
  Schema for plans (project planning and documentation).

  Plans capture project goals, roadmaps, strategies, and implementation details.
  Each plan has a title and body content.
  """

  use PopStash.Schema

  schema "plans" do
    field(:title, :string)
    field(:body, :string)
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
