defmodule ControlKeel.Skills.Exporter.LettaCodeNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    settings_path = Path.join(root, ".letta/settings.json")
    File.mkdir_p!(Path.dirname(settings_path))
    File.write!(settings_path, Jason.encode!(E.letta_settings_manifest(), pretty: true) <> "\n")

    local_settings_example_path = Path.join(root, ".letta/settings.local.example.json")

    File.write!(
      local_settings_example_path,
      Jason.encode!(E.letta_local_settings_example_manifest(), pretty: true) <> "\n"
    )

    hooks_root = Path.join(root, ".letta/hooks")
    File.mkdir_p!(hooks_root)

    findings_hook_path = Path.join(hooks_root, "controlkeel-findings.sh")
    File.write!(findings_hook_path, E.letta_findings_hook_contents())
    File.chmod!(findings_hook_path, 0o755)

    session_hook_path = Path.join(hooks_root, "controlkeel-session-start.sh")
    File.write!(session_hook_path, E.letta_session_start_hook_contents())
    File.chmod!(session_hook_path, 0o755)

    mcp_helper_path = Path.join(root, ".letta/controlkeel-mcp.sh")
    File.write!(mcp_helper_path, E.letta_mcp_helper_contents(project_root, opts))
    File.chmod!(mcp_helper_path, 0o755)

    readme_path = Path.join(root, ".letta/README.md")
    File.write!(readme_path, E.letta_readme_contents(project_root, opts))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("letta-code", project_root, opts))

    review_command_path = Path.join(root, ".letta/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Letta", "letta"))

    submit_command_path = Path.join(root, ".letta/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Letta", "letta", ".letta/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".letta/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Letta", "letta", ".letta/annotate.md")
    )

    last_command_path = Path.join(root, ".letta/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Letta"))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => settings_path, "kind" => "settings"},
        %{"path" => local_settings_example_path, "kind" => "settings"},
        %{"path" => findings_hook_path, "kind" => "hook"},
        %{"path" => session_hook_path, "kind" => "hook"},
        %{"path" => mcp_helper_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.agents/skills` in the repo so Letta discovers ControlKeel skills through its primary project skill path.",
        "Commit `.letta/settings.json` for shared hook defaults; keep personal overrides in `.letta/settings.local.json` based on the included example file.",
        "Register ControlKeel with Letta through `/mcp add --transport stdio controlkeel ./.letta/controlkeel-mcp.sh` or the hosted HTTP variant described in `.letta/README.md`.",
        "Use `letta -p` for headless runs and `letta server` for remote/listener workflows; the included README documents both without claiming a CK-owned runtime."
      ]
    )
  end
end
