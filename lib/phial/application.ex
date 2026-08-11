defmodule Phial.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    configure_model_alias()
    configure_action_timeout()

    children = [
      Phial.Jido,
      {Phoenix.PubSub, name: Phial.PubSub},
      Phial.RuntimeEvents,
      {Task.Supervisor, name: PhialWeb.TaskSupervisor},
      PhialWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Phial.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PhialWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ReqLLM starts before Phial and loads .env into the process environment. Set
  # the alias here so PHIAL_MODEL works both as an OS variable and from .env.
  defp configure_model_alias do
    aliases = Application.get_env(:jido_ai, :model_aliases, %{})
    model = Phial.ModelConfig.from_env()
    Application.put_env(:jido_ai, :model_aliases, Map.put(aliases, :phial, model))
  end

  defp configure_action_timeout do
    timeout =
      case Integer.parse(System.get_env("PHIAL_ACTION_TIMEOUT_MS", "300000")) do
        {value, ""} when value > 0 -> value
        _invalid -> 300_000
      end

    Application.put_env(:jido_action, :default_timeout, timeout)
  end
end
