defmodule PhialWeb.InspectorLive do
  @moduledoc "Live runtime inspector for a Phial agent swarm."

  use PhialWeb, :live_view

  alias Phial.Swarm

  @roles [:researcher, :critic, :scout]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        chat_pid: nil,
        chat_ref: nil,
        orchestrator: nil,
        orchestrator_ref: nil,
        snapshot: nil,
        roles: @roles,
        run_started_at: nil,
        run_status: :idle,
        messages: [
          message(:assistant, "Ask a real question. I’ll show you every process it wakes up.")
        ],
        local_events: []
      )

    if connected?(socket) do
      :ok = Phial.RuntimeEvents.subscribe()
      {:ok, chat_pid} = Phial.start_chat("web-chat-#{unique_id()}")
      chat_ref = Process.monitor(chat_pid)
      {:ok, assign(socket, chat_pid: chat_pid, chat_ref: chat_ref)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("submit", %{"prompt" => prompt}, socket) do
    prompt = String.trim(prompt)

    cond do
      prompt == "" ->
        {:noreply, socket}

      socket.assigns.run_status in [:dispatching, :running] ->
        {:noreply, put_flash(socket, :error, "A run is already active.")}

      true ->
        listener = self()
        chat_pid = socket.assigns.chat_pid

        {:ok, _task} =
          Task.Supervisor.start_child(PhialWeb.TaskSupervisor, fn ->
            result =
              Phial.chat(chat_pid, prompt,
                allowed_tools: ["greet", "delegate_to_swarm"],
                timeout: 360_000,
                tool_context: %{runtime_listener: listener}
              )

            send(listener, {:phial_chat_result, result})
          end)

        {:noreply,
         assign(socket,
           run_status: :dispatching,
           messages: socket.assigns.messages ++ [message(:user, prompt)],
           local_events: [runtime_event(:chat, "Prompt dispatched")],
           snapshot: nil,
           orchestrator: nil,
           orchestrator_ref: nil,
           run_started_at: System.monotonic_time(:millisecond)
         )}
    end
  end

  def handle_event("kill", %{"role" => role}, socket) do
    with {:ok, role} <- parse_role(role),
         orchestrator when is_pid(orchestrator) <- socket.assigns.orchestrator,
         {:ok, killed_pid} <- Swarm.kill(orchestrator, role) do
      event = runtime_event(:kill, "Killed #{role} #{inspect(killed_pid)}")
      {:noreply, update(socket, :local_events, &[event | &1])}
    else
      _error -> {:noreply, put_flash(socket, :error, "That process is no longer alive.")}
    end
  end

  @impl true
  def handle_info({:phial_tool_event, :delegate_to_swarm, :started}, socket) do
    event = runtime_event(:tool, "delegate_to_swarm called")

    {:noreply,
     assign(socket, run_status: :running, local_events: [event | socket.assigns.local_events])}
  end

  def handle_info({:phial_tool_event, :delegate_to_swarm, :completed}, socket) do
    event = runtime_event(:tool, "delegate_to_swarm completed")
    {:noreply, update(socket, :local_events, &[event | &1])}
  end

  def handle_info({:phial_tool_event, :delegate_to_swarm, {:failed, reason}}, socket) do
    event = runtime_event(:error, "delegate_to_swarm failed: #{inspect(reason)}")

    {:noreply,
     assign(socket, run_status: :failed, local_events: [event | socket.assigns.local_events])}
  end

  def handle_info({:phial_swarm_started, orchestrator}, socket) do
    orchestrator_ref = Process.monitor(orchestrator)

    socket =
      socket
      |> assign(
        orchestrator: orchestrator,
        orchestrator_ref: orchestrator_ref,
        run_status: :running
      )
      |> refresh_snapshot()

    {:noreply, socket}
  end

  def handle_info({:phial_swarm_completed, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot, run_status: :synthesizing)}
  end

  def handle_info({:phial_chat_result, {:ok, result}}, socket) do
    answer = result_text(result)

    {:noreply,
     assign(socket,
       run_status: :done,
       messages: socket.assigns.messages ++ [message(:assistant, answer)]
     )}
  end

  def handle_info({:phial_chat_result, {:error, reason}}, socket) do
    event = runtime_event(:error, "Chat failed: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       run_status: :failed,
       local_events: [event | socket.assigns.local_events],
       messages:
         socket.assigns.messages ++
           [message(:assistant, "The run failed before a response was produced.")]
     )}
  end

  def handle_info({:runtime_signal, metadata}, socket) do
    if relevant_signal?(metadata, socket.assigns.snapshot) do
      {:noreply, refresh_snapshot(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{chat_ref: ref}} = socket) do
    {:noreply, assign(socket, chat_pid: nil, chat_ref: nil, run_status: :failed)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{orchestrator_ref: ref}} = socket
      ) do
    {:noreply, assign(socket, orchestrator: nil, orchestrator_ref: nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    if is_pid(socket.assigns.chat_pid) and Process.alive?(socket.assigns.chat_pid) do
      GenServer.stop(socket.assigns.chat_pid)
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="runtime-shell">
      <header class="topbar">
        <div class="brand-lockup">
          <div class="brand-mark" aria-hidden="true"><span></span></div>
          <div>
            <p class="eyebrow">BEAM agent runtime</p>
            <h1>PHIAL</h1>
          </div>
        </div>

        <div class="runtime-summary" aria-label="Runtime summary">
          <span class={["connection-dot", connected_class(@chat_pid)]}></span>
          <span><strong>{agent_count(@snapshot)}</strong> agents</span>
          <span class="summary-divider">·</span>
          <span><strong>{if @snapshot, do: 1, else: 0}</strong> run</span>
          <span class={["run-state", "run-state--#{@run_status}"]}>{state_label(@run_status)}</span>
        </div>
      </header>

      <main class="workspace">
        <section class="graph-panel" aria-labelledby="process-graph-title">
          <div class="panel-heading">
            <div>
              <p class="eyebrow">Live topology</p>
              <h2 id="process-graph-title">Process graph</h2>
            </div>
            <div class="metric-cluster">
              <.metric label="messages" value={state_value(@snapshot, :messages)} />
              <.metric label="A2A" value={state_value(@snapshot, :a2a)} />
              <.metric label="restarts" value={state_value(@snapshot, :restarts)} />
            </div>
          </div>

          <div class={["process-tree", @snapshot && "process-tree--active"]}>
            <div class="orchestrator-wrap">
              <article class="agent-card agent-card--orchestrator">
                <div class="card-topline">
                  <span class="agent-kind">Parent</span>
                  <.status status={orchestrator_status(@snapshot)} />
                </div>
                <div class="agent-identity">
                  <div class="agent-glyph agent-glyph--orchestrator" aria-hidden="true">O</div>
                  <div>
                    <h3>Orchestrator</h3>
                    <code title={pid_text(orchestrator_pid(@snapshot))}>{pid_text(
                      orchestrator_pid(@snapshot)
                    )}</code>
                  </div>
                </div>
                <p class="agent-meta">parent: supervisor · children: {alive_children(@snapshot)}</p>
              </article>
            </div>

            <div class="tree-rail" aria-hidden="true"></div>

            <div class="worker-grid">
              <.worker_card
                :for={role <- @roles}
                role={role}
                data={role_data(@snapshot, role)}
                can_kill={can_kill?(@snapshot, role, @orchestrator)}
              />
            </div>

            <div :if={!@snapshot} class="empty-state">
              <div class="empty-pulse"><span></span><span></span><span></span></div>
              <p>Send a prompt to wake the process tree.</p>
              <span>Try “Use a swarm to compare SQLite and PostgreSQL.”</span>
            </div>
          </div>

          <div :if={latest_answer(@messages)} class="answer-strip">
            <span class="answer-label">Phial</span>
            <p>{latest_answer(@messages)}</p>
          </div>
        </section>

        <aside class="event-panel" aria-labelledby="event-stream-title">
          <div class="panel-heading panel-heading--events">
            <div>
              <p class="eyebrow">Mailbox activity</p>
              <h2 id="event-stream-title">Event stream</h2>
            </div>
            <span class="live-badge"><i></i> live</span>
          </div>

          <div class="event-list" id="event-stream" phx-update="replace">
            <div :if={runtime_events(@snapshot, @local_events) == []} class="events-empty">
              <span class="event-cursor"></span> Waiting for a runtime signal…
            </div>

            <article
              :for={event <- runtime_events(@snapshot, @local_events)}
              id={event_id(event)}
              class={["event-row", "event-row--#{event_tone(event)}"]}
            >
              <time>{elapsed(event, @run_started_at)}</time>
              <span class="event-node" aria-hidden="true"></span>
              <div>
                <strong>{event_title(event)}</strong>
                <p>{event_detail(event)}</p>
              </div>
            </article>
          </div>
        </aside>
      </main>

      <footer class="command-deck">
        <div class="conversation-context">
          <span class="prompt-symbol">›</span>
          <div>
            <span>Ask Phial</span>
            <small>{composer_hint(@run_status)}</small>
          </div>
        </div>

        <form phx-submit="submit" class="command-form">
          <label class="sr-only" for="phial-prompt">Prompt</label>
          <input
            id="phial-prompt"
            name="prompt"
            type="text"
            value=""
            autocomplete="off"
            placeholder="Give the swarm a decision to make…"
            disabled={@run_status in [:dispatching, :running, :synthesizing]}
          />
          <button
            type="submit"
            disabled={@run_status in [:dispatching, :running, :synthesizing] or is_nil(@chat_pid)}
            phx-disable-with="Running…"
          >
            <span>Send</span>
            <svg viewBox="0 0 20 20" aria-hidden="true">
              <path d="M4 10h11M11 5l5 5-5 5" />
            </svg>
          </button>
        </form>
      </footer>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :integer, required: true)

  defp metric(assigns) do
    ~H"""
    <div class="metric"><strong>{@value}</strong><span>{@label}</span></div>
    """
  end

  attr(:status, :atom, required: true)

  defp status(assigns) do
    ~H"""
    <span class={["status-pill", "status-pill--#{@status}"]}>
      <i></i>{state_label(@status)}
    </span>
    """
  end

  attr(:role, :atom, required: true)
  attr(:data, :map, required: true)
  attr(:can_kill, :boolean, required: true)

  defp worker_card(assigns) do
    ~H"""
    <article
      id={"agent-#{@role}"}
      class={["agent-card", "agent-card--worker", "agent-card--#{@data.status}"]}
    >
      <div class="card-topline">
        <span class="agent-kind">Child</span>
        <.status status={@data.status} />
      </div>
      <div class="agent-identity">
        <div class="agent-glyph" aria-hidden="true">{role_initial(@role)}</div>
        <div class="identity-copy">
          <h3>{role_label(@role)}</h3>
          <code title={@data.pid}>{@data.pid}</code>
        </div>
      </div>
      <div class="card-footer">
        <span>inbox <strong>{@data.inbox}</strong></span>
        <button
          :if={@can_kill}
          type="button"
          id={"kill-#{@role}"}
          class="kill-button"
          phx-click="kill"
          phx-value-role={@role}
          aria-label={"Kill #{role_label(@role)}"}
          title={"Kill #{role_label(@role)}"}
        >
          <svg viewBox="0 0 20 20" aria-hidden="true">
            <path d="M6.5 6.5l7 7m0-7l-7 7" />
          </svg>
          <span>Kill</span>
        </button>
      </div>
    </article>
    """
  end

  defp refresh_snapshot(%{assigns: %{orchestrator: pid}} = socket) when is_pid(pid) do
    case Swarm.snapshot(pid) do
      {:ok, snapshot} -> assign(socket, snapshot: snapshot)
      _error -> socket
    end
  end

  defp refresh_snapshot(socket), do: socket

  defp relevant_signal?(metadata, %{id: id}) when is_binary(id) do
    agent_id = to_string(metadata[:agent_id] || "")
    agent_id == id or String.starts_with?(agent_id, id <> "/")
  end

  defp relevant_signal?(_metadata, _snapshot), do: false

  defp role_data(nil, _role), do: %{status: :idle, pid: "—", inbox: 0}

  defp role_data(snapshot, role) do
    pid = snapshot.state.pids[role] || snapshot.children[role]

    %{
      status: snapshot.state.statuses[role] || :starting,
      pid: pid_text(pid),
      inbox: inbox_count(snapshot.children[role])
    }
  end

  defp inbox_count(pid) when is_pid(pid) do
    case GenServer.call(pid, :get_state, 250) do
      {:ok, state} -> length(state.agent.state.inbox)
      _other -> 0
    end
  catch
    :exit, _reason -> 0
  end

  defp inbox_count(_pid), do: 0

  defp can_kill?(snapshot, role, orchestrator) when is_map(snapshot) and is_pid(orchestrator) do
    is_pid(snapshot.children[role])
  end

  defp can_kill?(_snapshot, _role, _orchestrator), do: false

  defp runtime_events(snapshot, local_events) do
    state_events = if snapshot, do: snapshot.state.events, else: []

    (state_events ++ local_events)
    |> Enum.uniq_by(&event_id/1)
    |> Enum.sort_by(& &1.at, :desc)
    |> Enum.take(40)
  end

  defp event_id(event) do
    parts = [event.kind, event[:role], event[:from], event[:to], event[:at]]
    "event-#{:erlang.phash2(parts)}"
  end

  defp event_title(%{kind: :mission_started}), do: "Mission accepted"
  defp event_title(%{kind: :worker_started, role: role}), do: "#{role_label(role)} spawned"
  defp event_title(%{kind: :worker_restarted, role: role}), do: "#{role_label(role)} restarted"
  defp event_title(%{kind: :worker_crashed, role: role}), do: "#{role_label(role)} crashed"
  defp event_title(%{kind: :worker_stopped, role: role}), do: "#{role_label(role)} stopped"
  defp event_title(%{kind: :worker_result, role: role}), do: "#{role_label(role)} reported"
  defp event_title(%{kind: :a2a_message}), do: "send_message"
  defp event_title(%{kind: :tool}), do: "Tool call"
  defp event_title(%{kind: :kill}), do: "Process signal"
  defp event_title(%{kind: :chat}), do: "Chat"
  defp event_title(%{kind: :error}), do: "Runtime error"
  defp event_title(event), do: event.kind |> to_string() |> String.replace("_", " ")

  defp event_detail(%{kind: :a2a_message} = event) do
    "#{event.from} → #{event.to} · #{event.message_kind}"
  end

  defp event_detail(%{kind: :worker_restarted, previous_pid: pid}),
    do: "new PID replaced #{pid_text(pid)}"

  defp event_detail(%{kind: :worker_started, pid: pid}), do: pid_text(pid)

  defp event_detail(%{kind: kind, text: text}) when kind in [:tool, :kill, :chat, :error],
    do: text

  defp event_detail(event), do: event[:text] || "mailbox event processed"

  defp event_tone(%{kind: kind}) when kind in [:worker_crashed, :error, :kill], do: :danger
  defp event_tone(%{kind: :a2a_message}), do: :message
  defp event_tone(%{kind: kind}) when kind in [:worker_restarted, :worker_started], do: :active
  defp event_tone(_event), do: :neutral

  defp runtime_event(kind, text) do
    %{kind: kind, text: text, at: System.monotonic_time(:millisecond)}
  end

  defp elapsed(_event, nil), do: "+00.0s"

  defp elapsed(event, started_at) do
    milliseconds = max(event.at - started_at, 0)
    seconds = div(milliseconds, 1_000)
    tenths = div(rem(milliseconds, 1_000), 100)
    "+#{seconds |> Integer.to_string() |> String.pad_leading(2, "0")}.#{tenths}s"
  end

  defp state_value(nil, _key), do: 0
  defp state_value(snapshot, key), do: Map.get(snapshot.state, key, 0)

  defp orchestrator_status(nil), do: :idle

  defp orchestrator_status(%{state: %{recommendation: recommendation}}) when recommendation != "",
    do: :done

  defp orchestrator_status(_snapshot), do: :thinking

  defp orchestrator_pid(nil), do: nil
  defp orchestrator_pid(snapshot), do: snapshot.pid

  defp alive_children(nil), do: 0
  defp alive_children(snapshot), do: map_size(snapshot.children)

  defp agent_count(nil), do: 0
  defp agent_count(snapshot), do: 1 + map_size(snapshot.children)

  defp connected_class(pid) when is_pid(pid), do: "connection-dot--online"
  defp connected_class(_pid), do: "connection-dot--offline"

  defp state_label(:dispatching), do: "routing"
  defp state_label(:synthesizing), do: "synthesizing"
  defp state_label(:thinking), do: "thinking"
  defp state_label(:starting), do: "starting"
  defp state_label(:waiting), do: "waiting"
  defp state_label(:running), do: "running"
  defp state_label(:completed), do: "done"
  defp state_label(:done), do: "done"
  defp state_label(:crashed), do: "crashed"
  defp state_label(:failed), do: "failed"
  defp state_label(:idle), do: "idle"
  defp state_label(other), do: to_string(other)

  defp composer_hint(status) when status in [:dispatching, :running, :synthesizing],
    do: "Agents are working — watch the graph"

  defp composer_hint(_status), do: "Complex prompts automatically delegate to the swarm"

  defp role_label(:researcher), do: "Researcher"
  defp role_label(:critic), do: "Critic"
  defp role_label(:scout), do: "Scout"
  defp role_label(role), do: role |> to_string() |> String.capitalize()

  defp role_initial(role), do: role |> to_string() |> String.first() |> String.upcase()

  defp parse_role(role) when role in ["researcher", "critic", "scout"],
    do: {:ok, String.to_existing_atom(role)}

  defp parse_role(_role), do: {:error, :invalid_role}

  defp pid_text(pid) when is_pid(pid), do: inspect(pid)
  defp pid_text(_pid), do: "—"

  defp message(role, content),
    do: %{id: unique_id(), role: role, content: content}

  defp latest_answer(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: :assistant, content: content} -> content
      _message -> nil
    end)
  end

  defp result_text(%{result: result}) when is_binary(result), do: result
  defp result_text(result) when is_binary(result), do: result
  defp result_text(result), do: inspect(result, pretty: true)

  defp unique_id, do: System.unique_integer([:positive, :monotonic])
end
