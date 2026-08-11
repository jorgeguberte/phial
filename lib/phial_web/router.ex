defmodule PhialWeb.Router do
  use PhialWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PhialWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", PhialWeb do
    pipe_through(:browser)
    live("/", InspectorLive, :index)
  end
end
