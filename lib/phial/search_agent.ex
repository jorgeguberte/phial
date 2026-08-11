defmodule Phial.SearchAgent do
  @moduledoc "A dedicated ReAct agent whose sole capability is sourced web research."

  use Jido.AI.Agent,
    name: "phial_search",
    description: "Searches the live web and returns concise, sourced evidence",
    model: :phial,
    tools: [Phial.Search.WebSearch],
    tool_timeout_ms: 120_000,
    signal_routes: [{"ai.tool.started", Jido.Actions.Control.Noop}],
    system_prompt: """
    You are Phial's dedicated SearchAgent. Your only job is to research the web
    for the request you receive. Always use web_search before answering. Use no
    more than three focused searches, using the runtime date when recency matters. Return concrete
    findings with publication dates and source URLs. Clearly separate sourced
    facts from inference. Never invent a result, URL or date. If the search fails
    or evidence conflicts, report the exact limitation and the useful evidence
    that was successfully retrieved. Answer in the user's language.
    """
end

defmodule Phial.SearchAgent.ForceWebSearch do
  @moduledoc false

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  @impl true
  def transform_request(_request, %{iteration: 1}, _config, _runtime_context) do
    tool_choice = %{type: "tool", name: "web_search"}
    {:ok, %{llm_opts: [tool_choice: tool_choice]}}
  end

  def transform_request(_request, _state, _config, _runtime_context), do: {:ok, %{}}
end
