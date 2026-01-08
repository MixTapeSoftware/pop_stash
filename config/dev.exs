import Config

config :pop_stash, PopStash.Repo,
  database: "pop_stash_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5433,
  pool_size: 10,
  types: PopStash.PostgrexTypes,
  # Migration defaults (must be repeated in each env config due to config merging)
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]
