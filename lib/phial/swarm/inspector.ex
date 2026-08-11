defmodule Phial.Swarm.Inspector do
  @moduledoc "Renders a compact terminal view of a live Phial swarm."

  alias Phial.Swarm

  @roles [:researcher, :critic, :scout]

  @spec render(pid()) :: String.t()
  def render(orchestrator) when is_pid(orchestrator) do
    case Swarm.snapshot(orchestrator) do
      {:ok, snapshot} -> render_snapshot(snapshot)
      {:error, reason} -> "PHIAL\n\ninspector unavailable: #{inspect(reason)}"
    end
  end

  @spec render_snapshot(map()) :: String.t()
  def render_snapshot(snapshot) do
    state = snapshot.state
    orchestrator_status = if state.recommendation != "", do: :done, else: :thinking

    rows =
      @roles
      |> Enum.with_index()
      |> Enum.map(fn {role, index} ->
        connector = if index == length(@roles) - 1, do: "└─", else: "├─"
        pid = state.pids[role] || snapshot.children[role]
        status = state.statuses[role] || :starting
        "#{connector} #{dot(status)} #{pad(role, 12)} #{pad(pid_text(pid), 18)} #{status}"
      end)

    a2a_rows =
      state.events
      |> Enum.filter(&(&1.kind == :a2a_message))
      |> Enum.take(3)
      |> Enum.reverse()
      |> Enum.map(fn event ->
        "#{pad(event.from, 10)} → #{pad(event.to, 10)} #{event.message_kind}"
      end)

    [
      "PHIAL",
      "",
      "#{dot(orchestrator_status)} #{pad(:orchestrator, 15)} #{pad(pid_text(snapshot.pid), 18)} #{orchestrator_status}",
      rows,
      "",
      "Messages: #{state.messages}",
      "A2A:      #{state.a2a}",
      "Agents:   #{1 + map_size(snapshot.children)}",
      "Restarts: #{state.restarts}",
      if(a2a_rows == [], do: [], else: ["", a2a_rows])
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp dot(:done), do: "○"
  defp dot(:crashed), do: "×"
  defp dot(_status), do: "●"

  defp pid_text(pid) when is_pid(pid), do: inspect(pid)
  defp pid_text(_pid), do: "—"

  defp pad(value, width) do
    value
    |> to_string()
    |> String.pad_trailing(width)
  end
end
