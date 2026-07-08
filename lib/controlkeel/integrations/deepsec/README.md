# Deepsec Integration for ControlKeel

This directory contains the live ControlKeel integration with deepsec. Keep it limited to the scanner path that is actually wired into `ControlKeel.Scanner.FastPath`.

## Live modules

- `adapter.ex` converts deepsec findings into `ControlKeel.Scanner.Finding` structs.
- `cli.ex` wraps the installed deepsec CLI for init/scan/process/export. Output parsing lives in `ControlKeel.Validation.Matchers.Scanner`.
- `config.ex` reads the `:deepsec` configuration used by the scanner gate.
- `../deepsec.ex` is the budget/config gate used before invoking the CLI scan.

`ControlKeel.Validation.Matchers.Scanner.deepsec_scan/1` is the production entrypoint for running a scan and returning CK findings. The fast-path scanner calls it only when Deepsec is enabled, the artifact is security/code-like, severity passes the configured threshold, and the session has enough budget remaining.

## Configuration

```elixir
config :controlkeel, :deepsec,
  enabled: true,
  use_for_security_domain: true,
  min_severity_for_investigation: :high,
  max_scan_budget_cents: 10_000,
  workspace_path: ".deepsec"

config :controlkeel, :matcher_system, enabled: true
```

> The matcher subsystem (Layer 3) additionally requires its Registry process to be
> running and the built-in matchers loaded. Start and seed it before enabling the flag:
>
> ```elixir
> {:ok, _} = ControlKeel.Validation.Matchers.Registry.start_link()
> :ok = ControlKeel.Validation.Matchers.Registry.load_built_ins()
> ```
>
> If the flag is enabled without a running Registry, the scanner safely skips Layer 3
> (it no longer crashes), so no matcher findings are produced until the Registry is up.

## API

```elixir
{:ok, should_trigger} =
  ControlKeel.Integrations.Deepsec.should_trigger_deepsec?(session_id, :high)
```

```elixir
alias ControlKeel.Validation.Matchers.Scanner

{:ok, findings} =
  Scanner.deepsec_scan(
    workspace_path: "/path/to/workspace",
    session_id: 123,
    task_id: "task-abc",
    export_format: :json
  )
```

## Finding mapping

| Deepsec Field | CK Finding Field | Notes |
|---------------|------------------|-------|
| `vulnSlug` | `rule_id` | Prefixed with `deepsec.` |
| `severity` | `severity` | Mapped to CK severity levels |
| `title` | `plain_message` | Combined with description and recommendation |
| `filePath` | `location.path` | Finding path |
| `cweIds` | `metadata.cwe_ids` | CWE identifiers |
| `revalidation.verdict` | `decision` | `false-positive` maps to `allow`; otherwise `warn` |

## Environment

The CLI wrapper resolves `CONTROLKEEL_DEEPSEC_BIN`; when unset it defaults to the `deepsec` binary on PATH.
