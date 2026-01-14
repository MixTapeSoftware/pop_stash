defmodule PopStash.Memory.Thread do
  @moduledoc """
  Generates thread IDs for PopStash memory records.

  Thread IDs connect related records across revisions using the format:
  `{prefix}_{12_char_nanoid}`

  All PopStash records are immutable. Records with the same `thread_id`
  represent different versions of the same logical entity.
  """

  @doc """
  Generates a new thread ID with the given prefix.

  ## Parameters
    - prefix: A string prefix to identify the record type (e.g., "dthr", "pthr")

  ## Examples

      iex> PopStash.Memory.Thread.generate("dthr")
      "dthr_k8f2m9x1p4qz"

      iex> PopStash.Memory.Thread.generate("pthr")
      "pthr_m3k9n7x2p4qz"
  """
  def generate(prefix) do
    "#{prefix}_#{Nanoid.generate(12)}"
  end

  @doc """
  Validates if a string is a valid thread ID format.

  Returns `true` if the ID matches the pattern `{prefix}_{12_char_nanoid}`,
  `false` otherwise.

  ## Examples

      iex> PopStash.Memory.Thread.valid?("dthr_k8f2m9x1p4qz")
      true

      iex> PopStash.Memory.Thread.valid?("invalid")
      false

      iex> PopStash.Memory.Thread.valid?(nil)
      false
  """
  def valid?(thread_id) when is_binary(thread_id) do
    case String.split(thread_id, "_", parts: 2) do
      [_prefix, id] when byte_size(id) == 12 ->
        String.match?(id, ~r/^[A-Za-z0-9_-]+$/)

      _ ->
        false
    end
  end

  def valid?(_), do: false
end
