defmodule PopStash.Memory.PlanStep do
  @moduledoc """
  Schema for plan steps.

  Steps are mutable tasks associated with a plan. They can be marked as pending,
  in_progress, completed, or failed. The step_number is a float to allow insertion
  between existing steps (e.g., step 2.5 between 2 and 3).
  """

  use PopStash.Schema
  import Ecto.Changeset

  alias PopStash.Memory.Plan
  alias PopStash.Projects.Project

  @valid_statuses ~w(pending in_progress completed failed)
  @valid_creators ~w(user agent)

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

  @doc """
  Creates a changeset for a new plan step.

  Required fields: plan_id, step_number, description, project_id
  """
  def changeset(plan_step, attrs) do
    plan_step
    |> cast(attrs, [
      :plan_id,
      :step_number,
      :description,
      :status,
      :result,
      :created_by,
      :metadata,
      :project_id
    ])
    |> validate_required([:plan_id, :step_number, :description, :project_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:created_by, @valid_creators)
    |> foreign_key_constraint(:plan_id)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:plan_id, :step_number])
  end

  @doc """
  Creates a changeset for updating a plan step's status or result.

  This is used when marking a step as in_progress, completed, or failed,
  and optionally adding execution results or notes.
  """
  def update_changeset(plan_step, attrs) do
    plan_step
    |> cast(attrs, [:status, :result, :metadata])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
