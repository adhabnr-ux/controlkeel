defmodule ControlKeel.MCP.Discovery do
  @moduledoc """
  MCP server discovery module for auto-discovering tools from external MCP servers.

  This module implements progressive discovery for MCP tools, allowing CK to query
  an MCP server's tools/list endpoint and return discovered tool schemas without
  requiring manual configuration.

  Currently supports HTTP-based MCP servers. stdio-based discovery is planned
  for future implementation.
  """

  require Logger

  @default_timeout 10_000

  @doc """
  Discover tools from an MCP server.

  ## Parameters
    - server_url: URL of the MCP server (e.g., "http://localhost:3001/mcp")
    - opts: Optional parameters
      - :timeout - Request timeout in milliseconds (default: 10_000)
      - :transport - Transport type (:stdio or :http, default: auto-detect from URL)

  ## Returns
    - {:ok, discovery_result} on success
    - {:error, reason} on failure

  ## Example
      iex> ControlKeel.MCP.Discovery.discover("http://localhost:3001/mcp")
      {:ok, %{
        server_url: "http://localhost:3001/mcp",
        transport: :http,
        tools: [...],
        total: 5
      }}
  """
  def discover(server_url, opts \\ []) do
    transport = Keyword.get(opts, :transport, detect_transport(server_url))
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case transport do
      :http ->
        discover_http(server_url, timeout)

      :stdio ->
        discover_stdio(server_url, timeout)

      other ->
        {:error, {:unsupported_transport, other}}
    end
  end

  @doc """
  Validate that a server URL is accessible and responds to MCP protocol.

  ## Parameters
    - server_url: URL of the MCP server
    - opts: Optional parameters (same as discover/2)

  ## Returns
    - :ok if server is accessible
    - {:error, reason} if not
  """
  def validate_server(server_url, opts \\ []) do
    case discover(server_url, opts) do
      {:ok, _result} -> :ok
      error -> error
    end
  end

  defp detect_transport(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        :http

      String.starts_with?(url, "stdio://") or String.starts_with?(url, "/") ->
        :stdio

      true ->
        # Default to HTTP for unknown schemes
        :http
    end
  end

  defp discover_http(server_url, timeout) do
    request_body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list",
        "params" => %{}
      })

    url = String.to_charlist(normalize_http_url(server_url))
    headers = [{~c"Content-Type", ~c"application/json"}]
    content_type = ~c"application/json"

    http_options = [timeout: timeout]
    request_options = [body_format: :binary]

    case :httpc.request(
           :post,
           {url, headers, content_type, request_body},
           http_options,
           request_options
         ) do
      {:ok, {{_http_version, 200, _reason_phrase}, _resp_headers, body}} ->
        parse_tools_response(body, server_url, :http)

      {:ok, {{_http_version, status, _reason_phrase}, _resp_headers, _body}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_request_failed, reason}}
    end
  end

  defp normalize_http_url(url) do
    case URI.parse(url) do
      %{path: nil} -> url <> "/"
      %{path: ""} -> url <> "/"
      _ -> url
    end
  end

  defp discover_stdio(server_path, _timeout) do
    {:ok,
     %{
       server_url: server_path,
       transport: :stdio,
       tools: [],
       total: 0,
       note: "stdio discovery requires process spawning - not yet implemented"
     }}
  end

  defp parse_tools_response(body, server_url, transport) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"result" => %{"tools" => tools}}} when is_list(tools) ->
        {:ok,
         %{
           server_url: server_url,
           transport: transport,
           tools: normalize_tools(tools),
           total: length(tools)
         }}

      {:ok, %{"error" => error}} ->
        {:error, {:mcp_error, error}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, {:json_decode_failed, reason}}
    end
  end

  defp normalize_tools(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      %{
        "name" => Map.get(tool, "name"),
        "description" => Map.get(tool, "description"),
        "input_schema" => Map.get(tool, "inputSchema", %{}),
        "original" => tool
      }
    end)
  end
end
