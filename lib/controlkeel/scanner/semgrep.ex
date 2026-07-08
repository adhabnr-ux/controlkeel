defmodule ControlKeel.Scanner.Semgrep do
  @moduledoc false

  alias ControlKeel.Proxy
  alias ControlKeel.Scanner.Finding
  alias ControlKeel.Scanner.SnippetMaterializer, as: SM

  def available? do
    executable()
    |> case do
      nil -> false
      path -> File.exists?(path)
    end
  end

  def code_like?(input, opts \\ []) when is_map(input),
    do: SM.code_like?(input, opts)

  def scan(input, opts \\ []) when is_map(input) do
    normalized = SM.normalize_input(input)

    cond do
      not code_like?(normalized, opts) ->
        SM.result(:skipped, [], 0)

      is_nil(executable()) ->
        emit_telemetry(0, :unavailable, 0)
        :unavailable

      true ->
        start = System.monotonic_time(:millisecond)
        timeout_ms = Keyword.get(opts, :timeout_ms, Proxy.timeout_ms())

        with {:ok, temp_dir, files} <- SM.materialize_files(normalized, "controlkeel-semgrep"),
             {:ok, output, status} <- run_semgrep(temp_dir, files, timeout_ms),
             {:ok, findings} <- decode_output(output, normalized, temp_dir) do
          duration_ms = System.monotonic_time(:millisecond) - start

          case status do
            exit_status when exit_status in [0, 1] ->
              emit_telemetry(duration_ms, :ok, length(findings))
              SM.cleanup(temp_dir)
              SM.result(:ok, findings, duration_ms)

            _other ->
              emit_telemetry(duration_ms, :error, 0)
              SM.cleanup(temp_dir)
              SM.result(:error, [], duration_ms)
          end
        else
          {:timeout, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, :timeout, 0)
            SM.cleanup(temp_dir)
            SM.result(:timeout, [], duration_ms)

          {:error, :malformed_output, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, :malformed_output, 0)
            SM.cleanup(temp_dir)
            SM.result(:malformed_output, [], duration_ms)

          {:error, reason, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, reason, 0)
            SM.cleanup(temp_dir)
            SM.result(reason, [], duration_ms)
        end
    end
  end

  defp run_semgrep(temp_dir, files, timeout_ms) do
    executable = executable()

    args = [
      "scan",
      "--config",
      semgrep_rules_path(),
      "--json",
      "--quiet",
      "--metrics=off",
      "--disable-version-check"
      | files
    ]

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, temp_dir},
        {:args, args}
      ])

    SM.collect_output(port, "", timeout_ms, temp_dir)
  end

  defp decode_output(output, normalized, temp_dir) do
    case Jason.decode(output) do
      {:ok, %{"results" => results}} ->
        {:ok, Enum.map(results, &finding_from_result(&1, normalized))}

      {:ok, _other} ->
        {:error, :malformed_output, temp_dir}

      {:error, _error} ->
        {:error, :malformed_output, temp_dir}
    end
  end

  defp finding_from_result(result, normalized) do
    metadata = get_in(result, ["extra", "metadata"]) || %{}
    line_text = get_in(result, ["extra", "lines"]) || ""
    rule_id = metadata["controlkeel_rule_id"] || result["check_id"] || "security.semgrep"
    decision = metadata["controlkeel_decision"] || "warn"
    severity = metadata["controlkeel_severity"] || severity_from_semgrep(result)
    category = metadata["controlkeel_category"] || "security"
    path = result["path"] || normalized["path"]

    %Finding{
      id: fingerprint(rule_id, path, result["start"], result["end"]),
      severity: severity,
      category: category,
      rule_id: rule_id,
      decision: decision,
      plain_message: get_in(result, ["extra", "message"]) || "Semgrep detected a policy issue.",
      location: %{
        "path" => path,
        "kind" => normalized["kind"],
        "start" => result["start"],
        "end" => result["end"]
      },
      metadata: %{
        "scanner" => "semgrep",
        "matched_text_redacted" => redact(line_text),
        "check_id" => result["check_id"]
      }
    }
  end

  defp severity_from_semgrep(%{"extra" => %{"severity" => "ERROR"}}), do: "high"
  defp severity_from_semgrep(%{"extra" => %{"severity" => "WARNING"}}), do: "medium"
  defp severity_from_semgrep(_result), do: "medium"

  defp fingerprint(rule_id, path, start_location, end_location) do
    start_line = start_location && start_location["line"]
    end_line = end_location && end_location["line"]
    seed = Enum.join(Enum.reject([rule_id, path, start_line, end_line], &is_nil/1), ":")
    "sg_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp redact(value) when not is_binary(value) or value == "", do: nil
  defp redact(value) when byte_size(value) <= 12, do: "[redacted]"

  defp redact(value) do
    prefix = binary_part(value, 0, 4)
    suffix = binary_part(value, byte_size(value) - 4, 4)
    prefix <> "..." <> suffix
  end

  defp semgrep_rules_path do
    :controlkeel
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("semgrep/controlkeel.yml")
  end

  defp executable do
    configured = Proxy.semgrep_bin()

    cond do
      Path.type(configured) == :absolute and File.exists?(configured) -> configured
      is_binary(System.find_executable(configured)) -> System.find_executable(configured)
      true -> nil
    end
  end

  defp emit_telemetry(duration_ms, status, findings_count) do
    :telemetry.execute(
      [:controlkeel, :semgrep, :stop],
      %{duration_ms: duration_ms},
      %{status: status, findings_count: findings_count}
    )
  end
end
