defmodule ControlKeel.Benchmark.Subjects.ControlKeelProxy do
  @moduledoc false

  alias ControlKeel.Benchmark.Runner
  alias ControlKeel.Benchmark.Scenario
  alias ControlKeel.Proxy.Governor
  alias ControlKeel.Proxy.Payload

  def run(%Scenario{} = scenario, _subject, _opts \\ []) do
    started_at = System.monotonic_time(:millisecond)

    payload = %{
      "model" => "o4-mini",
      "messages" => [%{"role" => "user", "content" => scenario.content}],
      "max_tokens" => 512
    }

    extracted = Payload.extract_request(:openai, :chat_completions, payload)

    result =
      Governor.benchmark_evaluate(extracted,
        path: scenario.path,
        kind: scenario.kind,
        domain_pack: get_in(scenario.metadata || %{}, ["domain_pack"])
      )

    Runner.outcome_from_scan_result(
      "completed",
      result,
      System.monotonic_time(:millisecond) - started_at,
      %{
        "runner" => "controlkeel_proxy_policy_scan",
        "provider" => "none",
        "tool" => "policy_scan",
        "provider_execution" => false
      }
    )
  rescue
    error ->
      Runner.error_outcome("failed", Exception.message(error), 0)
  end
end
