defmodule ControlKeel.MCP.Tools.CkMcpDiscover do
  @moduledoc """
  MCP tool: ck_mcp_discover

  Auto-discovers tools from an external MCP server by querying its tools/list endpoint.
  This enables progressive discovery of MCP capabilities without manual configuration.
  """

  alias ControlKeel.MCP.Discovery

  def call(arguments) when is_map(arguments) do
    case validate_arguments(arguments) do
      :ok ->
        server_url = Map.get(arguments, "server_url")
        opts = build_opts(arguments)

        case Discovery.discover(server_url, opts) do
          {:ok, result} ->
            {:ok,
             %{
               "server_url" => result.server_url,
               "transport" => Atom.to_string(result.transport),
               "tools" => result.tools,
               "total" => result.total,
               "usage_hint" =>
                 "Use the discovered tool schemas to understand available capabilities. " <>
                   "To register these tools with CK, use the MCP client configuration or skills system."
             }
             |> then(fn r ->
               if Map.has_key?(result, :note), do: Map.put(r, "note", result.note), else: r
             end)}

          {:error, reason} ->
            {:error, format_error(reason)}
        end

      {:error, reason} ->
        {:error, {:invalid_arguments, reason}}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp validate_arguments(arguments) do
    case Map.get(arguments, "server_url") do
      nil -> {:error, "`server_url` is required"}
      url when is_binary(url) and url != "" -> :ok
      _ -> {:error, "`server_url` must be a non-empty string"}
    end
  end

  defp build_opts(arguments) do
    opts = []

    opts =
      if Map.has_key?(arguments, "timeout") do
        case Map.get(arguments, "timeout") do
          timeout when is_integer(timeout) and timeout > 0 ->
            [{:timeout, timeout} | opts]

          _ ->
            opts
        end
      else
        opts
      end

    opts =
      if Map.has_key?(arguments, "transport") do
        case Map.get(arguments, "transport") do
          "http" ->
            [{:transport, :http} | opts]

          _ ->
            opts
        end
      else
        opts
      end

    opts
  end

  defp format_error({:blocked_target, host}) do
    "Refusing to discover from private/loopback target: #{inspect(host)}. " <>
      "Set :controlkeel, :mcp_discovery_allow_private to true to opt in."
  end

  defp format_error({:invalid_url, url}) do
    "Invalid URL: #{inspect(url)}. Must include scheme and host."
  end

  defp format_error({:response_too_large, size}) do
    "MCP server response exceeded size limit (got #{inspect(size)} bytes)"
  end

  defp format_error({:unsupported_transport, transport}) do
    "Unsupported transport: #{inspect(transport)}. Supported transport: http"
  end

  defp format_error({:http_error, status}) do
    "HTTP request failed with status: #{status}"
  end

  defp format_error({:http_request_failed, reason}) do
    "HTTP request failed: #{inspect(reason)}"
  end

  defp format_error({:mcp_error, error}) do
    "MCP server returned an error: #{inspect(error)}"
  end

  defp format_error({:unexpected_response, response}) do
    "Unexpected MCP server response: #{inspect(response)}"
  end

  defp format_error({:json_decode_failed, reason}) do
    "Failed to decode MCP server response as JSON: #{inspect(reason)}"
  end

  defp format_error(reason) when is_binary(reason) do
    reason
  end

  defp format_error(reason) do
    inspect(reason)
  end
end
