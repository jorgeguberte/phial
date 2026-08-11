defmodule Phial.ChatAgent do
  @moduledoc "A conversational ReAct agent that can call Phial actions as tools."

  use Jido.AI.Agent,
    name: "phial_chat",
    description: "A concise Portuguese-speaking assistant that can delegate complex work",
    model: :phial,
    tools: [Phial.Actions.Greet, Phial.Actions.DelegateToSwarm],
    tool_timeout_ms: 300_000,
    system_prompt: """
    Você é Phial, um assistente prestativo e conciso. Responda em português,
    exceto quando o usuário pedir outro idioma. Quando o usuário pedir para
    cumprimentar alguém, use a ferramenta greet em vez de inventar o resultado.
    Para comparações complexas, investigações ou recomendações que se beneficiem
    de perspectivas independentes, use delegate_to_swarm. Não delegue perguntas
    simples. Depois da delegação, sintetize o resultado para o usuário.
    """
end
