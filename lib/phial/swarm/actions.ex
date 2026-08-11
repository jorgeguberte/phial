defmodule Phial.Swarm.Actions.StartMission do
  @moduledoc false

  use Jido.Action,
    name: "start_swarm_mission",
    description: "Spawns the parallel worker team",
    schema: [prompt: [type: :string, required: true]]

  alias Jido.Agent.Directive
  alias Phial.Swarm.Roles

  @impl true
  def run(%{prompt: prompt}, _context) do
    statuses = Map.new(Roles.all(), fn {role, _module} -> {role, :starting} end)

    directives =
      Enum.map(Roles.all(), fn {role, module} ->
        Directive.spawn_agent(module, role,
          meta: %{role: role},
          restart: :transient
        )
      end)

    {:ok,
     %{
       prompt: prompt,
       statuses: statuses,
       pids: %{},
       results: %{},
       recommendation: "",
       messages: 1,
       a2a: 0,
       a2a_sent: %{},
       restarts: 0,
       events: [
         %{kind: :mission_started, input: %{prompt: prompt}, at: now()}
       ]
     }, directives}
  end

  defp now, do: System.monotonic_time(:millisecond)
end

defmodule Phial.Swarm.Actions.ChildStarted do
  @moduledoc false

  use Jido.Action,
    name: "swarm_child_started",
    description: "Tracks a worker PID and dispatches its mission",
    schema: [
      parent_id: [type: :string, required: true],
      child_id: [type: :string, required: true],
      child_module: [type: :atom, required: true],
      tag: [type: :any, required: true],
      pid: [type: :any, required: true],
      meta: [type: :map, default: %{}],
      child_partition: [type: :any]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  @impl true
  def run(%{tag: role, pid: pid}, context) when is_atom(role) and is_pid(pid) do
    state = context.state
    previous_pid = state.pids[role]
    restarted? = is_pid(previous_pid) and previous_pid != pid
    completed? = Map.has_key?(state.results, role)

    updates = %{
      pids: Map.put(state.pids, role, pid),
      statuses: Map.put(state.statuses, role, if(completed?, do: :done, else: :thinking)),
      restarts: state.restarts + if(restarted?, do: 1, else: 0),
      messages: state.messages + 1,
      events:
        push_event(state.events, %{
          kind: if(restarted?, do: :worker_restarted, else: :worker_started),
          role: role,
          pid: pid,
          previous_pid: previous_pid,
          input: %{role: role, prompt: state.prompt},
          at: now()
        })
    }

    directives =
      if completed? do
        []
      else
        signal =
          Signal.new!("phial.worker.run", %{prompt: state.prompt},
            source: "/agent/#{context.agent.id}"
          )

        [Directive.emit_to_pid(signal, pid)]
      end

    {:ok, updates, directives}
  end

  def run(_params, _context), do: {:error, :invalid_child_started_signal}

  defp push_event(events, event), do: Enum.take([event | events], 50)
  defp now, do: System.monotonic_time(:millisecond)
end

defmodule Phial.Swarm.Actions.ChildExited do
  @moduledoc false

  use Jido.Action,
    name: "swarm_child_exited",
    description: "Records an individual worker exit",
    schema: [
      tag: [type: :any, required: true],
      pid: [type: :any, required: true],
      reason: [type: :any, required: true]
    ]

  @impl true
  def run(%{tag: role, pid: pid, reason: reason}, context) do
    completed? = Map.has_key?(context.state.results, role)

    {:ok,
     %{
       statuses: Map.put(context.state.statuses, role, if(completed?, do: :done, else: :crashed)),
       messages: context.state.messages + 1,
       events:
         Enum.take(
           [
             %{
               kind: if(completed?, do: :worker_stopped, else: :worker_crashed),
               role: role,
               pid: pid,
               reason: reason,
               output: %{reason: reason},
               at: System.monotonic_time(:millisecond)
             }
             | context.state.events
           ],
           50
         )
     }}
  end
end

defmodule Phial.Swarm.Actions.RecordResult do
  @moduledoc false

  use Jido.Action,
    name: "record_swarm_result",
    description: "Stores a result sent directly by a worker",
    schema: [
      role: [type: :atom, required: true],
      pid: [type: :any, required: true],
      result: [type: :string, required: true]
    ]

  @impl true
  def run(%{role: role, pid: pid, result: result}, context) do
    results = Map.put(context.state.results, role, result)
    recommendation = maybe_synthesize(context.state.prompt, results)

    updates = %{
      results: results,
      recommendation: recommendation,
      statuses: Map.put(context.state.statuses, role, :done),
      messages: context.state.messages + 1,
      events:
        Enum.take(
          [
            %{
              kind: :worker_result,
              role: role,
              pid: pid,
              input: %{role: role, prompt: context.state.prompt},
              output: result,
              at: System.monotonic_time(:millisecond)
            }
            | context.state.events
          ],
          50
        )
    }

    {:ok, updates, [Jido.Agent.Directive.stop_child(role, :completed)]}
  end

  defp maybe_synthesize(_prompt, results) when map_size(results) < 3, do: ""

  defp maybe_synthesize(prompt, results) do
    reasoner = Application.get_env(:phial, :swarm_reasoner, Phial.Swarm.Reasoner)

    case reasoner.synthesize(prompt, results) do
      {:ok, recommendation} when is_binary(recommendation) -> recommendation
      {:error, reason} -> "Synthesis failed: #{inspect(reason)}"
      other -> "Unexpected synthesis result: #{inspect(other)}"
    end
  end
end

defmodule Phial.Swarm.Actions.RunWorker do
  @moduledoc false

  use Jido.Action,
    name: "run_swarm_worker",
    description: "Runs one role-specific ReAct loop and reports to the parent",
    schema: [prompt: [type: :string, required: true]]

  alias Jido.Agent.Directive
  alias Jido.Signal
  alias Phial.Swarm.{Reasoner, Roles}

  @impl true
  def run(%{prompt: prompt}, context) do
    role = Roles.role_for(context.agent.agent_module)
    reasoner = Application.get_env(:phial, :swarm_reasoner, Reasoner)
    worker_pid = context[:agent_server_pid]

    case parent_pid(context.agent) do
      {:ok, parent_pid} ->
        child_spec =
          Task.child_spec(fn ->
            execute(reasoner, role, prompt, worker_pid, parent_pid, context.agent.id)
          end)

        {:ok, %{status: :thinking}, [Directive.spawn(child_spec, {:worker_reasoner, role})]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def execute(reasoner, role, prompt, worker_pid, parent_pid, agent_id) do
    result =
      case run_while_agent_alive(reasoner, role, prompt, worker_pid, parent_pid) do
        {:ok, text} when is_binary(text) -> text
        {:error, reason} -> "Worker failed: #{inspect(reason)}"
        other -> "Unexpected worker result: #{inspect(other)}"
      end

    if is_pid(worker_pid) and Process.alive?(worker_pid) and Process.alive?(parent_pid) do
      signal =
        Signal.new!(
          "phial.worker.result",
          %{role: role, pid: worker_pid, result: result},
          source: "/agent/#{agent_id}"
        )

      Jido.AgentServer.cast(parent_pid, signal)
    end
  end

  defp run_while_agent_alive(reasoner, role, prompt, agent_server_pid, parent_pid)
       when is_pid(agent_server_pid) do
    tool_context = %{parent_pid: parent_pid, from: role}
    task = Task.async(fn -> invoke_reasoner(reasoner, role, prompt, tool_context) end)
    agent_ref = Process.monitor(agent_server_pid)

    receive do
      {task_ref, result} when task_ref == task.ref ->
        Process.demonitor(agent_ref, [:flush])
        Process.demonitor(task.ref, [:flush])
        result

      {:DOWN, ^agent_ref, :process, ^agent_server_pid, reason} ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:agent_server_down, reason}}

      {:DOWN, task_ref, :process, _pid, reason} when task_ref == task.ref ->
        Process.demonitor(agent_ref, [:flush])
        {:error, {:reasoner_crashed, reason}}
    end
  end

  defp run_while_agent_alive(reasoner, role, prompt, _agent_server_pid, parent_pid) do
    invoke_reasoner(reasoner, role, prompt, %{parent_pid: parent_pid, from: role})
  end

  defp invoke_reasoner(reasoner, role, prompt, tool_context) do
    if Code.ensure_loaded?(reasoner) and function_exported?(reasoner, :run, 3) do
      reasoner.run(role, prompt, tool_context)
    else
      reasoner.run(role, prompt)
    end
  end

  defp parent_pid(%{state: %{__parent__: %{pid: pid}}}) when is_pid(pid), do: {:ok, pid}
  defp parent_pid(_agent), do: {:error, :worker_has_no_parent}
end
