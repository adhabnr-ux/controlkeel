defmodule ControlKeel.Cloud.McpRegistry do
  @moduledoc """
  Vetted registry of downstream MCP servers for the hosted gateway.

  Addresses the "Smithery has 6000+ unverified MCP servers" enterprise objection
  identified in the competitive research: enterprises want to declare which
  downstream MCP endpoints CK's gateway is willing to route to, and on what
  terms (e.g., must carry attestation).

  Config-first so it ships without a new schema or admin UI. A future slice can
  back the same shape with a DB table when org-admin UI lands.

  ## Configuration

      config :controlkeel,
        cloud_mcp_registry: %{
          default_policy: :deny,          # :allow_with_attestation | :allow_unrestricted
          allowlist: [
            %{name: "internal-pii-scrubber",
              url: "https://mcp.internal/pii",
              attestation: :required,
              note: "vendor-signed"},
            %{name: "github-mcp",
              url: "https://api.github.com/mcp",
              attestation: :optional}
          ],
          denylist: ["smithery-public"]
        }

  Denylist trumps allowlist. Servers not in either list are governed by
  `default_policy`. `attestation: :required` causes lookups to demand the
  caller pass `attested?: true` in the lookup options — the gateway routing
  layer (a later slice) will supply this from an out-of-band signature
  verification step.
  """

  @typedoc "Resolved disposition for a downstream MCP server."
  @type disposition ::
          :allowed
          | {:denied, :explicit_deny | :default_deny | :attestation_required | :unknown}

  @typedoc "Entry shape after normalization."
  @type entry :: %{
          name: String.t(),
          url: String.t() | nil,
          attestation: :required | :optional | :not_required,
          note: String.t() | nil
        }

  @doc "Resolve disposition for a server by name."
  @spec lookup(String.t(), keyword()) :: disposition()
  def lookup(server_name, opts \\ []) when is_binary(server_name) do
    registry = current()
    attested? = Keyword.get(opts, :attested?, false)

    cond do
      denied?(registry, server_name) ->
        {:denied, :explicit_deny}

      entry = find_allowlisted(registry, server_name) ->
        eval_allowlisted(entry, attested?)

      true ->
        eval_default(default_policy(registry), attested?)
    end
  end

  @doc "All entries the registry knows about."
  @spec entries() :: [entry()]
  def entries do
    current()
    |> Map.get(:allowlist, [])
    |> List.wrap()
    |> Enum.map(&normalize_entry/1)
  end

  @doc "Denylist names."
  @spec denylist() :: [String.t()]
  def denylist do
    current()
    |> Map.get(:denylist, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  @doc "Aggregate summary suitable for dashboards."
  @spec summary() :: %{
          allowlist_count: non_neg_integer(),
          denylist_count: non_neg_integer(),
          requires_attestation: non_neg_integer(),
          default_policy: :deny | :allow_with_attestation | :allow_unrestricted
        }
  def summary do
    entries = entries()

    %{
      allowlist_count: length(entries),
      denylist_count: length(denylist()),
      requires_attestation: Enum.count(entries, &(&1.attestation == :required)),
      default_policy: default_policy(current())
    }
  end

  defp eval_allowlisted(%{attestation: :required}, false), do: {:denied, :attestation_required}
  defp eval_allowlisted(_entry, _attested?), do: :allowed

  defp eval_default(:allow_unrestricted, _), do: :allowed
  defp eval_default(:allow_with_attestation, true), do: :allowed
  defp eval_default(:allow_with_attestation, false), do: {:denied, :attestation_required}
  defp eval_default(:deny, _), do: {:denied, :default_deny}
  defp eval_default(_, _), do: {:denied, :unknown}

  defp denied?(registry, server_name) do
    registry
    |> Map.get(:denylist, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.member?(server_name)
  end

  defp find_allowlisted(registry, server_name) do
    registry
    |> Map.get(:allowlist, [])
    |> List.wrap()
    |> Enum.map(&normalize_entry/1)
    |> Enum.find(fn entry -> entry.name == server_name end)
  end

  defp normalize_entry(%{} = entry) do
    %{
      name: fetch_string(entry, [:name, "name"]),
      url: fetch_string(entry, [:url, "url"]),
      attestation: normalize_attestation(fetch(entry, [:attestation, "attestation"])),
      note: fetch_string(entry, [:note, "note"])
    }
  end

  defp normalize_entry(name) when is_binary(name) do
    %{name: name, url: nil, attestation: :not_required, note: nil}
  end

  defp normalize_attestation(:required), do: :required
  defp normalize_attestation("required"), do: :required
  defp normalize_attestation(:optional), do: :optional
  defp normalize_attestation("optional"), do: :optional
  defp normalize_attestation(_), do: :not_required

  defp default_policy(registry) do
    case Map.get(registry, :default_policy, :deny) do
      v when v in [:deny, :allow_with_attestation, :allow_unrestricted] -> v
      "deny" -> :deny
      "allow_with_attestation" -> :allow_with_attestation
      "allow_unrestricted" -> :allow_unrestricted
      _ -> :deny
    end
  end

  defp fetch(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp fetch_string(map, keys) do
    case fetch(map, keys) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp current do
    case Application.get_env(:controlkeel, :cloud_mcp_registry) do
      registry when is_map(registry) -> registry
      _ -> %{}
    end
  end
end
