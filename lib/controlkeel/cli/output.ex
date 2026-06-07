defmodule ControlKeel.CLI.Output do
  @moduledoc """
  Shared machine-readable output helpers for CLI surfaces.

  Provides a stable JSON envelope for both success and error outputs.
  Agents can check the "status" key to distinguish success ("ok") from
  error ("error") without parsing the full payload shape.
  """

  @doc """
  Render a command result in either JSON or text format.

  Removes the repeated `case format do` boilerplate across every CLI dispatch
  command.  `text_fn` receives `payload` and must return a list of strings.
  """
  def render_format(format, payload, text_fn) do
    case format do
      "json" -> {:ok, [Jason.encode!(payload)]}
      _ -> {:ok, text_fn.(payload)}
    end
  end

  def json_requested?(argv) when is_list(argv) do
    Enum.any?(argv, &(&1 == "--json")) or format_json_requested?(argv)
  end

  @doc """
  Wraps a command payload in a standard success envelope.

  ## Envelope

      %{
        "status" => "ok",
        "command" => "status",
        "data" => <payload>,
        "version" => "0.3.33"
      }

  Opts:
    - `:version` — ControlKeel version string (recommended)
    - `:pagination` — optional pagination metadata map
  """
  def success_json(command_path, payload, opts \\ []) do
    envelope = %{
      "status" => "ok",
      "command" => command_path,
      "data" => payload,
      "version" => Keyword.get(opts, :version)
    }

    envelope
    |> maybe_put("pagination", Keyword.get(opts, :pagination))
    |> Jason.encode!()
  end

  @doc """
  Produces a stable JSON error envelope.

  Includes "status" => "error" so agents can branch on a single key
  alongside the existing error, code, command, hint, examples, and
  help_topic fields.
  """
  def error_json(message, code, entry, details \\ %{}) do
    %{
      "status" => "error",
      "error" => message,
      "code" => to_string(code),
      "command" => entry && entry.path,
      "version" => version(),
      "hint" => hint(entry),
      "examples" => examples(entry),
      "help_topic" => entry && entry.help_topic,
      "details" => details
    }
    |> Jason.encode!()
  end

  defp version do
    Application.spec(:controlkeel, :vsn)
    |> Kernel.||("0.1.0")
    |> to_string()
  end

  defp format_json_requested?(["--format", "json" | _rest]), do: true
  defp format_json_requested?([_head | rest]), do: format_json_requested?(rest)
  defp format_json_requested?([]), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp hint(nil), do: "Run: controlkeel help"
  defp hint(entry), do: "Run: controlkeel #{entry.path} --help"

  defp examples(nil), do: []
  defp examples(entry), do: entry.examples
end
