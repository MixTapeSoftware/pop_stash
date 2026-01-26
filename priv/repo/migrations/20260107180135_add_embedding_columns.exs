defmodule PopStash.Repo.Migrations.AddEmbeddingColumns do
  use Ecto.Migration

  def up do
    # Enable pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Contexts - embed name + summary
    alter table(:contexts) do
      add :embedding, :vector, size: 384
    end

    # Insights - embed key + content
    alter table(:insights) do
      add :embedding, :vector, size: 384
    end

    # Decisions - embed topic + decision + reasoning
    alter table(:decisions) do
      add :embedding, :vector, size: 384
    end

    # HNSW indexes for fast similarity search
    execute "CREATE INDEX contexts_embedding_idx ON contexts USING hnsw (embedding vector_cosine_ops)"

    execute "CREATE INDEX insights_embedding_idx ON insights USING hnsw (embedding vector_cosine_ops)"

    execute "CREATE INDEX decisions_embedding_idx ON decisions USING hnsw (embedding vector_cosine_ops)"
  end

  def down do
    execute "DROP INDEX IF EXISTS contexts_embedding_idx"
    execute "DROP INDEX IF EXISTS insights_embedding_idx"
    execute "DROP INDEX IF EXISTS decisions_embedding_idx"

    alter table(:contexts) do
      remove :embedding
    end

    alter table(:insights) do
      remove :embedding
    end

    alter table(:decisions) do
      remove :embedding
    end

    execute "DROP EXTENSION IF EXISTS vector"
  end
end
