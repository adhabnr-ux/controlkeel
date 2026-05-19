defmodule ControlKeel.Scanner.EntropyTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Scanner.Entropy

  setup do
    {:ok, rules: PackLoader.load!("baseline")}
  end

  test "detects high-entropy secret-like tokens", %{rules: rules} do
    token = ["N4f8", "qP2m", "X9vR", "7kL3", "cT6w", "H1sD", "0bY5", "uJ8"] |> Enum.join()

    findings = Entropy.detect(token, %{"path" => ".env", "kind" => "config"}, rules)

    assert Enum.any?(findings, &(&1.rule_id == "secret.high_entropy_token"))

    finding = Enum.find(findings, &(&1.rule_id == "secret.high_entropy_token"))
    assert finding.decision == "block"
    assert finding.metadata["matcher"] == "entropy"
    assert finding.metadata["matched_text_redacted"] =~ "N4f8"
    assert finding.metadata["entropy"] >= 4.2
  end

  test "ignores low-entropy benign strings", %{rules: rules} do
    content = "DATABASE_URL=postgres://localhost/controlkeel_dev"

    findings = Entropy.detect(content, %{"path" => ".env", "kind" => "config"}, rules)

    refute Enum.any?(findings, &(&1.rule_id == "secret.high_entropy_token"))
  end

  test "ignores code identifiers and URL paths that look entropic", %{rules: rules} do
    content = """
    describe "create_starter_config/1" do
      assert url == "https://github.com/acme/trial/pull/123.patch"
    end
    """

    findings =
      Entropy.detect(content, %{"path" => "test/example_test.exs", "kind" => "code"}, rules)

    refute Enum.any?(findings, &(&1.rule_id == "secret.high_entropy_token"))
  end

  test "still detects slash-containing high entropy tokens", %{rules: rules} do
    token = ["N4f8", "qP2m", "X9vR", "7kL3", "/", "cT6w", "H1sD", "0bY5", "uJ8"] |> Enum.join()

    findings = Entropy.detect(token, %{"path" => ".env", "kind" => "config"}, rules)

    assert Enum.any?(findings, &(&1.rule_id == "secret.high_entropy_token"))
  end
end
