defmodule ControlKeel.Runtime do
  @moduledoc false

  alias ControlKeel.Runtime.Mode

  def mode, do: Mode.current()

  def local?, do: mode() == :local
  def cloud?, do: mode() == :cloud
  def self_hosted?, do: mode() == :self_hosted
  def remote?, do: cloud?() or self_hosted?()

  def placement(surface), do: Mode.placement(mode(), surface)
  def placement_map, do: Mode.placement_map(mode())

  def pdf_renderer do
    case Application.get_env(:controlkeel, :pdf_renderer, :chromic) do
      :chromic -> ControlKeel.AuditExports.Renderer.Chromic
      module when is_atom(module) -> module
      _ -> ControlKeel.AuditExports.Renderer.Chromic
    end
  end

  def cloud_repo_enabled? do
    remote?() and cloud_repo_url_configured?()
  end

  @doc """
  Whether the local SQLite repo has enough config to be started safely.

  Used to gate `ControlKeel.Repo.Local` supervision: a prod cloud/self-hosted
  release intentionally leaves `Repo.Local` without a `:database`/`:url` (see
  `config/runtime.exs`), so starting it would crash boot before the app can
  serve traffic. Local mode and the test suite always configure it.
  """
  def local_repo_configured? do
    env = Application.get_env(:controlkeel, ControlKeel.Repo.Local, [])
    Keyword.has_key?(env, :database) or Keyword.has_key?(env, :url)
  end

  # CloudRepo counts as enabled only when it has a real connection string.
  # A bare `priv` entry (always present from config/config.exs) must NOT count,
  # otherwise a self-hosted box without DATABASE_URL would route queries to an
  # unconfigured Postgres repo instead of the SQLite database runtime.exs set up.
  defp cloud_repo_url_configured? do
    Application.get_env(:controlkeel, ControlKeel.CloudRepo, [])
    |> Keyword.get(:url)
    |> cloud_repo_url_present?()
  end

  defp cloud_repo_url_present?(nil), do: false
  defp cloud_repo_url_present?(""), do: false
  defp cloud_repo_url_present?(_url), do: true

  def memory_store_mode do
    if cloud_repo_enabled?(), do: :pgvector, else: :sqlite
  end
end
