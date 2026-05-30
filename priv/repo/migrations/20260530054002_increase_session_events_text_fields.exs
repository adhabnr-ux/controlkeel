defmodule ControlKeel.Repo.Migrations.IncreaseSessionEventsTextFields do
  use Ecto.Migration

  def change do
    if sqlite_repo?() do
      # SQLite doesn't support ALTER COLUMN, need to recreate table
      execute("""
      CREATE TABLE session_events_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
        event_type TEXT NOT NULL,
        actor TEXT NOT NULL,
        summary TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        payload TEXT NOT NULL DEFAULT '{}',
        metadata TEXT NOT NULL DEFAULT '{}',
        inserted_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
      """)

      execute("""
      INSERT INTO session_events_new
      SELECT * FROM session_events
      """)

      execute("DROP TABLE session_events")
      execute("ALTER TABLE session_events_new RENAME TO session_events")

      # Recreate indexes
      create index(:session_events, [:session_id])
      create index(:session_events, [:task_id])
      create index(:session_events, [:inserted_at])
    else
      alter table(:session_events) do
        modify :summary, :text
        modify :body, :text
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
