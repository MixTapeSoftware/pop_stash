defmodule PopStash.Repo.Migrations.AddFilesToMemoryTypes do
  use Ecto.Migration

  def change do
    alter table(:decisions) do
      add :files, {:array, :string}, default: []
    end

    alter table(:insights) do
      add :files, {:array, :string}, default: []
    end

    alter table(:plans) do
      add :files, {:array, :string}, default: []
    end
  end
end
