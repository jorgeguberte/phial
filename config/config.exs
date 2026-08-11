import Config

config :phial, Phial.Jido,
  max_tasks: 100,
  agent_pools: []

config :jido_ai,
  model_aliases: %{
    phial: "openai:gpt-5-mini"
  }
