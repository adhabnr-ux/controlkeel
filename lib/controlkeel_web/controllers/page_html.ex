defmodule ControlKeelWeb.PageHTML do
  use ControlKeelWeb, :html

  import ControlKeelWeb.ProviderStatusComponents

  embed_templates "page_html/*"

  def format_percent(nil), do: "Not recorded"
  def format_percent(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  def format_percent(value), do: "#{value}%"

  def format_number(nil), do: "Not recorded"
  def format_number(value) when is_float(value), do: Float.round(value, 1)
  def format_number(value), do: value
end
