defmodule ControlKeel.Repo.Migrations.CreateCloudMcpToolCalls do
  use Ecto.Migration

  def change do
    create table(:cloud_mcp_tool_calls) do
      add :workspace_id, :integer
      add :service_account_id, :integer
      add :resource, :string, null: false
      add :tool_name, :string, null: false
      add :outcome, :string, null: false
      add :denial_reason, :string
      add :scopes_granted, :text
      add :argument_keys, :text
      add :requested_at, :utc_datetime, null: false
    end

    create index(:cloud_mcp_tool_calls, [:workspace_id, :requested_at])
    create index(:cloud_mcp_tool_calls, [:tool_name, :requested_at])
    create index(:cloud_mcp_tool_calls, [:outcome, :requested_at])
  end
end
