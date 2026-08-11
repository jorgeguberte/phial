import Config

config :phial, PhialWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base:
    "test-phial-secret-key-base-6a2c8e4f0b7d3a9c5e1f6b2d8a4c0e7f3b9d5a1c6e2f8b4d0a7c3e9f5b1"

config :logger, level: :warning
