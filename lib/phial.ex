defmodule Phial do
  @moduledoc """
  Public API for the Phial greeting agent.

  Each agent ID identifies a long-lived OTP process whose greeting count is kept
  in the agent state.
  """

  alias Phial.GreeterAgent
  alias Phial.ChatAgent

  @doc "Starts a greeter agent with the given ID."
  @spec start_agent(String.t()) :: DynamicSupervisor.on_start_child()
  def start_agent(id \\ "greeter") do
    Phial.Jido.start_agent(GreeterAgent, id: id)
  end

  @doc "Sends a greeting signal to a running greeter agent."
  @spec greet(pid(), String.t()) :: {:ok, Jido.Agent.t()} | {:error, term()}
  def greet(pid, name) when is_pid(pid) and is_binary(name) do
    signal = Jido.Signal.new!("greet", %{name: name}, source: "/phial/user")
    Jido.AgentServer.call(pid, signal)
  end

  @doc "Starts an agent, greets one person, then stops the agent."
  @spec greet_once(String.t()) :: {:ok, Jido.Agent.t()} | {:error, term()}
  def greet_once(name) when is_binary(name) do
    id = "greeter-#{System.unique_integer([:positive, :monotonic])}"

    with {:ok, pid} <- start_agent(id),
         result <- greet(pid, name) do
      GenServer.stop(pid)
      result
    end
  end

  @doc "Starts a long-lived conversational AI agent."
  @spec start_chat(String.t()) :: DynamicSupervisor.on_start_child()
  def start_chat(id \\ "chat") do
    Phial.Jido.start_agent(ChatAgent, id: id)
  end

  @doc "Asks the conversational agent a question and waits for its final snapshot."
  @spec chat(pid(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def chat(pid, prompt, opts \\ [])

  def chat(pid, prompt, opts) when is_pid(pid) and is_binary(prompt) and is_list(opts) do
    ChatAgent.ask_sync(pid, prompt, opts)
  end

  @doc "Starts a conversational agent, performs one turn, then stops it."
  @spec chat_once(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def chat_once(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    id = "chat-#{System.unique_integer([:positive, :monotonic])}"

    with {:ok, pid} <- start_chat(id),
         result <- chat(pid, prompt, opts) do
      GenServer.stop(pid)
      result
    end
  end
end
