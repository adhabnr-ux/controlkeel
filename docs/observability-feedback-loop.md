# Local Observability Feedback Loop

ControlKeel's observability loop is local-first and human-gated. It helps operators convert governed findings into regression evidence without automatically changing policy, router, prompt, or autofix artifacts.

## Workflow

1. Inspect current observability posture:

   ```bash
   controlkeel obs status
   controlkeel obs problems
   controlkeel obs recommend
   ```

2. Save advisory eval candidates derived from grouped problems:

   ```bash
   controlkeel obs evals
   controlkeel obs evals save
   controlkeel obs evals persisted
   ```

3. Generate and review local benchmark drafts:

   ```bash
   controlkeel obs benchmarks draft
   controlkeel obs benchmarks drafts
   controlkeel obs benchmarks approve <draft-id>
   # or: controlkeel obs benchmarks reject <draft-id>
   # or: controlkeel obs benchmarks archive <draft-id>
   ```

4. Materialize approved drafts into local benchmark suites and scenarios:

   ```bash
   controlkeel obs benchmarks materialize
   controlkeel obs benchmarks scenarios
   ```

5. Preview and explicitly run generated scenarios from the CLI:

   ```bash
   controlkeel obs benchmarks run --dry-run --subjects controlkeel_validate
   controlkeel obs benchmarks run --execute --suite <observability-suite> --subjects controlkeel_validate
   ```

6. Inspect evidence and advisory promotion readiness:

   ```bash
   controlkeel obs benchmarks history
   controlkeel obs regressions
   controlkeel obs promotions
   ```

## Safety boundaries

- `obs evals save` stores local advisory eval candidate records only.
- `obs benchmarks draft` creates local draft scenarios only.
- `obs benchmarks approve|reject|archive` changes only local draft review state.
- `obs benchmarks materialize` creates local `Benchmark.Suite` and `Benchmark.Scenario` records; it does not run benchmarks.
- `obs benchmarks run --dry-run` is non-mutating preview.
- `obs benchmarks run --execute` is the only observability command in this loop that records benchmark execution, and it delegates to the existing local benchmark runner.
- `obs promotions` is advisory reporting only and returns promotion candidates with no policy, router, prompt, or autofix mutation.

## Local telemetry snapshots

Use local envelopes when you need to move or inspect observability evidence without mutating live sessions:

```bash
controlkeel obs export <session-id>
controlkeel obs import <file> --dry-run
controlkeel obs import <file> --persist
controlkeel obs imports
```

Persisted imports are snapshots and are deduplicated by payload hash; they do not rewrite sessions, findings, or memory.
