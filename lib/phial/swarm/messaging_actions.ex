defmodule Phial.Swarm.Actions.RouteMessage do
  @moduledoc false

  use Jido.Action,
    name: "route_worker_message",
    description: "Routes a worker message through the orchestrator",
    schema: [
      from: [type: :atom, required: true],
      to: [type: :atom, required: true],
      kind: [type: :atom, required: true],
      content: [type: :string, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  @max_messages_per_worker 2
  @roles [:researcher, :critic, :scout]

  @impl true
  def run(%{from: from, to: to, kind: kind, content: content}, context)
      when from in @roles and to in @roles do
    state = context.state
    sent_count = Map.get(state.a2a_sent, from, 0)

    cond do
      sent_count >= @max_messages_per_worker ->
        {:ok, %{messages: state.messages + 1}}

      not is_pid(state.pids[to]) ->
        {:ok, %{messages: state.messages + 1}}

      true ->
        payload = %{from: from, to: to, kind: kind, content: content}

        signal =
          Signal.new!("phial.worker.message_received", payload,
            source: "/agent/#{context.agent.id}"
          )

        event = %{
          kind: :a2a_message,
          from: from,
          to: to,
          message_kind: kind,
          input: payload,
          output: %{delivered: true, pid: state.pids[to]},
          at: System.monotonic_time(:millisecond)
        }

        updates = %{
          a2a: state.a2a + 1,
          a2a_sent: Map.put(state.a2a_sent, from, sent_count + 1),
          messages: state.messages + 2,
          events: Enum.take([event | state.events], 50)
        }

        {:ok, updates, [Directive.emit_to_pid(signal, state.pids[to])]}
    end
  end

  def run(_params, _context), do: {:error, :invalid_worker_message}
end

defmodule Phial.Swarm.Actions.ReceiveMessage do
  @moduledoc false

  use Jido.Action,
    name: "receive_worker_message",
    description: "Stores an A2A message in the worker inbox",
    schema: [
      from: [type: :atom, required: true],
      to: [type: :atom, required: true],
      kind: [type: :atom, required: true],
      content: [type: :string, required: true]
    ]

  @impl true
  def run(%{from: from, to: to, kind: kind, content: content}, context) do
    message = %{from: from, to: to, kind: kind, content: content}
    {:ok, %{inbox: context.state.inbox ++ [message]}}
  end
end
