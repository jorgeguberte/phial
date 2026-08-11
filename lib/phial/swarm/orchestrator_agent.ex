defmodule Phial.Swarm.OrchestratorAgent do
  @moduledoc "Owns a mission and supervises a short-lived team of worker agents."

  use Jido.Agent,
    name: "phial_orchestrator",
    description: "Spawns, monitors and collects results from a parallel agent team",
    schema: [
      prompt: [type: :string, default: ""],
      statuses: [type: :map, default: %{}],
      pids: [type: :map, default: %{}],
      results: [type: :map, default: %{}],
      recommendation: [type: :string, default: ""],
      messages: [type: :integer, default: 0],
      a2a: [type: :integer, default: 0],
      a2a_sent: [type: :map, default: %{}],
      restarts: [type: :integer, default: 0],
      events: [type: {:list, :map}, default: []]
    ],
    signal_routes: [
      {"phial.swarm.start", Phial.Swarm.Actions.StartMission},
      {"jido.agent.child.started", Phial.Swarm.Actions.ChildStarted},
      {"jido.agent.child.exit", Phial.Swarm.Actions.ChildExited},
      {"phial.worker.message", Phial.Swarm.Actions.RouteMessage},
      {"phial.worker.tool_trace", Phial.Swarm.Actions.RecordToolTrace},
      {"phial.worker.result", Phial.Swarm.Actions.RecordResult}
    ]
end
