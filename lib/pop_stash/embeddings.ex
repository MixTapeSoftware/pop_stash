defmodule PopStash.Embeddings do
  @moduledoc """
  Text embeddings using all-MiniLM-L6-v2 via Nx.Serving.

  Nx.Serving handles batching automatically - multiple concurrent
  embed/1 calls are batched together for efficient GPU/CPU usage.
  """

  require Logger

  @doc """
  Builds the Nx.Serving for text embeddings.
  Called by supervision tree at startup.
  """
  def serving do
    config = Application.get_env(:pop_stash, __MODULE__, [])
    model_name = Keyword.get(config, :model, "sentence-transformers/all-MiniLM-L6-v2")

    Logger.info("Loading embedding model: #{model_name}")

    cache_dir = Keyword.get(config, :cache_dir)
    {:ok, model} = Bumblebee.load_model({:hf, model_name, cache_dir: cache_dir})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name, cache_dir: cache_dir})

    Bumblebee.Text.text_embedding(model, tokenizer,
      defn_options: [compiler: EXLA],
      output_pool: :mean_pooling,
      output_attribute: :hidden_state
    )
  end

  @doc """
  Generate embedding for text. Blocks until model is ready.
  Returns {:ok, vector} or {:error, reason}.

  Times out after 30 seconds to prevent indefinite blocking.
  """
  def embed(text) when is_binary(text) do
    if enabled?() do
      task =
        Task.async(fn ->
          %{embedding: embedding} = Nx.Serving.batched_run(__MODULE__, text)
          Nx.to_list(embedding)
        end)

      case Task.yield(task, 30_000) || Task.shutdown(task) do
        {:ok, vector} -> {:ok, vector}
        nil -> {:error, :timeout}
      end
    else
      {:error, :embeddings_disabled}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Check if the embedding service is enabled.
  """
  def enabled? do
    config = Application.get_env(:pop_stash, __MODULE__, [])
    Keyword.get(config, :enabled, false)
  end

  @doc """
  Check if the embedding serving process is alive.
  """
  def ready? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
