defmodule PopStash.Search.Indexer do
  @moduledoc """
  Subscribes to Memory events and handles async embedding + Typesense indexing.
  Decoupled from Memory context via PubSub.
  """
  use GenServer
  require Logger

  alias PopStash.Embeddings
  alias PopStash.Repo
  alias PopStash.Search.Typesense

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(PopStash.PubSub, "memory:events")

    # Ensure Typesense collections exist (non-blocking, retry later if down)
    case Typesense.ensure_collections() do
      :ok ->
        {:ok, %{collections_ready: true}}

      {:error, reason} ->
        Logger.warning(
          "Typesense not available at boot: #{inspect(reason)}. Will retry on first index."
        )

        {:ok, %{collections_ready: false}}
    end
  end

  # Handle PubSub events
  @impl true
  def handle_info({:insight_created, insight}, state) do
    index_async(insight, &index_insight/1)
    {:noreply, state}
  end

  def handle_info({:insight_updated, insight}, state) do
    index_async(insight, &index_insight/1)
    {:noreply, state}
  end

  def handle_info({:decision_created, decision}, state) do
    index_async(decision, &index_decision/1)
    {:noreply, state}
  end

  def handle_info({:insight_deleted, insight_id}, state) do
    Typesense.delete_document("insights", insight_id)
    {:noreply, state}
  end

  def handle_info({:decision_deleted, decision_id}, state) do
    Typesense.delete_document("decisions", decision_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private

  defp index_async(entity, index_fn) do
    Task.Supervisor.start_child(PopStash.TaskSupervisor, fn ->
      # Ensure collections exist (handles Typesense being down at boot)
      Typesense.ensure_collections()
      index_fn.(entity)
    end)
  end

  defp index_insight(insight) do
    text = "#{insight.title || ""} #{insight.body}"

    with {:ok, embedding} <- Embeddings.embed(text),
         :ok <- update_embedding(insight, embedding),
         :ok <- Typesense.index_insight(insight, embedding) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to index insight #{insight.id}: #{inspect(reason)}")
        :error
    end
  end

  defp index_decision(decision) do
    text = "#{decision.title} #{decision.body} #{decision.reasoning || ""}"

    with {:ok, embedding} <- Embeddings.embed(text),
         :ok <- update_embedding(decision, embedding),
         :ok <- Typesense.index_decision(decision, embedding) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to index decision #{decision.id}: #{inspect(reason)}")
        :error
    end
  end

  defp update_embedding(entity, embedding) do
    # Update pgvector column in Postgres
    entity
    |> Ecto.Changeset.change(embedding: embedding)
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
