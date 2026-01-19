defmodule PopStash.Repo.Migrations.AddPlanStatus do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add :status, :string, default: "idle", null: false
    end
  end
end
