defmodule ControlKeel.Cloud.Doctor do
  @moduledoc """
  Read-only diagnostic for the cloud-mode boundary.

  Reports `Runtime.mode`, cloud repo configuration, bus selection, service-account
  inventory, hosted MCP/A2A route registration, and telemetry sync status.

  No mutation, no network egress, no telemetry emission. Safe to run in any mode.
  """

  alias ControlKeel.Cloud.Telemetry.Sender
  alias ControlKeel.Cloud.Telemetry.Config
  alias ControlKeel.Cloud.Telemetry.Queue
  alias ControlKeel.Cloud.Workspace.Identity
  alias ControlKeel.CloudRepo
  alias ControlKeel.Platform
  alias ControlKeel.Runtime

  @hosted_mcp_path "/mcp"
  @a2a_path "/a2a"
  @agent_card_path "/.well-known/agent-card.json"
  @service_account_age_warn_days 90

  @typedoc "One diagnostic line in the report."
  @type check :: %{
          id: atom(),
          label: String.t(),
          status: :ok | :info | :warn | :error | :not_applicable,
          detail: String.t()
        }

  @typedoc "Full doctor report."
  @type report :: %{
          mode: :local | :cloud | :self_hosted,
          ok: boolean(),
          checks: [check()]
        }

  @doc """
  Run all checks and return a structured report.

  `ok: true` means no `:error`-severity findings. Cloud-only checks return
  `:not_applicable` when `Runtime.mode/0` is `:local`.
  """
  @spec report() :: report()
  def report do
    mode = Runtime.mode()

    checks = [
      runtime_mode_check(mode),
      workspace_identity_check(),
      cloud_repo_check(mode),
      bus_check(mode),
      service_account_check(mode),
      hosted_mcp_check(),
      a2a_check(),
      telemetry_check(),
      sender_endpoint_check(),
      public_host_check(mode)
    ]

    %{
      mode: mode,
      ok: not Enum.any?(checks, &(&1.status == :error)),
      checks: checks
    }
  end

  defp runtime_mode_check(mode) do
    source =
      cond do
        System.get_env("CONTROLKEEL_RUNTIME_MODE") -> "env CONTROLKEEL_RUNTIME_MODE"
        Application.get_env(:controlkeel, :runtime_mode) -> "config :controlkeel, :runtime_mode"
        true -> "default (:local)"
      end

    %{
      id: :runtime_mode,
      label: "Runtime mode",
      status: :info,
      detail: "#{inspect(mode)} (source: #{source})"
    }
  end

  defp cloud_repo_check(:local) do
    not_applicable(:cloud_repo, "Cloud repo", "local mode")
  end

  defp cloud_repo_check(:self_hosted), do: cloud_repo_check(:cloud)

  defp cloud_repo_check(:cloud) do
    config = Application.get_env(:controlkeel, CloudRepo, [])
    database_url = System.get_env("DATABASE_URL")

    cond do
      config == [] ->
        %{
          id: :cloud_repo,
          label: "Cloud repo",
          status: :error,
          detail: "Runtime.mode is :cloud but ControlKeel.CloudRepo config is empty"
        }

      database_url in [nil, ""] ->
        %{
          id: :cloud_repo,
          label: "Cloud repo",
          status: :error,
          detail: "Runtime.mode is :cloud but DATABASE_URL is not set"
        }

      true ->
        %{
          id: :cloud_repo,
          label: "Cloud repo",
          status: :ok,
          detail: "configured (DATABASE_URL set)"
        }
    end
  end

  defp bus_check(_mode) do
    %{
      id: :bus,
      label: "Bus",
      status: :info,
      detail: "removed (Phoenix.PubSub only)"
    }
  end

  defp service_account_check(:local) do
    not_applicable(:service_accounts, "Service accounts", "local mode")
  end

  defp service_account_check(:self_hosted), do: service_account_check(:cloud)

  defp service_account_check(:cloud) do
    accounts =
      try do
        Platform.list_all_service_accounts()
      rescue
        _ -> :unavailable
      catch
        _, _ -> :unavailable
      end

    case accounts do
      :unavailable ->
        %{
          id: :service_accounts,
          label: "Service accounts",
          status: :info,
          detail: "service-account inventory unavailable (cloud repo may be offline)"
        }

      list when is_list(list) ->
        count = length(list)
        oldest_days = oldest_unused_age_days(list)

        detail =
          case {count, oldest_days} do
            {0, _} -> "none configured"
            {_, nil} -> "#{count} configured (none have been used yet)"
            {_, days} -> "#{count} configured; oldest unused token last seen #{days} day(s) ago"
          end

        status =
          if oldest_days && oldest_days > @service_account_age_warn_days, do: :warn, else: :ok

        %{id: :service_accounts, label: "Service accounts", status: status, detail: detail}
    end
  end

  defp oldest_unused_age_days(accounts) do
    now = DateTime.utc_now()

    accounts
    |> Enum.map(& &1.last_used_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&DateTime.diff(now, &1, :second))
    |> case do
      [] -> nil
      diffs -> diffs |> Enum.max() |> div(86_400)
    end
  end

  defp hosted_mcp_check do
    route_registered_check(
      :hosted_mcp,
      "Hosted MCP",
      :post,
      @hosted_mcp_path,
      "hosted MCP route (POST #{@hosted_mcp_path}) not registered"
    )
  end

  defp a2a_check do
    case {router_has_route?(:post, @a2a_path), router_has_route?(:get, @agent_card_path)} do
      {true, true} ->
        %{
          id: :a2a,
          label: "A2A",
          status: :ok,
          detail: "POST #{@a2a_path} and #{@agent_card_path} registered"
        }

      {true, false} ->
        %{
          id: :a2a,
          label: "A2A",
          status: :warn,
          detail: "POST #{@a2a_path} registered but agent-card discovery missing"
        }

      {false, _} ->
        %{
          id: :a2a,
          label: "A2A",
          status: :warn,
          detail: "A2A route (POST #{@a2a_path}) not registered"
        }
    end
  end

  defp workspace_identity_check do
    case Identity.load() do
      {:ok, identity} ->
        %{
          id: :workspace_identity,
          label: "Workspace identity",
          status: :ok,
          detail:
            "#{identity.workspace_id} (fingerprint #{Identity.short_fingerprint(identity)}...)"
        }

      {:error, :not_connected} ->
        %{
          id: :workspace_identity,
          label: "Workspace identity",
          status: :info,
          detail: "not connected (run `controlkeel cloud connect` to generate a local identity)"
        }

      {:error, {:malformed, reason}} ->
        %{
          id: :workspace_identity,
          label: "Workspace identity",
          status: :warn,
          detail: "identity file malformed: #{inspect(reason)}"
        }
    end
  end

  defp telemetry_check do
    state = Config.load()
    queue_summary = telemetry_queue_summary()

    {status, detail} =
      cond do
        state.load_error ->
          {:warn, "telemetry config error: #{state.load_error}"}

        Config.enabled?(state) ->
          {:info, "#{Config.summary(state)}#{queue_summary}"}

        true ->
          {:info, "disabled (opt-in only; cloud sync not configured)#{queue_summary}"}
      end

    %{id: :telemetry_sync, label: "Telemetry sync", status: status, detail: detail}
  end

  defp sender_endpoint_check do
    case Sender.endpoint() do
      nil ->
        %{
          id: :sender_endpoint,
          label: "Sender endpoint",
          status: :info,
          detail:
            "not configured (cloud_telemetry_endpoint unset; flush is a no-op)#{periodic_suffix()}"
        }

      url ->
        %{
          id: :sender_endpoint,
          label: "Sender endpoint",
          status: :ok,
          detail: "#{url}#{periodic_suffix()}"
        }
    end
  end

  defp public_host_check(:local) do
    not_applicable(:public_host, "Public host", "local mode")
  end

  defp public_host_check(:self_hosted) do
    phx_host = System.get_env("PHX_HOST")
    endpoint_config = Application.get_env(:controlkeel, ControlKeelWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    host = phx_host || Keyword.get(url_config, :host)

    cond do
      host in [nil, ""] ->
        %{
          id: :public_host,
          label: "Public host",
          status: :error,
          detail: "self-hosted mode requires PHX_HOST to be set to the hosted domain"
        }

      host == ControlKeel.Runtime.Mode.canonical_cloud_host() ->
        %{
          id: :public_host,
          label: "Public host",
          status: :error,
          detail: "self-hosted mode must not use controlkeel.com as PHX_HOST"
        }

      true ->
        %{
          id: :public_host,
          label: "Public host",
          status: :ok,
          detail: "#{host} (self-host deployment)"
        }
    end
  end

  defp public_host_check(:cloud) do
    phx_host = System.get_env("PHX_HOST")
    endpoint_config = Application.get_env(:controlkeel, ControlKeelWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    host = phx_host || Keyword.get(url_config, :host)

    cond do
      host in [nil, ""] ->
        %{
          id: :public_host,
          label: "Public host",
          status: :warn,
          detail:
            "no PHX_HOST set; defaulting to \"controlkeel.com\". " <>
              "Self-hosters must set PHX_HOST to their own domain."
        }

      host == ControlKeel.Runtime.Mode.canonical_cloud_host() ->
        %{
          id: :public_host,
          label: "Public host",
          status: :ok,
          detail: "controlkeel.com (canonical SaaS deployment)"
        }

      true ->
        %{
          id: :public_host,
          label: "Public host",
          status: :ok,
          detail: "#{host} (self-host deployment)"
        }
    end
  end

  defp periodic_suffix do
    case safe_periodic_status() do
      :not_running ->
        " (drainer: not running)"

      %{last_outcome: nil} ->
        " (drainer: running, no flushes yet)"

      %{last_outcome: outcome, consecutive_failures: 0} ->
        " (drainer: last=#{format_outcome(outcome)})"

      %{last_outcome: outcome, consecutive_failures: n, next_interval_ms: ms} ->
        " (drainer: last=#{format_outcome(outcome)}, failures=#{n}, backoff=#{ms}ms)"
    end
  end

  defp safe_periodic_status do
    ControlKeel.Cloud.Telemetry.Sender.Periodic.status()
  rescue
    _ -> :not_running
  catch
    _, _ -> :not_running
  end

  defp format_outcome({:ok, tag, count}), do: "#{tag}(#{count})"
  defp format_outcome({:error, reason, count}), do: "error:#{inspect(reason)}(#{count})"
  defp format_outcome(other), do: inspect(other)

  defp telemetry_queue_summary do
    try do
      case Queue.pending_count() do
        0 -> ""
        n -> " (queue: #{n} pending)"
      end
    rescue
      _ -> ""
    catch
      _, _ -> ""
    end
  end

  defp route_registered_check(id, label, method, path, error_detail) do
    if router_has_route?(method, path) do
      %{
        id: id,
        label: label,
        status: :ok,
        detail: "#{method |> Atom.to_string() |> String.upcase()} #{path} registered"
      }
    else
      %{id: id, label: label, status: :warn, detail: error_detail}
    end
  end

  defp router_has_route?(method, path) do
    if Code.ensure_loaded?(ControlKeelWeb.Router) do
      try do
        apply(ControlKeelWeb.Router, :__routes__, [])
        |> Enum.any?(fn route ->
          route_method(route) == method and route_path(route) == path
        end)
      rescue
        _ -> false
      end
    else
      false
    end
  end

  defp route_method(%{verb: verb}), do: verb
  defp route_method(_), do: nil

  defp route_path(%{path: path}), do: path
  defp route_path(_), do: nil

  defp not_applicable(id, label, reason) do
    %{id: id, label: label, status: :not_applicable, detail: "not applicable (#{reason})"}
  end

  @doc """
  Render a report as a list of human-readable lines.

  Format mirrors `agents doctor` / `provider doctor` output so the CLI dispatcher
  can return it without extra shaping.
  """
  @spec format(report()) :: [String.t()]
  def format(%{mode: mode, ok: ok?, checks: checks}) do
    header = [
      "ControlKeel cloud doctor",
      "Mode: #{inspect(mode)}",
      "Overall: #{if ok?, do: "OK", else: "ATTENTION"}",
      "Checks:"
    ]

    body =
      Enum.map(checks, fn check ->
        "  [#{status_glyph(check.status)}] #{check.label}: #{check.detail}"
      end)

    header ++ body
  end

  defp status_glyph(:ok), do: "ok"
  defp status_glyph(:info), do: "i "
  defp status_glyph(:warn), do: "! "
  defp status_glyph(:error), do: "x "
  defp status_glyph(:not_applicable), do: "- "
end
