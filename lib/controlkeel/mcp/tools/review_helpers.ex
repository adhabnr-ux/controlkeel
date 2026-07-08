defmodule ControlKeel.MCP.Tools.ReviewHelpers do
  @moduledoc false

  alias ControlKeel.Mission.ReviewBridge

  @doc """
  Resolves the `controlkeel` CLI binary path.
  """
  def controlkeel_bin do
    case System.get_env("CONTROLKEEL_BIN") do
      value when is_binary(value) and value != "" -> value
      _ -> System.find_executable("controlkeel") || "controlkeel"
    end
  end

  @doc """
  Resolves the project root from env vars, falling back to `File.cwd!/0`.
  """
  def resolved_project_root do
    case System.get_env("CONTROLKEEL_PROJECT_ROOT") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> fallback_project_root()
    end
  end

  @doc """
  Returns the fallback CLI variant options for different mix env / cwd combinations.
  """
  def fallback_variants do
    root = resolved_project_root()

    [
      [cd: root, stderr_to_stdout: true],
      [stderr_to_stdout: true],
      [cd: root, stderr_to_stdout: true, env: fallback_env("prod")],
      [stderr_to_stdout: true, env: fallback_env("prod")],
      [cd: root, stderr_to_stdout: true, env: fallback_env("dev")],
      [stderr_to_stdout: true, env: fallback_env("dev")]
    ]
  end

  @doc """
  Extracts the agent feedback string from a review record.
  """
  def review_agent_feedback(%{fallback_payload: payload}) do
    payload["agent_feedback"]
  end

  def review_agent_feedback(review), do: ReviewBridge.agent_feedback(review)

  @doc """
  Extracts the browser URL from a review record.
  """
  def review_browser_url(%{fallback_payload: payload}) do
    Map.get(payload, "browser_url") || safe_review_url(Map.get(payload, "review", %{})["id"])
  end

  def review_browser_url(review), do: safe_review_url(review.id)

  @doc """
  Builds approval instructions for a review.
  """
  def approval_instructions(review, nil) do
    %{
      "primary" =>
        "Review #{review.review_type} ##{review.id} in the ControlKeel UI when available.",
      "fallback_status_command" => "controlkeel review status #{review.id}",
      "fallback_approve_command" => "controlkeel review approve #{review.id}",
      "fallback_deny_command" => "controlkeel review deny #{review.id} --feedback '<reason>'"
    }
  end

  def approval_instructions(review, browser_url) do
    %{
      "primary" => "Open #{browser_url} to approve or deny #{review.review_type} ##{review.id}.",
      "fallback_status_command" => "controlkeel review status #{review.id}",
      "fallback_approve_command" => "controlkeel review approve #{review.id}",
      "fallback_deny_command" => "controlkeel review deny #{review.id} --feedback '<reason>'"
    }
  end

  @doc """
  Returns the reviewer roles for a given review type and plan refinement.
  """
  def review_roles("completion", _plan_refinement),
    do: ["operator", "security reviewer", "product/human QA"]

  def review_roles(_review_type, plan_refinement) do
    case Map.get(plan_refinement, "consulted_roles") do
      roles when is_list(roles) and roles != [] -> roles
      _ -> ["operator", "security reviewer", "platform maintainer"]
    end
  end

  @doc """
  Extracts a string field from a map with a default.
  """
  def map_string(map, key, default \\ nil) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> default
    end
  end

  @doc """
  Extracts a string-or-nil field from a map.
  """
  def map_string_or_nil(map, key) do
    case Map.get(map, key) do
      nil -> nil
      value -> map_string(%{key => value}, key)
    end
  end

  @doc """
  Extracts an integer field from a map with a default.
  """
  def map_integer(map, key, default) do
    case map_integer_or_nil(map, key) do
      nil -> default
      value -> value
    end
  end

  @doc """
  Extracts an integer-or-nil field from a map.
  """
  def map_integer_or_nil(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Extracts a balanced JSON object from CLI output.
  """
  def extract_json_object(output) when is_binary(output) do
    indices = :binary.matches(output, "{")

    Enum.reduce_while(indices, {:error, :json_not_found}, fn {offset, _length}, _acc ->
      slice = binary_part(output, offset, byte_size(output) - offset)

      with {:ok, candidate} <- take_balanced_json_object(slice),
           {:ok, decoded} <- Jason.decode(candidate) do
        {:halt, {:ok, decoded}}
      else
        _ -> {:cont, {:error, :json_not_found}}
      end
    end)
  end

  def extract_json_object(_output), do: {:error, :json_not_found}

  # Private functions

  defp fallback_project_root do
    case System.get_env("CK_PROJECT_ROOT") do
      value when is_binary(value) and value != "" -> String.trim(value)
      _ -> File.cwd!()
    end
  end

  defp fallback_env(mix_env) do
    System.get_env()
    |> Map.put("MIX_ENV", mix_env)
    |> Enum.into([])
  end

  defp safe_review_url(nil), do: nil

  defp safe_review_url(review_id) do
    try do
      ControlKeelWeb.Endpoint.url() <> "/reviews/#{review_id}"
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp take_balanced_json_object("{" <> _ = input) do
    bytes = :binary.bin_to_list(input)

    case scan_json_object(bytes, 0, false, false, 0) do
      {:ok, end_index} -> {:ok, binary_part(input, 0, end_index + 1)}
      :error -> {:error, :json_not_found}
    end
  end

  defp take_balanced_json_object(_input), do: {:error, :json_not_found}

  defp scan_json_object([], _depth, _in_string, _escaped, _index), do: :error

  defp scan_json_object([char | rest], depth, in_string, escaped, index) do
    cond do
      in_string and escaped ->
        scan_json_object(rest, depth, true, false, index + 1)

      in_string and char == ?\\ ->
        scan_json_object(rest, depth, true, true, index + 1)

      in_string and char == ?\" ->
        scan_json_object(rest, depth, false, false, index + 1)

      in_string ->
        scan_json_object(rest, depth, true, false, index + 1)

      char == ?\" ->
        scan_json_object(rest, depth, true, false, index + 1)

      char == ?{ ->
        scan_json_object(rest, depth + 1, false, false, index + 1)

      char == ?} and depth == 1 ->
        {:ok, index}

      char == ?} and depth > 1 ->
        scan_json_object(rest, depth - 1, false, false, index + 1)

      true ->
        scan_json_object(rest, depth, false, false, index + 1)
    end
  end
end
