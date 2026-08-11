defmodule Phial.Actions.DelegateToSwarm do
  @moduledoc "Delegates a complex question to the supervised Phial swarm."

  use Jido.Action,
    name: "delegate_to_swarm",
    description: """
    Runs three independent, supervised perspectives (researcher, critic and scout)
    concurrently and returns their combined recommendation. Use it for complex
    comparisons, investigations and decisions that benefit from parallel analysis.
    """,
    schema: [
      prompt: [
        type: :string,
        required: true,
        doc: "The complete question or decision the swarm should investigate"
      ]
    ]

  @impl true
  def run(%{prompt: prompt}, _context) do
    case Phial.Swarm.start(prompt) do
      {:ok, orchestrator} ->
        try do
          with {:ok, snapshot} <- Phial.Swarm.await(orchestrator, 300_000) do
            {:ok,
             %{
               recommendation: snapshot.state.recommendation,
               perspectives: snapshot.state.results,
               restarts: snapshot.state.restarts,
               messages: snapshot.state.messages
             }}
          end
        after
          if Process.alive?(orchestrator), do: GenServer.stop(orchestrator)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
