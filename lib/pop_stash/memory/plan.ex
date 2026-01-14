defmodule PopStash.Memory.Plan do
  @moduledoc """
  Schema for plans (project planning and documentation).

  Plans capture project goals, roadmaps, strategies, and implementation details.
  Each plan has a title and body content. Plans use threads to track evolution
  over time - multiple revisions of the same plan share the same thread_id.
  """

  use PopStash.Schema

  @thread_prefix "pthr"

  def thread_prefix, do: @thread_prefix

  schema "plans" do
    field(:title, :string)
    field(:body, :string)
    field(:tags, {:array, :string}, default: [])
    field(:thread_id, :string)
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)

    timestamps()
  end
end
