defmodule ControlKeel.Repo.Migrations.AddFullTextSearchToFindingsAndTasks do
  use Ecto.Migration

  def up do
    # Create FTS5 virtual table for findings
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

    # Create triggers to keep FTS table in sync
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

    # Populate existing findings
    execute """
    INSERT INTO findings_fts(rowid, title, plain_message, category, severity)
    SELECT id, title, plain_message, category, severity FROM findings
    """

    # Create FTS5 virtual table for tasks
    execute """
    CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
      title,
      validation_gate,
      status,
      content='tasks',
      content_rowid='id'
    )
    """

    # Create triggers to keep FTS table in sync
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

    # Populate existing tasks
    execute """
    INSERT INTO tasks_fts(rowid, title, validation_gate, status)
    SELECT id, title, validation_gate, status FROM tasks
    """
  end

  def down do
    # Drop FTS tables and triggers for tasks
    execute "DROP TRIGGER IF EXISTS tasks_fts_insert"
    execute "DROP TRIGGER IF EXISTS tasks_fts_delete"
    execute "DROP TRIGGER IF EXISTS tasks_fts_update"
    execute "DROP TABLE IF EXISTS tasks_fts"

    # Drop FTS tables and triggers for findings
    execute "DROP TRIGGER IF EXISTS findings_fts_insert"
    execute "DROP TRIGGER IF EXISTS findings_fts_delete"
    execute "DROP TRIGGER IF EXISTS findings_fts_update"
    execute "DROP TABLE IF EXISTS findings_fts"
  end
end
