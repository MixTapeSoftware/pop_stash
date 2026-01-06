defmodule PopStash.Repo do
  use Ecto.Repo,
    otp_app: :pop_stash,
    adapter: Ecto.Adapters.Postgres
end
