defmodule ControlKeel.Repo.Migrations.AddSuiteLastRunAt do
  use Ecto.Migration

  def change do
    alter table(:benchmark_suites) do
      add :last_run_at, :utc_datetime
    end
  end
end
