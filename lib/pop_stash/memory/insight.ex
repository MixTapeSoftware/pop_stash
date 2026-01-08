defmodule PopStash.Memory.Insight do
  @moduledoc """
  Schema for insights (persistent codebase knowledge).

  Insights are facts about the codebase that are discovered and shared.
  They never expire and are searchable by key.
  """

  use PopStash.Schema

  schema "insights" do
    field(:key, :string)
    field(:content, :string)
    field(:tags, {:array, :string}, default: [])
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
