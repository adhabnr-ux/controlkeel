defmodule ControlKeel.Repo.Migrations.AddChunkIndexToMemoryEmbeddings do
  @moduledoc """
  Adds `chunk_index` to `memory_embeddings` for chunked retrieval.

  Chunked bodies store one row per chunk; the primary chunk keeps chunk_index 0
  and the original (provider, model) pair, while later chunks keep their own
  index. The unique constraint widens to include chunk_index.
  """
  use Ecto.Migration

  def up do
    alter table(:memory_embeddings) do
      add :chunk_index, :integer, null: false, default: 0
    end

    drop unique_index(:memory_embeddings, [:memory_record_id, :provider, :model])
    create unique_index(:memory_embeddings, [:memory_record_id, :provider, :model, :chunk_index])
    create index(:memory_embeddings, [:memory_record_id, :chunk_index])
  end

  def down do
    drop unique_index(:memory_embeddings, [:memory_record_id, :provider, :model, :chunk_index])
    drop index(:memory_embeddings, [:memory_record_id, :chunk_index])

    execute("""
    DELETE FROM memory_embeddings
    WHERE id NOT IN (
      SELECT MIN(id) FROM memory_embeddings
      GROUP BY memory_record_id, provider, model
    )
    """)

    create unique_index(:memory_embeddings, [:memory_record_id, :provider, :model])

    alter table(:memory_embeddings) do
      remove :chunk_index
    end
  end
end
