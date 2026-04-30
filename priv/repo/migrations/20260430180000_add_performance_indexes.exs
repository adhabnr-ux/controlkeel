defmodule ControlKeel.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # findings: hot path in problems/1 filters status IN [open,blocked,escalated]
    # and orders by inserted_at DESC — composite avoids a full scan + sort.
    create index(:findings, [:status, :inserted_at], name: :findings_status_inserted_at_idx)

    # findings: session_run/1 and problem_findings/1 filter session_id + status together.
    create index(:findings, [:session_id, :status], name: :findings_session_id_status_idx)

    # findings: category+rule_id grouping in problems/1 — partial composite for active rows.
    create index(:findings, [:category, :rule_id, :status],
             name: :findings_category_rule_id_status_idx
           )

    # memory_records: memory quality and search filter workspace_id, exclude archived,
    # order by inserted_at DESC — composite eliminates the filesort.
    create index(:memory_records, [:workspace_id, :archived_at, :inserted_at],
             name: :memory_records_workspace_archived_inserted_idx
           )

    # memory_records: score-ordered retrieval filters workspace_id + record_type.
    create index(:memory_records, [:workspace_id, :record_type, :inserted_at],
             name: :memory_records_workspace_type_inserted_idx
           )

    # sessions: workspace + inserted_at ordering is the trend_sessions hot path.
    create index(:sessions, [:workspace_id, :inserted_at],
             name: :sessions_workspace_inserted_at_idx
           )

    # invocations: cost grouping queries filter session/workspace + inserted_at.
    create index(:invocations, [:session_id, :inserted_at],
             name: :invocations_session_inserted_at_idx
           )
  end
end
