defmodule ControlKeel.Scanner.Aislop do
  @moduledoc false

  alias ControlKeel.Proxy
  alias ControlKeel.Scanner.Finding
  alias ControlKeel.Scanner.SnippetMaterializer, as: SM

  @engine_category_map %{
    "format" => "code_quality",
    "lint" => "correctness",
    "code-quality" => "code_quality",
    "ai-slop" => "code_quality",
    "architecture" => "architecture",
    "security" => "security"
  }

  @high_severity_rules ~w(
    ai-slop/unsafe-any
    security/eval
    security/innerHTML
    security/sql-injection
    security/shell-injection
    security/vulnerable-dependency
  )

  @medium_security_rules ~w(
    ai-slop/todo-stub
    ai-slop/dead-pattern
  )

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
        timeout_ms = Keyword.get(opts, :timeout_ms, 8_000)

        with {:ok, temp_dir, files} <- SM.materialize_files(normalized, "controlkeel-aislop"),
             {:ok, output, status} <- run_aislop(temp_dir, files, timeout_ms),
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

  defp run_aislop(temp_dir, files, timeout_ms) do
    {bin, args} = aislop_command(files)

    port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:cd, temp_dir},
        {:args, args}
      ])

    SM.collect_output(port, "", timeout_ms, temp_dir)
  end

  defp aislop_command(files) do
    configured = Proxy.aislop_bin()

    cond do
      configured == "npx" ->
        bin = System.find_executable("npx") || "npx"
        {bin, ["-y", "aislop", "scan", "--json", "--quiet" | files]}

      true ->
        bin = System.find_executable(configured) || configured
        {bin, ["scan", "--json", "--quiet" | files]}
    end
  end

  defp decode_output(output, normalized, temp_dir) do
    case Jason.decode(output) do
      {:ok, %{"diagnostics" => diagnostics}} when is_list(diagnostics) ->
        {:ok, Enum.map(diagnostics, &finding_from_diagnostic(&1, normalized))}

      {:ok, _other} ->
        {:error, :malformed_output, temp_dir}

      {:error, _error} ->
        {:error, :malformed_output, temp_dir}
    end
  end

  defp finding_from_diagnostic(diagnostic, normalized) do
    rule = diagnostic["rule"] || "unknown"
    engine = diagnostic["engine"] || "ai-slop"
    severity = severity_for_rule(rule, diagnostic["severity"])
    category = category_for_engine(engine)
    decision = decision_for_severity(severity)
    path = diagnostic["filePath"] || normalized["path"]

    %Finding{
      id: fingerprint(rule, path, diagnostic["line"]),
      severity: severity,
      category: category,
      rule_id: "aislop.#{rule}",
      decision: decision,
      plain_message: diagnostic["message"] || "aislop detected a code quality issue.",
      location: %{
        "path" => path,
        "kind" => normalized["kind"],
        "start" => %{"line" => diagnostic["line"], "col" => diagnostic["column"]},
        "end" => %{"line" => diagnostic["line"], "col" => diagnostic["column"]}
      },
      metadata: %{
        "scanner" => "aislop",
        "engine" => engine,
        "rule" => rule,
        "fixable" => diagnostic["fixable"] || false,
        "aislop_help" => diagnostic["help"],
        "aislop_category" => diagnostic["category"]
      }
    }
  end

  defp severity_for_rule(rule, _aislop_severity) when rule in @high_severity_rules, do: "high"
  defp severity_for_rule(rule, _aislop_severity) when rule in @medium_security_rules, do: "medium"
  defp severity_for_rule(_rule, "error"), do: "medium"
  defp severity_for_rule(_rule, "warning"), do: "medium"
  defp severity_for_rule(_rule, "info"), do: "low"
  defp severity_for_rule(_rule, _other), do: "medium"

  defp category_for_engine(engine) do
    Map.get(@engine_category_map, engine, "code_quality")
  end

  defp decision_for_severity(_severity), do: "warn"

  defp fingerprint(rule_id, path, line) do
    seed = Enum.join(Enum.reject([rule_id, path, line], &is_nil/1), ":")
    "as_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end

  defp executable do
    configured = Proxy.aislop_bin()

    cond do
      configured == "npx" -> System.find_executable("npx")
      Path.type(configured) == :absolute and File.exists?(configured) -> configured
      is_binary(System.find_executable(configured)) -> System.find_executable(configured)
      true -> nil
    end
  end

  defp emit_telemetry(duration_ms, status, findings_count) do
    :telemetry.execute(
      [:controlkeel, :aislop, :stop],
      %{duration_ms: duration_ms},
      %{status: status, findings_count: findings_count}
    )
  end
end
