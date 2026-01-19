defmodule PopStash.Memory.PlanStep do
  @moduledoc """
  Schema for plan steps.

  Steps are mutable tasks associated with a plan. They can be marked as pending,
  in_progress, completed, failed, or deferred. The step_number is a float to allow
  insertion between existing steps (e.g., step 2.5 between 2 and 3).

  ## Step Statuses

  - `pending` - Not yet started
  - `in_progress` - Currently being worked on
  - `completed` - Successfully finished
  - `failed` - Failed during execution
  - `deferred` - Skipped, will not be executed
  - `outdated` - No longer relevant, won't be executed
  """

  use PopStash.Schema

  alias PopStash.Memory.Plan
  alias PopStash.Projects.Project

  schema "plan_steps" do
    field(:step_number, :float)
    field(:description, :string)
    field(:status, :string, default: "pending")
    field(:result, :string)
    field(:created_by, :string, default: "user")
    field(:metadata, :map, default: %{})

    belongs_to(:plan, Plan)
    belongs_to(:project, Project)

    timestamps()
  end
end
