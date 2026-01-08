import Config

# Runtime configuration is executed at runtime (not compile time),
# including for releases. This is the place to read environment variables.

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :pop_stash, PopStash.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Optionally configure the MCP port
  if port = System.get_env("MCP_PORT") do
    config :pop_stash, mcp_port: String.to_integer(port)
  end

  # Typesense configuration from environment
  typesense_url = System.get_env("TYPESENSE_URL") || raise("TYPESENSE_URL not set")
  typesense_api_key = System.get_env("TYPESENSE_API_KEY") || raise("TYPESENSE_API_KEY not set")

  # Parse URL to extract host, port, protocol
  uri = URI.parse(typesense_url)

  config :pop_stash, :typesense,
    api_key: typesense_api_key,
    nodes: [
      %{
        host: uri.host,
        port: uri.port || 8108,
        protocol: uri.scheme || "https"
      }
    ],
    enabled: true
end
