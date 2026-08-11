defmodule PhialWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phial

  @session_options [
    store: :cookie,
    key: "_phial_key",
    signing_salt: "nX7mQ2pL"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/",
    from: :phial,
    gzip: false,
    only: PhialWeb.static_paths()
  )

  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false,
    only: ~w(phoenix.mjs)
  )

  plug(Plug.Static,
    at: "/vendor/live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.esm.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(PhialWeb.Router)
end
