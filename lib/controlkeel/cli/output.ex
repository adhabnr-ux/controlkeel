defmodule ControlKeel.CLI.Output do
  @moduledoc """
  Shared machine-readable output helpers for CLI surfaces.
  """

  def json_requested?(argv) when is_list(argv) do
    Enum.any?(argv, &(&1 == "--json")) or format_json_requested?(argv)
  end

  def error_json(message, code, entry, details \\ %{}) do
    payload = %{
      "error" => message,
      "code" => to_string(code),
      "command" => entry && entry.path,
      "hint" => hint(entry),
      "examples" => examples(entry),
      "help_topic" => entry && entry.help_topic,
      "details" => details
    }

    Jason.encode!(payload)
  end

  defp format_json_requested?(["--format", "json" | _rest]), do: true
  defp format_json_requested?([_head | rest]), do: format_json_requested?(rest)
  defp format_json_requested?([]), do: false

  defp hint(nil), do: "Run: controlkeel help"
  defp hint(entry), do: "Run: controlkeel #{entry.path} --help"

  defp examples(nil), do: []
  defp examples(entry), do: entry.examples
end
