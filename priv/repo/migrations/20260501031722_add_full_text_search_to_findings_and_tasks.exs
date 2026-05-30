defmodule ControlKeel.Repo.Migrations.AddFullTextSearchToFindingsAndTasks do
  use Ecto.Migration

  def up do
    if sqlite_repo?() do
      execute """
      CREATE VIRTUAL TABLE IF NOT EXISTS findings_fts USING fts5(
        title,
        plain_message,
        category,
        severity,
        content='findings',
        content_rowid='id'
      )
      """

      execute """
      CREATE TRIGGER IF NOT EXISTS findings_fts_insert AFTER INSERT ON findings BEGIN
        INSERT INTO findings_fts(rowid, title, plain_message, category, severity)
        VALUES (new.id, new.title, new.plain_message, new.category, new.severity);
      END
      """

      execute """
      CREATE TRIGGER IF NOT EXISTS findings_fts_delete AFTER DELETE ON findings BEGIN
        INSERT INTO findings_fts(findings_fts, rowid, title, plain_message, category, severity)
        VALUES ('delete', old.id, old.title, old.plain_message, old.category, old.severity);
      END
      """

      execute """
      CREATE TRIGGER IF NOT EXISTS findings_fts_update AFTER UPDATE ON findings BEGIN
        INSERT INTO findings_fts(findings_fts, rowid, title, plain_message, category, severity)
        VALUES ('delete', old.id, old.title, old.plain_message, old.category, old.severity);
        INSERT INTO findings_fts(rowid, title, plain_message, category, severity)
        VALUES (new.id, new.title, new.plain_message, new.category, new.severity);
      END
      """

      execute """
      INSERT INTO findings_fts(rowid, title, plain_message, category, severity)
      SELECT id, title, plain_message, category, severity FROM findings
      """

      execute """
      CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
        title,
        validation_gate,
        status,
        content='tasks',
        content_rowid='id'
      )
      """

      execute """
      CREATE TRIGGER IF NOT EXISTS tasks_fts_insert AFTER INSERT ON tasks BEGIN
        INSERT INTO tasks_fts(rowid, title, validation_gate, status)
        VALUES (new.id, new.title, new.validation_gate, new.status);
      END
      """

      execute """
      CREATE TRIGGER IF NOT EXISTS tasks_fts_delete AFTER DELETE ON tasks BEGIN
        INSERT INTO tasks_fts(tasks_fts, rowid, title, validation_gate, status)
        VALUES ('delete', old.id, old.title, old.validation_gate, old.status);
      END
      """

      execute """
      CREATE TRIGGER IF NOT EXISTS tasks_fts_update AFTER UPDATE ON tasks BEGIN
        INSERT INTO tasks_fts(tasks_fts, rowid, title, validation_gate, status)
        VALUES ('delete', old.id, old.title, old.validation_gate, old.status);
        INSERT INTO tasks_fts(rowid, title, validation_gate, status)
        VALUES (new.id, new.title, new.validation_gate, new.status);
      END
      """

      execute """
      INSERT INTO tasks_fts(rowid, title, validation_gate, status)
      SELECT id, title, validation_gate, status FROM tasks
      """
    end
  end

  def down do
    if sqlite_repo?() do
      execute "DROP TRIGGER IF EXISTS tasks_fts_insert"
      execute "DROP TRIGGER IF EXISTS tasks_fts_delete"
      execute "DROP TRIGGER IF EXISTS tasks_fts_update"
      execute "DROP TABLE IF EXISTS tasks_fts"

      execute "DROP TRIGGER IF EXISTS findings_fts_insert"
      execute "DROP TRIGGER IF EXISTS findings_fts_delete"
      execute "DROP TRIGGER IF EXISTS findings_fts_update"
      execute "DROP TABLE IF EXISTS findings_fts"
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
