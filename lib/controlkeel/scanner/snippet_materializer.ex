defmodule ControlKeel.Scanner.SnippetMaterializer do
  @moduledoc false

  @code_extensions ~w(
    .c .cc .cpp .cs .css .env .ex .exs .go .graphql .heex .html .ini .java .js .json .jsx .kt
    .md .php .py .rb .rs .sh .sql .swift .toml .ts .tsx .xml .yaml .yml
  )

  @fence_regex ~r/```([\w#+.-]+)?\s*\n([\s\S]*?)```/
  @code_markers ~r/\b(def|class|function|const|let|var|SELECT|INSERT|UPDATE|DELETE|apiVersion|kind|resource)\b/

  def code_like?(input, opts \\ []) when is_map(input) do
    normalized = normalize_input(input)
    force? = Keyword.get(opts, :force, false)

    force? or
      normalized["kind"] in ["code", "config", "shell"] or
      path_code_like?(normalized["path"]) or
      Regex.match?(@fence_regex, normalized["content"]) or
      Regex.match?(@code_markers, normalized["content"])
  end

  def normalize_input(input) do
    %{
      "content" => Map.get(input, "content", Map.get(input, :content, "")) || "",
      "path" => Map.get(input, "path", Map.get(input, :path)),
      "kind" => Map.get(input, "kind", Map.get(input, :kind, "code")) || "code"
    }
  end

  def materialize_files(normalized, prefix) do
    temp_dir =
      Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    with :ok <- File.mkdir_p(temp_dir),
         snippets when is_list(snippets) <- snippets(normalized),
         {:ok, files} <- write_snippets(temp_dir, snippets, normalized) do
      {:ok, temp_dir, files}
    else
      {:error, reason} -> {:error, reason, temp_dir}
    end
  end

  def collect_output(port, acc, timeout_ms, temp_dir) do
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

  def cleanup(temp_dir) when is_binary(temp_dir), do: File.rm_rf(temp_dir)
  def cleanup(_temp_dir), do: :ok

  def result(status, findings, duration_ms) do
    {:ok, %{status: status, findings: findings, duration_ms: duration_ms}}
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
end
