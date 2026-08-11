defmodule Phial.GreeterAgent do
  @moduledoc "A stateful agent that greets people when it receives a `greet` signal."

  use Jido.Agent,
    name: "greeter",
    description: "Keeps a count and produces a personalized greeting",
    schema: [
      greeting_count: [type: :integer, default: 0],
      last_name: [type: :string, default: ""],
      last_greeting: [type: :string, default: ""]
    ],
    signal_routes: [
      {"greet", Phial.Actions.Greet}
    ]
end
