defmodule ControlKeel.Skills.Exporter.FrameworkAdapter do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    readme_path = Path.join(root, "framework-adapters/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.framework_adapter_contents(project_root, opts))

    config_path = Path.join(root, "framework-adapters/frameworks.json")

    File.write!(
      config_path,
      Jason.encode!(
        %{
          "frameworks" => [
            %{"id" => "dspy", "mode" => "benchmark_adapter"},
            %{"id" => "gepa", "mode" => "policy_training_adapter"},
            %{"id" => "deepagents", "mode" => "runtime_harness_adapter"}
          ]
        },
        pretty: true
      ) <> "\n"
    )

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"}
      ],
      [
        "Use this E.export as the typed scaffold for DSPy, GEPA, or DeepAgents benchmark and training adapters."
      ]
    )
  end
end
