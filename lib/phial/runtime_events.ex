defmodule Phial.RuntimeEvents do
  @moduledoc "Bridges Jido runtime telemetry into local Phoenix PubSub events."

  use GenServer

  @topic "phial:runtime"
  @handler_id "phial-runtime-events"
  @signal_stop [:jido, :agent_server, :signal, :stop]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Phial.PubSub, @topic)

  @doc false
  def handle_telemetry(_event, _measurements, metadata, _config) do
    Phoenix.PubSub.broadcast(Phial.PubSub, @topic, {:runtime_signal, metadata})
  end

  @impl true
  def init(:ok) do
    :ok = :telemetry.attach(@handler_id, @signal_stop, &__MODULE__.handle_telemetry/4, nil)
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end
end
