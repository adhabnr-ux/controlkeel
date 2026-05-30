defmodule ControlKeel.Runtime do
  @moduledoc false

  alias ControlKeel.RuntimeMode

  def mode, do: RuntimeMode.current()

  def local?, do: mode() == :local
  def cloud?, do: mode() == :cloud
  def self_hosted?, do: mode() == :self_hosted
  def remote?, do: cloud?() or self_hosted?()

  def placement(surface), do: RuntimeMode.placement(mode(), surface)
  def placement_map, do: RuntimeMode.placement_map(mode())
  def runtime_diagnostic, do: RuntimeMode.diagnostic(mode())

  def bus do
    Application.get_env(:controlkeel, :bus, default_bus())
  end

  def bus_module do
    case bus() do
      :nats -> ControlKeel.Bus.Nats
      :jet_stream -> ControlKeel.Bus.JetStream
      _ -> ControlKeel.Bus.Local
    end
  end

  def pdf_renderer do
    case Application.get_env(:controlkeel, :pdf_renderer, :chromic) do
      :chromic -> ControlKeel.AuditExports.Renderer.Chromic
      module when is_atom(module) -> module
      _ -> ControlKeel.AuditExports.Renderer.Chromic
    end
  end

  def cloud_repo_enabled? do
    remote?() and Application.get_env(:controlkeel, ControlKeel.CloudRepo, []) != []
  end

  def memory_store_mode do
    if cloud_repo_enabled?(), do: :pgvector, else: :sqlite
  end

  defp default_bus do
    if remote?(), do: :nats, else: :local
  end
end
