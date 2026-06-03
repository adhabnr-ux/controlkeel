defmodule ControlKeel.CLI.Dispatch.BenchmarksHarness do
  @moduledoc false

  alias ControlKeel.Benchmark
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :eval_list, options: _options}, _project_root) do
    alias ControlKeel.Cloud.EvalRunner

    suites = EvalRunner.list_suites()

    rows =
      if suites == [] do
        ["No eval suites available."]
      else
        ["Eval suites:"] ++
          Enum.map(suites, fn s ->
            "  #{s.slug}\t(#{s.case_count} cases)\t#{s.title}"
          end)
      end

    {:ok, rows}
  end

  def run_command(%{command: :eval_run, options: options}, _project_root) do
    alias ControlKeel.Cloud.EvalRunner

    slug = options[:suite] || "governance-regression"

    case EvalRunner.run(slug) do
      :not_found ->
        {:error, "Unknown eval suite: #{slug}"}

      {:ok, result} ->
        header = [
          "Eval suite: #{result.title} (#{result.slug})",
          "Total: #{result.total}",
          "Passed: #{result.passed}",
          "Failed: #{result.failed}"
        ]

        case_rows =
          Enum.map(result.cases, fn c ->
            badge = if c.status == :pass, do: "PASS", else: "FAIL"

            extras =
              cond do
                c.missing_rule_ids != [] ->
                  " missing=#{Enum.join(c.missing_rule_ids, ",")}"

                c.unexpected_block_rule_ids != [] ->
                  " unexpected_block=#{Enum.join(c.unexpected_block_rule_ids, ",")}"

                true ->
                  ""
              end

            "  [#{badge}] #{c.name} decision=#{c.decision}#{extras}"
          end)

        lines = header ++ case_rows

        if result.failed == 0 do
          {:ok, lines}
        else
          {:error, Enum.join(lines, "\n")}
        end
    end
  end

  def run_command(%{command: :benchmark_list, options: options}, project_root) do
    with {:ok, format} <- cli_output_format(options) do
      filter_opts = benchmark_filter_opts(options[:domain_pack])
      suites = Benchmark.list_suites(filter_opts)
      runs = Benchmark.list_recent_runs(filter_opts)
      subjects = Benchmark.available_subjects(project_root)
      help_lines = benchmark_list_help_lines(suites, runs, subjects)

      payload = %{
        "summary" => %{
          "suite_count" => length(suites),
          "subject_count" => length(subjects),
          "recent_run_count" => length(runs),
          "filter_summary" => benchmark_filter_summary(options)
        },
        "suites" =>
          Enum.map(suites, fn suite ->
            packs = Benchmark.domain_packs_for_suite(suite)

            %{
              "slug" => suite.slug,
              "version" => suite.version,
              "name" => suite.name,
              "scenario_count" => length(suite.scenarios),
              "domains" => format_domain_packs(packs)
            }
          end),
        "subjects" =>
          Enum.map(subjects, fn subject ->
            %{
              "id" => subject["id"],
              "type" => subject["type"],
              "label" => subject["label"]
            }
          end),
        "recent_runs" =>
          Enum.map(runs, fn run ->
            %{
              "id" => run.id,
              "suite_slug" => run.suite.slug,
              "status" => run.status,
              "catch_rate" => run.catch_rate,
              "baseline_subject" => run.baseline_subject
            }
          end),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      suite_lines =
        if suites == [] do
          [
            "Benchmark suites: 0#{benchmark_filter_summary(options)}",
            "Available subjects: #{length(subjects)}",
            "Recent runs: #{length(runs)}"
          ]
        else
          [
            "Benchmark suites: #{length(suites)}#{benchmark_filter_summary(options)}",
            "Available subjects: #{length(subjects)}",
            "Recent runs: #{length(runs)}",
            "Benchmark suites:"
            | Enum.map(suites, fn suite ->
                packs = Benchmark.domain_packs_for_suite(suite)

                "  #{suite.slug} v#{suite.version} — #{suite.name} (#{length(suite.scenarios)} scenarios; domains: #{format_domain_packs(packs)})"
              end)
          ]
        end

      subject_lines =
        [
          "",
          "Available subjects:"
          | Enum.map(subjects, fn subject ->
              "  #{subject["id"]} [#{subject["type"]}] #{subject["label"]}"
            end)
        ]

      run_lines =
        if runs == [] do
          ["", "No benchmark runs recorded yet."]
        else
          [
            "",
            "Recent runs:"
            | Enum.map(runs, fn run ->
                "  ##{run.id} #{run.suite.slug} [#{run.status}] catch #{run.catch_rate}% baseline #{run.baseline_subject}"
              end)
          ]
        end

      render_format(format, payload, fn _p ->
        suite_lines ++ subject_lines ++ run_lines ++ help_lines
      end)
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}
    end
  end

  def run_command(%{command: :benchmark_run, options: options}, project_root) do
    attrs = %{
      "suite" => options[:suite] || "vibe_failures_v1",
      "subjects" => options[:subjects],
      "baseline_subject" => options[:baseline_subject],
      "scenario_slugs" => options[:scenario_slugs],
      "domain_pack" => options[:domain_pack]
    }

    case Benchmark.run_suite(attrs, project_root) do
      {:ok, run} ->
        detail = Benchmark.run_detail_metrics(run)

        {:ok,
         [
           "Benchmark run ##{run.id} completed.",
           "Suite: #{run.suite.slug}",
           "Domains: #{format_domain_packs(Benchmark.domain_packs_for_run(run))}",
           "Subjects: #{Enum.join(run.subjects, ", ")}",
           "Status: #{run.status}",
           "Catch rate: #{run.catch_rate}%",
           "Block rate: #{detail.block_rate}%",
           "Expected rule hit rate: #{detail.expected_rule_hit_rate}%",
           "Average overhead: #{format_percent(run.average_overhead_percent)}"
         ]}

      {:error, :suite_not_found} ->
        {:error, "Benchmark suite was not found."}

      {:error, reason} ->
        {:error, "Failed to run benchmark: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_show, args: [id]}, _project_root) do
    with {:ok, run_id} <- parse_id(id),
         %{} = run <- Benchmark.get_run(run_id) do
      detail = Benchmark.run_detail_metrics(run)

      subject_lines =
        run.results
        |> Enum.group_by(& &1.subject)
        |> Enum.map(fn {subject, results} ->
          catches = Enum.count(results, &(&1.findings_count > 0))
          blocked = Enum.count(results, &(&1.decision == "block"))
          "  #{subject}: #{catches} caught, #{blocked} blocked, #{length(results)} total"
        end)

      {:ok,
       [
         "Benchmark run ##{run.id}",
         "Suite: #{run.suite.name} (#{run.suite.slug})",
         "Domains: #{format_domain_packs(Benchmark.domain_packs_for_run(run))}",
         "Status: #{run.status}",
         "Baseline subject: #{run.baseline_subject}",
         "Catch rate: #{run.catch_rate}%",
         "Block rate: #{detail.block_rate}%",
         "Expected rule hit rate: #{detail.expected_rule_hit_rate}%",
         "Median latency: #{format_ms(run.median_latency_ms)}",
         "Average overhead: #{format_percent(run.average_overhead_percent)}",
         "Subjects:"
         | subject_lines
       ] ++ benchmark_show_help_lines(run)}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      nil ->
        {:error, "Benchmark run not found."}
    end
  end

  def run_command(
        %{command: :benchmark_import, args: [run_id, subject, file_path]},
        _project_root
      ) do
    with {:ok, parsed_id} <- parse_id(run_id),
         {:ok, contents} <- File.read(file_path),
         {:ok, payload} <- Jason.decode(contents),
         {:ok, run} <- Benchmark.import_result(parsed_id, subject, payload) do
      {:ok,
       [
         "Imported benchmark output for #{subject} into run ##{run.id}.",
         "Run status: #{run.status}",
         "Catch rate: #{run.catch_rate}%"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      {:error, :enoent} ->
        {:error, "Benchmark import file was not found."}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Benchmark import file must be valid JSON: #{Exception.message(error)}"}

      {:error, :scenario_slug_required} ->
        {:error, "Benchmark import payload must include `scenario_slug`."}

      {:error, :result_not_found} ->
        {:error,
         "No matching benchmark result slot exists for that run, subject, and scenario_slug."}

      {:error, :not_found} ->
        {:error, "Benchmark run was not found."}

      {:error, reason} ->
        {:error, "Failed to import benchmark output: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_export, args: [run_id], options: options}, _project_root) do
    with {:ok, parsed_id} <- parse_id(run_id),
         {:ok, output} <- Benchmark.export_run(parsed_id, options[:format] || "json") do
      {:ok, [output]}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      {:error, :not_found} ->
        {:error, "Benchmark run was not found."}
    end
  end
end
