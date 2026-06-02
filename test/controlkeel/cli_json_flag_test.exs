defmodule ControlKeel.CLI.JsonFlagTest do
  use ControlKeel.DataCase

  alias ControlKeel.CLI

  defp assert_json_parsed!(argv, expected_command) do
    {:ok, parsed} = CLI.parse(argv)
    assert parsed.command == expected_command
    assert Keyword.get(parsed.options, :json) == true
  end

  describe "switch-based commands accept --json" do
    test "init --json" do
      assert_json_parsed!(["init", "--json"], :init)
    end

    test "status --json" do
      assert_json_parsed!(["status", "--json"], :status)
    end

    test "doctor --json" do
      assert_json_parsed!(["doctor", "--json"], :doctor)
    end

    test "capabilities --json" do
      assert_json_parsed!(["capabilities", "--json"], :capabilities)
    end

    test "update --json" do
      assert_json_parsed!(["update", "--json"], :update)
    end

    test "context --json" do
      assert_json_parsed!(["context", "--json"], :context)
    end

    test "validate --json" do
      assert_json_parsed!(["validate", "--json"], :validate)
    end

    test "findings --json" do
      assert_json_parsed!(["findings", "--json"], :findings)
    end

    test "findings translate --json" do
      assert_json_parsed!(["findings", "translate", "--json"], :findings_translate)
    end

    test "proofs --json" do
      assert_json_parsed!(["proofs", "--json"], :proofs)
    end

    test "mcp --json" do
      assert_json_parsed!(["mcp", "--json"], :mcp)
    end

    test "me --json" do
      assert_json_parsed!(["me", "--json"], :me)
    end

    test "memory search --json" do
      assert_json_parsed!(["memory", "search", "test", "--json"], :memory_search)
    end

    test "deploy analyze --json" do
      assert_json_parsed!(["deploy", "analyze", "--json"], :deploy_analyze)
    end

    test "deploy cost --json" do
      assert_json_parsed!(["deploy", "cost", "--json"], :deploy_cost)
    end

    test "cost optimize --json" do
      assert_json_parsed!(["cost", "optimize", "--json"], :cost_optimize)
    end

    test "cost compare --json" do
      assert_json_parsed!(["cost", "compare", "--json"], :cost_compare)
    end

    test "precommit-check --json" do
      assert_json_parsed!(["precommit-check", "--json"], :precommit_check)
    end

    test "progress --json" do
      assert_json_parsed!(["progress", "--json"], :progress)
    end

    test "circuit-breaker status --json" do
      assert_json_parsed!(["circuit-breaker", "status", "--json"], :circuit_breaker_status)
    end

    test "agents monitor --json" do
      assert_json_parsed!(["agents", "monitor", "--json"], :agents_monitor)
    end

    test "skills list --json" do
      assert_json_parsed!(["skills", "list", "--json"], :skills_list)
    end

    test "skills validate --json" do
      assert_json_parsed!(["skills", "validate", "--json"], :skills_validate)
    end

    test "skills export --json" do
      assert_json_parsed!(["skills", "export", "--json"], :skills_export)
    end

    test "skills install --json" do
      assert_json_parsed!(["skills", "install", "--json"], :skills_install)
    end

    test "skills doctor --json" do
      assert_json_parsed!(["skills", "doctor", "--json"], :skills_doctor)
    end

    test "token audit --json" do
      assert_json_parsed!(["token", "audit", "--json"], :token_audit)
    end

    test "tool groups suggest --json" do
      assert_json_parsed!(["tool", "groups", "suggest", "--json"], :tool_groups_suggest)
    end

    test "benchmark list --json" do
      assert_json_parsed!(["benchmark", "list", "--json"], :benchmark_list)
    end

    test "benchmark run --json" do
      assert_json_parsed!(["benchmark", "run", "--json"], :benchmark_run)
    end

    test "benchmark export --json" do
      assert_json_parsed!(["benchmark", "export", "1", "--json"], :benchmark_export)
    end

    test "obs status --json" do
      assert_json_parsed!(["obs", "status", "--json"], :obs_status)
    end

    test "obs costs --json" do
      assert_json_parsed!(["obs", "costs", "--json"], :obs_costs)
    end

    test "obs problems --json" do
      assert_json_parsed!(["obs", "problems", "--json"], :obs_problems)
    end

    test "review diff --json" do
      assert_json_parsed!(["review", "diff", "--json"], :review_diff)
    end

    test "review pr --json" do
      assert_json_parsed!(["review", "pr", "--json"], :review_pr)
    end

    test "review socket --json" do
      assert_json_parsed!(["review", "socket", "--json"], :review_socket)
    end

    test "review plan submit --json" do
      assert_json_parsed!(["review", "plan", "submit", "--stdin", "--json"], :review_plan_submit)
    end

    test "review plan open --json" do
      assert_json_parsed!(["review", "plan", "open", "--json"], :review_plan_open)
    end

    test "review plan wait --json" do
      assert_json_parsed!(["review", "plan", "wait", "--json"], :review_plan_wait)
    end

    test "release-ready --json" do
      assert_json_parsed!(["release-ready", "--json"], :release_ready)
    end

    test "route-agent --json" do
      assert_json_parsed!(["route-agent", "--json"], :route_agent)
    end

    test "agents list --json" do
      assert_json_parsed!(["agents", "list", "--json"], :agents_list)
    end

    test "agents discover --json" do
      assert_json_parsed!(["agents", "discover", "/tmp", "--json"], :agents_discover)
    end

    test "provider list --json" do
      assert_json_parsed!(["provider", "list", "--json"], :provider_list)
    end

    test "provider show --json" do
      assert_json_parsed!(["provider", "show", "--json"], :provider_show)
    end

    test "provider doctor --json" do
      assert_json_parsed!(["provider", "doctor", "--json"], :provider_doctor)
    end

    test "eval list --json" do
      assert_json_parsed!(["eval", "list", "--json"], :eval_list)
    end

    test "eval run --json" do
      assert_json_parsed!(["eval", "run", "--json"], :eval_run)
    end

    test "bootstrap --json" do
      assert_json_parsed!(["bootstrap", "--json"], :bootstrap)
    end

    test "setup --json" do
      assert_json_parsed!(["setup", "--json"], :setup)
    end

    test "watch --json" do
      assert_json_parsed!(["watch", "--json"], :watch)
    end

    test "audit-log --json" do
      assert_json_parsed!(["audit-log", "1", "--json"], :audit_log)
    end

    test "telemetry status --json" do
      assert_json_parsed!(["telemetry", "status", "--json"], :telemetry_status)
    end

    test "telemetry enable --json" do
      assert_json_parsed!(["telemetry", "enable", "--json"], :telemetry_enable)
    end

    test "telemetry disable --json" do
      assert_json_parsed!(["telemetry", "disable", "--json"], :telemetry_disable)
    end

    test "telemetry queue --json" do
      assert_json_parsed!(["telemetry", "queue", "--json"], :telemetry_queue)
    end

    test "telemetry flush --json" do
      assert_json_parsed!(["telemetry", "flush", "--json"], :telemetry_flush)
    end

    test "mcp registry list --json" do
      assert_json_parsed!(["mcp", "registry", "list", "--json"], :mcp_registry_list)
    end

    test "mcp registry check --json" do
      assert_json_parsed!(
        ["mcp", "registry", "check", "test-server", "--json"],
        :mcp_registry_check
      )
    end

    test "mcp guardrails list --json" do
      assert_json_parsed!(["mcp", "guardrails", "list", "--json"], :mcp_guardrails_list)
    end

    test "govern install github --json" do
      assert_json_parsed!(["govern", "install", "github", "--json"], :govern_install_github)
    end

    test "govern bind github --json" do
      assert_json_parsed!(["govern", "bind", "github", "--json"], :govern_bind_github)
    end

    test "cloud doctor --json" do
      assert_json_parsed!(["cloud", "doctor", "--json"], :cloud_doctor)
    end

    test "cloud connect --json" do
      assert_json_parsed!(["cloud", "connect", "--json"], :cloud_connect)
    end

    test "cloud push --json" do
      assert_json_parsed!(["cloud", "push", "--json"], :cloud_sync_push)
    end

    test "cloud pull --json" do
      assert_json_parsed!(["cloud", "pull", "--json"], :cloud_sync_pull)
    end

    test "cloud migrate --json" do
      assert_json_parsed!(["cloud", "migrate", "--json"], :cloud_sync_migrate)
    end

    test "runtime export --json" do
      assert_json_parsed!(["runtime", "export", "devin", "--json"], :runtime_export)
    end

    test "selfhost pack --json" do
      assert_json_parsed!(["selfhost", "pack", "--json"], :selfhost_pack)
    end

    test "selfhost verify --json" do
      assert_json_parsed!(["selfhost", "verify", "--json"], :selfhost_verify)
    end

    test "selfhost manifest --json" do
      assert_json_parsed!(["selfhost", "manifest", "--json"], :selfhost_manifest)
    end

    test "baseline compute --json" do
      assert_json_parsed!(["baseline", "compute", "--json"], :baseline_compute)
    end

    test "audit export --json" do
      assert_json_parsed!(["audit", "export", "--json"], :audit_export)
    end

    test "attach --json" do
      assert_json_parsed!(["attach", "opencode", "--json"], :attach)
    end

    test "obs loop --json" do
      assert_json_parsed!(["obs", "loop", "--json"], :obs_loop_status)
    end

    test "obs trends --json" do
      assert_json_parsed!(["obs", "trends", "--json"], :obs_trends)
    end

    test "obs imports --json" do
      assert_json_parsed!(["obs", "imports", "--json"], :obs_imports)
    end

    test "obs regressions --json" do
      assert_json_parsed!(["obs", "regressions", "--json"], :obs_regressions)
    end

    test "obs recommend --json" do
      assert_json_parsed!(["obs", "recommend", "--json"], :obs_recommend)
    end

    test "obs evals --json" do
      assert_json_parsed!(["obs", "evals", "--json"], :obs_evals)
    end

    test "obs benchmarks drafts --json" do
      assert_json_parsed!(["obs", "benchmarks", "drafts", "--json"], :obs_benchmark_drafts)
    end
  end

  describe "refactored arg-only commands now accept --json" do
    test "session list --json" do
      assert_json_parsed!(["session", "list", "--json"], :session_list)
    end

    test "session list without --json still works" do
      {:ok, parsed} = CLI.parse(["session", "list"])
      assert parsed.command == :session_list
    end

    test "session switch --json" do
      {:ok, parsed} = CLI.parse(["session", "switch", "42", "--json"])
      assert parsed.command == :session_switch
      assert Keyword.get(parsed.options, :json) == true
      assert parsed.args == ["42"]
    end

    test "session switch without --json still works" do
      {:ok, parsed} = CLI.parse(["session", "switch", "42"])
      assert parsed.command == :session_switch
      assert parsed.args == ["42"]
    end

    test "sandbox status --json" do
      assert_json_parsed!(["sandbox", "status", "--json"], :sandbox_status)
    end

    test "sandbox status without --json still works" do
      {:ok, parsed} = CLI.parse(["sandbox", "status"])
      assert parsed.command == :sandbox_status
    end

    test "outcome record --json" do
      {:ok, parsed} = CLI.parse(["outcome", "record", "1", "success", "--json"])
      assert parsed.command == :outcome_record
      assert Keyword.get(parsed.options, :json) == true
      assert parsed.args == ["1", "success"]
    end

    test "outcome record without --json still works" do
      {:ok, parsed} = CLI.parse(["outcome", "record", "1", "success"])
      assert parsed.command == :outcome_record
      assert parsed.args == ["1", "success"]
    end

    test "outcome score --json" do
      {:ok, parsed} = CLI.parse(["outcome", "score", "claude", "--json"])
      assert parsed.command == :outcome_score
      assert Keyword.get(parsed.options, :json) == true
      assert parsed.args == ["claude"]
    end

    test "outcome score without --json still works" do
      {:ok, parsed} = CLI.parse(["outcome", "score", "claude"])
      assert parsed.command == :outcome_score
      assert parsed.args == ["claude"]
    end

    test "outcome leaderboard --json" do
      assert_json_parsed!(["outcome", "leaderboard", "--json"], :outcome_leaderboard)
    end

    test "outcome leaderboard without --json still works" do
      {:ok, parsed} = CLI.parse(["outcome", "leaderboard"])
      assert parsed.command == :outcome_leaderboard
    end
  end

  describe "--json is parsed into options correctly" do
    test "json boolean is true when --json is passed" do
      {:ok, parsed} = CLI.parse(["doctor", "--json"])
      assert Keyword.get(parsed.options, :json) == true
    end

    test "json is absent when --json is not passed" do
      {:ok, parsed} = CLI.parse(["doctor"])
      refute Keyword.get(parsed.options, :json)
    end

    test "json works alongside other flags" do
      {:ok, parsed} =
        CLI.parse(["validate", "--content", "hello", "--kind", "text", "--json"])

      assert Keyword.get(parsed.options, :json) == true
      assert Keyword.get(parsed.options, :content) == "hello"
      assert Keyword.get(parsed.options, :kind) == "text"
    end

    test "outcome record --json preserves args" do
      {:ok, parsed} = CLI.parse(["outcome", "record", "99", "failure", "--json"])
      assert parsed.args == ["99", "failure"]
      assert Keyword.get(parsed.options, :json) == true
    end
  end
end
