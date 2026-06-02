defmodule ControlKeel.Skills.ClaudeHooks do
  @moduledoc false

  def write_hooks(root) do
    hooks_dir = Path.join(root, ".claude/hooks")
    File.mkdir_p!(hooks_dir)

    hooks = [
      {"config-change.sh", config_change_hook()},
      {"permission-request.sh", permission_request_hook()},
      {"post-compact.sh", post_compact_hook()},
      {"post-tool-use-bash.sh", post_tool_use_bash_hook()},
      {"pre-tool-use-bash.sh", pre_tool_use_bash_hook()},
      {"pre-tool-use-write.sh", pre_tool_use_write_hook()},
      {"session-start.sh", session_start_hook()},
      {"stop.sh", stop_hook()},
      {"subagent-start.sh", subagent_start_hook()},
      {"user-prompt-submit.sh", user_prompt_submit_hook()}
    ]

    paths =
      for {filename, content} <- hooks do
        path = Path.join(hooks_dir, filename)
        File.write!(path, content)
        File.chmod!(path, 0o755)
        %{"path" => path, "kind" => "hook"}
      end

    paths
  end

  defp config_change_hook do
    """
    #!/usr/bin/env sh
    printf '{"systemMessage":"Configuration changed. Governance constraints and hooks may have been updated. Call ck_context to refresh your governance state if needed."}'
    """
  end

  defp permission_request_hook do
    """
    #!/usr/bin/env sh
    controlkeel review plan submit --stdin --submitted-by claude-code
    """
  end

  defp post_compact_hook do
    """
    #!/usr/bin/env sh
    printf '{"systemMessage":"Context was compacted. You are in a ControlKeel-governed session: always call ck_context before proceeding, ck_validate before code or shell changes, and ck_finding for any issues you discover."}'
    """
  end

  defp post_tool_use_bash_hook do
    """
    #!/usr/bin/env sh
    TOOL_INPUT=$(cat)
    FAILED=$(printf '%s' "$TOOL_INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("tool_response",{}); ec=r.get("exitCode",r.get("exit_code",0)); st=str(r.get("status","")).lower(); print("true" if (isinstance(ec,(int,float)) and int(ec)!=0) or st in ("failed","error") else "false")' 2>/dev/null || echo "false")
    [ "$FAILED" != "true" ] && exit 0
    CMD=$(printf '%s' "$TOOL_INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")
    printf '%s' "$CMD" | grep -qiE '(mix[[:space:]]+test|npm[[:space:]]+test|pytest|pnpm[[:space:]]+test|yarn[[:space:]]+test)' && printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Test run failed. Summarize failures clearly before moving on."}}' || printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Shell command failed. Re-check the result and run ck_validate again if the next step changes code or config."}}'
    exit 0
    """
  end

  defp pre_tool_use_bash_hook do
    """
    #!/usr/bin/env sh
    TOOL_INPUT=$(cat)
    if command -v jq >/dev/null 2>&1; then
      CMD=$(printf '%s' "$TOOL_INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null)
    else
      CMD=$(printf '%s' "$TOOL_INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command") or d.get("command", ""))' 2>/dev/null || true)
    fi
    printf '%s' "$CMD" | grep -qiE '(deploy|fly |wrangler publish|mix release|docker push|heroku|git push origin)' && printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Deploy-like command detected. Confirm ck_validate and ck_review_submit were called this turn before proceeding."}}' || true
    """
  end

  defp pre_tool_use_write_hook do
    """
    #!/usr/bin/env sh
    fp=$(cat | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)
    [ -z "$fp" ] && exit 0
    printf '%s' "$fp" | grep -qiE '(\\.env$|credentials|secret|\\.pem$|\\.key$|id_rsa|passw)' && printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Writing to potentially sensitive file: %s. Verify ck_validate approved this change."}}\\n' "$fp" || true
    """
  end

  defp session_start_hook do
    """
    #!/usr/bin/env sh
    controlkeel context --json >/dev/null 2>&1 || true
    printf '{"systemMessage":"ControlKeel available. Start with ck_context to load mission state."}'
    """
  end

  defp stop_hook do
    """
    #!/usr/bin/env sh
    blocked=$(controlkeel context --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("active_findings",{}).get("blocked",0))' 2>/dev/null || echo 0)
    [ "$blocked" = "0" ] && exit 0
    printf '{"decision":"block","reason":"ControlKeel has blocked findings. Call ck_context, resolve them, then complete the turn."}'
    """
  end

  defp subagent_start_hook do
    """
    #!/usr/bin/env sh
    printf '{"systemMessage":"You are in a ControlKeel-governed session. Call ck_context before proceeding with any task, ck_validate before code or shell changes, and ck_finding for issues you discover."}'
    """
  end

  defp user_prompt_submit_hook do
    """
    #!/usr/bin/env sh
    input=$(cat)
    prompt=$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null || echo "")
    [ -z "$prompt" ] && exit 0
    printf '%s' "$prompt" | grep -qE '(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|PGP) PRIVATE KEY)' && printf '{"decision":"block","reason":"Potential secret in prompt. Remove credentials before continuing."}' && exit 0
    blocked=$(controlkeel context --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("active_findings",{}).get("blocked",0))' 2>/dev/null || echo 0)
    [ "${blocked:-0}" != "0" ] && [ "${blocked:-0}" != "" ] && printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"WARNING: %s blocked finding(s) active. Call ck_context and resolve them before proceeding."}}' "$blocked" || true
    """
  end
end
