defmodule Phial.Swarm.Roles do
  @moduledoc false

  alias Phial.Swarm.{CriticAgent, ResearcherAgent, ScoutAgent}

  @roles [
    researcher: ResearcherAgent,
    critic: CriticAgent,
    scout: ScoutAgent
  ]

  @spec all() :: keyword(module())
  def all, do: @roles

  @spec role_for(module()) :: atom()
  def role_for(module) do
    case Enum.find(@roles, fn {_role, agent_module} -> agent_module == module end) do
      {role, _module} -> role
      nil -> :worker
    end
  end

  @spec system_prompt(atom()) :: String.t()
  def system_prompt(:researcher) do
    """
    Você é o Researcher. Investigue as opções relevantes, fatos técnicos,
    maturidade e evidências. Entregue achados concretos e ressalve incertezas.
    Use send_message para enviar ao Critic sua evidência mais importante com
    kind "evidence". Você pode enviar no máximo 2 mensagens na missão.
    Seja compacto: no máximo 8 bullets e 300 palavras.
    """
  end

  def system_prompt(:critic) do
    """
    Você é o Critic. Procure riscos, custos ocultos, hipóteses frágeis e casos
    em que a escolha sugerida falharia. Seja rigoroso e específico.
    Use send_message para enviar ao Researcher seu principal contraponto com
    kind "challenge". Você pode enviar no máximo 2 mensagens na missão.
    Limite a resposta a 8 bullets e 300 palavras.
    """
  end

  def system_prompt(:scout) do
    """
    Você é o Scout. Explore alternativas diferentes e trade-offs. Produza uma
    shortlist pragmática com critérios claros para decidir.
    Use send_message para enviar ao Critic a alternativa mais promissora com
    kind "alternative". Você pode enviar no máximo 2 mensagens na missão.
    Use no máximo 8 bullets e 300 palavras.
    """
  end

  def system_prompt(:orchestrator) do
    """
    Você é o Orchestrator. Sintetize pareceres independentes numa decisão
    coerente, explícita e acionável. Não esconda divergências importantes.
    Entregue escolha, motivos, riscos e condição de mudança em até 300 palavras.
    """
  end

  def system_prompt(_role), do: "Analise a missão de forma objetiva."
end
