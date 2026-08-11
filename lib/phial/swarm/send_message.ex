defmodule Phial.Swarm.SendMessage do
  @moduledoc "A ReAct tool that sends a typed message to another swarm worker."

  use Jido.Action,
    name: "send_message",
    description: """
    Sends one concise message to another worker through the swarm orchestrator.
    Each worker may send at most two messages per mission.
    """,
    schema: [
      to: [type: :string, required: true, doc: "researcher, critic or scout"],
      kind: [type: :string, required: true, doc: "evidence, challenge or alternative"],
      content: [type: :string, required: true]
    ]

  alias Jido.Signal

  @roles %{"researcher" => :researcher, "critic" => :critic, "scout" => :scout}
  @kinds %{"evidence" => :evidence, "challenge" => :challenge, "alternative" => :alternative}

  @impl true
  def run(%{to: to, kind: kind, content: content}, context) do
    with {:ok, parent_pid} <- fetch_parent(context),
         {:ok, from} <- fetch_sender(context),
         {:ok, to_role} <- fetch_known(@roles, to, :invalid_recipient),
         {:ok, message_kind} <- fetch_known(@kinds, kind, :invalid_message_kind),
         :ok <- validate_content(content) do
      payload = %{from: from, to: to_role, kind: message_kind, content: content}

      signal =
        Signal.new!("phial.worker.message", payload, source: "/agent/#{from}")

      case Jido.AgentServer.cast(parent_pid, signal) do
        :ok -> {:ok, %{sent: true, to: to_role, kind: message_kind}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_parent(%{parent_pid: pid}) when is_pid(pid), do: {:ok, pid}
  defp fetch_parent(_context), do: {:error, :missing_parent}

  defp fetch_sender(%{from: from}) when from in [:researcher, :critic, :scout], do: {:ok, from}
  defp fetch_sender(_context), do: {:error, :invalid_sender}

  defp fetch_known(known, value, error) when is_atom(value) do
    fetch_known(known, Atom.to_string(value), error)
  end

  defp fetch_known(known, value, error) when is_binary(value) do
    case Map.fetch(known, String.downcase(value)) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, error}
    end
  end

  defp fetch_known(_known, _value, error), do: {:error, error}

  defp validate_content(content) when is_binary(content) and content != "", do: :ok
  defp validate_content(_content), do: {:error, :empty_content}
end
