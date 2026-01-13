import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pop_stash, PopStash.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pop_stash_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pop_stash, PopStashWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Jpk5t+RR1DjNOcurgsgDiKVlI+lSNwzkEpdSHVRO3GkMzjH/dSMNWX0e3439UksR",
  server: false

# In test we don't send emails
config :pop_stash, PopStash.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

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
config :pop_stash, PopStash.Embeddings,
  model: "sentence-transformers/all-MiniLM-L6-v2",
  dimensions: 384,
  enabled: false,
  cache_dir: ".cache/bumblebee"

config :pop_stash, :typesense, enabled: false

config :logger, level: :warning
