defmodule PopStash.Repo.Migrations.RemoveThreadFromPlans do
  use Ecto.Migration

  def change do
    drop index(:plans, [:thread_id])

    alter table(:plans) do
      remove :thread_id, :string
    end
  end
end
