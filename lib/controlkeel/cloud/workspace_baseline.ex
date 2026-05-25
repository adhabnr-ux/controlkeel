defmodule ControlKeel.Cloud.WorkspaceBaseline do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace

  schema "workspace_baselines" do
    field :window_days, :integer, default: 7
    field :baseline_data, :string, default: "{}"
    field :sample_sessions, :integer, default: 0
    field :computed_at, :utc_datetime

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:workspace_id, :window_days, :baseline_data, :sample_sessions, :computed_at])
    |> validate_required([:workspace_id, :window_days, :baseline_data, :sample_sessions, :computed_at])
    |> validate_number(:window_days, greater_than: 0)
    |> validate_number(:sample_sessions, greater_than_or_equal_to: 0)
    |> assoc_constraint(:workspace)
    |> unique_constraint(:workspace_id)
  end

  @doc "Decode the stored baseline JSON into a map."
  def decode(%__MODULE__{baseline_data: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  def decode(_), do: %{}
end
