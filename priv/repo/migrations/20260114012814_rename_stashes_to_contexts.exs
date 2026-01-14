defmodule PopStash.Repo.Migrations.RenameStashesToContexts do
  use Ecto.Migration

  def up do
    # Rename the table
    rename table(:stashes), to: table(:contexts)

    # Indexes are automatically updated when renaming tables in PostgreSQL
    # but we'll recreate them to ensure consistency

    # Drop old indexes (they'll be renamed with the table, but let's be explicit)
    drop_if_exists index(:contexts, [:project_id])
    drop_if_exists index(:contexts, [:project_id, :name])
    drop_if_exists index(:contexts, [:expires_at])

    # Recreate indexes with proper names
    create index(:contexts, [:project_id])
    create index(:contexts, [:project_id, :name])
    create index(:contexts, [:expires_at])
  end

  def down do
    # Rename the table back
    rename table(:contexts), to: table(:stashes)

    # Drop the indexes
    drop_if_exists index(:stashes, [:project_id])
    drop_if_exists index(:stashes, [:project_id, :name])
    drop_if_exists index(:stashes, [:expires_at])

    # Recreate indexes with old names
    create index(:stashes, [:project_id])
    create index(:stashes, [:project_id, :name])
    create index(:stashes, [:expires_at])
  end
end
