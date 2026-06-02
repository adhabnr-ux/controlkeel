defmodule ControlKeel.Skills.Exporter.InstructionsOnly do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("agents", project_root, opts))

    claude_path = Path.join(root, "CLAUDE.md")
    File.write!(claude_path, E.instructions_only_contents("claude", project_root, opts))

    copilot_path = Path.join(root, "copilot-instructions.md")
    File.write!(copilot_path, E.instructions_only_contents("copilot", project_root, opts))

    aider_path = Path.join(root, "AIDER.md")
    File.write!(aider_path, E.aider_instructions_contents())

    aider_config_path = Path.join(root, ".aider.conf.yml")
    File.write!(aider_config_path, E.aider_config_contents(project_root, opts))

    aider_command_path = Path.join(root, ".aider/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(aider_command_path))
    File.write!(aider_command_path, E.aider_command_contents())

    aider_annotate_command_path = Path.join(root, ".aider/commands/controlkeel-annotate.md")

    File.write!(
      aider_annotate_command_path,
      E.host_annotate_command_contents("Aider", "aider", ".aider/annotate.md")
    )

    aider_last_command_path = Path.join(root, ".aider/commands/controlkeel-last.md")
    File.write!(aider_last_command_path, E.host_last_command_contents("Aider"))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => claude_path, "kind" => "instructions"},
        %{"path" => copilot_path, "kind" => "instructions"},
        %{"path" => aider_path, "kind" => "instructions"},
        %{"path" => aider_config_path, "kind" => "settings"},
        %{"path" => aider_command_path, "kind" => "command"},
        %{"path" => aider_annotate_command_path, "kind" => "command"},
        %{"path" => aider_last_command_path, "kind" => "command"}
      ],
      [
        "Use these snippets with MCP-only or command-driven tools such as Aider that do not support native skills or plugins."
      ]
    )
  end
end
