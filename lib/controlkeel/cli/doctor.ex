defmodule ControlKeel.CLI.Doctor do
  @moduledoc false

  alias ControlKeel.AgentExecution
  alias ControlKeel.CLI.Catalog
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.LocalProject
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ProviderBroker
  alias ControlKeel.SetupAdvisor

  def payload(project_root, version) do
    root = ProjectRoot.resolve(project_root)
    snapshot = SetupAdvisor.snapshot(root)
    provider_status = ProviderBroker.status(root)
    agents = AgentExecution.doctor(root)
    catalog_families = Catalog.families()
    sandbox = ExecutionSandbox.adapter_name([])

    base = %{
      "status" => "ok",
      "project_root" => root,
      "version" => version,
      "update_check" => %{"status" => "not_run", "next" => "controlkeel update --json"},
      "setup" => %{
        "detected_hosts" => snapshot["detected_hosts"] || [],
        "core_loop" => SetupAdvisor.core_loop()
      },
      "provider" => %{
        "source" => provider_status["selected_source"],
        "provider" => provider_status["selected_provider"],
        "auth_mode" => provider_status["selected_auth_mode"],
        "auth_owner" => provider_status["selected_auth_owner"],
        "bootstrap_mode" => get_in(provider_status, ["bootstrap", "mode"])
      },
      "agents" => %{
        "attached" => agents["attached_agents"] || [],
        "direct_ready" => agents["direct_ready"] || [],
        "handoff_ready" => agents["handoff_ready"] || [],
        "runtime_ready" => agents["runtime_ready"] || []
      },
      "sandbox" => %{"adapter" => sandbox},
      "capabilities" => %{
        "families" => catalog_families |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
        "command_count" => length(Catalog.all())
      }
    }

    {binding_status, binding, session} = load_binding(root)

    base
    |> Map.put("binding", binding_status)
    |> Map.put("session", session_payload(session))
    |> Map.put("governance", governance_payload(session))
    |> Map.put("attached_agents", if(binding, do: attached_agent_payload(binding), else: []))
    |> Map.put("next_steps", next_steps(binding_status, session, agents))
  end

  def lines(payload) do
    binding = payload["binding"]
    session = payload["session"]
    governance = payload["governance"]
    provider = payload["provider"]
    agents = payload["agents"]
    capabilities = payload["capabilities"]

    [
      "ControlKeel doctor",
      "Project root: #{payload["project_root"]}",
      "Version: #{payload["version"]} (update check not run; use controlkeel update --json)",
      "Binding: #{binding["status"]}#{binding_suffix(binding)}",
      "Session: #{session_line(session)}",
      "Governance: ready=#{governance["ready"]} blocked_findings=#{governance["blocked_findings"]} pending_reviews=#{governance["pending_reviews"]} proofs=#{governance["proof_bundles"]}",
      "Provider: #{provider["provider"]} via #{provider["source"]} (auth #{provider["auth_mode"]}/#{provider["auth_owner"]})",
      "Sandbox: #{get_in(payload, ["sandbox", "adapter"])}",
      "Attached agents: #{if agents["attached"] == [], do: "none", else: Enum.join(agents["attached"], ", ")}",
      "Agent readiness: direct=#{length(agents["direct_ready"])} handoff=#{length(agents["handoff_ready"])} runtime=#{length(agents["runtime_ready"])}",
      "CLI capabilities: #{capabilities["command_count"]} command(s) across #{length(capabilities["families"])} families",
      "Next steps:"
    ] ++ Enum.map(payload["next_steps"], &"  - #{&1}")
  end

  defp load_binding(root) do
    case LocalProject.load(root) do
      {:ok, binding, session} ->
        {%{
           "status" => "bound",
           "workspace_id" => binding["workspace_id"],
           "session_id" => binding["session_id"],
           "mode" => get_in(binding, ["bootstrap", "mode"]) || "project"
         }, binding, session}

      {:error, reason} ->
        {%{"status" => "missing", "reason" => inspect(reason)}, nil, nil}
    end
  end

  defp session_payload(nil), do: nil

  defp session_payload(session) do
    active_task = current_session_task(session)

    %{
      "id" => session.id,
      "title" => session.title,
      "risk_tier" => session.risk_tier,
      "current_task" => task_payload(active_task),
      "active_tasks" => Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      "active_findings" =>
        Enum.count(session.findings, &(&1.status in ["open", "blocked", "escalated"]))
    }
  end

  defp governance_payload(nil) do
    %{"ready" => false, "blocked_findings" => 0, "pending_reviews" => 0, "proof_bundles" => 0}
  end

  defp governance_payload(session) do
    blocked = Enum.count(loaded_assoc(session.findings), &(&1.status == "blocked"))
    pending_reviews = Enum.count(loaded_assoc(session.reviews), &(&1.status == "pending"))
    proofs = length(loaded_assoc(session.proof_bundles))

    %{
      "ready" => blocked == 0 and pending_reviews == 0,
      "blocked_findings" => blocked,
      "pending_reviews" => pending_reviews,
      "proof_bundles" => proofs
    }
  end

  defp loaded_assoc(%Ecto.Association.NotLoaded{}), do: []
  defp loaded_assoc(nil), do: []
  defp loaded_assoc(values) when is_list(values), do: values

  defp next_steps(%{"status" => "missing"}, _session, _agents) do
    ["controlkeel init", "controlkeel attach <agent>", "controlkeel doctor --json"]
  end

  defp next_steps(_binding, session, agents) do
    base = ["controlkeel status --json", "controlkeel findings"]

    attach =
      if (agents["attached_agents"] || []) == [], do: ["controlkeel attach doctor"], else: []

    proof = if session, do: ["controlkeel proofs"], else: []
    base ++ attach ++ proof
  end

  defp attached_agent_payload(binding) do
    binding
    |> Map.get("attached_agents", %{})
    |> Enum.sort_by(fn {agent, _attrs} -> agent end)
    |> Enum.map(fn {agent, attrs} ->
      %{
        "agent" => agent,
        "controlkeel_version" => attrs["controlkeel_version"] || "unknown"
      }
    end)
  end

  defp current_session_task(session) do
    Enum.find(session.tasks, &(&1.status == "in_progress")) ||
      Enum.find(session.tasks, &(&1.status == "queued")) ||
      List.first(session.tasks)
  end

  defp task_payload(nil), do: nil

  defp task_payload(task) do
    %{"id" => task.id, "title" => task.title, "status" => task.status}
  end

  defp binding_suffix(%{"status" => "bound"} = binding) do
    " session=#{binding["session_id"]} workspace=#{binding["workspace_id"]} mode=#{binding["mode"]}"
  end

  defp binding_suffix(%{"reason" => reason}), do: " (#{reason})"
  defp binding_suffix(_binding), do: ""

  defp session_line(nil), do: "none"

  defp session_line(session) do
    "#{session["title"]} (##{session["id"]}, #{session["risk_tier"]}) active_tasks=#{session["active_tasks"]} active_findings=#{session["active_findings"]}"
  end
end
