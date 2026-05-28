defmodule ControlKeel.Governance.TechDebtDetectorTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.TechDebtDetector
  alias ControlKeel.Mission

  defp workspace!(name_seed) do
    {:ok, workspace} =
      Mission.create_workspace(%{
        name: "Detector-#{name_seed}",
        slug: "detector-#{name_seed}-#{:rand.uniform(99_999)}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })

    workspace
  end

  defp session!(workspace, title) do
    {:ok, session} =
      Mission.create_session(%{
        title: title,
        objective: "test",
        risk_tier: "low",
        budget_cents: 10_000,
        daily_budget_cents: 5_000,
        workspace_id: workspace.id
      })

    session
  end

  defp finding!(session, rule_id, path) do
    {:ok, f} =
      Mission.create_finding(%{
        session_id: session.id,
        title: "f",
        severity: "medium",
        category: "code_quality",
        rule_id: rule_id,
        plain_message: "patch",
        status: "open",
        metadata: %{"path" => path}
      })

    f
  end

  describe "detect_for_session/2 — CK-TECHDEBT-001 (repeated patches)" do
    test "emits a signal when threshold findings land on the same path across sessions" do
      ws = workspace!("repeated")
      [s1, s2, s3] = Enum.map(1..3, &session!(ws, "S#{&1}"))

      for s <- [s1, s2, s3], do: finding!(s, "CK-LINT-001", "lib/legacy.ex")

      signals = TechDebtDetector.detect_for_session(s3.id)

      assert [signal] = Enum.filter(signals, &(&1.signal_type == "repeated_patches"))
      assert signal.rule_id == "CK-TECHDEBT-001"
      assert signal.path == "lib/legacy.ex"
      assert signal.count == 3
      assert Enum.sort(signal.recent_session_ids) == Enum.sort([s1.id, s2.id, s3.id])
    end

    test "suppresses the signal below threshold (count = 2)" do
      ws = workspace!("below")
      [s1, s2] = Enum.map(1..2, &session!(ws, "S#{&1}"))
      for s <- [s1, s2], do: finding!(s, "CK-LINT-001", "lib/legacy.ex")

      signals = TechDebtDetector.detect_for_session(s2.id)
      assert Enum.filter(signals, &(&1.signal_type == "repeated_patches")) == []
    end

    test "suppresses the signal when an intervening refactor commit is recorded" do
      ws = workspace!("refactor")
      [s1, s2, s3] = Enum.map(1..3, &session!(ws, "S#{&1}"))

      tmp = Path.join(System.tmp_dir!(), "ck_techdebt_#{:rand.uniform(99_999)}")
      File.mkdir_p!(tmp)
      System.cmd("git", ["init", "-q"], cd: tmp)
      System.cmd("git", ["config", "user.email", "t@t"], cd: tmp)
      System.cmd("git", ["config", "user.name", "t"], cd: tmp)
      File.mkdir_p!(Path.join(tmp, "lib"))
      File.write!(Path.join(tmp, "lib/legacy.ex"), "x")
      System.cmd("git", ["add", "."], cd: tmp)
      System.cmd("git", ["commit", "-q", "-m", "refactor: clean up legacy"], cd: tmp)

      for s <- [s1, s2, s3], do: finding!(s, "CK-LINT-001", "lib/legacy.ex")

      signals = TechDebtDetector.detect_for_session(s3.id, project_root: tmp)
      assert Enum.filter(signals, &(&1.signal_type == "repeated_patches")) == []

      File.rm_rf!(tmp)
    end
  end

  describe "detect_for_session/2 — CK-TECHDEBT-002 (unresolved pattern)" do
    test "emits a signal when the same rule_id fires across threshold distinct sessions" do
      ws = workspace!("pattern")
      [s1, s2, s3] = Enum.map(1..3, &session!(ws, "S#{&1}"))

      # Same rule_id across 3 sessions, but spread across different paths so
      # the path-based signal does not fire and we test only CK-TECHDEBT-002.
      finding!(s1, "CK-FOO-001", "lib/a.ex")
      finding!(s2, "CK-FOO-001", "lib/b.ex")
      finding!(s3, "CK-FOO-001", "lib/c.ex")

      signals = TechDebtDetector.detect_for_session(s3.id)

      assert [signal] = Enum.filter(signals, &(&1.signal_type == "unresolved_pattern"))
      assert signal.rule_id == "CK-TECHDEBT-002"
      assert signal.count == 3
      assert Enum.sort(signal.recent_session_ids) == Enum.sort([s1.id, s2.id, s3.id])
    end

    test "excludes CK-TECHDEBT-* rule_ids from the unresolved-pattern signal" do
      ws = workspace!("noselfamp")
      [s1, s2, s3] = Enum.map(1..3, &session!(ws, "S#{&1}"))

      for s <- [s1, s2, s3], do: finding!(s, "CK-TECHDEBT-001", "lib/a.ex")

      signals = TechDebtDetector.detect_for_session(s3.id)
      assert Enum.filter(signals, &(&1.signal_type == "unresolved_pattern")) == []
    end
  end
end
