defmodule Phial.Swarm.ResearcherAgent do
  @moduledoc "Research worker running in its own AgentServer process."

  use Jido.Agent,
    name: "phial_researcher",
    description: "Researches evidence for a delegated mission",
    schema: [
      status: [type: :atom, default: :waiting],
      inbox: [type: {:list, :map}, default: []]
    ],
    signal_routes: [
      {"phial.worker.run", Phial.Swarm.Actions.RunWorker},
      {"phial.worker.message_received", Phial.Swarm.Actions.ReceiveMessage}
    ]
end

defmodule Phial.Swarm.CriticAgent do
  @moduledoc "Critic worker running in its own AgentServer process."

  use Jido.Agent,
    name: "phial_critic",
    description: "Challenges assumptions for a delegated mission",
    schema: [
      status: [type: :atom, default: :waiting],
      inbox: [type: {:list, :map}, default: []]
    ],
    signal_routes: [
      {"phial.worker.run", Phial.Swarm.Actions.RunWorker},
      {"phial.worker.message_received", Phial.Swarm.Actions.ReceiveMessage}
    ]
end

defmodule Phial.Swarm.ScoutAgent do
  @moduledoc "Scout worker running in its own AgentServer process."

  use Jido.Agent,
    name: "phial_scout",
    description: "Explores alternatives for a delegated mission",
    schema: [
      status: [type: :atom, default: :waiting],
      inbox: [type: {:list, :map}, default: []]
    ],
    signal_routes: [
      {"phial.worker.run", Phial.Swarm.Actions.RunWorker},
      {"phial.worker.message_received", Phial.Swarm.Actions.ReceiveMessage}
    ]
end
