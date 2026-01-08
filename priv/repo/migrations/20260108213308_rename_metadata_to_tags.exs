defmodule PopStash.Repo.Migrations.RenameMetadataToTags do
  use Ecto.Migration

  def change do
    # Stashes: rename metadata to tags
    alter table(:stashes) do
      remove :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
    end

    # Insights: rename metadata to tags
    alter table(:insights) do
      remove :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
    end

    # Decisions: rename metadata to tags
    alter table(:decisions) do
      remove :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
    end

    # Projects: rename metadata to tags
    alter table(:projects) do
      remove :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []
    end
  end
end
