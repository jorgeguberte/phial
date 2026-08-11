import Config

config :phial, PhialWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base:
    "dev-phial-secret-key-base-7f3d9c1a5b8e2f4d6a0c3e9b1f7d5a8c2e6b0d4f9a1c7e3b5d8f2a6c0e4"

config :logger, :console, format: "[$level] $message\n"
