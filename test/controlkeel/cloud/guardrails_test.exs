defmodule ControlKeel.Cloud.GuardrailsTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.Cloud.Guardrails
  alias ControlKeel.Cloud.McpToolCall
  alias ControlKeel.ProtocolInterop
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, :cloud_mcp_guardrails)
    Application.delete_env(:controlkeel, :cloud_mcp_guardrails)

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :cloud_mcp_guardrails, previous)
      else
        Application.delete_env(:controlkeel, :cloud_mcp_guardrails)
      end
    end)

    :ok
  end

  describe "default (disabled)" do
    test "scan/2 returns :ok regardless of contents" do
      assert :ok = Guardrails.scan(%{"data" => "sk-AAAAAAAAAAAAAAAAAAAAAAAA"}, "ck_context")
    end

    test "summary reflects disabled state" do
      summary = Guardrails.summary()
      assert summary.enabled == false
      assert summary.pattern_count > 0
    end
  end

  describe "enabled with all built-in patterns" do
    setup do
      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{enabled: true})
      :ok
    end

    test "detects OpenAI-style key" do
      assert {:error, {:guardrail, :openai_api_key}} =
               Guardrails.scan(%{"prompt" => "key=sk-ABCDEFGHIJKLMNOPQRSTUVWX"}, "ck_finding")
    end

    test "detects Anthropic key (distinct from openai_api_key)" do
      assert {:error, {:guardrail, :anthropic_api_key}} =
               Guardrails.scan(%{"key" => "sk-ant-AAABBBCCCDDDEEEFFFGGGHHH"}, "ck_finding")
    end

    test "detects GitHub token variants" do
      for prefix <- ~w(ghp gho ghu ghs ghr) do
        token = "#{prefix}_" <> String.duplicate("A", 36)
        result = Guardrails.scan(%{"token" => token}, "ck_finding")
        assert {:error, {:guardrail, :github_token}} = result, "expected match for #{prefix}"
      end
    end

    test "detects AWS access key" do
      assert {:error, {:guardrail, :aws_access_key}} =
               Guardrails.scan(%{"creds" => "AKIA0123456789ABCDEF"}, "ck_finding")
    end

    test "passes clean arguments" do
      assert :ok = Guardrails.scan(%{"prompt" => "what is the weather today?"}, "ck_context")
    end

    test "scans recursively into nested maps" do
      args = %{"outer" => %{"inner" => %{"deep" => "sk-AAAAAAAAAAAAAAAAAAAAAAAA"}}}
      assert {:error, {:guardrail, :openai_api_key}} = Guardrails.scan(args, "ck_context")
    end

    test "scans recursively into lists" do
      args = %{"items" => ["safe", "sk-AAAAAAAAAAAAAAAAAAAAAAAA", "also safe"]}
      assert {:error, {:guardrail, :openai_api_key}} = Guardrails.scan(args, "ck_context")
    end

    test "stops at first match" do
      args = %{
        "k1" => "AKIA0123456789ABCDEF",
        "k2" => "sk-AAAAAAAAAAAAAAAAAAAAAAAA"
      }

      {:error, {:guardrail, name}} = Guardrails.scan(args, "ck_context")
      assert name in [:aws_access_key, :openai_api_key]
    end
  end

  describe "enabled with explicit pattern subset" do
    test "scans only the listed patterns" do
      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{
        enabled: true,
        patterns: [:aws_access_key]
      })

      # Openai key NOT scanned because only aws_access_key is listed
      assert :ok = Guardrails.scan(%{"k" => "sk-AAAAAAAAAAAAAAAAAAAAAAAA"}, "ck_context")

      assert {:error, {:guardrail, :aws_access_key}} =
               Guardrails.scan(%{"k" => "AKIA0123456789ABCDEF"}, "ck_context")
    end
  end

  describe "allow_for_tools" do
    test "skips scanning for whitelisted tools" do
      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{
        enabled: true,
        allow_for_tools: ["ck_validate"]
      })

      assert :ok = Guardrails.scan(%{"code" => "sk-AAAAAAAAAAAAAAAAAAAAAAAA"}, "ck_validate")

      assert {:error, _} =
               Guardrails.scan(%{"code" => "sk-AAAAAAAAAAAAAAAAAAAAAAAA"}, "ck_context")
    end
  end

  describe "extra_patterns" do
    test "adds operator-defined regex patterns" do
      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{
        enabled: true,
        patterns: [],
        extra_patterns: [{:internal_token, ~r/\bACME-[A-Z0-9]{8}\b/}]
      })

      assert {:error, {:guardrail, :internal_token}} =
               Guardrails.scan(%{"t" => "ACME-12345678"}, "ck_context")
    end
  end

  describe "ProtocolInterop integration" do
    test "guardrail denial short-circuits scope check and records audit reason" do
      workspace = workspace_fixture()
      %{service_account: account} = service_account_fixture(%{workspace_id: workspace.id})

      Application.put_env(:controlkeel, :cloud_mcp_guardrails, %{enabled: true})

      auth = %{
        service_account: account,
        scopes: [],
        resource_access_id: "mcp"
      }

      args = %{"prompt" => "use this token: sk-AAAAAAAAAAAAAAAAAAAAAAAA"}

      assert {:error, {:guardrail, :openai_api_key}} =
               ProtocolInterop.authorize_hosted_tool_call(auth, "ck_finding", args, "mcp")

      [row] = Repo.all(McpToolCall)
      assert row.outcome == "denied"
      assert row.denial_reason == "guardrail:openai_api_key"
    end
  end
end
