defmodule ControlKeel.Scanner.Aislop do
  @moduledoc false

  alias ControlKeel.Proxy
  alias ControlKeel.Scanner.Finding

  @code_extensions ~w(
    .c .cc .cpp .cs .css .env .ex .exs .go .graphql .heex .html .ini .java .js .json .jsx .kt
    .md .php .py .rb .rs .sh .sql .swift .toml .ts .tsx .xml .yaml .yml
  )

  @fence_regex ~r/```([\w#+.-]+)?\s*\n([\s\S]*?)```/
  @code_markers ~r/\b(def|class|function|const|let|var|SELECT|INSERT|UPDATE|DELETE|apiVersion|kind|resource)\b/

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

  def code_like?(input, opts \\ []) when is_map(input) do
    normalized = normalize_input(input)
    force? = Keyword.get(opts, :force, false)

    force? or
      normalized["kind"] in ["code", "config", "shell"] or
      path_code_like?(normalized["path"]) or
      Regex.match?(@fence_regex, normalized["content"]) or
      Regex.match?(@code_markers, normalized["content"])
  end

  def scan(input, opts \\ []) when is_map(input) do
    normalized = normalize_input(input)

    cond do
      not code_like?(normalized, opts) ->
        result(:skipped, [], 0)

      is_nil(executable()) ->
        emit_telemetry(0, :unavailable, 0)
        :unavailable

      true ->
        start = System.monotonic_time(:millisecond)
        timeout_ms = Keyword.get(opts, :timeout_ms, 8_000)

        with {:ok, temp_dir, files} <- materialize_files(normalized),
             {:ok, output, status} <- run_aislop(temp_dir, files, timeout_ms),
             {:ok, findings} <- decode_output(output, normalized, temp_dir) do
          duration_ms = System.monotonic_time(:millisecond) - start

          case status do
            exit_status when exit_status in [0, 1] ->
              emit_telemetry(duration_ms, :ok, length(findings))
              cleanup(temp_dir)
              result(:ok, findings, duration_ms)

            _other ->
              emit_telemetry(duration_ms, :error, 0)
              cleanup(temp_dir)
              result(:error, [], duration_ms)
          end
        else
          {:timeout, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, :timeout, 0)
            cleanup(temp_dir)
            result(:timeout, [], duration_ms)

          {:error, :malformed_output, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, :malformed_output, 0)
            cleanup(temp_dir)
            result(:malformed_output, [], duration_ms)

          {:error, :no_snippets, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, :skipped, 0)
            cleanup(temp_dir)
            result(:skipped, [], duration_ms)

          {:error, reason, temp_dir} ->
            duration_ms = System.monotonic_time(:millisecond) - start
            emit_telemetry(duration_ms, reason, 0)
            cleanup(temp_dir)
            result(reason, [], duration_ms)
        end
    end
  end

  defp normalize_input(input) do
    %{
      "content" => Map.get(input, "content", Map.get(input, :content, "")) || "",
      "path" => Map.get(input, "path", Map.get(input, :path)),
      "kind" => Map.get(input, "kind", Map.get(input, :kind, "code")) || "code"
    }
  end

  defp materialize_files(normalized) do
    temp_dir =
      Path.join(System.tmp_dir!(), "controlkeel-aislop-#{System.unique_integer([:positive])}")

    with :ok <- File.mkdir_p(temp_dir),
         snippets when is_list(snippets) <- snippets(normalized),
         true <- snippets != [] || {:error, :no_snippets, temp_dir},
         {:ok, files} <- write_snippets(temp_dir, snippets, normalized) do
      {:ok, temp_dir, files}
    else
      {:error, reason} -> {:error, reason, temp_dir}
      false -> {:error, :no_snippets, temp_dir}
    end
  end

  defp snippets(%{"content" => content, "path" => path, "kind" => kind}) do
    fenced =
      Regex.scan(@fence_regex, content)
      |> Enum.map(fn
        [_, language, snippet] -> %{content: snippet, language: normalize_language(language)}
      end)

    cond do
      fenced != [] ->
        fenced

      true ->
        [%{content: content, language: extension_to_language(path) || normalize_language(kind)}]
    end
  end

  defp write_snippets(temp_dir, snippets, normalized) do
    files =
      snippets
      |> Enum.with_index(1)
      |> Enum.map(fn {%{content: content, language: language}, index} ->
        ext = language_to_extension(language, normalized["path"])
        path = Path.join(temp_dir, "snippet_#{index}#{ext}")
        File.write!(path, content)
        path
      end)

    {:ok, files}
  rescue
    error -> {:error, {:write_failed, error}}
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

    collect_output(port, "", timeout_ms, temp_dir)
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

  defp collect_output(port, acc, timeout_ms, temp_dir) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, acc <> data, timeout_ms, temp_dir)

      {^port, {:exit_status, status}} ->
        {:ok, acc, status}
    after
      timeout_ms ->
        Port.close(port)
        {:timeout, temp_dir}
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

  defp decision_for_severity("critical"), do: "block"
  defp decision_for_severity("high"), do: "warn"
  defp decision_for_severity(_), do: "warn"

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

  defp path_code_like?(nil), do: false

  defp path_code_like?(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @code_extensions))
  end

  defp normalize_language(nil), do: nil
  defp normalize_language(""), do: nil
  defp normalize_language(language), do: String.downcase(language)

  defp extension_to_language(nil), do: nil

  defp extension_to_language(path) do
    case Path.extname(path || "") do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".jsx" -> "javascript"
      ".ts" -> "typescript"
      ".tsx" -> "typescript"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".java" -> "java"
      ".json" -> "json"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".sql" -> "sql"
      ".sh" -> "bash"
      _other -> nil
    end
  end

  defp language_to_extension(nil, path), do: Path.extname(path || "") |> default_extension()
  defp language_to_extension("elixir", _path), do: ".ex"
  defp language_to_extension("javascript", _path), do: ".js"
  defp language_to_extension("typescript", _path), do: ".ts"
  defp language_to_extension("python", _path), do: ".py"
  defp language_to_extension("ruby", _path), do: ".rb"
  defp language_to_extension("go", _path), do: ".go"
  defp language_to_extension("java", _path), do: ".java"
  defp language_to_extension("yaml", _path), do: ".yml"
  defp language_to_extension("json", _path), do: ".json"
  defp language_to_extension("sql", _path), do: ".sql"
  defp language_to_extension("bash", _path), do: ".sh"
  defp language_to_extension("config", _path), do: ".yml"
  defp language_to_extension("shell", _path), do: ".sh"
  defp language_to_extension(_language, path), do: Path.extname(path || "") |> default_extension()

  defp default_extension(""), do: ".txt"
  defp default_extension(ext), do: ext

  defp emit_telemetry(duration_ms, status, findings_count) do
    :telemetry.execute(
      [:controlkeel, :aislop, :stop],
      %{duration_ms: duration_ms},
      %{status: status, findings_count: findings_count}
    )
  end

  defp cleanup(temp_dir) when is_binary(temp_dir), do: File.rm_rf(temp_dir)
  defp cleanup(_temp_dir), do: :ok

  defp result(status, findings, duration_ms) do
    {:ok, %{status: status, findings: findings, duration_ms: duration_ms}}
  end
end
