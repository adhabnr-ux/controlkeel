defmodule ControlKeel.Repo.Migrations.AddLockVersionToEvalCandidates do
  @moduledoc """
  Adds a `lock_version` column to `observability_eval_candidates` for Ecto
  optimistic locking.

  `Observability.update_eval_candidate_from_results/4` performs a
  read-modify-write on `candidate.metadata` (it reads `lifecycle_seq`, builds a
  new marker, and writes the whole map). Without optimistic locking, two
  benchmark runs completing concurrently for the same candidate both read the
  same snapshot and the last write silently drops the other transition's
  marker, which can mislead the `Observability.Promotion` policy (issue #50).

  Wrapping that write in `Ecto.Changeset.optimistic_lock(:lock_version)` makes
  a stale-snapshot update return `{:error, :stale}`, which the caller retries
  against a fresh read.

  ## SQLite + Postgres

  Both support `ALTER TABLE … ADD COLUMN … DEFAULT … NOT NULL` when a default
  is supplied (existing rows are backfilled to 1, matching the schema default).
  No adapter branching is needed.
  """

  use Ecto.Migration

  def change do
    alter table(:observability_eval_candidates) do
      add :lock_version, :integer, default: 1, null: false
    end
  end
end
