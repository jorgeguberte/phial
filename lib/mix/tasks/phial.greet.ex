defmodule Mix.Tasks.Phial.Greet do
  @shortdoc "Runs the Phial greeting agent"

  @moduledoc """
  Runs the greeting agent from the command line.

      mix phial.greet Ada
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    name = Enum.join(args, " ")

    if name == "" do
      Mix.raise("usage: mix phial.greet NAME")
    end

    case Phial.greet_once(name) do
      {:ok, agent} -> Mix.shell().info(agent.state.last_greeting)
      {:error, reason} -> Mix.raise("agent failed: #{inspect(reason)}")
    end
  end
end
