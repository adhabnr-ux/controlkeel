defmodule ControlKeel.Repo.Migrations.AddRlmFieldsToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :input_refs, {:array, :string}, default: []
      add :output_ref, :string
      add :trust_policy, :string, default: "full"
    end
  end
end
