defmodule ControlKeelWeb.FormatHelpers do
  @moduledoc """
  Shared presentation helpers imported into every view through the
  `html_helpers` block in `ControlKeelWeb`. Dependency-free: stdlib
  `Calendar`/`DateTime` only.

  Extracted from the private `format_datetime/1` copies that lived in
  `observability_problems_live`, `proof_browser_live`, and the session run
  page so every view formats timestamps the same way.
  """

  @doc """
  Formats a timestamp for display. Accepts a `DateTime`, `NaiveDateTime`,
  ISO8601 string, `nil`, or `""`. Unparseable strings pass through unchanged.

  `fallback` is returned for `nil`/`""` so callers can preserve page-specific
  empty-state copy (e.g. the proof browser shows "Not recorded"). Defaults to
  "unknown" to match the observability pages.
  """
  def format_datetime(value, fallback \\ "unknown")

  def format_datetime(nil, fallback), do: fallback
  def format_datetime("", fallback), do: fallback

  def format_datetime(%DateTime{} = dt, _fallback),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  def format_datetime(%NaiveDateTime{} = dt, _fallback),
    do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")

  def format_datetime(value, _fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
          _ -> value
        end
    end
  end

  def format_datetime(value, _fallback), do: to_string(value)

  @doc """
  CSS class string for a neutral pill/badge used in observability pages.
  Consolidated here to eliminate duplication across eight LiveViews.
  """
  def neutral_pill_class,
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,255,255,0.04)] text-[var(--ck-text)]"
end
