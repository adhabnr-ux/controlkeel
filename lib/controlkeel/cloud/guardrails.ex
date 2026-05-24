defmodule ControlKeel.Cloud.Guardrails do
  @moduledoc """
  Inbound content guardrails for hosted MCP / A2A tool dispatches.

  Recursively scans tool call arguments for known secret and PII patterns
  before the call dispatches. When a pattern matches, the call is denied with
  a structured reason (e.g., `{:guardrail, :openai_api_key}`) and the
  authorization gate records the denial in the audit log.

  Default: **disabled** — guardrails are opt-in per workspace. This avoids
  surprising deployments where a previously-working tool call suddenly fails
  due to a pattern matching legitimate test data. Operators enable explicitly:

      config :controlkeel,
        cloud_mcp_guardrails: %{
          enabled: true,
          patterns: [:openai_api_key, :anthropic_api_key, :github_token, :aws_access_key],
          allow_for_tools: ["ck_validate"]
        }

  ## Built-in patterns

  Each pattern matches one well-known secret shape. Adding more is a config
  concern, not a code concern — see `extra_patterns` below.

    - `:openai_api_key` — `sk-[A-Za-z0-9]{20,}` (and ant variants)
    - `:anthropic_api_key` — `sk-ant-...`
    - `:github_token` — `ghp_/gho_/ghu_/ghs_/ghr_` prefixed
    - `:aws_access_key` — `AKIA[A-Z0-9]{16}`
    - `:slack_bot_token` — `xoxb-...`
    - `:google_api_key` — `AIza...`
    - `:stripe_secret_key` — `sk_live_...` / `sk_test_...`

  PII patterns are intentionally not built in — false-positive risk is high
  for free-form text payloads. Add them via `extra_patterns` config when the
  deployment really does want to block emails or phone numbers at the gateway.

  ## Allow-for tools

  `allow_for_tools` skips scanning for tools whose entire job is to handle
  sensitive content (e.g., a secret rotator). The list is workspace-trusted —
  these tools must still pass scope and policy checks.
  """

  @typedoc "Scan verdict."
  @type verdict ::
          :ok
          | {:error, {:guardrail, atom()}}

  @builtin_patterns %{
    openai_api_key: ~r/\bsk-(?!ant-)[A-Za-z0-9_\-]{20,}\b/,
    anthropic_api_key: ~r/\bsk-ant-[A-Za-z0-9_\-]{20,}\b/,
    github_token: ~r/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b/,
    aws_access_key: ~r/\bAKIA[A-Z0-9]{16}\b/,
    slack_bot_token: ~r/\bxox[abp]-[A-Za-z0-9\-]{10,}\b/,
    google_api_key: ~r/\bAIza[0-9A-Za-z\-_]{35}\b/,
    stripe_secret_key: ~r/\bsk_(?:live|test)_[A-Za-z0-9]{20,}\b/
  }

  @doc "Built-in pattern names."
  @spec builtin_pattern_names() :: [atom()]
  def builtin_pattern_names, do: Map.keys(@builtin_patterns) |> Enum.sort()

  @doc "Whether guardrails are currently enabled in config."
  @spec enabled?() :: boolean()
  def enabled? do
    config = current()
    Map.get(config, :enabled, false) == true
  end

  @doc "Currently active patterns (after config filtering and extras)."
  @spec active_patterns() :: [{atom(), Regex.t()}]
  def active_patterns do
    config = current()

    requested =
      case Map.get(config, :patterns) do
        nil -> Map.keys(@builtin_patterns)
        [] -> []
        list when is_list(list) -> list
      end

    base =
      requested
      |> Enum.flat_map(fn name ->
        case Map.get(@builtin_patterns, name) do
          nil -> []
          regex -> [{name, regex}]
        end
      end)

    extras =
      config
      |> Map.get(:extra_patterns, [])
      |> List.wrap()
      |> Enum.flat_map(&normalize_extra/1)

    base ++ extras
  end

  @doc "Compact summary suitable for dashboards / CLI."
  @spec summary() :: %{
          enabled: boolean(),
          pattern_count: non_neg_integer(),
          patterns: [atom()],
          allow_for_tools: [String.t()]
        }
  def summary do
    patterns = active_patterns()

    %{
      enabled: enabled?(),
      pattern_count: length(patterns),
      patterns: Enum.map(patterns, fn {name, _} -> name end),
      allow_for_tools: allow_for_tools()
    }
  end

  @doc """
  Scan one tool call's arguments for secret patterns.

  Returns `:ok` when guardrails are disabled, the tool is in the allow list,
  or no pattern matches. Returns `{:error, {:guardrail, pattern_name}}` on
  first match.
  """
  @spec scan(map(), String.t()) :: verdict()
  def scan(arguments, tool_name) when is_map(arguments) and is_binary(tool_name) do
    cond do
      not enabled?() -> :ok
      tool_name in allow_for_tools() -> :ok
      true -> scan_value(arguments, active_patterns())
    end
  end

  defp scan_value(value, patterns) when is_binary(value) do
    Enum.find_value(patterns, :ok, fn {name, regex} ->
      if Regex.match?(regex, value), do: {:error, {:guardrail, name}}, else: nil
    end)
  end

  defp scan_value(value, patterns) when is_list(value) do
    Enum.reduce_while(value, :ok, fn item, _acc ->
      case scan_value(item, patterns) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp scan_value(value, patterns) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {_k, v}, _acc ->
      case scan_value(v, patterns) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp scan_value(_, _), do: :ok

  defp allow_for_tools do
    current()
    |> Map.get(:allow_for_tools, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp normalize_extra({name, regex}) when is_atom(name) and is_struct(regex, Regex),
    do: [{name, regex}]

  defp normalize_extra(_), do: []

  defp current do
    case Application.get_env(:controlkeel, :cloud_mcp_guardrails) do
      m when is_map(m) -> m
      _ -> %{}
    end
  end
end
