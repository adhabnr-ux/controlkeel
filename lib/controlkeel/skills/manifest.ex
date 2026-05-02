defmodule ControlKeel.Skills.Manifest do
  @moduledoc false

  @manifest_filename ".controlkeel-manifest.json"

  def list_export_manifests(project_root) do
    root = Path.expand(project_root)

    root
    |> export_manifest_paths()
    |> Enum.flat_map(fn path ->
      case read_manifest(path) do
        {:ok, manifest} -> [%{path: path, manifest: manifest}]
        {:error, _} -> []
      end
    end)
  end

  defp export_manifest_paths(root) do
    Path.wildcard(Path.join([root, "controlkeel", "dist", "*", @manifest_filename]))
  end

  defp read_manifest(path) do
    with {:ok, body} <- File.read(path),
         {:ok, manifest} <- Jason.decode(body) do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
