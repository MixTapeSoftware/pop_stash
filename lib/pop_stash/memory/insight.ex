defmodule PopStash.Memory.Insight do
  @moduledoc """
  Schema for insights (persistent codebase knowledge).

  Insights are facts about the codebase that are discovered and shared.
  They never expire and are searchable by title.
  """

  use PopStash.Schema

  @thread_prefix "ithr"

  def thread_prefix, do: @thread_prefix

  schema "insights" do
    field(:title, :string)
    field(:body, :string)
    field(:tags, {:array, :string}, default: [])
    field(:thread_id, :string)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
