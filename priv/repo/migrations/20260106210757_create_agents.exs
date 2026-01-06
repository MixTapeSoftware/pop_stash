defmodule PopStash.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string
      add :current_task, :text
      add :status, :string, default: "active", null: false
      add :connected_at, :utc_datetime_usec
      add :last_seen_at, :utc_datetime_usec
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agents, [:project_id])
    create index(:agents, [:project_id, :status])
  end
end
