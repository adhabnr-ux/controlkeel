defmodule ControlKeel.Cloud.Workspace.Identity do
  @moduledoc """
  Local-only workspace identity primitive backing `controlkeel cloud connect`.

  Per architectural decision D2 in
  [docs/cloud-enterprise-roadmap.md](../../docs/cloud-enterprise-roadmap.md),
  a workspace owns a long-lived ed25519 keypair generated at `cloud connect`
  time. The public key is what eventually registers the workspace with a cloud
  control plane; runtime authorization (hosted MCP, A2A, cloud-agent) continues
  to use service-account OAuth tokens, not this key.

  This module is local-only. It does not contact any remote service. Rotation
  is explicit and forward-only — the previous keypair is discarded once rotated.

  ## Storage

  Keypair lives at `ControlKeel.Runtime.Paths.config_dir/0 <> /workspace-identity.json`.
  Permissions are tightened to `0600` after write so the private key is not
  world-readable.

  ## Fields

    - `workspace_id` — ULID prefixed `ws_`
    - `algorithm` — currently `"ed25519"`
    - `public_key` / `private_key` — base64-encoded raw key material
    - `fingerprint` — hex sha256 of the public key (16-byte prefix is shown in CLI)
    - `created_at` — ISO8601 timestamp
  """

  alias ControlKeel.Runtime.Paths

  @filename "workspace-identity.json"
  @algorithm "ed25519"
  @file_mode 0o600

  @typedoc "On-disk workspace identity."
  @type t :: %{
          workspace_id: String.t(),
          algorithm: String.t(),
          public_key: String.t(),
          private_key: String.t(),
          fingerprint: String.t(),
          created_at: DateTime.t(),
          path: String.t()
        }

  @doc "Absolute path to the identity file (does not create it)."
  @spec path() :: String.t()
  def path, do: Path.join(Paths.config_dir(), @filename)

  @doc "True when an identity has been generated and persisted."
  @spec connected?() :: boolean()
  def connected?, do: File.exists?(path())

  @doc """
  Ensure an identity exists. Returns the existing one if present, otherwise
  generates and persists a new one.

  Idempotent — safe to call from `cloud connect` and from any read path that
  needs a stable workspace ID. Pass `force: true` to rotate.
  """
  @spec ensure(keyword()) :: {:ok, t(), :existing | :created | :rotated} | {:error, term()}
  def ensure(opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    cond do
      force? ->
        with {:ok, identity} <- generate_and_write() do
          {:ok, identity, :rotated}
        end

      connected?() ->
        case load() do
          {:ok, identity} -> {:ok, identity, :existing}
          {:error, _} = err -> err
        end

      true ->
        with {:ok, identity} <- generate_and_write() do
          {:ok, identity, :created}
        end
    end
  end

  @doc """
  Load the persisted identity. Returns `{:error, :not_connected}` when the
  file is missing, `{:error, {:malformed, reason}}` when the file is unreadable
  or malformed.
  """
  @spec load() :: {:ok, t()} | {:error, :not_connected | {:malformed, term()}}
  def load do
    file_path = path()

    case File.read(file_path) do
      {:error, :enoent} ->
        {:error, :not_connected}

      {:error, reason} ->
        {:error, {:malformed, reason}}

      {:ok, body} ->
        with {:ok, map} <- Jason.decode(body),
             {:ok, identity} <- decode(map, file_path) do
          {:ok, identity}
        else
          {:error, %Jason.DecodeError{} = err} ->
            {:error, {:malformed, Exception.message(err)}}

          {:error, reason} ->
            {:error, {:malformed, reason}}
        end
    end
  end

  @doc "Short fingerprint (first 16 hex chars) suitable for CLI display."
  @spec short_fingerprint(t() | String.t()) :: String.t()
  def short_fingerprint(%{fingerprint: fp}), do: short_fingerprint(fp)

  def short_fingerprint(fp) when is_binary(fp), do: String.slice(fp, 0, 16)

  defp generate_and_write do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    fingerprint = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)
    workspace_id = generate_workspace_id()
    created_at = DateTime.utc_now() |> DateTime.truncate(:second)
    file_path = path()

    identity = %{
      workspace_id: workspace_id,
      algorithm: @algorithm,
      public_key: Base.encode64(pub),
      private_key: Base.encode64(priv),
      fingerprint: fingerprint,
      created_at: created_at,
      path: file_path
    }

    with :ok <- File.mkdir_p(Path.dirname(file_path)),
         :ok <- File.write(file_path, encode(identity)),
         :ok <- chmod_secure(file_path) do
      {:ok, identity}
    end
  end

  defp encode(identity) do
    Jason.encode!(%{
      "workspace_id" => identity.workspace_id,
      "algorithm" => identity.algorithm,
      "public_key" => identity.public_key,
      "private_key" => identity.private_key,
      "fingerprint" => identity.fingerprint,
      "created_at" => DateTime.to_iso8601(identity.created_at)
    })
  end

  defp decode(map, file_path) when is_map(map) do
    required = ~w(workspace_id algorithm public_key private_key fingerprint created_at)
    missing = Enum.reject(required, &Map.has_key?(map, &1))

    cond do
      missing != [] ->
        {:error, "missing fields: #{Enum.join(missing, ", ")}"}

      Map.get(map, "algorithm") != @algorithm ->
        {:error, "unsupported algorithm: #{inspect(Map.get(map, "algorithm"))}"}

      true ->
        with {:ok, created_at, _} <- DateTime.from_iso8601(Map.get(map, "created_at")) do
          {:ok,
           %{
             workspace_id: Map.get(map, "workspace_id"),
             algorithm: Map.get(map, "algorithm"),
             public_key: Map.get(map, "public_key"),
             private_key: Map.get(map, "private_key"),
             fingerprint: Map.get(map, "fingerprint"),
             created_at: created_at,
             path: file_path
           }}
        else
          _ -> {:error, "invalid created_at"}
        end
    end
  end

  defp decode(_, _), do: {:error, "config is not a JSON object"}

  defp chmod_secure(file_path) do
    case File.chmod(file_path, @file_mode) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp generate_workspace_id do
    random = :crypto.strong_rand_bytes(10) |> Base.encode32(padding: false, case: :lower)
    "ws_" <> random
  end
end
