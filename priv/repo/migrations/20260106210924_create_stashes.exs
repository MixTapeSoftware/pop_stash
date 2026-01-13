defmodule PopStash.Repo.Migrations.CreateStashes do
  use Ecto.Migration

  def change do
    create table(:stashes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :summary, :text, null: false
      add :files, {:array, :string}, default: []
      add :metadata, :map, default: %{}
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stashes, [:project_id])
    create index(:stashes, [:project_id, :name])
  end
end
