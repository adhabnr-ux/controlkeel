defmodule ControlKeel.Utils.Yaml do
  @moduledoc false

  @doc """
  Serializes a map/list value into a YAML document string with sorted keys
  and explicit empty-map (`{}`) / empty-list (`[]`) handling.
  """
  def document(value) do
    encode(value, 0)
  end

  defp encode(value, indent) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("", fn {key, nested} ->
      key_value(to_string(key), nested, indent)
    end)
  end

  defp encode(value, indent) when is_list(value) do
    Enum.map_join(value, "", fn
      nested when is_map(nested) ->
        "#{String.duplicate(" ", indent)}-\n" <> encode(nested, indent + 2)

      nested ->
        "#{String.duplicate(" ", indent)}- #{scalar(nested)}\n"
    end)
  end

  defp key_value(key, value, indent) when is_map(value) do
    if map_size(value) == 0 do
      "#{String.duplicate(" ", indent)}#{key}: {}\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> encode(value, indent + 2)
    end
  end

  defp key_value(key, value, indent) when is_list(value) do
    if value == [] do
      "#{String.duplicate(" ", indent)}#{key}: []\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> encode(value, indent + 2)
    end
  end

  defp key_value(key, value, indent) do
    "#{String.duplicate(" ", indent)}#{key}: #{scalar(value)}\n"
  end

  defp scalar(value) when is_binary(value), do: Jason.encode!(value)
  defp scalar(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp scalar(nil), do: "null"
  defp scalar(value) when is_integer(value) or is_float(value), do: to_string(value)
end
