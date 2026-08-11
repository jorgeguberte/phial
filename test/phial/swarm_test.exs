defmodule Phial.SwarmTest do
  use ExUnit.Case, async: false

  alias Phial.Swarm

  defmodule FakeReasoner do
    @behaviour Phial.Swarm.Reasoner

    @impl true
    def run(role, prompt) do
      if owner = Application.get_env(:phial, :swarm_test_owner) do
        send(owner, {:reasoner_started, role, self()})
      end

      delays = Application.get_env(:phial, :swarm_test_delays, %{})
      Process.sleep(Map.get(delays, role, 10))
      {:ok, "#{role}: #{prompt}"}
    end

    @impl true
    def synthesize(prompt, results) do
      {:ok, "recommendation for #{prompt} from #{map_size(results)} workers"}
    end
  end

  setup do
    previous_reasoner = Application.get_env(:phial, :swarm_reasoner)
    previous_owner = Application.get_env(:phial, :swarm_test_owner)
    previous_delays = Application.get_env(:phial, :swarm_test_delays)

    Application.put_env(:phial, :swarm_reasoner, FakeReasoner)
    Application.put_env(:phial, :swarm_test_owner, self())
    Application.put_env(:phial, :swarm_test_delays, %{})

    on_exit(fn ->
      restore_env(:swarm_reasoner, previous_reasoner)
      restore_env(:swarm_test_owner, previous_owner)
      restore_env(:swarm_test_delays, previous_delays)
    end)

    :ok
  end

  test "runs three isolated workers concurrently and collects mailbox results" do
    assert {:ok, orchestrator} = Swarm.start("choose a database")
    assert {:ok, snapshot} = Swarm.await(orchestrator, 5_000)

    assert Map.keys(snapshot.state.results) |> Enum.sort() == [:critic, :researcher, :scout]
    assert snapshot.state.results.researcher == "researcher: choose a database"

    assert snapshot.state.recommendation ==
             "recommendation for choose a database from 3 workers"

    assert Enum.all?(snapshot.state.statuses, fn {_role, status} -> status == :done end)
    assert snapshot.state.messages >= 7
    assert snapshot.state.restarts == 0

    GenServer.stop(orchestrator)
  end

  test "exposes the supervised swarm as a chat tool action" do
    assert {:ok, result} =
             Phial.Actions.DelegateToSwarm.run(%{prompt: "choose a database"}, %{})

    assert result.recommendation == "recommendation for choose a database from 3 workers"
    assert Map.keys(result.perspectives) |> Enum.sort() == [:critic, :researcher, :scout]
    assert result.restarts == 0
    assert result.messages >= 7
  end

  test "a killed worker gets a new PID and resumes its assigned mission" do
    Application.put_env(:phial, :swarm_test_delays, %{researcher: 500, critic: 20, scout: 20})

    assert {:ok, orchestrator} = Swarm.start("survive a crash")
    assert_receive {:reasoner_started, :researcher, _execution_pid}, 2_000
    assert {:ok, first_pid} = Jido.Await.get_child(orchestrator, :researcher)

    assert {:ok, ^first_pid} = Swarm.kill(orchestrator, :researcher)
    assert {:ok, second_pid} = await_replacement(orchestrator, :researcher, first_pid, 2_000)
    refute second_pid == first_pid
    assert_receive {:reasoner_started, :researcher, _execution_pid}, 2_000

    assert {:ok, snapshot} = Swarm.await(orchestrator, 5_000)
    assert snapshot.state.results.researcher == "researcher: survive a crash"
    assert snapshot.state.recommendation == "recommendation for survive a crash from 3 workers"
    assert snapshot.state.restarts >= 1

    assert Enum.any?(snapshot.state.events, fn event ->
             event.kind == :worker_restarted and event.role == :researcher
           end)

    GenServer.stop(orchestrator)
  end

  defp restore_env(key, nil), do: Application.delete_env(:phial, key)
  defp restore_env(key, value), do: Application.put_env(:phial, key, value)

  defp await_replacement(orchestrator, role, old_pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_replacement(orchestrator, role, old_pid, deadline)
  end

  defp do_await_replacement(orchestrator, role, old_pid, deadline) do
    case Jido.Await.get_child(orchestrator, role) do
      {:ok, pid} when pid != old_pid ->
        {:ok, pid}

      _other ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(10)
          do_await_replacement(orchestrator, role, old_pid, deadline)
        end
    end
  end
end
