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

      # Explicit column list rather than a positional `SELECT *`: if the live
      # table's column order ever diverges from this fresh-schema order (later
      # ALTER ADD COLUMN migrations append at the end), a positional copy would
      # misalign columns and violate NOT NULL constraints.
      execute("""
      INSERT INTO benchmark_scenarios_new (
        id, suite_id, slug, name, category, incident_label, path, kind, content,
        expected_rules, expected_decision, position, split, metadata, inserted_at, updated_at
      )
      SELECT
        id, suite_id, slug, name, category, incident_label, path, kind, content,
        expected_rules, expected_decision, position, split, metadata, inserted_at, updated_at
      FROM benchmark_scenarios
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
