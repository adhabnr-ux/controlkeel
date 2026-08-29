defmodule ControlKeel.Cloud.EvalRunner do
  @moduledoc """
  Runs eval suites that re-validate fixture inputs against the live `ck_validate`
  pipeline and asserts the same set of findings still fire.

  Closes the gap identified in the May 2026 competitive research:
  Braintrust / Langfuse / Laminar all ship eval-driven CI; ControlKeel has the
  benchmark/trace surfaces locally but no team-level regression gate. This
  module is that gate.

  ## Suite shape

  Each suite is a map:

      %{
        slug: "governance-regression",
        title: "Governance regression",
        description: "...",
        cases: [
          %{
            name: "rm -rf scope",
            content: "rm -rf /",
            kind: "shell",
            path: "/tmp/example.sh",
            expected_rule_ids: ["destructive.rm_rf_root"],
            expected_decisions: ["block"]
          },
          ...
        ]
      }

  ## CI integration

  `controlkeel eval run --suite governance-regression` exits 0 on pass, non-zero
  on regression. CI pipelines can call it as-is.
  """

  alias ControlKeel.Scanner.FastPath

  @typedoc "Per-case outcome."
  @type case_outcome :: %{
          name: String.t(),
          status: :pass | :fail,
          missing_rule_ids: [String.t()],
          unexpected_block_rule_ids: [String.t()],
          actual_rule_ids: [String.t()],
          decision: String.t() | nil
        }

  @typedoc "Result of running a suite."
  @type suite_result :: %{
          slug: String.t(),
          title: String.t(),
          total: non_neg_integer(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          cases: [case_outcome()]
        }

  @builtin_suites %{
    "governance-regression" => %{
      slug: "governance-regression",
      title: "Governance regression",
      description:
        "Re-runs ck_validate against held-out fixtures; CI blocks on any change in finding rule_ids or decisions.",
      cases: [
        %{
          name: "rm -rf at root scope",
          content: "rm -rf /",
          kind: "shell",
          path: "/tmp/sample-rm-rf.sh",
          expected_rule_ids: ["destructive.shell.rm_rf_repo_scope"],
          expected_decisions: ["block"]
        },
        %{
          name: "aws access key leak",
          content: "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
          kind: "config",
          path: "/tmp/sample-aws.env",
          expected_rule_ids: ["secret.aws_access_key"],
          expected_decisions: ["block"]
        },
        %{
          name: "clean shell command",
          content: "ls -la",
          kind: "shell",
          path: "/tmp/clean.sh",
          expected_rule_ids: [],
          expected_decisions: ["allow"]
        }
      ]
    }
  }

  @doc "List available built-in suites."
  @spec list_suites() :: [
          %{
            slug: String.t(),
            title: String.t(),
            description: String.t(),
            case_count: non_neg_integer()
          }
        ]
  def list_suites do
    @builtin_suites
    |> Map.values()
    |> Enum.map(fn s ->
      %{
        slug: s.slug,
        title: s.title,
        description: s.description,
        case_count: length(s.cases)
      }
    end)
    |> Enum.sort_by(& &1.slug)
  end

  @doc "Look up a built-in suite by slug, or return `:not_found`."
  @spec get_suite(String.t()) :: {:ok, map()} | :not_found
  def get_suite(slug) when is_binary(slug) do
    case Map.get(@builtin_suites, slug) do
      nil -> :not_found
      suite -> {:ok, suite}
    end
  end

  @doc """
  Run a built-in suite by slug. Returns `{:ok, result}` on found suite (whether
  cases passed or failed) and `:not_found` for unknown slug. Inspect
  `result.failed` for CI gating: zero means clean.
  """
  @spec run(String.t()) :: {:ok, suite_result()} | :not_found
  def run(slug) when is_binary(slug) do
    case get_suite(slug) do
      :not_found -> :not_found
      {:ok, suite} -> {:ok, run_suite(suite)}
    end
  end

  defp run_suite(%{slug: slug, title: title, cases: cases}) do
    outcomes = Enum.map(cases, &run_case/1)

    %{
      slug: slug,
      title: title,
      total: length(outcomes),
      passed: Enum.count(outcomes, &(&1.status == :pass)),
      failed: Enum.count(outcomes, &(&1.status == :fail)),
      cases: outcomes
    }
  end

  defp run_case(%{name: name, content: content} = c) do
    input = %{
      "content" => content,
      "path" => Map.get(c, :path) || "/tmp/eval-case",
      "kind" => Map.get(c, :kind, "code")
    }

    result = FastPath.scan(input)
    actual_rule_ids = result.findings |> MapSet.new(& &1.rule_id) |> Enum.sort()
    expected_rule_ids = Map.get(c, :expected_rule_ids, []) |> Enum.sort()
    expected_decisions = Map.get(c, :expected_decisions, []) |> MapSet.new()

    missing = expected_rule_ids -- actual_rule_ids

    unexpected_block =
      if "block" in expected_decisions do
        []
      else
        result.findings
        |> Enum.filter(&(&1.decision == "block"))
        |> Enum.map(& &1.rule_id)
        |> Enum.uniq()
      end

    decision_ok =
      expected_decisions == MapSet.new() or MapSet.member?(expected_decisions, result.decision)

    status =
      cond do
        missing != [] -> :fail
        unexpected_block != [] -> :fail
        not decision_ok -> :fail
        true -> :pass
      end

    %{
      name: name,
      status: status,
      missing_rule_ids: missing,
      unexpected_block_rule_ids: unexpected_block,
      actual_rule_ids: actual_rule_ids,
      decision: result.decision
    }
  end
end
