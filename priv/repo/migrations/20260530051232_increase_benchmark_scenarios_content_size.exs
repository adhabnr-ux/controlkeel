defmodule ControlKeel.Repo.Migrations.IncreaseBenchmarkScenariosContentSize do
  use Ecto.Migration

  def change do
    if sqlite_repo?() do
      # SQLite doesn't support ALTER COLUMN, need to recreate table
      execute("""
      CREATE TABLE benchmark_scenarios_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        suite_id INTEGER NOT NULL REFERENCES benchmark_suites(id) ON DELETE CASCADE,
        slug TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        incident_label TEXT,
        path TEXT,
        kind TEXT NOT NULL DEFAULT 'code',
        content TEXT NOT NULL,
        expected_rules TEXT NOT NULL DEFAULT '[]',
        expected_decision TEXT,
        position INTEGER NOT NULL DEFAULT 0,
        split TEXT NOT NULL DEFAULT 'public',
        metadata TEXT NOT NULL DEFAULT '{}',
        inserted_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
      """)

      execute("""
      INSERT INTO benchmark_scenarios_new
      SELECT * FROM benchmark_scenarios
      """)

      execute("DROP TABLE benchmark_scenarios")
      execute("ALTER TABLE benchmark_scenarios_new RENAME TO benchmark_scenarios")

      create unique_index(:benchmark_scenarios, [:suite_id, :slug])
      create index(:benchmark_scenarios, [:suite_id, :position])
      create index(:benchmark_scenarios, [:split])
    else
      alter table(:benchmark_scenarios) do
        modify :content, :text
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
