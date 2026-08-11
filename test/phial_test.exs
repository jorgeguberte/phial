defmodule PhialTest do
  use ExUnit.Case, async: false

  test "routes a signal through a supervised AgentServer" do
    id = "test-greeter-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, pid} = Phial.start_agent(id)

    assert {:ok, agent} = Phial.greet(pid, "Linus")
    assert agent.state.greeting_count == 1
    assert agent.state.last_greeting == "Olá, Linus! Você é a visita número 1."

    assert Phial.Jido.whereis(id) == pid
    GenServer.stop(pid)
  end
end
