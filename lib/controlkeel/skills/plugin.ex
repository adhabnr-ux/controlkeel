defmodule ControlKeel.Skills.Plugin do
  @moduledoc false

  @type plugin :: %{
          id: String.t(),
          label: String.t(),
          target_id: String.t(),
          install_path: String.t(),
          manifest_file: String.t(),
          description: String.t()
        }

  @callback id() :: String.t()
  @callback label() :: String.t()
  @callback target_id() :: String.t()
  @callback install_path() :: String.t()
  @callback manifest_file() :: String.t()
  @callback description() :: String.t()

  def info(module) when is_atom(module) do
    %{
      id: module.id(),
      label: module.label(),
      target_id: module.target_id(),
      install_path: module.install_path(),
      manifest_file: module.manifest_file(),
      description: module.description()
    }
  end
end
