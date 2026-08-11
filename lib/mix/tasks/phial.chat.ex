defmodule Mix.Tasks.Phial.Chat do
  @shortdoc "Chats with the Phial AI agent"

  @moduledoc """
  Runs one prompt passed as arguments or opens an interactive conversation.

      mix phial.chat "Cumprimente Ada"
      mix phial.chat
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {:ok, pid} = Phial.start_chat(unique_id())
    Process.put(:phial_chat_pid, pid)

    try do
      case Enum.join(args, " ") do
        "" -> interactive(pid)
        prompt -> ask_and_print(pid, prompt)
      end
    after
      if Process.alive?(pid), do: GenServer.stop(pid)
    end
  end

  defp interactive(pid) do
    Mix.shell().info("Phial iniciado. Digite /sair para encerrar.\n")
    loop(pid)
  end

  defp loop(pid) do
    case IO.gets("você> ") do
      input when input in [:eof, nil] -> :ok
      input -> handle_input(pid, String.trim(input))
    end
  end

  defp handle_input(_pid, input) when input in ["/sair", "/exit", "/quit"], do: :ok
  defp handle_input(pid, ""), do: loop(pid)

  defp handle_input(pid, prompt) do
    ask_and_print(pid, prompt)
    loop(pid)
  end

  defp ask_and_print(pid, prompt) do
    case Phial.chat(pid, prompt,
           allowed_tools: ["greet", "delegate_to_search", "delegate_to_swarm"],
           timeout: 360_000
         ) do
      {:ok, snapshot} -> Mix.shell().info("phial> #{result_text(snapshot)}")
      {:error, reason} -> Mix.raise("chat failed: #{Exception.format_exit(reason)}")
    end
  end

  defp result_text(%{result: result}) when is_binary(result), do: result
  defp result_text(result) when is_binary(result), do: result
  defp result_text(result), do: inspect(result, pretty: true)

  defp unique_id, do: "cli-chat-#{System.unique_integer([:positive, :monotonic])}"
end
