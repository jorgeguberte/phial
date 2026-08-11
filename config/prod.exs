import Config

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise "SECRET_KEY_BASE must be set in production"

config :phial, PhialWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
  server: true,
  secret_key_base: secret_key_base
