defmodule PopStash.Repo.Migrations.AddThreadIdToMemoryTables do
  use Ecto.Migration

  def change do
    # Add thread_id to insights
    alter table(:insights) do
      add :thread_id, :string
    end

    create index(:insights, [:thread_id])

    # Add thread_id to contexts
    alter table(:contexts) do
      add :thread_id, :string
    end

    create index(:contexts, [:thread_id])

    # Add thread_id to decisions
    alter table(:decisions) do
      add :thread_id, :string
    end

    create index(:decisions, [:thread_id])

    # Add thread_id to plans
    alter table(:plans) do
      add :thread_id, :string
    end

    create index(:plans, [:thread_id])
  end
end
