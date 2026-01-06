ExUnit.start()

# Start the Ecto sandbox for async tests
Ecto.Adapters.SQL.Sandbox.mode(PopStash.Repo, :manual)
