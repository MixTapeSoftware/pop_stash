defmodule PopStash.Repo.Migrations.FixPlansUniqueConstraint do
  use Ecto.Migration

  def change do
    # Drop the incorrect unique constraint that was created
    # Plans can have multiple records with the same title and thread_id (they're revisions)
    drop_if_exists unique_index(:plans, [:project_id, :title, :thread_id])
  end
end
