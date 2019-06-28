use Mix.Config

config :logger, :console,
  format: "[$time][$level] $metadata$message\n",
  metadata: [:id]
