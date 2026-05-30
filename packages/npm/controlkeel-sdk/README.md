# @aryaminus/controlkeel-sdk

TypeScript SDK for the [ControlKeel](https://github.com/aryaminus/controlkeel) cloud governance API.

## Install

```bash
npm install @aryaminus/controlkeel-sdk
```

## Quick start

```ts
import { ControlKeelClient } from "@aryaminus/controlkeel-sdk";

const ck = new ControlKeelClient({
  baseUrl: "https://controlkeel.com",
  token: process.env.CK_WORKSPACE_KEY!,
});

// Push findings to cloud
const { accepted } = await ck.syncPush("ws-123", [
  { type: "finding", id: "f-001", title: "Missing auth check" },
]);
console.log(`Accepted ${accepted} records.`);

// Pull latest records since a timestamp
const { records } = await ck.syncPull("ws-123", "2026-05-29T00:00:00Z");
```

## API

### Sync

| Method | Endpoint | Description |
|---|---|---|
| `syncPush(workspaceId, records)` | POST `/cloud/v1/sync/push` | Push records to cloud |
| `syncPull(workspaceId, since)` | POST `/cloud/v1/sync/pull` | Pull records since ISO timestamp |

### Workspace

| Method | Endpoint | Description |
|---|---|---|
| `registerWorkspace(envelope)` | POST `/cloud/v1/workspaces/register` | Register a new workspace |

### Service accounts

| Method | Endpoint | Description |
|---|---|---|
| `listServiceAccounts(workspaceId)` | GET `/cloud/v1/workspaces/:id/service-accounts` | List service accounts |
| `createServiceAccount(workspaceId, params)` | POST `/cloud/v1/workspaces/:id/service-accounts` | Create (token shown once) |

### Webhooks

| Method | Endpoint | Description |
|---|---|---|
| `listWebhooks(workspaceId)` | GET `/cloud/v1/workspaces/:id/webhooks` | List webhooks |
| `createWebhook(workspaceId, params)` | POST `/cloud/v1/workspaces/:id/webhooks` | Create a webhook |

### Tool policy

| Method | Endpoint | Description |
|---|---|---|
| `getToolPolicy(workspaceId)` | GET `/cloud/v1/workspaces/:id/tool-policy` | Get current policy |
| `setToolPolicy(workspaceId, params)` | PUT `/cloud/v1/workspaces/:id/tool-policy` | Set policy mode + tools |

### Policy sets

| Method | Endpoint | Description |
|---|---|---|
| `listPolicySets(workspaceId)` | GET `/cloud/v1/workspaces/:id/policy-sets` | List policy sets |
| `createPolicySet(workspaceId, params)` | POST `/cloud/v1/workspaces/:id/policy-sets` | Create a policy set |
| `applyPolicySet(workspaceId, policySetId)` | POST `/cloud/v1/workspaces/:id/policy-sets/:psId/apply` | Apply to workspace |

### Telemetry

| Method | Endpoint | Description |
|---|---|---|
| `ingestTelemetry(payload)` | POST `/cloud/v1/telemetry` | Ingest telemetry events |
| `postRuntimeCallback(payload)` | POST `/cloud/v1/runtime/callbacks` | Post runtime callback |

## Error handling

```ts
import { ControlKeelError } from "@aryaminus/controlkeel-sdk";

try {
  await ck.syncPush("ws-123", records);
} catch (err) {
  if (err instanceof ControlKeelError) {
    console.error(`API error ${err.status}: ${err.body}`);
    if (err.retryAfter) {
      console.log(`Rate limited. Retry after ${err.retryAfter}s.`);
    }
  }
}
```

The SDK automatically retries on 429 and 5xx responses (up to `maxRetries`, default 2). It respects the `Retry-After` header from the ControlKeel rate limiter.

## Options

```ts
const ck = new ControlKeelClient({
  baseUrl: "https://controlkeel.com",  // Required
  token: "ck_wk_...",                  // Required (workspace key or SA token)
  maxRetries: 3,                       // Default: 2
  timeoutMs: 60_000,                   // Default: 30000
});
```

## Requirements

- Node.js 18+ (uses native `fetch`)
- Zero runtime dependencies

## License

Apache-2.0
