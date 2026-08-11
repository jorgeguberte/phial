defmodule Phial.Swarm.Reasoner do
  @moduledoc "Runs the role-specific ReAct loop used by a swarm worker."

  alias Jido.AI.Reasoning.ReAct
  alias Phial.Swarm.Roles

  @callback run(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback synthesize(String.t(), %{atom() => String.t()}) ::
              {:ok, String.t()} | {:error, term()}

  @spec run(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def run(role, prompt) do
    config = %{
      model: :phial,
      system_prompt: Roles.system_prompt(role),
      tools: [],
      max_iterations: 4,
      max_tokens: 1_200,
      streaming: false,
      capture_thinking?: false,
      capture_deltas?: false
    }

    case ReAct.run(prompt, config) do
      %{result: result, termination_reason: reason}
      when is_binary(result) and reason in [:final_answer, :completed] ->
        {:ok, result}

      %{result: result} when is_binary(result) ->
        {:ok, result}

      %{termination_reason: reason, result: result} ->
        {:error, {reason, result}}
    end
  rescue
    error -> {:error, error}
  end

  @spec synthesize(String.t(), %{atom() => String.t()}) :: {:ok, String.t()} | {:error, term()}
  def synthesize(prompt, results) do
    evidence =
      Enum.map_join([:researcher, :critic, :scout], "\n\n", fn role ->
        "## #{role}\n#{Map.fetch!(results, role)}"
      end)

    synthesis_prompt = """
    Missão original:
    #{prompt}

    Pareceres paralelos:
    #{evidence}

    Produza uma recomendação final clara. Declare a escolha, os principais
    motivos, riscos e a condição que faria você escolher outra alternativa.
    """

    run(:orchestrator, synthesis_prompt)
  end
end
