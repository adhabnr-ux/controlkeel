defmodule ControlKeel.MCP.Tools.CkSession do
  @moduledoc false

  alias ControlKeel.Project.Local
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission
  alias ControlKeel.Project.Binding

  @allowed_modes ~w(list status switch)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments),
         {:ok, result} <- dispatch(normalized) do
      {:ok, result}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, mode} <- mode(arguments),
         {:ok, limit} <- parse_limit(arguments) do
      {:ok,
       %{
         "session_id" => raw_session_id(arguments),
         "mode" => mode,
         "limit" => limit,
         "confirm" => Map.get(arguments, "confirm", false),
         "project_root" => Arguments.project_root(arguments)
       }}
    end
  end

  defp dispatch(%{"mode" => "list", "limit" => limit}) do
    sessions = Mission.list_recent_sessions(limit)

    {:ok,
     %{
       "sessions" => Enum.map(sessions, &session_response/1),
       "total" => length(sessions)
     }}
  end

  defp dispatch(%{"mode" => "status"} = normalized) do
    case resolve_session(normalized) do
      {:ok, session} ->
        {:ok, session_detail_response(session)}

      {:error, _} = error ->
        error
    end
  end

  defp dispatch(%{"mode" => "switch", "confirm" => confirm}) when confirm != true do
    {:error, {:invalid_arguments, "`confirm` must be true to switch sessions"}}
  end

  defp dispatch(%{"mode" => "switch", "confirm" => true} = normalized) do
    session_id = normalized["session_id"]

    case parse_session_id(session_id) do
      {:ok, parsed_id} ->
        case Mission.get_session(parsed_id) do
          nil ->
            {:error, {:invalid_arguments, "Session not found: #{session_id}"}}

          %{} = target ->
            project_root = normalized["project_root"]

            case Local.load(project_root) do
              {:ok, binding, _current_session} ->
                updated =
                  binding
                  |> Map.put("session_id", target.id)
                  |> Map.put("workspace_id", target.workspace_id)

                case Binding.write_effective(updated, project_root,
                       mode: binding_write_mode(binding)
                     ) do
                  {:ok, written} ->
                    {:ok, _updated_session} =
                      Mission.attach_session_runtime_context(target.id, %{
                        "project_root" => project_root
                      })

                    {:ok,
                     %{
                       "switched" => true,
                       "session_id" => target.id,
                       "title" => target.title,
                       "project_root" => written["project_root"]
                     }}

                  {:error, reason} ->
                    {:error, {:invalid_arguments, "Could not switch session: #{inspect(reason)}"}}
                end

              _ ->
                {:error,
                 {:invalid_arguments,
                  "No local project binding found. Run from a bound project or pass `project_root`."}}
            end
        end

      {:error, _} = error ->
        error
    end
  end

  defp resolve_session(%{"session_id" => session_id} = _normalized)
       when is_binary(session_id) and session_id != "" do
    case parse_session_id(session_id) do
      {:ok, parsed_id} ->
        case Mission.get_session(parsed_id) do
          nil -> {:error, {:invalid_arguments, "Session not found"}}
          session -> {:ok, session}
        end

      {:error, _} = error ->
        error
    end
  end

  defp resolve_session(%{"session_id" => nil} = normalized) do
    resolve_from_binding(normalized)
  end

  defp resolve_session(%{"session_id" => id} = _normalized) when is_integer(id) do
    case Mission.get_session(id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp resolve_session(normalized) do
    resolve_from_binding(normalized)
  end

  defp resolve_from_binding(%{"project_root" => project_root}) do
    case Local.load(project_root) do
      {:ok, _binding, session} ->
        {:ok, session}

      _ ->
        {:error,
         {:invalid_arguments,
          "No active session found. Pass `session_id` or run from a bound project."}}
    end
  end

  defp parse_session_id(value) when is_integer(value), do: {:ok, value}

  defp parse_session_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`session_id` must be an integer"}}
    end
  end

  defp parse_session_id(_), do: {:error, {:invalid_arguments, "`session_id` must be an integer"}}

  defp session_response(session) do
    %{
      "id" => session.id,
      "title" => session.title,
      "risk_tier" => session.risk_tier,
      "workspace_id" => session.workspace_id
    }
  end

  defp session_detail_response(session) do
    %{
      "id" => session.id,
      "title" => session.title,
      "risk_tier" => session.risk_tier,
      "workspace_id" => session.workspace_id,
      "status" => session.status
    }
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "status") do
      value when value in @allowed_modes ->
        {:ok, value}

      _ ->
        {:error,
         {:invalid_arguments, "`mode` must be one of: #{Enum.join(@allowed_modes, ", ")}"}}
    end
  end

  defp raw_session_id(arguments) do
    Map.get(arguments, "session_id")
  end

  defp parse_limit(arguments) do
    case Map.get(arguments, "limit", 20) do
      value when is_integer(value) and value > 0 and value <= 100 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 and parsed <= 100 -> {:ok, parsed}
          _ -> {:error, {:invalid_arguments, "`limit` must be between 1 and 100"}}
        end

      _ ->
        {:error, {:invalid_arguments, "`limit` must be between 1 and 100"}}
    end
  end

  defp binding_write_mode(%{"bootstrap" => %{"mode" => mode}}), do: String.to_existing_atom(mode)
  defp binding_write_mode(_), do: :project
end
