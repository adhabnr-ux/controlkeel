defmodule ControlKeel.Repo.Migrations.AddOrgFkToWorkspaces do
  @moduledoc """
  Enforces referential integrity for `workspaces.org_id`.

  Solo workspaces (org_id NULL) remain a first-class product concept —
  cloud execution authz authorizes them without org membership. This
  migration only guarantees that a non-null org_id always references an
  existing org row, closing the dangling-reference gap. Org deletion
  detaches its workspaces back to solo rather than cascading.
  """
  use Ecto.Migration

  def up do
    # Clean any dangling references before adding the constraint.
    execute("""
    UPDATE workspaces SET org_id = NULL
    WHERE org_id IS NOT NULL AND org_id NOT IN (SELECT id FROM orgs)
    """)

    if sqlite_repo?() do
      rebuild_workspaces_with_fk()
    else
      execute("""
      ALTER TABLE workspaces
      ADD CONSTRAINT workspaces_org_id_fkey
      FOREIGN KEY (org_id) REFERENCES orgs(id) ON DELETE SET NULL
      """)
    end
  end

  def down do
    if sqlite_repo?() do
      rebuild_workspaces_without_fk()
    else
      execute("ALTER TABLE workspaces DROP CONSTRAINT workspaces_org_id_fkey")
    end
  end

  defp rebuild_workspaces_with_fk do
    execute("""
    CREATE TABLE workspaces_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      industry TEXT NOT NULL,
      agent TEXT NOT NULL,
      budget_cents INTEGER NOT NULL DEFAULT 0,
      compliance_profile TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      org_id INTEGER REFERENCES orgs(id) ON DELETE SET NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO workspaces_new (id, name, slug, industry, agent, budget_cents, compliance_profile, status, org_id, inserted_at, updated_at)
    SELECT id, name, slug, industry, agent, budget_cents, compliance_profile, status, org_id, inserted_at, updated_at
    FROM workspaces
    """)

    execute("DROP TABLE workspaces")
    execute("ALTER TABLE workspaces_new RENAME TO workspaces")

    recreate_indexes()
  end

  defp rebuild_workspaces_without_fk do
    execute("""
    CREATE TABLE workspaces_old (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      industry TEXT NOT NULL,
      agent TEXT NOT NULL,
      budget_cents INTEGER NOT NULL DEFAULT 0,
      compliance_profile TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      org_id INTEGER,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO workspaces_old (id, name, slug, industry, agent, budget_cents, compliance_profile, status, org_id, inserted_at, updated_at)
    SELECT id, name, slug, industry, agent, budget_cents, compliance_profile, status, org_id, inserted_at, updated_at
    FROM workspaces
    """)

    execute("DROP TABLE workspaces")
    execute("ALTER TABLE workspaces_old RENAME TO workspaces")

    recreate_indexes()
  end

  defp recreate_indexes do
    create unique_index(:workspaces, [:slug])
    create index(:workspaces, [:industry])
    create index(:workspaces, [:agent])
    create index(:workspaces, [:org_id])
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
