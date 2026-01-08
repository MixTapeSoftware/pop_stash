defmodule PopStash.Repo.Migrations.CreateInsights do
  use Ecto.Migration

  def change do
    create table(:insights, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string
      add :content, :text, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:insights, [:project_id])
    create index(:insights, [:project_id, :key])
  end
end
