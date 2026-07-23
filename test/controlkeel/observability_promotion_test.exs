defmodule ControlKeel.Observability.PromotionTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Observability.Promotion

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
    assert %{state: "reopen"} =
             Promotion.evaluate(%{
               status: "archived",
               metadata: %{"lifecycle_reopened_by_run" => %{"run_id" => 7}}
             })
  end

  test "uses lifecycle evidence without requiring database access" do
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
end
