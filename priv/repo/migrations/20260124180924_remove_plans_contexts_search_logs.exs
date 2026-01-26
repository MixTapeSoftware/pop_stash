defmodule PopStash.Repo.Migrations.RemovePlansContexts do
  use Ecto.Migration

  def change do
    drop table(:plan_steps)
    drop table(:plans)
    drop table(:contexts)
  end
end
