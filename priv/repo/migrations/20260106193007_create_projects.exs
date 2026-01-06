defmodule PopStash.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    # Enable pgvector extension (will be used later, but set up now)
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:projects, [:name])
  end
end
