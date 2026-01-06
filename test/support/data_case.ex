defmodule PopStash.DataCase do
  @moduledoc """
  Test case for tests that require database access.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias PopStash.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import PopStash.DataCase
    end
  end

  setup tags do
    PopStash.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(PopStash.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
