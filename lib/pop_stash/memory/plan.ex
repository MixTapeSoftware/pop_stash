defmodule PopStash.Memory.Plan do
  @moduledoc """
  Schema for plans (project planning and documentation).

  Plans capture project goals, roadmaps, strategies, and implementation details.
  Each plan has a title, version, and body content. Plans are versioned to track
  evolution over time - the same title can have multiple versions.
  """

  use PopStash.Schema

  schema "plans" do
    field(:title, :string)
    field(:version, :string)
    field(:body, :string)
    field(:tags, {:array, :string}, default: [])
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
