defmodule ControlKeel.Repo.Migrations.AddVisibilityToMemoryRecords do
  use Ecto.Migration

  def change do
    alter table(:memory_records) do
      add :visibility, :string, default: "workspace", null: false
      add :shared_org_id, :integer
    end

    create index(:memory_records, [:visibility])
    create index(:memory_records, [:shared_org_id])
  end
end
