# Deepsec Integration for ControlKeel

This directory contains the integration between ControlKeel and [deepsec](https://github.com/vercel-labs/deepsec), Vercel's agent-powered vulnerability scanner.

## Overview

The deepsec integration provides:

1. **Findings Adapter**: Converts deepsec findings to ControlKeel findings for unified governance
2. **Proof Bundle Integration**: Wraps deepsec scan results in CK proof bundles for durable evidence
3. **Configuration Management**: Centralized configuration for deepsec integration behavior
4. **Budget Controls**: Ensures expensive deepsec scans respect CK's budget system
5. **Matcher System**: Pattern-based validation with noise tiers for security scanning
6. **AI Investigation Hook**: Optional AI-powered security investigation for high-severity findings
7. **CLI Integration**: Direct execution of deepsec CLI commands for real security scanning (Phase 3)
8. **Scan Caching**: ETS-based cache for scan results to avoid re-scanning unchanged files (Phase 4)
9. **Incremental Scanning**: Only scan files that have changed since last scan (Phase 4)
10. **Custom Configuration**: JSON-based configuration files for customizing scan behavior (Phase 4)
11. **Streaming Support**: Real-time streaming of findings as they're discovered (Phase 4)
12. **Finding Deduplication**: Multiple strategies for deduplicating findings across scans (Phase 4)
13. **Priority Triage**: P0/P1/P2/P3 classification based on severity and exploitability (Phase 4)
14. **Performance Metrics**: Comprehensive metrics tracking for scan performance (Phase 4)
15. **Fast Path Integration**: Automatic integration with CK's Fast Path scanner (Phase 4)

## Architecture

```
lib/controlkeel/integrations/deepsec/
├── adapter.ex         # Converts deepsec findings to CK findings
├── proof_bundle.ex    # Creates CK proof bundles from deepsec scans
├── config.ex          # Configuration management
├── cli.ex             # CLI interface for deepsec commands (Phase 3)
├── deepsec.ex         # Main integration API
└── README.md          # This file

lib/controlkeel/validation/matchers/
├── matcher.ex                    # Matcher data structure
├── registry.ex                   # Matcher registry (GenServer)
├── scanner.ex                    # Content scanner (with CLI integration in Phase 3)
├── ai_investigation.ex           # AI investigation hook (uses CLI in Phase 3)
└── sample_security_matchers.ex   # Built-in security matchers
```

## Usage

### Basic Configuration

Add to your `config/config.exs`:

```elixir
config :controlkeel, :deepsec,
  enabled: true,
  use_for_security_domain: true,
  min_severity_for_investigation: :high,
  block_on_security_findings: false,
  max_scan_budget_cents: 10_000,  # $100
  workspace_path: ".deepsec",
  auto_create_proof_bundles: true,
  custom_matchers: [],
  matcher_system_enabled?: true,  # Phase 2: Enable matcher system
  ai_investigation_enabled?: false  # Phase 2: Enable AI investigation

config :controlkeel, :ai_investigation,
  enabled: true,
  min_severity: :high,
  max_investigation_budget_cents: 5_000  # $50 per investigation
```

### Processing Deepsec Findings

```elixir
import ControlKeel.Integrations.Deepsec

# Convert deepsec findings to CK findings
ck_findings = Deepsec.process_findings(deepsec_findings,
  session_id: session_id,
  task_id: task_id
)

# Process a complete scan with proof bundle
{:ok, result} = Deepsec.process_scan(deepsec_results, session_id, task_id)
# result.findings - List of CK findings
# result.proof_bundle - CK proof bundle (if enabled)
```

### Creating Proof Bundles

```elixir
import ControlKeel.Integrations.Deepsec

# Create a proof bundle from scan results
{:ok, proof_bundle} = Deepsec.create_proof_bundle(deepsec_results, session_id, task_id)

# Get security summary
summary = Deepsec.security_summary(proof_bundle)
# %{
#   total_findings: 42,
#   critical_count: 3,
#   high_count: 10,
#   medium_count: 20,
#   low_count: 9,
#   revalidated_count: 30,
#   false_positive_count: 5
# }
```

### Budget-Aware Triggering

```elixir
import ControlKeel.Integrations.Deepsec

# Check if deepsec should be triggered based on budget and configuration
{:ok, should_trigger} = Deepsec.should_trigger_deepsec?(session_id, :high)
```

### Using the Matcher System (Phase 2)

```elixir
# Start the matcher registry
start_supervised!(ControlKeel.Validation.Matchers.Registry)

# Load built-in security matchers
:ok = ControlKeel.Validation.Matchers.Registry.load_built_ins()

# Scan a file for security patterns
content = File.read!("app/models/user.ex")
findings = ControlKeel.Validation.Matchers.Scanner.scan(
  "app/models/user.ex",
  content,
  max_noise_tier: :normal
)

# Register a custom matcher
custom_matcher = ControlKeel.Validation.Matchers.Matcher.new(
  "custom-api-key",
  :precise,
  ["**/*.ex"],
  [~r/MY_API_KEY\s*[:=]\s*["']([a-zA-Z0-9]{20,})["']/],
  "Custom API key detection",
  category: "security",
  severity: "critical"
)

:ok = ControlKeel.Validation.Matchers.Registry.register(custom_matcher)
```

### Using AI Investigation (Phase 2)

```elixir
# Check if AI investigation should be triggered
{:ok, should_trigger} = ControlKeel.Validation.Matchers.AIInvestigation.should_trigger?(
  session_id,
  "security",
  :critical
)

if should_trigger do
  # Trigger investigation
  {:ok, result} = ControlKeel.Validation.Matchers.AIInvestigation.investigate(
    content,
    file_path,
    session_id,
    task_id,
    workspace_path: "/path/to/workspace"  # Phase 3: workspace path
  )

  # Process results
  {:ok, findings} = ControlKeel.Validation.Matchers.AIInvestigation.process_results(
    result,
    session_id,
    task_id
  )
end
```

### Using Deepsec CLI (Phase 3)

Phase 3 adds direct CLI integration for executing deepsec commands:

```elixir
alias ControlKeel.Integrations.Deepsec.CLI

# Check if deepsec CLI is available
if CLI.available?() do
  # Get version
  {:ok, version} = CLI.version()

  # Initialize workspace
  {:ok, _} = CLI.init(workspace_path: "/path/to/workspace")

  # Run scan (regex-based pattern matching)
  {:ok, scan_output} = CLI.scan(workspace_path: "/path/to/workspace")

  # Run AI investigation
  {:ok, process_output} = CLI.process(workspace_path: "/path/to/workspace")

  # Revalidate findings to reduce false positives
  {:ok, revalidate_output} = CLI.revalidate(workspace_path: "/path/to/workspace")

  # Export findings as JSON
  {:ok, export_output} = CLI.export(:json, workspace_path: "/path/to/workspace")

  # Or export as markdown
  {:ok, export_output} = CLI.export(:md_dir, workspace_path: "/path/to/workspace")
end

# Run complete workflow in one call
{:ok, results} = CLI.run_full_workflow(
  workspace_path: "/path/to/workspace",
  skip_revalidate: false,
  export_format: :json
)
```

### Scanner CLI Integration (Phase 3)

The scanner module now integrates with the deepsec CLI:

```elixir
alias ControlKeel.Validation.Matchers.Scanner

# Run deepsec scan and convert to CK findings
{:ok, findings} = Scanner.deepsec_scan(
  workspace_path: "/path/to/workspace",
  session_id: 123,
  task_id: "task-abc",
  export_format: :json
)

# Run full workflow including revalidation
{:ok, findings} = Scanner.deepsec_full_scan(
  workspace_path: "/path/to/workspace",
  skip_revalidate: true,  # Skip for faster results
  session_id: 123,
  task_id: "task-abc"
)
```

### Parsing CLI Output (Phase 3)

The CLI module provides utilities for parsing deepsec output:

```elixir
alias ControlKeel.Integrations.Deepsec.CLI

# Parse JSON output from deepsec commands
{:ok, data} = CLI.parse_json_output(raw_output)

# Extract findings from output (with fallback to text extraction)
{:ok, findings} = CLI.extract_findings(raw_output)
```

### Using Scan Caching (Phase 4)

Phase 4 adds ETS-based caching for scan results:

```elixir
alias ControlKeel.Integrations.Deepsec.Cache

# Start the cache server
start_supervised!(Cache)

# Cache a scan result
Cache.put("lib/app.ex", "/workspace", %{file_hash: "abc123", findings: [...]})

# Check if file has changed
changed = Cache.file_changed?("lib/app.ex", "/workspace")

# Get cached result
case Cache.get("lib/app.ex", "/workspace") do
  {:hit, result} -> # Use cached result
  :miss -> # Run new scan
end

# Get cache statistics
stats = Cache.stats()
# %{size: 100, memory_bytes: 102400, memory_mb: 0.1}
```

### Using Incremental Scanning (Phase 4)

Only scan files that have changed since the last scan:

```elixir
alias ControlKeel.Integrations.Deepsec.Incremental

# Perform incremental scan
{:ok, results} = Incremental.incremental_scan(
  "/workspace",
  file_patterns: ["**/*.{ex,exs}"],
  ignore_patterns: ["node_modules/**", "_build/**"]
)

# Force full scan
{:ok, results} = Incremental.incremental_scan(
  "/workspace",
  force: true
)
```

### Using Custom Configuration (Phase 4)

Load custom deepsec configuration from JSON files:

```elixir
alias ControlKeel.Integrations.Deepsec.CustomConfig

# Load custom configuration
{:ok, config} = CustomConfig.load_config("deepsec.config.json", "/workspace")

# Apply configuration to workspace
:ok = CustomConfig.apply_config(config, "/workspace")

# Create sample configuration
{:ok, path} = CustomConfig.create_sample_config("sample.config.json")
```

### Using Streaming (Phase 4)

Stream findings in real-time as they're discovered:

```elixir
alias ControlKeel.Integrations.Deepsec.Stream

# Start the stream server
start_supervised!(Stream)

# Subscribe to finding stream
session_id = "session-123"
Stream.subscribe(session_id)

# Stream findings to a callback
Stream.stream_scan(
  fn finding ->
    IO.puts("New finding: #{inspect(finding)}")
  end,
  "/workspace"
)
```

### Using Deduplication (Phase 4)

Remove duplicate findings across scans:

```elixir
alias ControlKeel.Integrations.Deepsec.Dedup

# Exact deduplication
deduplicated = Dedup.deduplicate_findings(findings, strategy: :exact)

# Similarity-based deduplication
deduplicated = Dedup.deduplicate_findings(
  findings,
  strategy: :similar,
  similarity_threshold: 0.8
)

# Deduplicate across scans
{:ok, deduplicated, new_count} = Dedup.deduplicate_across_scans(
  new_findings,
  previous_findings
)
```

### Using Priority Triage (Phase 4)

Classify findings by priority (P0/P1/P2/P3):

```elixir
alias ControlKeel.Integrations.Deepsec.Triage

# Classify a finding
priority = Triage.classify_priority(%{"severity" => "critical"})
# Returns :p0, :p1, :p2, or :p3

# Classify multiple findings
classified = Triage.classify_findings(findings)
# %{p0: [...], p1: [...], p2: [...], p3: [...]}

# Get priority summary
summary = Triage.priority_summary(findings)
# %{p0: 5, p1: 10, p2: 20, p3: 50, total: 85}

# Check if should block
should_block = Triage.should_block?(finding)
# P0 findings block by default
```

### Using Performance Metrics (Phase 4)

Track scan performance metrics:

```elixir
alias ControlKeel.Integrations.Deepsec.Metrics

# Start the metrics server
start_supervised!(Metrics)

# Track execution with automatic timing
{:ok, result, duration_ms} = Metrics.track_execution(
  "session-123",
  "scan",
  fn -> perform_scan() end
)

# Get metrics for a session
{:ok, metrics} = Metrics.get_metrics("session-123")

# Get aggregated metrics
aggregated = Metrics.get_aggregated_metrics()
# %{total_scans: 10, total_duration_ms: 50000, avg_duration_ms: 5000, ...}
```

## Finding Mapping

The adapter maps deepsec findings to CK findings as follows:

| Deepsec Field | CK Finding Field | Notes |
|---------------|------------------|-------|
| vulnSlug | rule_id | Prefixed with "deepsec." |
| severity | severity | Mapped to CK severity levels |
| title | plain_message | Combined with description and recommendation |
| filePath | location.path | File path of the finding |
| cweIds | metadata.cwe_ids | CWE identifiers |
| revalidation.verdict | decision | "false-positive" → "allow", others → "warn" |
| description | metadata.description | Detailed description |
| recommendation | metadata.recommendation | Fix recommendation |

### Severity Mapping

| Deepsec | ControlKeel |
|---------|-------------|
| LOW | low |
| MEDIUM | medium |
| HIGH | high |
| CRITICAL | critical |

## Security Workflow Integration

When `use_for_security_domain` is enabled, deepsec can be integrated into CK's security workflow:

1. **Discovery Phase**: deepsec scans identify potential vulnerabilities
2. **Triage Phase**: Findings are converted to CK findings with proper metadata
3. **Validation Phase**: Proof bundles capture scan evidence
4. **Disclosure Phase**: Security summaries provide disclosure-ready data

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| enabled | boolean | false | Whether deepsec integration is enabled |
| use_for_security_domain | boolean | false | Use deepsec for security domain validation |
| min_severity_for_investigation | atom | :high | Minimum severity to trigger investigation |
| block_on_security_findings | boolean | false | Block on security findings (vs warn) |
| max_scan_budget_cents | integer | 10000 | Maximum budget for scans (in cents) |
| workspace_path | string | ".deepsec" | Path to deepsec workspace |
| auto_create_proof_bundles | boolean | true | Auto-create proof bundles for scans |
| custom_matchers | list | [] | Custom matcher configurations |
| matcher_system_enabled? | boolean | false | Enable matcher system in FastPath (Phase 2) |
| ai_investigation_enabled? | boolean | false | Enable AI investigation (Phase 2) |

### AI Investigation Configuration (Phase 2)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| enabled | boolean | false | Whether AI investigation is enabled |
| min_severity | atom | :high | Minimum severity to trigger AI investigation |
| max_investigation_budget_cents | integer | 5000 | Maximum budget per investigation (in cents) |

### Cache Configuration (Phase 4)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| ttl_hours | integer | 24 | Cache time-to-live in hours |

## Integration with Validation

The matcher system (Phase 2) is integrated with CK's FastPath validation. When `matcher_system_enabled?` is true:

1. The matcher registry is initialized with built-in security matchers
2. Files are scanned using registered matchers
3. Findings are returned with noise tier information
4. AI investigation can be triggered for high-severity findings

## Future Enhancements

Potential future improvements:

- **Distributed Caching** - Share cache across multiple nodes
- **Real-time File Watching** - Use file system events for instant change detection
- **Advanced Deduplication** - Machine learning-based similarity detection
- **Custom Priority Rules** - User-defined priority classification rules
- **Metrics Export** - Export metrics to external monitoring systems
- **Streaming to External Systems** - Stream findings to webhooks or queues
- **Configuration Templates** - Pre-built configuration templates for different languages/frameworks

## Testing

To test the integration:

```elixir
# Test configuration
:ok = ControlKeel.Integrations.Deepsec.validate_config()

# Test findings conversion
sample_finding = %{
  "vulnSlug" => "sql-injection",
  "severity" => "HIGH",
  "title" => "SQL Injection Vulnerability",
  "description" => "User input not sanitized",
  "filePath" => "app/models/user.ex"
}

ck_finding = ControlKeel.Integrations.Deepsec.Adapter.to_ck_finding(sample_finding)

# Test CLI availability (Phase 3)
if ControlKeel.Integrations.Deepsec.CLI.available?() do
  {:ok, version} = ControlKeel.Integrations.Deepsec.CLI.version()
end

# Test JSON parsing (Phase 3)
json_output = ~s({"findings": [{"vulnSlug": "test", "severity": "HIGH"}]})
{:ok, data} = ControlKeel.Integrations.Deepsec.CLI.parse_json_output(json_output)
```

### Test Coverage

- **Phase 1**: Adapter, config, proof bundle tests (26 tests)
- **Phase 2**: Matcher system tests (35 tests), AI investigation tests (15 tests)
- **Phase 3**: CLI tests (11 tests), scanner integration tests (3 tests)
- **Phase 4**: Cache tests (8 tests), dedup tests (4 tests), triage tests (11 tests), custom config tests (4 tests), streaming tests (2 tests), incremental tests (6 tests), metrics tests (9 tests)

Total: **134 deepsec integration tests** (all passing)

## Error Handling

The integration uses tagged tuples for error handling:

- `{:ok, result}` on success
- `{:error, reason}` on failure

Common error reasons:
- `:invalid_format` - Invalid deepsec finding format
- `:missing_required_fields` - Required fields missing
- `:invalid_config` - Configuration validation failed
- `:budget_exceeded` - Scan would exceed budget
- `:deepsec_not_available` - Deepsec CLI not installed (Phase 3)
- `:workspace_not_initialized` - Deepsec workspace not initialized (Phase 3)

## Installation Requirements (Phase 3)

To use the CLI integration features in Phase 3, you must have deepsec installed:

```bash
# Install deepsec globally
npm install -g deepsec

# Or use npx without installation
npx deepsec --help
```

The integration will gracefully handle cases where deepsec is not installed, returning appropriate errors.

## Contributing

When adding new features to the deepsec integration:

1. Update this README with new functionality
2. Add tests for new functions
3. Update configuration options if needed
4. Ensure backward compatibility with existing API

## License

This integration is part of ControlKeel and follows the same license.