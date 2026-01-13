defmodule PopStash.Repo.Migrations.CreateSearchLogs do
  use Ecto.Migration

  def change do
    create table(:search_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :query, :text, null: false
      add :collection, :string, null: false
      add :search_type, :string, null: false
      add :tool, :string
      add :result_count, :integer, default: 0
      add :found, :boolean, default: false
      add :duration_ms, :integer

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:search_logs, [:project_id])
    create index(:search_logs, [:project_id, :collection])
    create index(:search_logs, [:project_id, :inserted_at])
    create index(:search_logs, [:tool])
  end
end
