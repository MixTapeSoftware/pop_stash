defmodule PopStash.Repo.Migrations.CreatePlanSteps do
  use Ecto.Migration

  def change do
    create table(:plan_steps) do
      add :plan_id, references(:plans, on_delete: :delete_all), null: false
      add :step_number, :float, null: false
      add :description, :text, null: false
      add :status, :string, default: "pending"
      add :result, :text
      add :created_by, :string, default: "user"
      add :metadata, :map, default: %{}
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps()
      end

    create index(:plan_steps, [:plan_id])
    create index(:plan_steps, [:project_id])
    create index(:plan_steps, [:status])
    create unique_index(:plan_steps, [:plan_id, :step_number])
  end
end
