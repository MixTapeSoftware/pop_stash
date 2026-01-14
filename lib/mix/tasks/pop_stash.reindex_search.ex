defmodule Mix.Tasks.PopStash.ReindexSearch do
  @moduledoc """
  Rebuilds Typesense search index from database.

  ## Usage

      # Reindex all collections
      mix pop_stash.reindex_search

      # Reindex specific collection
      mix pop_stash.reindex_search contexts

      # Regenerate all embeddings
      mix pop_stash.reindex_search --regenerate-embeddings

      # Reindex specific collection and regenerate embeddings
      mix pop_stash.reindex_search insights --regenerate-embeddings

  ## Options

    * `--regenerate-embeddings` - Regenerate embeddings even if they exist
  """
  use Mix.Task

  alias PopStash.Embeddings
  alias PopStash.Memory.Context
  alias PopStash.Memory.Decision
  alias PopStash.Memory.Insight
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  @shortdoc "Rebuild Typesense search index from database"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, collections, _} =
      OptionParser.parse(args,
        switches: [regenerate_embeddings: :boolean]
      )

    collections = if collections === [], do: ~w(contexts insights decisions), else: collections

    Mix.shell().info("Starting reindex...")
    Typesense.ensure_collections()

    collections
    |> Task.async_stream(&reindex_collection(&1, opts), timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Reindex complete.")
  end

  defp reindex_collection("contexts", opts) do
    Mix.shell().info("Reindexing contexts...")

    Context
    |> Repo.all()
    |> Task.async_stream(&index_context(&1, opts), max_concurrency: 10, timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Contexts reindexed.")
  end

  defp reindex_collection("insights", opts) do
    Mix.shell().info("Reindexing insights...")

    Insight
    |> Repo.all()
    |> Task.async_stream(&index_insight(&1, opts), max_concurrency: 10, timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Insights reindexed.")
  end

  defp reindex_collection("decisions", opts) do
    Mix.shell().info("Reindexing decisions...")

    Decision
    |> Repo.all()
    |> Task.async_stream(&index_decision(&1, opts), max_concurrency: 10, timeout: :infinity)
    |> Stream.run()

    Mix.shell().info("Decisions reindexed.")
  end

  defp index_context(context, opts) do
    embedding =
      get_or_generate_embedding(context, opts, fn c ->
        "#{c.title} #{c.body || ""}"
      end)

    Typesense.index_context(context, embedding)
  end

  defp index_insight(insight, opts) do
    embedding =
      get_or_generate_embedding(insight, opts, fn i ->
        "#{i.title || ""} #{i.body}"
      end)

    Typesense.index_insight(insight, embedding)
  end

  defp index_decision(decision, opts) do
    embedding =
      get_or_generate_embedding(decision, opts, fn d ->
        "#{d.title} #{d.body} #{d.reasoning || ""}"
      end)

    Typesense.index_decision(decision, embedding)
  end

  defp get_or_generate_embedding(entity, opts, text_fn) do
    cond do
      opts[:regenerate_embeddings] ->
        generate_and_save_embedding(entity, text_fn)

      entity.embedding != nil ->
        entity.embedding

      true ->
        generate_and_save_embedding(entity, text_fn)
    end
  end

  defp generate_and_save_embedding(entity, text_fn) do
    {:ok, embedding} = Embeddings.embed(text_fn.(entity))
    save_embedding(entity, embedding)
    embedding
  end

  defp save_embedding(entity, embedding) do
    entity
    |> Ecto.Changeset.change(embedding: embedding)
    |> Repo.update!()
  end
end
