defmodule Phial.Actions.Greet do
  @moduledoc "Creates a greeting and records it in the agent state."

  use Jido.Action,
    name: "greet",
    description: "Greets a person by name",
    schema: [
      name: [type: :string, required: true]
    ]

  @impl true
  def run(%{name: name}, context) do
    count = (context.state[:greeting_count] || 0) + 1
    greeting = "Olá, #{name}! Você é a visita número #{count}."

    {:ok,
     %{
       greeting_count: count,
       last_name: name,
       last_greeting: greeting
     }}
  end
end
