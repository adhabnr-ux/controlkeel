defmodule ControlKeel.Observability.PromotionTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Observability.Promotion

  @earlier "2026-07-23T10:00:00Z"
  @later "2026-07-23T12:00:00Z"

  test "keeps unproven behavior in review" do
    assert %{state: "review", deterministic: true, human_gate_required: true} =
             Promotion.evaluate(%{status: "open", human_gate_required: true})
  end

  test "requires approval even when benchmark evidence passes" do
    result = Promotion.evaluate(%{status: "open"}, %{outcome: "passed"})

    assert result.state == "review"
    assert result.human_gate_required
  end

  test "promotes only approved passing behavior" do
    result = Promotion.evaluate(%{status: "approved"}, %{outcome: "passed"})

    assert result.state == "promote"
    refute result.human_gate_required
    assert result.deterministic
  end

  test "reopens on failed or flaky evidence" do
    for outcome <- ["failed", "flaky"] do
      assert %{state: "reopen"} =
               Promotion.evaluate(%{status: "approved"}, %{outcome: outcome})
    end
  end

  test "reopens when a previously closed candidate records a regression" do
    # Only a reopen marker exists (no prior closed marker) → currently regressed.
    assert %{state: "reopen"} =
             Promotion.evaluate(%{
               status: "open",
               metadata: %{"lifecycle_reopened_by_run" => %{"run_id" => 7}}
             })
  end

  test "reopens when pass-then-fail leaves the reopen marker as the latest" do
    # Both markers present; the reopen happened after the close → regressed.
    assert %{state: "reopen"} =
             Promotion.evaluate(%{
               status: "open",
               metadata: %{
                 "lifecycle_closed_by_run" => %{"all_matched" => true, "closed_at" => @earlier},
                 "lifecycle_reopened_by_run" => %{"all_matched" => false, "closed_at" => @later}
               }
             })
  end

  test "promotes an approved candidate after a passing run archives it" do
    # Production transition overwrites status from "approved" to "archived" on a
    # passing run. The closed marker must still imply prior approval.
    result =
      Promotion.evaluate(%{
        status: "archived",
        metadata: %{
          "lifecycle_closed_by_run" => %{"all_matched" => true, "closed_at" => @earlier}
        }
      })

    assert result.state == "promote"
    refute result.human_gate_required
  end

  test "recovers to promote after a fail-then-pass lifecycle sequence" do
    # Both markers present; the close happened after the reopen → recovered.
    result =
      Promotion.evaluate(%{
        status: "archived",
        metadata: %{
          "lifecycle_reopened_by_run" => %{"all_matched" => false, "closed_at" => @earlier},
          "lifecycle_closed_by_run" => %{"all_matched" => true, "closed_at" => @later}
        }
      })

    assert result.state == "promote"
  end

  test "recovers to promote when fail-then-pass lands in the same wall-clock second" do
    # Lifecycle closed_at is truncated to second precision, so a fail followed
    # by a pass within the same second produces equal timestamps. The monotonic
    # `seq` counter disambiguates the ordering (see PR #43 Greptile P1).
    tie = "2026-07-23T12:00:00Z"

    result =
      Promotion.evaluate(%{
        status: "archived",
        metadata: %{
          "lifecycle_reopened_by_run" => %{"all_matched" => false, "closed_at" => tie, "seq" => 1},
          "lifecycle_closed_by_run" => %{"all_matched" => true, "closed_at" => tie, "seq" => 2}
        }
      })

    assert result.state == "promote"
  end

  test "reopens when pass-then-fail lands in the same wall-clock second" do
    # Symmetric to the recovery case: the later failing transition must win.
    tie = "2026-07-23T12:00:00Z"

    result =
      Promotion.evaluate(%{
        status: "open",
        metadata: %{
          "lifecycle_closed_by_run" => %{"all_matched" => true, "closed_at" => tie, "seq" => 1},
          "lifecycle_reopened_by_run" => %{"all_matched" => false, "closed_at" => tie, "seq" => 2}
        }
      })

    assert result.state == "reopen"
  end

  test "explicit human approval with passing evidence promotes without lifecycle markers" do
    result =
      Promotion.evaluate(%{status: "open"}, %{outcome: "passed", human_approved: true})

    assert result.state == "promote"
  end

  test "explicit human_approved metadata with a closed marker promotes" do
    result =
      Promotion.evaluate(%{
        status: "archived",
        metadata: %{
          "lifecycle_closed_by_run" => %{"all_matched" => true},
          "human_approved" => true
        }
      })

    assert result.state == "promote"
  end

  test "nil candidate and evidence do not crash" do
    assert %{state: "review"} = Promotion.evaluate(nil, nil)
  end
end
