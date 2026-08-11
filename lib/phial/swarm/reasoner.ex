defmodule Phial.Swarm.Reasoner do
  @moduledoc "Runs the role-specific ReAct loop used by a swarm worker."

  alias Jido.AI.Reasoning.ReAct
  alias Phial.Swarm.Roles

  @callback run(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback run(atom(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @callback synthesize(String.t(), %{atom() => String.t()}) ::
              {:ok, String.t()} | {:error, term()}
  @optional_callbacks run: 3

  @spec run(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def run(role, prompt) do
    run(role, prompt, %{})
  end

  @spec run(atom(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def run(role, prompt, tool_context) when is_map(tool_context) do
    config = %{
      model: :phial,
      system_prompt: Roles.system_prompt(role),
      tools: tools_for(role),
      max_iterations: 4,
      max_tokens: 1_200,
      streaming: false,
      capture_thinking?: false,
      capture_deltas?: false
    }

    case ReAct.run(prompt, config, context: tool_context) do
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

  @doc false
  def tools_for(:scout),
    do: [Phial.Swarm.SendMessage, Phial.Swarm.WebSearch]

  def tools_for(role) when role in [:researcher, :critic],
    do: [Phial.Swarm.SendMessage]

  def tools_for(_role), do: []

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
    Se a missão pedir informações atuais ou recentes, use os achados com URLs
    do Scout como autoridade para fatos que mudam com o tempo. Não apresente
    como atual uma afirmação sem fonte. Entregue primeiro os fatos confirmados,
    com datas e links; explique limitações depois, sem esconder achados válidos.
    """

    run(:orchestrator, synthesis_prompt)
  end
end
