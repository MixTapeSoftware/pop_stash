import Config

config :pop_stash,
  start_server: false

config :pop_stash, PopStash.Repo,
  database: "pop_stash_test#{System.get_env("MIX_TEST_PARTITION")}",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5433,
  pool: Ecto.Adapters.SQL.Sandbox,
  types: PopStash.PostgrexTypes,
  # Migration defaults (must be repeated in each env config due to config merging)
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

# Disable embeddings and Typesense in tests (use mocks)
config :pop_stash, PopStash.Embeddings, enabled: false
config :pop_stash, :typesense, enabled: false

config :logger, level: :warning
