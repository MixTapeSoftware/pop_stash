defmodule PopStash.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans) do
      add :title, :string, null: false
      add :version, :string, null: false
      add :body, :text, null: false
      add :tags, {:array, :string}, default: []
      add :embedding, :vector, size: 1536
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:plans, [:project_id])
    create index(:plans, [:title])
    create index(:plans, [:version])
    create unique_index(:plans, [:project_id, :title, :version])
  end
end
