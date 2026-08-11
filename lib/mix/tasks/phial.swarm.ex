defmodule Mix.Tasks.Phial.Swarm do
  @shortdoc "Runs a supervised parallel Phial agent swarm"

  @moduledoc """
  Spawns researcher, critic and scout workers as independent BEAM processes.

      mix phial.swarm "Descubra qual banco usar para meu produto"
      mix phial.swarm --kill researcher --kill-after 1500 "Compare bancos"
  """

  use Mix.Task

  alias Phial.Swarm
  alias Phial.Swarm.Inspector

  @switches [kill: :string, kill_after: :integer, timeout: :integer]
  @roles %{"researcher" => :researcher, "critic" => :critic, "scout" => :scout}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, prompt_parts, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    prompt = Enum.join(prompt_parts, " ")
    if prompt == "", do: Mix.raise("usage: mix phial.swarm [options] PROMPT")

    {:ok, orchestrator} = Swarm.start(prompt)

    try do
      maybe_schedule_kill(orchestrator, opts)
      monitor(orchestrator, Keyword.get(opts, :timeout, 300_000))
    after
      if Process.alive?(orchestrator), do: GenServer.stop(orchestrator)
    end
  end

  defp maybe_schedule_kill(_orchestrator, opts) when not is_list(opts), do: :ok

  defp maybe_schedule_kill(orchestrator, opts) do
    case Keyword.get(opts, :kill) do
      nil ->
        :ok

      role_name ->
        role = Map.get(@roles, role_name) || Mix.raise("unknown role: #{role_name}")
        delay = Keyword.get(opts, :kill_after, 1_500)
        owner = self()

        spawn(fn ->
          Process.sleep(delay)
          send(owner, {:kill_result, role, Swarm.kill(orchestrator, role)})
        end)
    end
  end

  defp monitor(orchestrator, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    loop(orchestrator, deadline, nil)
  end

  defp loop(orchestrator, deadline, previous_render) do
    case Swarm.snapshot(orchestrator) do
      {:ok, snapshot} ->
        rendered = Inspector.render_snapshot(snapshot)
        if rendered != previous_render, do: Mix.shell().info("\n#{rendered}")

        if snapshot.state.recommendation != "" do
          print_results(snapshot.state.results, snapshot.state.recommendation)
        else
          receive do
            {:kill_result, role, {:ok, pid}} ->
              Mix.shell().info("\n> kill #{inspect(pid)} (#{role})")
              Mix.shell().info("#{role} crashed\nSupervisor restarting...")

            {:kill_result, role, {:error, reason}} ->
              Mix.shell().error("could not kill #{role}: #{inspect(reason)}")
          after
            150 -> :ok
          end

          if System.monotonic_time(:millisecond) >= deadline do
            Mix.raise("swarm timed out")
          else
            loop(orchestrator, deadline, rendered)
          end
        end

      {:error, :busy} ->
        if System.monotonic_time(:millisecond) >= deadline do
          Mix.raise("swarm timed out while orchestrator was busy")
        else
          Process.sleep(150)
          loop(orchestrator, deadline, previous_render)
        end

      {:error, reason} ->
        Mix.raise("inspector failed: #{inspect(reason)}")
    end
  end

  defp print_results(results, recommendation) do
    Mix.shell().info("\nRESULTS\n")

    Enum.each([:researcher, :critic, :scout], fn role ->
      Mix.shell().info("[#{role}]\n#{Map.fetch!(results, role)}\n")
    end)

    Mix.shell().info("RECOMMENDATION\n\n#{recommendation}")
  end
end
