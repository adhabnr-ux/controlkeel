defmodule ControlKeel.Repo.Migrations.IncreaseMemoryRecordsTextFields do
  use Ecto.Migration

  def up do
    if sqlite_repo?() do
      # SQLite doesn't support ALTER COLUMN, need to recreate table
      execute("""
      CREATE TABLE memory_records_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
        external_id TEXT,
        record_type TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '[]',
        source_type TEXT NOT NULL,
        source_id TEXT,
        metadata TEXT NOT NULL,
        archived_at DATETIME,
        visibility TEXT NOT NULL DEFAULT 'workspace',
        shared_org_id INTEGER,
        synced_at DATETIME,
        inserted_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
      """)

      execute("""
      INSERT INTO memory_records_new (
        id, workspace_id, session_id, task_id, external_id, record_type, title, summary, body, tags,
        source_type, source_id, metadata, archived_at, visibility, shared_org_id, synced_at,
        inserted_at, updated_at
      )
      SELECT
        id, workspace_id, session_id, task_id, external_id, record_type, title, summary, body, tags,
        source_type, source_id, metadata, archived_at, visibility, shared_org_id, synced_at,
        inserted_at, updated_at
      FROM memory_records
      """)

      execute("DROP TABLE memory_records")
      execute("ALTER TABLE memory_records_new RENAME TO memory_records")

      # Recreate indexes
      create index(:memory_records, [:workspace_id])
      create index(:memory_records, [:session_id])
      create index(:memory_records, [:task_id])
      create index(:memory_records, [:record_type])
      create index(:memory_records, [:archived_at])
      create index(:memory_records, [:visibility])
      create index(:memory_records, [:shared_org_id])
      create index(:memory_records, [:synced_at])
      create unique_index(:memory_records, [:external_id], where: "external_id IS NOT NULL")

      # Recreate FTS triggers
      execute("""
      CREATE TRIGGER memory_records_ai AFTER INSERT ON memory_records BEGIN
        INSERT INTO memory_records_fts(memory_record_id, document)
        VALUES (
          new.id,
          trim(
            coalesce(new.title, '') || ' ' ||
            coalesce(new.summary, '') || ' ' ||
            coalesce(new.body, '') || ' ' ||
            coalesce(json_extract(new.tags, '$'), '')
          )
        );
      END;
      """)

      execute("""
      CREATE TRIGGER memory_records_au AFTER UPDATE ON memory_records BEGIN
        DELETE FROM memory_records_fts WHERE memory_record_id = old.id;
        INSERT INTO memory_records_fts(memory_record_id, document)
        VALUES (
          new.id,
          trim(
            coalesce(new.title, '') || ' ' ||
            coalesce(new.summary, '') || ' ' ||
            coalesce(new.body, '') || ' ' ||
            coalesce(json_extract(new.tags, '$'), '')
          )
        );
      END;
      """)
    else
      alter table(:memory_records) do
        modify :title, :text
        modify :summary, :text
        modify :body, :text
      end
    end
  end

  def down do
    if sqlite_repo?() do
      # Revert the table recreation
      execute("DROP TRIGGER IF EXISTS memory_records_au")
      execute("DROP TRIGGER IF EXISTS memory_records_ai")

      execute("""
      CREATE TABLE memory_records_old (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
        external_id TEXT,
        record_type TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '[]',
        source_type TEXT NOT NULL,
        source_id TEXT,
        metadata TEXT NOT NULL,
        archived_at DATETIME,
        visibility TEXT NOT NULL DEFAULT 'workspace',
        shared_org_id INTEGER,
        synced_at DATETIME,
        inserted_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
      """)

      execute("""
      INSERT INTO memory_records_old (
        id, workspace_id, session_id, task_id, external_id, record_type, title, summary, body, tags,
        source_type, source_id, metadata, archived_at, visibility, shared_org_id, synced_at,
        inserted_at, updated_at
      )
      SELECT
        id, workspace_id, session_id, task_id, external_id, record_type, title, summary, body, tags,
        source_type, source_id, metadata, archived_at, visibility, shared_org_id, synced_at,
        inserted_at, updated_at
      FROM memory_records
      """)

      execute("DROP TABLE memory_records")
      execute("ALTER TABLE memory_records_old RENAME TO memory_records")

      # Recreate indexes
      create index(:memory_records, [:workspace_id])
      create index(:memory_records, [:session_id])
      create index(:memory_records, [:task_id])
      create index(:memory_records, [:record_type])
      create index(:memory_records, [:archived_at])
      create index(:memory_records, [:visibility])
      create index(:memory_records, [:shared_org_id])
      create index(:memory_records, [:synced_at])
      create unique_index(:memory_records, [:external_id], where: "external_id IS NOT NULL")

      # Recreate FTS triggers
      execute("""
      CREATE TRIGGER memory_records_ai AFTER INSERT ON memory_records BEGIN
        INSERT INTO memory_records_fts(memory_record_id, document)
        VALUES (
          new.id,
          trim(
            coalesce(new.title, '') || ' ' ||
            coalesce(new.summary, '') || ' ' ||
            coalesce(new.body, '') || ' ' ||
            coalesce(json_extract(new.tags, '$'), '')
          )
        );
      END;
      """)

      execute("""
      CREATE TRIGGER memory_records_au AFTER UPDATE ON memory_records BEGIN
        DELETE FROM memory_records_fts WHERE memory_record_id = old.id;
        INSERT INTO memory_records_fts(memory_record_id, document)
        VALUES (
          new.id,
          trim(
            coalesce(new.title, '') || ' ' ||
            coalesce(new.summary, '') || ' ' ||
            coalesce(new.body, '') || ' ' ||
            coalesce(json_extract(new.tags, '$'), '')
          )
        );
      END;
      """)
    else
      alter table(:memory_records) do
        modify :title, :string
        modify :summary, :string
        modify :body, :string
      end
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
