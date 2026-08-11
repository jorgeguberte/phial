defmodule Phial.Swarm.WebSearchTest do
  use ExUnit.Case, async: true

  alias Phial.Swarm.WebSearch

  defmodule FakeFirecrawl do
    def search_and_scrape(params, opts) do
      send(self(), {:firecrawl_called, params, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "success" => true,
           "creditsUsed" => 2,
           "data" => %{
             "web" => [
               %{
                 "title" => "OTP Design Principles",
                 "url" => "https://www.erlang.org/doc/system/design_principles.html",
                 "description" => "Official Erlang documentation",
                 "markdown" => "# OTP\nSupervision and processes."
               }
             ]
           }
         }
       }}
    end
  end

  defmodule FailingFirecrawl do
    def search_and_scrape(_params, _opts), do: {:error, :rate_limited}
  end

  test "searches through Firecrawl and returns compact source data" do
    assert {:ok, result} =
             WebSearch.run(
               %{query: "Erlang OTP supervision", limit: 2},
               %{firecrawl_client: FakeFirecrawl, firecrawl_api_key: "fc-test"}
             )

    assert_receive {:firecrawl_called, params, [api_key: "fc-test"]}
    assert params[:query] == "Erlang OTP supervision"
    assert params[:limit] == 2
    assert params[:sources] == ["web"]
    assert params[:scrape_options][:formats] == ["markdown"]

    assert result.credits_used == 2
    assert [source] = result.results
    assert source.title == "OTP Design Principles"
    assert source.url == "https://www.erlang.org/doc/system/design_principles.html"
    assert source.markdown =~ "Supervision"
  end

  test "validates limits and surfaces client failures" do
    assert {:error, :invalid_web_search} =
             WebSearch.run(
               %{query: "too many", limit: 6},
               %{firecrawl_client: FakeFirecrawl, firecrawl_api_key: "fc-test"}
             )

    assert {:error, :rate_limited} =
             WebSearch.run(
               %{query: "current database options", limit: 3},
               %{firecrawl_client: FailingFirecrawl, firecrawl_api_key: "fc-test"}
             )
  end

  test "exposes web search only to the Scout" do
    assert Phial.Swarm.Reasoner.tools_for(:scout) == [
             Phial.Swarm.SendMessage,
             Phial.Swarm.WebSearch
           ]

    assert Phial.Swarm.Reasoner.tools_for(:researcher) == [Phial.Swarm.SendMessage]
    assert Phial.Swarm.Reasoner.tools_for(:critic) == [Phial.Swarm.SendMessage]
  end

  test "records Firecrawl calls as worker tool trace events" do
    params = %{
      role: :scout,
      tool: :web_search,
      input: %{query: "BEAM agents", limit: 3},
      output: %{results: []},
      status: :ok,
      duration_ms: 42
    }

    assert {:ok, updates} =
             Phial.Swarm.Actions.RecordToolTrace.run(params, %{
               state: %{messages: 4, events: []}
             })

    assert updates.messages == 5
    assert [event] = updates.events
    assert event.kind == :worker_tool
    assert event.role == :scout
    assert event.input.query == "BEAM agents"
    assert event.duration_ms == 42
  end
end
