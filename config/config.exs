import Config

config :pop_stash,
  mcp_port: 4001,
  mcp_protocol_version: "2025-03-26"

import_config "#{config_env()}.exs"
