defmodule Phial.GreeterAgentTest do
  use ExUnit.Case, async: true

  alias Phial.Actions.Greet
  alias Phial.GreeterAgent

  test "executes a greeting deterministically with cmd/2" do
    agent = GreeterAgent.new()

    {agent, directives} = GreeterAgent.cmd(agent, {Greet, %{name: "Ada"}})

    assert directives == []
    assert agent.state.greeting_count == 1
    assert agent.state.last_name == "Ada"
    assert agent.state.last_greeting == "Olá, Ada! Você é a visita número 1."
  end

  test "preserves state across commands" do
    agent = GreeterAgent.new()
    {agent, []} = GreeterAgent.cmd(agent, {Greet, %{name: "Ada"}})
    {agent, []} = GreeterAgent.cmd(agent, {Greet, %{name: "Grace"}})

    assert agent.state.greeting_count == 2
    assert agent.state.last_greeting == "Olá, Grace! Você é a visita número 2."
  end
end
