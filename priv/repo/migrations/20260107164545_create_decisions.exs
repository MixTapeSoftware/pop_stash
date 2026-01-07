defmodule PopStash.Repo.Migrations.CreateDecisions do
  use Ecto.Migration

  def change do
    create table(:decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :topic, :string, null: false
      add :decision, :text, null: false
      add :reasoning, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Query by project
    create index(:decisions, [:project_id])
    # Query by topic within project (most common query)
    create index(:decisions, [:project_id, :topic])
    # Query recent decisions
    create index(:decisions, [:project_id, :inserted_at])
  end
end
