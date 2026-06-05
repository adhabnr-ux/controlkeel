#!/usr/bin/env bash
# ControlKeel agent-host benchmark wrapper.
#
# Usage: scripts/benchmark-host.sh <host>
#
#   Supported hosts:
#     opencode | opencode-pure | opencode-ck-bounded
#     claude   | claude-pure   | claude-ck-bounded
#
# Reproducibility contract (so external parties can compare like-for-like):
#   * <host>-pure        : the agent runs with NO ControlKeel available (no MCP,
#                          no plugin, no project governance) — the honest
#                          "without CK" arm of a with-vs-without comparison.
#   * <host>-ck-bounded  : the same agent and model, ControlKeel MCP available,
#                          prompted to call CK context + validation exactly once
#                          and then finalize. This bounds the governance cost so
#                          the efficiency delta is meaningful.
#   * <host> (bare name) : the agent in its default local configuration.
#
# Always pin and record host version, model, CK version, prompt version, and
# policy version next to any published numbers. Token / cost / tool-call
# telemetry below is best-effort parsing of each host's JSON output; verify it
# against the installed host version before quoting model-backed numbers.
#
# Required env:
#   CONTROLKEEL_BENCHMARK_PROMPT_FILE   prompt text for the scenario
#   CONTROLKEEL_BENCHMARK_SCENARIO_FILE scenario JSON (slug + artifact path)
#   CONTROLKEEL_BENCHMARK_OUTPUT_DIR    where to write the artifact + telemetry
# Optional env:
#   OPENCODE_BENCHMARK_MODEL  default: openai/gpt-5.5
#   CLAUDE_BENCHMARK_MODEL    default: claude-sonnet-4-6
set -euo pipefail

host="${1:-opencode}"
prompt_file="${CONTROLKEEL_BENCHMARK_PROMPT_FILE:?CONTROLKEEL_BENCHMARK_PROMPT_FILE is required}"
scenario_file="${CONTROLKEEL_BENCHMARK_SCENARIO_FILE:?CONTROLKEEL_BENCHMARK_SCENARIO_FILE is required}"
output_dir="${CONTROLKEEL_BENCHMARK_OUTPUT_DIR:?CONTROLKEEL_BENCHMARK_OUTPUT_DIR is required}"

mkdir -p "${output_dir}"
events_file="${output_dir}/host-events.jsonl"

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

started_ms=$(now_ms)

scenario_slug=$(python3 - "${scenario_file}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("slug", "scenario"))
PY
)

scenario_path=$(python3 - "${scenario_file}" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("path") or "artifact.txt")
PY
)

artifact_path="${output_dir}/${scenario_path}"
mkdir -p "$(dirname "${artifact_path}")"

artifact_preamble="Benchmark mode: produce only the final artifact text for the requested scenario. Do not edit files, do not run shell commands, do not ask follow-up questions, and do not include explanatory prose outside the artifact."
ck_bounded_preamble="Use ControlKeel at most once before finalizing: call ck_context if available, call ck_validate on the final artifact if available, then write only the final artifact. Do not keep iterating after one validation pass."

base_prompt="${artifact_preamble}

$(cat "${prompt_file}")"

case "${host}" in
  opencode|opencode-pure|opencode-ck-bounded)
    if ! command -v opencode >/dev/null 2>&1; then
      echo "opencode is not installed" >&2
      exit 127
    fi

    model="${OPENCODE_BENCHMARK_MODEL:-openai/gpt-5.5}"
    prompt="${base_prompt}"

    if [ "${host}" = "opencode-ck-bounded" ]; then
      prompt="${ck_bounded_preamble}

${prompt}"
    fi

    run_args=(run --model "${model}" --format json --title "ck-benchmark-${scenario_slug}")

    if [ "${host}" = "opencode-pure" ]; then
      run_args+=(--pure)
    fi

    set +e
    raw_output=$(opencode "${run_args[@]}" "${prompt}" 2>&1)
    status=$?
    set -e

    printf '%s\n' "${raw_output}" > "${events_file}"

    # OpenCode emits JSON events; collect every text-bearing field as the artifact.
    python3 - "${events_file}" "${artifact_path}" <<'PY'
import json, sys
events_path, artifact_path = sys.argv[1:3]
texts = []

def collect_text(obj):
    if isinstance(obj, dict):
        if obj.get("type") == "text" and isinstance(obj.get("text"), str):
            texts.append(obj["text"])
        for key in ("text", "content", "message", "output"):
            value = obj.get(key)
            if isinstance(value, str):
                texts.append(value)
        for value in obj.values():
            collect_text(value)
    elif isinstance(obj, list):
        for item in obj:
            collect_text(item)

with open(events_path, errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except Exception:
            continue
        collect_text(event)
with open(artifact_path, "w") as out:
    out.write("\n".join(dict.fromkeys(texts)).strip())
PY
    ;;

  claude|claude-pure|claude-ck-bounded)
    if ! command -v claude >/dev/null 2>&1; then
      echo "claude is not installed" >&2
      exit 127
    fi

    model="${CLAUDE_BENCHMARK_MODEL:-claude-sonnet-4-6}"
    prompt="${base_prompt}"

    run_args=(--print --model "${model}" --output-format json --permission-mode bypassPermissions)

    case "${host}" in
      claude-pure)
        # Honest "without ControlKeel" arm: disable all MCP servers (no ck_*
        # tools) and skip project/local settings that could attach governance.
        run_args+=(--strict-mcp-config --mcp-config '{}' --setting-sources user)
        ;;
      claude-ck-bounded)
        # Relies on the project's configured ControlKeel MCP server being present.
        prompt="${ck_bounded_preamble}

