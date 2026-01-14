defmodule PopStash.Repo.Migrations.StandardizeMemorySchemasToTitleBody do
  use Ecto.Migration

  def change do
    # Insights: key -> title, content -> body
    rename table(:insights), :key, to: :title
    rename table(:insights), :content, to: :body

    # Contexts: name -> title, summary -> body
    rename table(:contexts), :name, to: :title
    rename table(:contexts), :summary, to: :body

    # Decisions: topic -> title, decision -> body (keep reasoning)
    rename table(:decisions), :topic, to: :title
    rename table(:decisions), :decision, to: :body
  end
end
