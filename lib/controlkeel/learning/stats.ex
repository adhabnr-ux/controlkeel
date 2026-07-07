defmodule ControlKeel.Learning.Stats do
  @moduledoc false

  @doc """
  Numeric median of a list. Returns nil for an empty list, a float rounded to
  one decimal place otherwise. Used by OutcomeTracker and observability so
  depth/length aggregates stay consistent across surfaces.
  """
  def median([]), do: nil

  def median(values) when is_list(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 0 do
      ((Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2) |> Float.round(1)
    else
      Enum.at(sorted, mid) * 1.0
    end
  end

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

  @doc """
  True when `value` falls within `[from, to]`, inclusive on both ends. Accepts
  the same value shapes as `at_or_after?/2`.
  """
  def within?(value, %DateTime{} = from, %DateTime{} = to) do
    at_or_after?(value, from) and not at_or_after?(value, DateTime.add(to, 1, :second))
  end

  @doc """
  Convenience wrapper: returns a DateTime `seconds` before now.
  """
  def ago(seconds) when is_integer(seconds) and seconds >= 0,
    do: DateTime.add(DateTime.utc_now(), -seconds, :second)
end
