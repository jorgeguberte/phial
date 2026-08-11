defmodule Phial.Swarm.ResearcherAgent do
  @moduledoc "Research worker running in its own AgentServer process."

  use Jido.Agent,
    name: "phial_researcher",
    description: "Researches evidence for a delegated mission",
    schema: [status: [type: :atom, default: :waiting]],
    signal_routes: [{"phial.worker.run", Phial.Swarm.Actions.RunWorker}]
end

defmodule Phial.Swarm.CriticAgent do
  @moduledoc "Critic worker running in its own AgentServer process."

  use Jido.Agent,
    name: "phial_critic",
    description: "Challenges assumptions for a delegated mission",
    schema: [status: [type: :atom, default: :waiting]],
    signal_routes: [{"phial.worker.run", Phial.Swarm.Actions.RunWorker}]
end

defmodule Phial.Swarm.ScoutAgent do
  @moduledoc "Scout worker running in its own AgentServer process."

  use Jido.Agent,
    name: "phial_scout",
    description: "Explores alternatives for a delegated mission",
    schema: [status: [type: :atom, default: :waiting]],
    signal_routes: [{"phial.worker.run", Phial.Swarm.Actions.RunWorker}]
end
