defmodule ControlKeel.Repo.Migrations.AddProvenanceToFindings do
  use Ecto.Migration

  def change do
    alter table(:findings) do
      add :extends_finding_id, references(:findings, on_delete: :nilify_all)
      add :contradicts_finding_id, references(:findings, on_delete: :nilify_all)
    end

    create index(:findings, [:extends_finding_id])
    create index(:findings, [:contradicts_finding_id])
  end
end
