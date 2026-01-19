defmodule PopStash.Memory.Plan do
  @moduledoc """
  Schema for plans (project planning and documentation).

  Plans capture project goals, roadmaps, strategies, and implementation details.
  Each plan has a title and body content.

  ## Plan Statuses

  - `idle` - Ready for an agent to claim and work a step
  - `running` - An agent is actively working a step
  - `paused` - User stopped execution
  - `completed` - All steps done
  - `failed` - A step failed
  """

  use PopStash.Schema

  schema "plans" do
    field(:title, :string)
    field(:body, :string)
    field(:status, :string, default: "idle")
    field(:files, {:array, :string}, default: [])
    field(:tags, {:array, :string}, default: [])
    field(:embedding, Pgvector.Ecto.Vector)

    belongs_to(:project, PopStash.Projects.Project)
    has_many(:steps, PopStash.Memory.PlanStep)

    timestamps()
  end
end
