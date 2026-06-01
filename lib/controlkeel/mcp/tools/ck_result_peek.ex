defmodule ControlKeel.MCP.Tools.CkResultPeek do
  @moduledoc false

  @default_peek_bytes 2_000
  @max_peek_bytes 32_000

  def call(arguments) when is_map(arguments) do
    with {:ok, package_root} <- required_binary(arguments, "package_root"),
         {:ok, peek_bytes} <- normalize_peek_bytes(Map.get(arguments, "peek_bytes")),
         {:ok, offset} <- normalize_offset(Map.get(arguments, "offset")) do
      stdout_path = Path.join(package_root, "stdout.txt")

      case File.stat(stdout_path) do
        {:ok, %{size: total_bytes}} ->
          content =
            case File.open(stdout_path, [:read, :binary]) do
              {:ok, io} ->
                _ = if offset > 0, do: :file.position(io, offset)
                chunk = IO.binread(io, peek_bytes)
                _ = File.close(io)
                if is_binary(chunk), do: chunk, else: ""

              _ ->
                ""
            end

          {:ok,
           %{
             "package_root" => package_root,
             "total_bytes" => total_bytes,
             "offset" => offset,
             "peek_bytes" => peek_bytes,
             "content" => content,
             "remaining_bytes" => max(0, total_bytes - offset - byte_size(content)),
             "truncated" => total_bytes > offset + peek_bytes
           }}

        {:error, :enoent} ->
          {:error,
           {:invalid_arguments,
            "No stdout.txt found at package_root — result may not have been written yet"}}

        {:error, reason} ->
          {:error, "Could not read result: #{inspect(reason)}"}
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp required_binary(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, String.trim(value)}
      _ -> {:error, {:invalid_arguments, "`#{key}` is required"}}
    end
  end

  defp normalize_peek_bytes(nil), do: {:ok, @default_peek_bytes}
  defp normalize_peek_bytes(n) when is_integer(n) and n > 0, do: {:ok, min(n, @max_peek_bytes)}

  defp normalize_peek_bytes(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> {:ok, min(n, @max_peek_bytes)}
      _ -> {:error, {:invalid_arguments, "`peek_bytes` must be a positive integer"}}
    end
  end

  defp normalize_peek_bytes(_),
    do: {:error, {:invalid_arguments, "`peek_bytes` must be a positive integer"}}

  defp normalize_offset(nil), do: {:ok, 0}
  defp normalize_offset(n) when is_integer(n) and n >= 0, do: {:ok, n}

  defp normalize_offset(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, {:invalid_arguments, "`offset` must be a non-negative integer"}}
    end
  end

  defp normalize_offset(_),
    do: {:error, {:invalid_arguments, "`offset` must be a non-negative integer"}}
end
