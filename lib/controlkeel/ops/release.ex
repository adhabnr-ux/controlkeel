defmodule ControlKeel.Ops.Release do
  @moduledoc """
  Release-time tasks for migrating the database without Mix being available.

  Invoked by the Fly.io `release_command` (see [../fly.toml](../fly.toml)) and
  by any other release runtime (Render, k8s, etc.) that runs the production
  binary directly.

  ## Usage

      bin/controlkeel eval "ControlKeel.Ops.Release.migrate()"
      bin/controlkeel eval "ControlKeel.Ops.Release.rollback(ControlKeel.CloudRepo, 20260524004330)"
  """

  @app :controlkeel

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    runtime_mode = Application.get_env(@app, :runtime_mode, :local)

    case runtime_mode do
      :cloud -> [ControlKeel.CloudRepo]
      _ -> [ControlKeel.Repo.Local]
    end
  end

  defp load_app do
    Application.load(@app)
  end
end
