defmodule Phial.ModelConfig do
  @moduledoc "Builds the ReqLLM model spec used by the Phial chat agent."

  @default_model "openai:gpt-5-mini"

  @doc "Builds a model string or an OpenAI-compatible model spec from environment values."
  @spec from_env(map()) :: String.t() | map()
  def from_env(env \\ System.get_env()) when is_map(env) do
    model = present(env["PHIAL_MODEL"]) || @default_model
    base_url = present(env["OPENAI_BASE_URL"])

    case {split_model(model), base_url} do
      {{:openai, id}, url} when is_binary(url) ->
        %{
          provider: :openai,
          id: id,
          base_url: String.trim_trailing(url, "/")
        }

      _other ->
        model
    end
  end

  defp split_model("openai:" <> id) when id != "", do: {:openai, id}
  defp split_model(_model), do: :other

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
end
