defmodule Phial.ChatRouting do
  @moduledoc "Deterministic routing rules for chat turns that require fresh web data."

  @fresh_markers [
    "agora",
    "atual",
    "hoje",
    "recent",
    "recem-public",
    "tempo real",
    "ultima",
    "ultimo",
    "novidade",
    "noticia",
    "latest",
    "current",
    "today",
    "news",
    "real-time",
    "real time",
    "this week"
  ]

  @doc "Returns true when a prompt explicitly asks for current information."
  @spec fresh_web_request?(String.t()) :: boolean()
  def fresh_web_request?(prompt) when is_binary(prompt) do
    normalized =
      prompt
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^a-z0-9\s-]/u, "")

    Enum.any?(@fresh_markers, &String.contains?(normalized, &1))
  end

  @doc "Adds deterministic first-turn swarm routing when fresh information is requested."
  @spec options_for(String.t(), keyword()) :: keyword()
  def options_for(prompt, opts) when is_binary(prompt) and is_list(opts) do
    if fresh_web_request?(prompt) do
      Keyword.put(opts, :request_transformer, Phial.ChatRouting.ForceSwarm)
    else
      opts
    end
  end

  @doc "Adds the runtime date so models interpret relative recency correctly."
  @spec prompt_for(String.t(), Date.t()) :: String.t()
  def prompt_for(prompt, today \\ Date.utc_today()) when is_binary(prompt) do
    if fresh_web_request?(prompt) do
      """
      Contexto de atualidade do runtime: hoje é #{Date.to_iso8601(today)}.
      Interprete "recente", "atual", "hoje" e termos equivalentes em relação
      a essa data. Delegue esta missão à swarm e pesquise a web antes de responder.

      Pedido do usuário:
      #{prompt}
      """
    else
      prompt
    end
  end
end

defmodule Phial.ChatRouting.ForceSwarm do
  @moduledoc false

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  @impl true
  def transform_request(_request, %{iteration: 1}, _config, _runtime_context) do
    tool_choice = %{type: "tool", name: "delegate_to_swarm"}
    {:ok, %{llm_opts: [tool_choice: tool_choice]}}
  end

  def transform_request(_request, _state, _config, _runtime_context), do: {:ok, %{}}
end
