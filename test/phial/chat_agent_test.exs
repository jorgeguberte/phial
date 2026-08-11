defmodule Phial.ChatAgentTest do
  use ExUnit.Case, async: false

  alias Phial.ChatAgent

  test "declares greeting, search and swarm delegation as AI tools" do
    id = "test-chat-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, pid} = Phial.start_chat(id)

    assert {:ok, true} = Jido.AI.has_tool?(pid, "greet")
    assert {:ok, true} = Jido.AI.has_tool?(pid, "delegate_to_search")
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

  test "the dedicated SearchAgent exposes only web search" do
    id = "test-search-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, pid} = Phial.start_search(id)

    assert {:ok, true} = Jido.AI.has_tool?(pid, "web_search")
    assert {:ok, false} = Jido.AI.has_tool?(pid, "delegate_to_swarm")
    assert {:ok, false} = Jido.AI.has_tool?(pid, "send_message")

    GenServer.stop(pid)
  end

  test "a SearchAgent always performs web search on its first iteration" do
    transformer = Phial.SearchAgent.ForceWebSearch

    expected_choice = %{type: "tool", name: "web_search"}

    assert {:ok, %{llm_opts: [tool_choice: ^expected_choice]}} =
             transformer.transform_request(%{}, %{iteration: 1}, %{}, %{})

    assert {:ok, %{}} = transformer.transform_request(%{}, %{iteration: 2}, %{}, %{})
  end
end
