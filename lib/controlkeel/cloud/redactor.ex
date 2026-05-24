defmodule ControlKeel.Cloud.Redactor do
  @moduledoc """
  Apply the workspace's redaction policy to a telemetry payload before it leaves
  the local node.

  This module is intentionally a thin skeleton in this slice — the call site is
  stable so later slices can plug in pattern-based PII/secret detection without
  changing every emitter. The redaction-policy version is stamped on every
  envelope so consumers know which rules ran.

  Current rules (policy version "2026.05"):

    - Pass-through for governance-metadata-level payloads (counts, IDs, severity)
    - Drop unknown atom values (force string/integer/map at envelope build time)
    - No PII / secret pattern matching yet — that lands in a follow-up slice

  Returning `{:ok, payload, policy_version}` lets callers persist the policy
  version inline. Returning `{:error, reason}` blocks the egress (fail-closed).
  """

  @policy_version "2026.05"

  @doc "The redaction policy version that this module currently implements."
  @spec policy_version() :: String.t()
  def policy_version, do: @policy_version

  @doc """
  Redact a payload according to the current policy.

  In this slice the rules are minimal: enforce that the payload is a map of
  string keys and primitive values. Anything else fails closed.
  """
  @spec redact(map()) :: {:ok, map(), String.t()} | {:error, term()}
  def redact(payload) when is_map(payload) do
    case normalize_payload(payload) do
      {:ok, normalized} -> {:ok, normalized, @policy_version}
      {:error, _} = err -> err
    end
  end

  def redact(_), do: {:error, :payload_must_be_a_map}

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

  defp normalize_value(value) when is_binary(value), do: {:ok, value}
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
