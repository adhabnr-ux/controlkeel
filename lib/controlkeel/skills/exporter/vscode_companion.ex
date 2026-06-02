defmodule ControlKeel.Skills.Exporter.VscodeCompanion do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, _project_root, _skills, _opts) do
    extension_root = Path.join(root, "extension")
    File.mkdir_p!(extension_root)

    package_json_path = Path.join(extension_root, "package.json")

    File.write!(
      package_json_path,
      Jason.encode!(E.vscode_companion_manifest(), pretty: true) <> "\n"
    )

    extension_js_path = Path.join(extension_root, "extension.js")
    File.write!(extension_js_path, E.vscode_companion_extension_contents())

    readme_path = Path.join(extension_root, "README.md")
    File.write!(readme_path, E.vscode_companion_readme_contents())

    license_path = Path.join(extension_root, "LICENSE")
    File.write!(license_path, "MIT License\n\nCopyright (c) 2026 ControlKeel Authors")

    E.with_common_assets(
      root,
      root,
      [],
      [
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => extension_js_path, "kind" => "runtime"},
        %{"path" => readme_path, "kind" => "instructions"},
        %{"path" => license_path, "kind" => "license"}
      ],
      [
        "Zip the `extension/` directory as a `.vsix` when publishing the VS Code companion.",
        "The companion opens ControlKeel review URLs inside a VS Code webview and injects terminal routing env vars."
      ]
    )
  end
end
