defmodule Phial.ChatAgentTest do
  use ExUnit.Case, async: false

  alias Phial.ChatAgent
  alias Phial.ChatRouting

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

  test "routes requests for recent information deterministically to the swarm" do
    assert ChatRouting.fresh_web_request?("Informações recentes")
    assert ChatRouting.fresh_web_request?("Quais são as notícias de Magic hoje?")
    assert ChatRouting.fresh_web_request?("Latest Elixir releases")
    refute ChatRouting.fresh_web_request?("Explique o que é OTP")

    opts = ChatRouting.options_for("Informações recentes", timeout: 123)
    assert opts[:timeout] == 123
    assert opts[:request_transformer] == Phial.ChatRouting.ForceSwarm

    routed_prompt =
      ChatRouting.prompt_for("Informações recentes", ~D[2026-08-11])

    assert routed_prompt =~ "hoje é 2026-08-11"
    assert routed_prompt =~ "Informações recentes"
    assert ChatRouting.prompt_for("Explique OTP", ~D[2026-08-11]) == "Explique OTP"
  end

  test "forces delegation only on the first ReAct iteration" do
    transformer = Phial.ChatRouting.ForceSwarm

    expected_choice = %{type: "tool", name: "delegate_to_swarm"}

    assert {:ok, %{llm_opts: [tool_choice: ^expected_choice]}} =
             transformer.transform_request(%{}, %{iteration: 1}, %{}, %{})

    assert {:ok, %{}} = transformer.transform_request(%{}, %{iteration: 2}, %{}, %{})
  end
end
