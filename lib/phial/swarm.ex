defmodule Phial.Swarm do
  @moduledoc "Public runtime API for supervised parallel agent missions."

  alias Phial.Swarm.OrchestratorAgent

  @roles [:researcher, :critic, :scout]

  @spec start(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    id = Keyword.get(opts, :id, "swarm-#{System.unique_integer([:positive, :monotonic])}")

    with {:ok, pid} <- Phial.Jido.start_agent(OrchestratorAgent, id: id),
         signal <- Jido.Signal.new!("phial.swarm.start", %{prompt: prompt}, source: "/phial/user"),
         {:ok, _agent} <- Jido.AgentServer.call(pid, signal) do
      {:ok, pid}
    end
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(pid) when is_pid(pid) do
    with {:ok, server_state} <- safe_server_state(pid) do
      {:ok,
       %{
         pid: pid,
         id: server_state.id,
         status: server_state.status,
         children: Map.new(server_state.children, fn {tag, child} -> {tag, child.pid} end),
         state: server_state.agent.state
       }}
    end
  end

  defp safe_server_state(pid) do
    GenServer.call(pid, :get_state, 500)
  catch
    :exit, {:timeout, _details} -> {:error, :busy}
    :exit, {:noproc, _details} -> {:error, :not_found}
    :exit, reason -> {:error, reason}
  end

  @spec await(pid(), timeout()) :: {:ok, map()} | {:error, term()}
  def await(pid, timeout \\ 120_000) when is_pid(pid) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await(pid, deadline)
  end

  @spec kill(pid(), atom()) :: {:ok, pid()} | {:error, term()}
  def kill(orchestrator, role) when is_pid(orchestrator) and role in @roles do
    with {:ok, child_pid} <- Jido.Await.get_child(orchestrator, role) do
      Process.exit(child_pid, :kill)
      {:ok, child_pid}
    end
  end

  defp do_await(pid, deadline) do
    case snapshot(pid) do
      {:ok, %{state: %{recommendation: recommendation}} = snapshot}
      when is_binary(recommendation) and recommendation != "" ->
        {:ok, snapshot}

      {:ok, _snapshot} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(25)
          do_await(pid, deadline)
        end

      {:error, :busy} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(50)
          do_await(pid, deadline)
        end

      {:error, _reason} = error ->
        error
    end
  end
end
