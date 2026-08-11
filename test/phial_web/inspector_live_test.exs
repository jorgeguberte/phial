defmodule PhialWeb.InspectorLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Phial.Swarm

  @endpoint PhialWeb.Endpoint

  defmodule FakeReasoner do
    @behaviour Phial.Swarm.Reasoner

    @impl true
    def run(role, prompt) do
      Process.sleep(500)
      {:ok, "#{role}: #{prompt}"}
    end

    @impl true
    def synthesize(prompt, results) do
      {:ok, "recommendation for #{prompt} from #{map_size(results)} workers"}
    end
  end

  setup do
    previous_reasoner = Application.get_env(:phial, :swarm_reasoner)
    Application.put_env(:phial, :swarm_reasoner, FakeReasoner)

    on_exit(fn ->
      if previous_reasoner do
        Application.put_env(:phial, :swarm_reasoner, previous_reasoner)
      else
        Application.delete_env(:phial, :swarm_reasoner)
      end
    end)

    :ok
  end

  test "renders the single-page runtime inspector" do
    assert {:ok, view, html} = live(build_conn(), "/")

    assert html =~ "Process graph"
    assert html =~ "Event stream"
    assert has_element?(view, "#phial-prompt")
    assert has_element?(view, "form[phx-submit=submit]")
    assert render(view) =~ "Send a prompt to wake the process tree"
  end

  test "shows real PIDs, A2A traffic and a supervised worker restart" do
    assert {:ok, view, _html} = live(build_conn(), "/")
    assert {:ok, orchestrator} = Swarm.start("inspect the runtime")

    on_exit(fn ->
      if Process.alive?(orchestrator), do: GenServer.stop(orchestrator)
    end)

    send(view.pid, {:phial_swarm_started, orchestrator})

    assert_eventually(fn ->
      has_element?(view, "#agent-researcher code", "#PID") and
        has_element?(view, "#kill-critic")
    end)

    assert {:ok, _queued} =
             Phial.Swarm.SendMessage.run(
               %{to: "critic", kind: "evidence", content: "runtime evidence"},
               %{parent_pid: orchestrator, from: :researcher}
             )

    assert_eventually(fn -> render(view) =~ "researcher → critic · evidence" end)

    assert {:ok, critic_pid} = await_child(orchestrator, :critic, 2_000)
    render_click(element(view, "#kill-critic"))
    assert {:ok, replacement_pid} = await_replacement(orchestrator, :critic, critic_pid, 2_000)
    refute replacement_pid == critic_pid
    assert {:ok, replacement_snapshot} = Swarm.snapshot(orchestrator)
    send(view.pid, {:runtime_signal, %{agent_id: replacement_snapshot.id}})

    replacement_html = render(view)
    critic_card = render(element(view, "#agent-critic"))
    assert critic_card =~ "#PID"
    refute critic_card =~ inspect(critic_pid)
    assert replacement_html =~ "Critic restarted", replacement_html

    assert {:ok, completed} = Swarm.await(orchestrator, 5_000)
    send(view.pid, {:phial_swarm_completed, completed})
    send(view.pid, {:phial_chat_result, {:ok, completed.state.recommendation}})
    assert_eventually(fn -> render(view) =~ "recommendation for inspect the runtime" end)
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
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
end
