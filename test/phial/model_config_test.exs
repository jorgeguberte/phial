defmodule Phial.ModelConfigTest do
  use ExUnit.Case, async: true

  alias Phial.ModelConfig

  test "builds an OpenAI-compatible model spec with a custom base URL" do
    env = %{
      "PHIAL_MODEL" => "openai:my-model",
      "OPENAI_BASE_URL" => "http://localhost:8000/v1/"
    }

    assert ModelConfig.from_env(env) == %{
             provider: :openai,
             id: "my-model",
             base_url: "http://localhost:8000/v1"
           }
  end

  test "keeps the regular model string when no custom endpoint is configured" do
    assert ModelConfig.from_env(%{"PHIAL_MODEL" => "openai:gpt-5-mini"}) ==
             "openai:gpt-5-mini"
  end

  test "does not apply an OpenAI endpoint to another provider" do
    env = %{
      "PHIAL_MODEL" => "anthropic:claude-haiku-4-5",
      "OPENAI_BASE_URL" => "http://localhost:8000/v1"
    }

    assert ModelConfig.from_env(env) == "anthropic:claude-haiku-4-5"
  end
end
