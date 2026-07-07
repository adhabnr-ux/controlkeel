defmodule ControlKeel.Learning.Stats do
  @moduledoc false

  @doc """
  True when `value` is at or after `cutoff`. Accepts DateTime, NaiveDateTime
  (treated as UTC), or an ISO-8601 string. nil and unparseable inputs are false.
  """
  def at_or_after?(nil, _cutoff), do: false

  def at_or_after?(%DateTime{} = dt, %DateTime{} = cutoff),
    do: DateTime.compare(dt, cutoff) in [:gt, :eq]

  def at_or_after?(%NaiveDateTime{} = naive, %DateTime{} = cutoff),
    do: at_or_after?(DateTime.from_naive!(naive, "Etc/UTC"), cutoff)

  def at_or_after?(iso, %DateTime{} = cutoff) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> at_or_after?(dt, cutoff)
      _ -> false
    end
  end

  def at_or_after?(_value, _cutoff), do: false
end
