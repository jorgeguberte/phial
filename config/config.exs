import Config

config :phial, Phial.Jido,
  max_tasks: 100,
  agent_pools: []

config :phial, PhialWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: PhialWeb.ErrorHTML], layout: false],
  pubsub_server: Phial.PubSub,
  live_view: [signing_salt: "4p8QJkFh1zM0xVnD"]

config :jido_ai,
  model_aliases: %{
    phial: "openai:gpt-5-mini"
  }

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
