defmodule ControlKeel.Utils do
  @moduledoc false

  @doc """
  Shallow key stringification: converts top-level keys to strings, leaves values untouched.
  """
  def stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  @doc """
  Deep key stringification: recursively converts map keys to strings, recursing into
  nested maps and lists. Non-map/non-list values pass through unchanged.
  """
  def stringify_keys_deep(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys_deep(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  def stringify_keys_deep(value), do: value

  @doc """
  Deep key stringification with list recursion: recursively converts map keys to
  strings, recursing into nested maps and lists. Non-map/non-list values pass
  through unchanged. Returns `%{}` for non-map inputs.
  """
  def stringify_keys_deep_list(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {to_string(key), stringify_keys_deep_list_value(value)}
    end)
  end

  def stringify_keys_deep_list(_other), do: %{}

  defp stringify_keys_deep_list_value(value) when is_map(value),
    do: stringify_keys_deep_list(value)

  defp stringify_keys_deep_list_value(value) when is_list(value),
    do: Enum.map(value, &stringify_keys_deep_list_value/1)

  defp stringify_keys_deep_list_value(value), do: value

  @doc """
  Converts nil and empty strings to nil, passes through all other values.
  """
  def blank_to_nil(nil), do: nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value
end
