defmodule ControlKeel.Cloud.Redactor do
  @moduledoc """
  Apply the workspace's redaction policy to a telemetry payload before it leaves
  the local node.

  Two surfaces:

    * `redact/1` — full normalization + pattern scrubbing. Returns
      `{:ok, payload, policy_version}` on success or `{:error, reason}`. Fail-closed:
      payloads with non-JSON-safe values are rejected outright.

    * `redact_string/1` and `redact_value/1` — pattern-only scrubbing for callers
      that have already normalized the shape (e.g. `Cloud.Sync.serialize_payload`).

  Current rules (policy version `2026.05.28`):

    * Anthropic `sk-ant-*` keys → `[REDACTED:sk-ant]`
    * Generic `sk-*` keys → `[REDACTED:sk]`
    * GitHub PATs (`gh[psour]_*`) → `[REDACTED:gh-token]`
    * `Authorization` / `Bearer` headers → `[REDACTED]`
    * `token=` / `key=` / `secret=` / `password=` / `api_key=` env-style → `[REDACTED]`
    * Long base64-ish strings (≥60 chars) → `[REDACTED:base64-ish]` (heuristic; runs last)

  False positives are preferable to leaks.
  """

  @policy_version "2026.05.28"

  # Patterns are applied in order — earlier patterns win when matches overlap.
  @patterns [
    {~r/sk-ant-[A-Za-z0-9_-]{20,}/, "[REDACTED:sk-ant]"},
    {~r/sk-[A-Za-z0-9_-]{20,}/, "[REDACTED:sk]"},
    {~r/gh[psour]_[A-Za-z0-9_]{30,}/, "[REDACTED:gh-token]"},
    # Authorization: Bearer <token> (full header — also catches "Authorization=...")
    {~r/(?i)authorization\s*[:=]\s*(?:bearer\s+)?\S+/, "Authorization: [REDACTED]"},
    # Standalone "Bearer <token>"
    {~r/(?i)bearer\s+\S+/, "Bearer [REDACTED]"},
    {~r/(?i)(token|key|secret|password|api_key)\s*=\s*[^\s&]+/, "\\1=[REDACTED]"},
    {~r/[A-Za-z0-9+\/]{60,}={0,2}/, "[REDACTED:base64-ish]"}
  ]

  @doc "The redaction policy version that this module currently implements."
  @spec policy_version() :: String.t()
  def policy_version, do: @policy_version

  @doc """
  Redact a payload according to the current policy.

  Normalizes the payload to JSON-safe shapes (strings/numbers/booleans/nil/maps/lists)
  and applies pattern scrubbing to every string value.
  """
  @spec redact(map()) :: {:ok, map(), String.t()} | {:error, term()}
  def redact(payload) when is_map(payload) do
    case normalize_payload(payload) do
      {:ok, normalized} -> {:ok, normalized, @policy_version}
      {:error, _} = err -> err
    end
  end

  def redact(_), do: {:error, :payload_must_be_a_map}

  @doc """
  Scrub credential-shaped substrings from a string. Idempotent: re-scrubbing a
  scrubbed value is a no-op.
  """
  @spec redact_string(term()) :: term()
  def redact_string(value) when is_binary(value) do
    Enum.reduce(@patterns, value, fn {pattern, replacement}, acc ->
      String.replace(acc, pattern, replacement)
    end)
  end

  def redact_string(value), do: value

  @doc """
  Recursively scrub a value of any JSON-safe shape. Strings get pattern-replaced,
  maps and lists are walked, DateTime/Date/Time and other terms pass through.
  """
  @spec redact_value(term()) :: term()
  def redact_value(value) when is_binary(value), do: redact_string(value)

  def redact_value(%DateTime{} = v), do: v
  def redact_value(%NaiveDateTime{} = v), do: v
  def redact_value(%Date{} = v), do: v
  def redact_value(%Time{} = v), do: v

  def redact_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, redact_value(v)} end)
  end

  def redact_value(value) when is_list(value), do: Enum.map(value, &redact_value/1)

  def redact_value(value), do: value

  defp normalize_payload(payload) do
    payload
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, key_string} <- normalize_key(key),
           {:ok, normalized_value} <- normalize_value(value) do
        {:cont, {:ok, Map.put(acc, key_string, normalized_value)}}
      else
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp normalize_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_key(_), do: {:error, :payload_keys_must_be_strings_or_atoms}

  defp normalize_value(value) when is_binary(value), do: {:ok, redact_string(value)}
  defp normalize_value(value) when is_integer(value), do: {:ok, value}
  defp normalize_value(value) when is_float(value), do: {:ok, value}
  defp normalize_value(value) when is_boolean(value), do: {:ok, value}
  defp normalize_value(nil), do: {:ok, nil}

  defp normalize_value(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case normalize_value(item) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      err -> err
    end
  end

  defp normalize_value(value) when is_map(value), do: normalize_payload(value)

  defp normalize_value(_), do: {:error, :unsupported_payload_value_type}
end
