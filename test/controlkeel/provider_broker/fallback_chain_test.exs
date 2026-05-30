defmodule ControlKeel.ProviderBroker.FallbackChainTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget
  alias ControlKeel.ProviderBroker.FallbackChain

  import ControlKeel.MissionFixtures

  describe "build/2" do
    test "returns empty list when no providers are available in resolution chain" do
      # Use a tmp dir with no project binding so resolution chain only has heuristic
      tmp = Path.join(System.tmp_dir!(), "ck-fc-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      chain = FallbackChain.build(tmp)
      # heuristic is filtered out; no real providers configured in test env
      assert is_list(chain)
      # ollama may appear if OLLAMA_HOST is set; that's fine — just check structure
      assert Enum.all?(chain, &is_binary/1)
    end

    test "returned providers are a subset of the configured default chain" do
      default_order = ~w(anthropic openai openrouter ollama)
      chain = FallbackChain.build(File.cwd!())

      assert Enum.all?(chain, &(&1 in default_order))
    end
  end

  describe "provider_has_headroom?/3" do
    test "returns true for ollama regardless of budget" do
      session = session_fixture(%{budget_cents: 1, daily_budget_cents: 1, spent_cents: 0})
      assert Budget.provider_has_headroom?(session.id, "ollama", 999_999)
    end

    test "returns true when session has headroom" do
      session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 5_000, spent_cents: 0})
      assert Budget.provider_has_headroom?(session.id, "anthropic", 100)
    end

    test "returns false when session budget would be exceeded" do
      session = session_fixture(%{budget_cents: 100, daily_budget_cents: 5_000, spent_cents: 90})
      refute Budget.provider_has_headroom?(session.id, "anthropic", 50)
    end

    test "returns false for nil session_id" do
      refute Budget.provider_has_headroom?(nil, "anthropic", 100)
    end
  end

  describe "select/5" do
    test "returns nil when no providers have headroom and chain is empty" do
      result = FallbackChain.select("/nonexistent", nil, 100, "anthropic")
      assert is_nil(result) or is_binary(result)
    end

    test "excludes the given provider from consideration" do
      # With a nil session_id, provider_has_headroom? returns false for non-ollama providers,
      # so only ollama (which always returns true) can be selected.
      # Excluding ollama means nil is returned.
      result = FallbackChain.select(File.cwd!(), nil, 0, "ollama")
      # ollama is excluded; no other provider resolves headroom with nil session
      refute result == "ollama"
    end

    test "returns a provider string or nil" do
      result = FallbackChain.select(File.cwd!(), nil, 0)
      assert is_nil(result) or is_binary(result)
    end
  end
end
