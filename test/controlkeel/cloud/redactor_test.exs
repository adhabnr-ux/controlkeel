defmodule ControlKeel.Cloud.RedactorTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Cloud.Redactor

  describe "redact_string/1 (closes CK-CLOUD-SYNC-001)" do
    test "scrubs Anthropic sk-ant keys" do
      assert Redactor.redact_string("ANTHROPIC_API_KEY=sk-ant-abcdefghij1234567890ABCDEF") =~
               "[REDACTED]"

      refute Redactor.redact_string("sk-ant-abcdefghij1234567890ABCDEF") =~ "abcdefghij"
    end

    test "scrubs OpenAI / generic sk- keys" do
      assert Redactor.redact_string("sk-1234567890abcdef1234567890ABCD") =~ "[REDACTED:sk]"
    end

    test "scrubs GitHub PATs" do
      for prefix <- ["ghp_", "ghs_", "gho_", "ghu_", "ghr_"] do
        token = prefix <> String.duplicate("a", 36)
        assert Redactor.redact_string("token: " <> token) =~ "[REDACTED:gh-token]"
      end
    end

    test "scrubs Authorization: Bearer headers" do
      assert Redactor.redact_string("Authorization: Bearer abc123") =~ "[REDACTED]"
      assert Redactor.redact_string("authorization: bearer abc123") =~ "[REDACTED]"
    end

    test "scrubs env-style credential assignments" do
      assert Redactor.redact_string("OPENAI_API_KEY=sk-secretkey") =~ "[REDACTED]"
      assert Redactor.redact_string("token=verysecret&other=ok") =~ "token=[REDACTED]"
      assert Redactor.redact_string("password=hunter2") =~ "password=[REDACTED]"
    end

    test "passes through clean content unchanged" do
      clean = "Refactor the parser to use a recursive-descent grammar."
      assert Redactor.redact_string(clean) == clean
    end

    test "is idempotent" do
      input = "Authorization: Bearer secret"
      once = Redactor.redact_string(input)
      assert Redactor.redact_string(once) == once
    end
  end

  describe "redact_value/1" do
    test "walks maps recursively" do
      input = %{
        "outer" => %{
          "inner" => "ANTHROPIC_API_KEY=sk-ant-abcdefghij1234567890ABCDEF",
          "ok" => "fine"
        }
      }

      result = Redactor.redact_value(input)
      assert result["outer"]["inner"] =~ "[REDACTED]"
      assert result["outer"]["ok"] == "fine"
    end

    test "walks lists recursively" do
      assert Redactor.redact_value([
               "clean",
               "sk-ant-abcdefghij1234567890ABCDEF"
             ]) == ["clean", "[REDACTED:sk-ant]"]
    end

    test "passes DateTime / numbers / booleans through" do
      dt = ~U[2026-05-28 12:00:00Z]
      assert Redactor.redact_value(dt) == dt
      assert Redactor.redact_value(42) == 42
      assert Redactor.redact_value(true) == true
    end
  end
end
