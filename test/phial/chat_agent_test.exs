defmodule Phial.ChatAgentTest do
  use ExUnit.Case, async: false

  alias Phial.ChatAgent

  test "declares the greeting and swarm actions as AI tools" do
    id = "test-chat-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, pid} = Phial.start_chat(id)

    assert {:ok, true} = Jido.AI.has_tool?(pid, "greet")
    assert {:ok, true} = Jido.AI.has_tool?(pid, "delegate_to_swarm")
    assert Phial.Jido.whereis(id) == pid

    GenServer.stop(pid)
  end

  test "resolves the configured model alias without an API request" do
    assert Jido.AI.resolve_model(:phial) == Phial.ModelConfig.from_env()

    assert ChatAgent.name() == "phial_chat"
  end

  test "accepts the Jido tool lifecycle signal used for observability" do
    id = "test-chat-lifecycle-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, pid} = Phial.start_chat(id)

    signal =
      Jido.Signal.new!("ai.tool.started", %{
        call_id: "test-call",
        tool_name: "delegate_to_swarm",
        arguments: %{}
      })

    assert {:ok, _agent} = Jido.AgentServer.call(pid, signal)
    GenServer.stop(pid)
  end
end
