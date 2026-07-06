defmodule ControlKeel.ProviderBroker.FallbackChain do
  @moduledoc """
  Cost-ordered provider fallback chain.

  When the selected provider's session budget is exhausted, `select/4`
  walks the chain and returns the first provider that has headroom for the
  estimated cost. The chain is intersected with providers that have an active
  resolution (configured API key, local Ollama, agent bridge, etc.) so only
  reachable providers are considered.

  Default order (most to least expensive): anthropic → openai → openrouter → ollama

  Operators override the order by adding `"fallback_chain": [...]` to
  `~/.controlkeel/config.json`.
  """

  alias ControlKeel.Budget
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProviderBroker.Config

  @default_chain ~w(anthropic openai openrouter ollama)

  @doc """
  Returns the cost-ordered list of provider ids available for the given
  project root. Intersects the configured order with providers that have
  an active resolution.
  """
  @spec build(String.t(), keyword()) :: [String.t()]
  def build(project_root \\ File.cwd!(), opts \\ []) do
    configured = configured_chain()

    available =
      project_root
      |> ProviderBroker.resolution_chain(opts)
      |> Enum.map(& &1.provider)
      |> MapSet.new()

    Enum.filter(configured, &MapSet.member?(available, &1))
  end

  @doc """
  Returns the first provider in the fallback chain that has budget headroom
  for `estimated_cost_cents` in the given session, excluding
  `exclude_provider` (the one that already blocked).

  Returns `nil` when no provider has headroom or the chain is empty.
  """
  @spec select(String.t() | nil, String.t() | nil, non_neg_integer(), String.t() | nil, keyword()) ::
          String.t() | nil
  def select(project_root, session_id, estimated_cost_cents, exclude_provider \\ nil, opts \\ []) do
    root = project_root || File.cwd!()

    root
    |> build(opts)
    |> Enum.reject(&(&1 == exclude_provider))
    |> Enum.find(fn provider ->
      Budget.provider_has_headroom?(session_id, provider, estimated_cost_cents)
    end)
  end

  defp configured_chain do
    case Config.read() do
      {:ok, %{"fallback_chain" => chain}} when is_list(chain) and chain != [] -> chain
      _ -> @default_chain
    end
  end
end
