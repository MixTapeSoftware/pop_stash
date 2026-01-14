defmodule PopStash.Repo.Migrations.RemoveVersionFromPlans do
  use Ecto.Migration

  def change do
    # Drop the unique constraint first
    drop unique_index(:plans, [:project_id, :title, :version])

    # Remove the version column
    alter table(:plans) do
      remove :version
    end

    # No unique constraint needed - plans use thread_id for grouping revisions
    # Multiple records can have the same title and thread_id (they're revisions)
  end
end
