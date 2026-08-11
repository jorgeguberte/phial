defmodule Phial.Actions.DelegateToSearch do
  @moduledoc "Delegates live-web research to a dedicated SearchAgent process."

  use Jido.Action,
    name: "delegate_to_search",
    description: """
    Starts a dedicated web-search agent and returns sourced findings. Use it
    whenever answering accurately requires information outside the conversation
    or facts that may have changed, including recent events, current versions,
    schedules, prices, releases and explicit requests to search or cite sources.
    Do not use it for timeless knowledge or text already supplied by the user.
    """,
    schema: [
      prompt: [
        type: :string,
        required: true,
        doc: "A self-contained description of what the SearchAgent must find"
      ]
    ]

  @impl true
  def run(%{prompt: prompt}, context) do
    listener = context[:runtime_listener]
    input = %{prompt: prompt}

    notify(listener, {:phial_tool_event, :delegate_to_search, :started, %{input: input}})

    id = "search-#{System.unique_integer([:positive, :monotonic])}"

    case Phial.start_search(id) do
      {:ok, search_pid} ->
        notify(listener, {:phial_search_started, search_pid})

        try do
          opts = [
            timeout: 180_000,
            tool_context: %{runtime_listener: listener, from: :search}
          ]

          case Phial.search(search_pid, prompt, opts) do
            {:ok, result} ->
              answer = result_text(result)
              output = %{answer: answer}

              notify(
                listener,
                {:phial_tool_event, :delegate_to_search, :completed,
                 %{input: input, output: output}}
              )

              {:ok, output}

            {:error, reason} ->
              notify_failure(listener, input, reason)
              {:error, reason}
          end
        after
          if Process.alive?(search_pid), do: GenServer.stop(search_pid)
          notify(listener, {:phial_search_stopped, search_pid})
        end

      {:error, reason} ->
        notify_failure(listener, input, reason)
        {:error, reason}
    end
  end

  defp result_text(%{result: result}) when is_binary(result), do: result
  defp result_text(result) when is_binary(result), do: result
  defp result_text(result), do: inspect(result, pretty: true)

  defp notify_failure(listener, input, reason) do
    notify(
      listener,
      {:phial_tool_event, :delegate_to_search, {:failed, reason},
       %{input: input, output: %{error: inspect(reason)}}}
    )
  end

  defp notify(pid, message) when is_pid(pid), do: send(pid, message)
  defp notify(_listener, _message), do: :ok
end
