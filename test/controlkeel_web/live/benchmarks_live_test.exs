defmodule ControlKeelWeb.BenchmarksLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import Phoenix.LiveViewTest

  test "index renders suites, recent runs, and launches a benchmark run", %{conn: conn} do
    existing_run = benchmark_run_fixture()

    {:ok, view, html} = live(conn, ~p"/benchmarks")

    assert has_element?(view, "h1", "Benchmark engine")
    assert has_element?(view, "button[form='benchmark-runner'][type='submit']")
    assert html =~ "OpenCode vs ControlKeel"
    assert has_element?(view, "#benchmark-runner")
    assert has_element?(view, "#benchmark-preset-opencode")
    assert has_element?(view, "#benchmark-subjects-input")
    assert has_element?(view, "#benchmark-baseline-input")
    assert has_element?(view, "#benchmark-runs")

    assert has_element?(view, "a[href=\"/benchmarks/runs/#{existing_run.id}\"]")

    render_submit(
      form(view, "#benchmark-runner",
        benchmark: %{
          "suite" => "vibe_failures_v1",
          "subjects" => ["controlkeel_validate"],
          "baseline_subject" => "controlkeel_validate"
        }
      )
    )

    {path, _flash} = assert_redirect(view)
    assert path =~ "/benchmarks/runs/"
  end

  test "index preset buttons fill subject fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/benchmarks")

    view |> element("#benchmark-preset-proxy") |> render_click()

    assert has_element?(
             view,
             "#benchmark-runner input[name='benchmark[subjects][]'][value='controlkeel_validate']"
           )

    assert has_element?(
             view,
             "#benchmark-runner input[name='benchmark[subjects][]'][value='controlkeel_proxy']"
           )

    view |> element("#benchmark-preset-opencode") |> render_click()

    assert has_element?(
             view,
             "#benchmark-runner input[name='benchmark[subjects][]'][value='opencode_manual']"
           )

    view |> element("#benchmark-preset-ck-only") |> render_click()
    assert render(view) =~ "benchmark-subjects-input"
  end

  test "index surfaces configured external subjects", %{conn: conn} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-benchmarks-live-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    write_benchmark_subjects!(tmp_dir, [
      %{
        "id" => "opencode_manual",
        "label" => "OpenCode Manual Import",
        "type" => "manual_import"
      }
    ])

    original_cwd = File.cwd!()
    File.cd!(tmp_dir)

    on_exit(fn -> File.cd!(original_cwd) end)

    {:ok, _view, html} = live(conn, ~p"/benchmarks")

    assert html =~ "OpenCode Manual Import (external)"
  end

  test "show renders the persisted scenario matrix", %{conn: conn} do
    run =
      benchmark_run_fixture(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hr_discriminatory_candidate_filter,legal_privileged_memo_logging"
      })

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert html =~ "Scenario matrix"
    assert html =~ "Catch rate"
    assert html =~ "Promotion integrity"
    assert has_element?(view, "#scenario-hr_discriminatory_candidate_filter")
    assert has_element?(view, "a[href=\"/api/v1/benchmarks/runs/#{run.id}/export?format=csv\"]")

    # Loop access: each subject label renders (zip alignment + subject lookup).
    assert html =~ "ControlKeel Validate"
    assert html =~ "ControlKeel Proxy Policy Scan"

    # Loop access: result fields resolve inside scenario_result/1.
    assert html =~ "findings"
    assert html =~ "latency"
    assert html =~ "overhead"

    # Status badge renders (was previously suppressed for "completed").
    assert html =~ "completed"

    # Loop access: the second scenario row renders too.
    assert has_element?(view, "#scenario-legal_privileged_memo_logging")
  end

  test "show renders the comparison panel for a multi-subject run", %{conn: conn} do
    run =
      benchmark_run_fixture(%{
        "suite" => "domain_expansion_v1",
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate",
        "scenario_slugs" => "hr_discriminatory_candidate_filter,legal_privileged_memo_logging"
      })

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert has_element?(view, "#comparison-panel")
    assert html =~ "Subject comparison"
    assert has_element?(view, "#comparison-subject-controlkeel_validate")
    assert has_element?(view, "#comparison-subject-controlkeel_proxy")
    assert has_element?(view, "#comparison-chart-controlkeel_validate")
    assert has_element?(view, "#comparison-chart-controlkeel_proxy")
    assert html =~ "baseline"

    assert html =~ "TPR"
    assert html =~ "FPR"
    assert html =~ "Youden"
    assert html =~ "CK tool calls"
    assert html =~ "Safe claim:"
    assert html =~ "Caveat:"
    assert html =~ "Δ"
  end

  test "show renders empty comparison state for a single-subject run", %{conn: conn} do
    run = benchmark_run_fixture()

    {:ok, view, html} = live(conn, ~p"/benchmarks/runs/#{run.id}")

    assert has_element?(view, "#comparison-panel")
    assert html =~ "No comparable subjects"
    refute has_element?(view, "#comparison-subject-controlkeel_validate")
    refute has_element?(view, "#comparison-chart")
  end

  test "index preset buttons fill multi-host subject fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/benchmarks")

    view |> element("#benchmark-preset-copilot-vs-opencode") |> render_click()
    html = render(view)
    assert html =~ "host_comparison_v1"
    assert html =~ "copilot_manual"

    view |> element("#benchmark-preset-full-compare") |> render_click()
    html = render(view)
    assert html =~ "host_comparison_v1"
    assert html =~ "gemini_manual"
    assert html =~ "codex_manual"
    assert html =~ "claude_manual"
  end

  test "multi-select subject dropdown toggles subjects on and off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/benchmarks")

    refute has_element?(view, "#benchmark-subjects-input [role='listbox']")

    view
    |> element("#benchmark-subjects-input button[phx-click='toggle_subjects_dropdown']")
    |> render_click()

    assert has_element?(view, "#benchmark-subjects-input [role='listbox']")

    view
    |> element(
      "#benchmark-subjects-input button[role='option'][data-subject-id='controlkeel_proxy']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#benchmark-subjects-input input[name='benchmark[subjects][]'][value='controlkeel_proxy']"
           )

    view
    |> element(
      "#benchmark-subjects-input button[role='option'][data-subject-id='controlkeel_proxy']"
    )
    |> render_click()

    refute has_element?(
             view,
             "#benchmark-subjects-input input[name='benchmark[subjects][]'][value='controlkeel_proxy']"
           )
  end

  test "manually toggling a subject clears the active preset", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/benchmarks")

    assert has_element?(view, "#benchmark-preset-opencode[aria-pressed='true']")

    view |> element("#benchmark-preset-ck-only") |> render_click()
    assert has_element?(view, "#benchmark-preset-ck-only[aria-pressed='true']")

    view
    |> element("#benchmark-subjects-input button[phx-click='toggle_subjects_dropdown']")
    |> render_click()

    view
    |> element(
      "#benchmark-subjects-input button[role='option'][data-subject-id='controlkeel_proxy']"
    )
    |> render_click()

    refute has_element?(view, "#benchmark-preset-ck-only[aria-pressed='true']")
  end

  test "index renders an empty state when there are no runs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/benchmarks")

    assert html =~ "No benchmark runs yet"
  end

  test "show redirects to index when the run is not found", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/benchmarks", flash: flash}}} =
             live(conn, ~p"/benchmarks/runs/999999")

    assert flash["error"] == "Benchmark run not found."
  end
end