${prompt}"
        ;;
    esac

    set +e
    raw_output=$(claude "${run_args[@]}" "${prompt}" 2>&1)
    status=$?
    set -e

    printf '%s\n' "${raw_output}" > "${events_file}"

    # Claude --output-format json returns a single result object; the final
    # artifact is in ".result". Fall back to recursive text collection for
    # stream-json or error shapes.
    python3 - "${events_file}" "${artifact_path}" <<'PY'
import json, sys
events_path, artifact_path = sys.argv[1:3]
text = ""

def collect_text(obj, acc):
    if isinstance(obj, dict):
        for key in ("result", "text", "content", "message", "output"):
            value = obj.get(key)
            if isinstance(value, str):
                acc.append(value)
        for value in obj.values():
            collect_text(value, acc)
    elif isinstance(obj, list):
        for item in obj:
            collect_text(item, acc)

with open(events_path, errors="replace") as f:
    raw = f.read()

try:
    data = json.loads(raw)
    if isinstance(data, dict) and isinstance(data.get("result"), str):
        text = data["result"]
    else:
        acc = []
        collect_text(data, acc)
        text = "\n".join(dict.fromkeys(acc))
except Exception:
    acc = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            collect_text(json.loads(line), acc)
        except Exception:
            continue
    text = "\n".join(dict.fromkeys(acc))

with open(artifact_path, "w") as out:
    out.write(text.strip())
PY
    ;;

  *)
    echo "Unsupported benchmark host: ${host}" >&2
    echo "Supported hosts: opencode, opencode-pure, opencode-ck-bounded, claude, claude-pure, claude-ck-bounded" >&2
    exit 64
    ;;
esac

finished_ms=$(now_ms)
duration_ms=$((finished_ms - started_ms))

# Shared best-effort telemetry extractor. Walks the host JSON output and sums
# token counts, cost, and tool-call names (flagging ck_* / ControlKeel calls).
python3 - "${events_file}" "${output_dir}" "${host}" "${model:-}" "${duration_ms}" <<'PY'
import json, re, sys
events_path, output_dir, host, model, duration_ms = sys.argv[1:6]
input_tokens = output_tokens = total_tokens = cost_cents = 0
tool_calls = []
ck_tool_calls = []

token_keys = {
    "input": ("input_tokens", "prompt_tokens", "cache_read_input_tokens"),
    "output": ("output_tokens", "completion_tokens"),
    "total": ("total_tokens",),
    "cost_cents": ("cost_cents", "estimated_cost_cents"),
    "cost_usd": ("total_cost_usd", "cost_usd", "estimated_cost_usd", "total_cost", "cost"),
}

def add_numbers(obj):
    global input_tokens, output_tokens, total_tokens, cost_cents
    if not isinstance(obj, dict):
        return
    lower = {str(k).lower(): v for k, v in obj.items()}
    tokens = lower.get("tokens")
    if isinstance(tokens, dict):
        token_lower = {str(k).lower(): v for k, v in tokens.items()}
        if isinstance(token_lower.get("input"), (int, float)):
            input_tokens += token_lower["input"]
        if isinstance(token_lower.get("output"), (int, float)):
            output_tokens += token_lower["output"]
        if isinstance(token_lower.get("total"), (int, float)):
            total_tokens += token_lower["total"]
    for key in token_keys["input"]:
        if isinstance(lower.get(key), (int, float)):
            input_tokens += lower[key]
    for key in token_keys["output"]:
        if isinstance(lower.get(key), (int, float)):
            output_tokens += lower[key]
    for key in token_keys["total"]:
        if isinstance(lower.get(key), (int, float)):
            total_tokens += lower[key]
    for key in token_keys["cost_cents"]:
        if isinstance(lower.get(key), (int, float)):
            cost_cents += lower[key]
    for key in token_keys["cost_usd"]:
        if isinstance(lower.get(key), (int, float)):
            cost_cents += lower[key] * 100
    name = lower.get("tool") or lower.get("tool_name") or lower.get("name")
    if isinstance(name, str):
        tool_calls.append(name)
        if name.startswith("ck_") or "controlkeel" in name.lower():
            ck_tool_calls.append(name)
    for value in obj.values():
        if isinstance(value, dict):
            add_numbers(value)
        elif isinstance(value, list):
            for item in value:
                add_numbers(item)

try:
    with open(events_path, errors="replace") as f:
        raw = f.read()
    parsed_whole = False
    try:
        add_numbers(json.loads(raw))
        parsed_whole = True
    except Exception:
        parsed_whole = False
    if not parsed_whole:
        for line in raw.splitlines():
            try:
                add_numbers(json.loads(line))
            except Exception:
                text = line.lower()
                for label, attr in (("input", "input_tokens"), ("output", "output_tokens"), ("total", "total_tokens")):
                    m = re.search(label + r"[^0-9]{0,20}([0-9]+)", text)
                    if m:
                        if attr == "input_tokens": input_tokens += int(m.group(1))
                        if attr == "output_tokens": output_tokens += int(m.group(1))
                        if attr == "total_tokens": total_tokens += int(m.group(1))
except FileNotFoundError:
    pass

if not total_tokens:
    total_tokens = input_tokens + output_tokens

metrics = {
    "host": host,
    "model": model,
    "duration_ms": int(duration_ms),
    "input_tokens": int(input_tokens),
    "output_tokens": int(output_tokens),
    "total_tokens": int(total_tokens),
    "cost_cents": cost_cents,
    "tool_calls": sorted(set(tool_calls)),
    "ck_tool_calls": sorted(set(ck_tool_calls)),
    "tool_call_count": len(set(tool_calls)),
    "ck_tool_call_count": len(set(ck_tool_calls)),
    "metrics_source": f"{host}_json_events_best_effort",
}

with open(f"{output_dir}/.controlkeel_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)
PY

exit "${status:-0}"
