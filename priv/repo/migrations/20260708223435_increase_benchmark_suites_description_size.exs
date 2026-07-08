defmodule ControlKeel.Repo.Migrations.IncreaseBenchmarkSuitesDescriptionSize do
  use Ecto.Migration

  def change do
    # SQLite has TEXT affinity for both VARCHAR and TEXT and does not enforce
    # length limits, so the column change is a no-op there. Postgres enforces
    # varchar(255) and rejects the 298-char host_comparison_v1 description.
    unless sqlite_repo?() do
      alter table(:benchmark_suites) do
        modify :description, :text
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
