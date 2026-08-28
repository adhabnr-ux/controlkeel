defmodule ControlKeel.Memory.Embedding do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Memory.Record
  alias ControlKeel.Types.JsonList

  schema "memory_embeddings" do
    field :provider, :string
    field :model, :string
    field :dimensions, :integer
    field :chunk_index, :integer, default: 0
    field :embedding, JsonList, source: :embedding_text, default: []

    belongs_to :memory_record, Record

    timestamps(type: :utc_datetime)
  end

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [:memory_record_id, :provider, :model, :dimensions, :chunk_index, :embedding])
    |> validate_required([:memory_record_id, :provider, :model, :dimensions, :embedding])
    |> validate_number(:dimensions, greater_than: 0)
    |> validate_number(:chunk_index, greater_than_or_equal_to: 0)
    |> unique_constraint([:memory_record_id, :provider, :model, :chunk_index])
    |> assoc_constraint(:memory_record)
  end
end
