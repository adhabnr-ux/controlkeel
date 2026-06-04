defmodule ControlKeel.CLI.Doctor do
  @moduledoc false

  alias ControlKeel.AgentExecution
  alias ControlKeel.CLI.Catalog
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.LocalProject
  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ProviderBroker
  alias ControlKeel.SetupAdvisor

  @ck_gitignore_required ["/controlkeel/", "/.controlkeel/"]

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
    health = install_health(root, version, binding)

    # Note: top-level "status" stays "ok" (it signals the command ran, a
    # stable contract for JSON consumers). Setup health is surfaced via the
    # dedicated install_health block, the human lines, and next_steps.
    base
    |> Map.put("binding", binding_status)
    |> Map.put("session", session_payload(session))
    |> Map.put("governance", governance_payload(session))
    |> Map.put("install_health", health)
    |> Map.put("attached_agents", if(binding, do: attached_agent_payload(binding), else: []))
    |> Map.put("next_steps", next_steps(binding_status, session, agents, health))
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
      "CLI capabilities: #{capabilities["command_count"]} command(s) across #{length(capabilities["families"])} families"
    ] ++
      install_health_lines(payload["install_health"]) ++
      ["Next steps:"] ++ Enum.map(payload["next_steps"], &"  - #{&1}")
  end

  defp install_health_lines(nil), do: []

  defp install_health_lines(health) do
    gitignore = health["gitignore"]

    gitignore_status =
      if gitignore["complete"],
        do: "complete",
        else: "incomplete (missing #{Enum.join(gitignore["missing"], ", ")})"

    skill_consistency = get_in(health, ["skill_consistency"])

    skill_line =
      if skill_consistency do
        if skill_consistency["ok"],
          do: "  skill consistency: ok",
          else: "  skill consistency: DRIFT (#{length(skill_consistency["drifted"])} differences)"
      else
        ""
      end

    base_lines = [
      "Install health: #{if health["ok"], do: "ok", else: "attention"}",
      "  git: #{if health["git_available"], do: "available", else: "MISSING"}",
      "  gitignore: #{gitignore_status}",
      "  mcp wrapper: #{if get_in(health, ["mcp_wrapper", "present"]), do: "present", else: "missing"}"
    ]

    if(skill_line != "", do: base_lines ++ [skill_line], else: base_lines) ++
      Enum.map(health["problems"] || [], &"  ! #{&1}")
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

  defp next_steps(%{"status" => "missing"}, _session, _agents, _health) do
    ["controlkeel init", "controlkeel attach <agent>", "controlkeel doctor --json"]
  end

  defp next_steps(_binding, session, agents, health) do
    base = ["controlkeel status --json", "controlkeel findings"]

    attach =
      if (agents["attached_agents"] || []) == [], do: ["controlkeel attach doctor"], else: []

    proof = if session, do: ["controlkeel proofs"], else: []
    base ++ attach ++ proof ++ install_health_next_steps(health)
  end

  defp install_health_next_steps(%{"ok" => true}), do: []

  defp install_health_next_steps(health) do
    drift = if Enum.any?(health["attached"] || [], & &1["version_drift"]), do: true, else: false

    []
    |> prepend_if(not get_in(health, ["mcp_wrapper", "present"]), "controlkeel attach <agent>")
    |> prepend_if(not get_in(health, ["gitignore", "complete"]), "controlkeel init")
    |> prepend_if(drift, "controlkeel update --sync-attached")
  end

  defp prepend_if(list, true, step), do: list ++ [step]
  defp prepend_if(list, _false, _step), do: list

  defp install_health(root, version, binding) do
    git_available = ControlKeel.Git.available?()
    gitignore = gitignore_health(root)
    wrapper_path = ProjectBinding.mcp_wrapper_path(root)
    wrapper_present = File.exists?(wrapper_path)
    attached = attached_health(version, binding)

    drifted = Enum.filter(attached, & &1["version_drift"])
    missing_dest = Enum.filter(attached, &(&1["destination_present"] == false))

    skill_consistency = skill_consistency_health(binding)

    problems =
      [
        unless(git_available, do: "git not on PATH (git-backed proof/worktrees unavailable)"),
        unless(gitignore["complete"],
          do: "gitignore missing: " <> Enum.join(gitignore["missing"], ", ")
        ),
        unless(wrapper_present, do: "MCP wrapper missing (run: controlkeel attach <agent>)"),
        if(drifted != [], do: "version drift: " <> Enum.map_join(drifted, ", ", & &1["agent"])),
        if(missing_dest != [],
          do:
            "attached skills missing on disk: " <>
              Enum.map_join(missing_dest, ", ", & &1["agent"])
        ),
        if(skill_consistency["drifted"] != [],
          do:
            "skill drift across targets: " <>
              Enum.map_join(
                skill_consistency["drifted"],
                ", ",
                &(&1["skill"] <> " in " <> &1["path"])
              )
        )
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "git_available" => git_available,
      "gitignore" => gitignore,
      "mcp_wrapper" => %{"present" => wrapper_present, "path" => wrapper_path},
      "attached" => attached,
      "skill_consistency" => skill_consistency,
      "problems" => problems,
      "ok" => problems == []
    }
  end

  defp gitignore_health(root) do
    contents =
      case File.read(Path.join(root, ".gitignore")) do
        {:ok, value} -> value
        _ -> ""
      end

    missing = Enum.reject(@ck_gitignore_required, &String.contains?(contents, &1))
    %{"present" => contents != "", "missing" => missing, "complete" => missing == []}
  end

  defp attached_health(_version, nil), do: []

  defp attached_health(version, binding) do
    binding
    |> Map.get("attached_agents", %{})
    |> Enum.sort_by(fn {agent, _attrs} -> agent end)
    |> Enum.map(fn {agent, attrs} ->
      agent_version = attrs["controlkeel_version"] || "unknown"
      dest = attrs["destination"] || attrs["config_destination"] || attrs["config_path"]

      %{
        "agent" => agent,
        "controlkeel_version" => agent_version,
        "version_drift" => agent_version != "unknown" and agent_version != version,
        "destination" => dest,
        "destination_present" => if(is_binary(dest), do: File.exists?(dest), else: nil)
      }
    end)
  end

  defp skill_consistency_health(nil), do: %{"ok" => true, "drifted" => []}

  defp skill_consistency_health(binding) do
    agents = Map.get(binding, "attached_agents", %{})

    # Collect all skill directories with their manifests
    skill_dirs =
      agents
      |> Enum.flat_map(fn {_key, attrs} ->
        [
          Map.get(attrs, "skills_destination"),
          Map.get(attrs, "compat_skills_destination"),
          Map.get(attrs, "compat_destination")
        ]
        |> Enum.filter(&is_binary/1)
      end)
      |> Enum.filter(fn dir -> is_binary(dir) and File.dir?(dir) end)
      |> Enum.uniq()

    if skill_dirs == [] do
      %{"ok" => true, "drifted" => []}
    else
      # Read manifest from each dir and compare skill sets
      dir_skills =
        skill_dirs
        |> Enum.map(fn dir ->
          manifest_path = Path.join(dir, ".controlkeel-skills.json")

          skills =
            with {:ok, body} <- File.read(manifest_path),
                 {:ok, %{"skills" => s}} when is_list(s) <- Jason.decode(body) do
              Enum.filter(s, &is_binary/1) |> Enum.sort()
            else
              _ -> nil
            end

          {dir, skills}
        end)

      # Find dirs with manifest and check consistency
      with_manifests = Enum.filter(dir_skills, fn {_, s} -> s != nil end)

      if length(with_manifests) < 2 do
        %{"ok" => true, "drifted" => []}
      else
        [{baseline_dir, baseline_skills} | rest] = with_manifests

        drifted =
          rest
          |> Enum.flat_map(fn {dir, skills} ->
            if skills != baseline_skills do
              only_in_baseline = baseline_skills -- skills
              only_in_dir = skills -- baseline_skills

              diffs =
                Enum.map(
                  only_in_baseline,
                  &%{"skill" => &1, "direction" => "missing", "path" => Path.basename(dir)}
                ) ++
                  Enum.map(
                    only_in_dir,
                    &%{"skill" => &1, "direction" => "extra", "path" => Path.basename(dir)}
                  )

              diffs
            else
              []
            end
          end)

        %{"ok" => drifted == [], "drifted" => drifted, "baseline" => Path.basename(baseline_dir)}
      end
    end
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
