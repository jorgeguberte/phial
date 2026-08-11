defmodule Phial.Search.WebSearch do
  @moduledoc "Firecrawl Search tool used exclusively by the dedicated SearchAgent."

  use Jido.Action,
    name: "web_search",
    description: """
    Searches the live web with Firecrawl. Use it for current facts, existing
    products, technical evidence and sources. Returns titles, URLs, descriptions
    and compact markdown excerpts. Use a focused query and cite returned URLs.
    """,
    schema: [
      query: [type: :string, required: true, doc: "Focused web search query"],
      limit: [type: :integer, default: 3, doc: "Number of results, from 1 to 5"]
    ]

  @max_results 5
  @excerpt_length 4_000

  @impl true
  def run(%{query: query, limit: limit}, context) do
    started_at = System.monotonic_time(:millisecond)

    try do
      result =
        with :ok <- validate(query, limit),
             {:ok, api_key} <- api_key(context),
             client <- context[:firecrawl_client] || Firecrawl,
             {:ok, response} <-
               client.search_and_scrape(search_params(query, limit), client_options(api_key)),
             {:ok, normalized} <- normalize_response(response, query) do
          {:ok, normalized}
        end

      trace(context, query, limit, result, started_at)
      result
    rescue
      exception ->
        result = {:error, Exception.message(exception)}
        trace(context, query, limit, result, started_at)
        result
    catch
      kind, reason ->
        result = {:error, {kind, reason}}
        trace(context, query, limit, result, started_at)
        result
    end
  end

  defp validate(query, limit)
       when is_binary(query) and query != "" and limit in 1..@max_results,
       do: :ok

  defp validate(_query, _limit), do: {:error, :invalid_web_search}

  defp api_key(%{firecrawl_api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_context) do
    case System.get_env("FIRECRAWL_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, :missing_firecrawl_api_key}
    end
  end

  defp search_params(query, limit) do
    [
      query: query,
      limit: limit,
      sources: ["web"],
      scrape_options: [formats: ["markdown"], only_main_content: true]
    ]
  end

  defp client_options(api_key) do
    case System.get_env("FIRECRAWL_BASE_URL") do
      base_url when is_binary(base_url) and base_url != "" ->
        [api_key: api_key, base_url: base_url]

      _default ->
        [api_key: api_key]
    end
  end

  defp normalize_response(%Req.Response{body: body}, query), do: normalize_body(body, query)
  defp normalize_response(%{body: body}, query), do: normalize_body(body, query)
  defp normalize_response(_response, _query), do: {:error, :unexpected_firecrawl_response}

  defp normalize_body(body, query) when is_map(body) do
    with data when is_map(data) <- field(body, "data"),
         web when is_list(web) <- field(data, "web") do
      {:ok,
       %{
         query: query,
         results: Enum.map(web, &normalize_result/1),
         credits_used: field(body, "creditsUsed"),
         warning: field(body, "warning")
       }}
    else
      _unexpected -> {:error, :unexpected_firecrawl_response}
    end
  end

  defp normalize_body(_body, _query), do: {:error, :unexpected_firecrawl_response}

  defp normalize_result(result) when is_map(result) do
    %{
      title: field(result, "title") || "Untitled result",
      url: field(result, "url"),
      description: field(result, "description"),
      markdown: result |> field("markdown") |> excerpt()
    }
  end

  defp field(map, key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp excerpt(nil), do: nil

  defp excerpt(text) when is_binary(text) do
    if String.length(text) > @excerpt_length do
      String.slice(text, 0, @excerpt_length) <> "\n… [truncated by Phial]"
    else
      text
    end
  end

  defp excerpt(value), do: inspect(value)

  defp trace(context, query, limit, result, started_at) do
    duration_ms = System.monotonic_time(:millisecond) - started_at

    {status, output} =
      case result do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, %{error: inspect(reason)}}
      end

    notify_listener(context, query, limit, status, output, duration_ms)
  end

  defp notify_listener(context, query, limit, status, output, duration_ms) do
    case context[:runtime_listener] do
      listener when is_pid(listener) ->
        send(
          listener,
          {:phial_tool_event, :web_search, :completed,
           %{
             input: %{query: query, limit: limit},
             output: output,
             status: status,
             duration_ms: duration_ms
           }}
        )

      _missing_listener ->
        :ok
    end
  end
end
