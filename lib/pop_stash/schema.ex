defmodule PopStash.Schema do
  @moduledoc false
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      # We use UUIDs everywhere in order to make model ID
      # collisions almost impossible (e.g. save User.id over
      # Token.id by mistake)
      # A side bonus is that our internal IDs will look
      # different than most external IDs (e.g. Wrike IDs),
      # which is nice when visually analyzing db records
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
