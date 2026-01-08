defmodule PopStash.Memory.Insight do
  @moduledoc """
  Schema for insights (persistent codebase knowledge).

  Insights are facts about the codebase that agents discover and share.
  They never expire and are searchable by key.
  """

  use PopStash.Schema

  schema "insights" do
    field(:key, :string)
    field(:content, :string)
    field(:metadata, :map, default: %{})
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)
    belongs_to(:agent, PopStash.Agents.Agent, foreign_key: :created_by)

    timestamps()
  end
end
