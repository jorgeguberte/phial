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
    def run(role, prompt, context) do
      if owner = Application.get_env(:phial, :swarm_test_owner) do
        send(owner, {:reasoner_context, role, context})
      end

      run(role, prompt)
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
    assert {:ok, orchestrator} = start_swarm("choose a database")
    assert {:ok, snapshot} = Swarm.await(orchestrator, 5_000)

    assert Map.keys(snapshot.state.results) |> Enum.sort() == [:critic, :researcher, :scout]
    assert snapshot.state.results.researcher == "researcher: choose a database"

    assert snapshot.state.recommendation ==
             "recommendation for choose a database from 3 workers"

    assert Enum.all?(snapshot.state.statuses, fn {_role, status} -> status == :done end)
    assert snapshot.state.messages >= 7
    assert snapshot.state.restarts == 0

    mission_event = Enum.find(snapshot.state.events, &(&1.kind == :mission_started))

    researcher_event =
      Enum.find(snapshot.state.events, &(&1.kind == :worker_result and &1.role == :researcher))

    assert mission_event.input == %{prompt: "choose a database"}
    assert researcher_event.input == %{role: :researcher, prompt: "choose a database"}
    assert researcher_event.output == "researcher: choose a database"

    GenServer.stop(orchestrator)
  end

  test "exposes the supervised swarm as a chat tool action" do
    assert {:ok, result} =
             Phial.Actions.DelegateToSwarm.run(%{prompt: "choose a database"}, %{
               runtime_listener: self()
             })

    assert result.recommendation == "recommendation for choose a database from 3 workers"
    assert Map.keys(result.perspectives) |> Enum.sort() == [:critic, :researcher, :scout]
    assert result.restarts == 0
    assert result.messages >= 7

    assert_receive {:phial_tool_event, :delegate_to_swarm, :started,
                    %{input: %{prompt: "choose a database"}}}

    assert_receive {:phial_tool_event, :delegate_to_swarm, :completed,
                    %{input: %{prompt: "choose a database"}, output: output}}

    assert output.recommendation == result.recommendation
  end

  test "a killed worker gets a new PID and resumes its assigned mission" do
    Application.put_env(:phial, :swarm_test_delays, %{researcher: 500, critic: 500, scout: 20})

    assert {:ok, orchestrator} = start_swarm("survive a crash")
    assert_receive {:reasoner_started, :researcher, _execution_pid}, 2_000

    assert_receive {:reasoner_context, :researcher,
                    %{parent_pid: ^orchestrator, from: :researcher}},
                   2_000

    assert {:ok, first_pid} = await_child(orchestrator, :researcher, 2_000)
    assert {:ok, critic_pid} = await_child(orchestrator, :critic, 2_000)

    assert {:ok, %{sent: true}} =
             Phial.Swarm.SendMessage.run(
               %{to: "critic", kind: "evidence", content: "primary evidence"},
               %{parent_pid: orchestrator, from: :researcher}
             )

    assert {:ok, inbox} = await_inbox(critic_pid, 1, 2_000)

    assert inbox == [
             %{
               from: :researcher,
               to: :critic,
               kind: :evidence,
               content: "primary evidence"
             }
           ]

    assert {:ok, message_snapshot} = await_a2a(orchestrator, 1, 2_000)
    assert message_snapshot.state.a2a == 1

    message_event = Enum.find(message_snapshot.state.events, &(&1.kind == :a2a_message))
    assert message_event.input.content == "primary evidence"
    assert message_event.output.delivered
    assert message_event.output.pid == critic_pid

    inspector = Phial.Swarm.Inspector.render_snapshot(message_snapshot)
    assert inspector =~ "A2A:      1"
    assert inspector =~ "researcher → critic"

    assert {:ok, ^critic_pid} = Swarm.kill(orchestrator, :critic)
    assert {:ok, new_critic_pid} = await_replacement(orchestrator, :critic, critic_pid, 2_000)
    refute new_critic_pid == critic_pid

    assert {:ok, ^first_pid} = Swarm.kill(orchestrator, :researcher)
    assert {:ok, second_pid} = await_replacement(orchestrator, :researcher, first_pid, 2_000)
    refute second_pid == first_pid
    assert_receive {:reasoner_started, :researcher, _execution_pid}, 2_000

    assert {:ok, snapshot} = Swarm.await(orchestrator, 5_000)
    assert snapshot.state.results.researcher == "researcher: survive a crash"
    assert snapshot.state.recommendation == "recommendation for survive a crash from 3 workers"
    assert snapshot.state.restarts >= 2
    assert snapshot.state.a2a == 1

    assert Enum.any?(snapshot.state.events, fn event ->
             event.kind == :worker_restarted and event.role == :researcher
           end)

    GenServer.stop(orchestrator)
  end

  test "routes at most two A2A messages per sender" do
    Application.put_env(:phial, :swarm_test_delays, %{researcher: 500, critic: 500, scout: 500})

    assert {:ok, orchestrator} = start_swarm("limit messages")
    assert {:ok, critic_pid} = await_child(orchestrator, :critic, 2_000)

    Enum.each(1..3, fn number ->
      assert {:ok, %{sent: true}} =
               Phial.Swarm.SendMessage.run(
                 %{to: "critic", kind: "evidence", content: "evidence #{number}"},
                 %{parent_pid: orchestrator, from: :researcher}
               )
    end)

    assert {:ok, inbox} = await_inbox(critic_pid, 2, 2_000)
    Process.sleep(50)
    {:ok, critic_state} = GenServer.call(critic_pid, :get_state)
    final_inbox = critic_state.agent.state.inbox
    assert Enum.map(inbox, & &1.content) |> Enum.sort() == ["evidence 1", "evidence 2"]
    assert final_inbox == inbox

    assert {:ok, snapshot} = await_a2a(orchestrator, 2, 2_000)
    assert snapshot.state.a2a == 2
    assert snapshot.state.a2a_sent.researcher == 2

    assert {:ok, _completed} = Swarm.await(orchestrator, 5_000)
    GenServer.stop(orchestrator)
  end

  defp restore_env(key, nil), do: Application.delete_env(:phial, key)
  defp restore_env(key, value), do: Application.put_env(:phial, key, value)

  defp start_swarm(prompt) do
    with {:ok, orchestrator} <- Swarm.start(prompt) do
      on_exit(fn ->
        if Process.alive?(orchestrator), do: GenServer.stop(orchestrator)
      end)

      {:ok, orchestrator}
    end
  end

  defp await_child(orchestrator, role, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_child(orchestrator, role, deadline)
  end

  defp do_await_child(orchestrator, role, deadline) do
    case Jido.Await.get_child(orchestrator, role) do
      {:ok, pid} ->
        {:ok, pid}

      _other ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(10)
          do_await_child(orchestrator, role, deadline)
        end
    end
  end

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

  defp await_inbox(worker, expected_count, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_inbox(worker, expected_count, deadline)
  end

  defp do_await_inbox(worker, expected_count, deadline) do
    {:ok, server_state} = GenServer.call(worker, :get_state)
    inbox = server_state.agent.state.inbox

    cond do
      length(inbox) >= expected_count ->
        {:ok, inbox}

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timeout}

      true ->
        Process.sleep(10)
        do_await_inbox(worker, expected_count, deadline)
    end
  end

  defp await_a2a(orchestrator, expected_count, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_a2a(orchestrator, expected_count, deadline)
  end

  defp do_await_a2a(orchestrator, expected_count, deadline) do
    case Swarm.snapshot(orchestrator) do
      {:ok, %{state: %{a2a: count}} = snapshot} when count >= expected_count ->
        {:ok, snapshot}

      _other ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(10)
          do_await_a2a(orchestrator, expected_count, deadline)
        end
    end
  end
end
