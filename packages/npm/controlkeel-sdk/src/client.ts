/**
 * ControlKeel cloud API client.
 *
 * Wraps all `/cloud/v1` endpoints with typed methods. Uses native `fetch`
 * (available in Node 18+). Zero runtime dependencies.
 *
 * ## Quick start
 *
 * ```ts
 * import { ControlKeelClient } from "@aryaminus/controlkeel-sdk";
 *
 * const ck = new ControlKeelClient({
 *   baseUrl: "https://controlkeel.com",
 *   token: process.env.CK_WORKSPACE_KEY!,
 * });
 *
 * const { accepted } = await ck.syncPush("ws-123", records);
 * ```
 */

import type {
  ControlKeelClientOptions,
  CreateServiceAccountParams,
  CreateServiceAccountResponse,
  ServiceAccount,
  CreateWebhookParams,
  Webhook,
  ToolPolicy,
  SetToolPolicyParams,
  SyncPushRequest,
  SyncPushResponse,

  SyncPullResponse,
  RegisterEnvelope,
  RegisterResponse,
  TelemetryPayload,
  RuntimeCallbackPayload,
  PolicySet,
  CreatePolicySetParams,
} from "./types.js";
import { ControlKeelError } from "./error.js";

const DEFAULT_MAX_RETRIES = 2;
const DEFAULT_TIMEOUT_MS = 30_000;

export class ControlKeelClient {
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly maxRetries: number;
  private readonly timeoutMs: number;

  constructor(opts: ControlKeelClientOptions) {
    this.baseUrl = opts.baseUrl.replace(/\/+$/, "");
    this.token = opts.token;
    this.maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES;
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  }

  // ── Sync ──────────────────────────────────────────────────────────

  /** Push records to cloud. */
  async syncPush(
    workspaceId: string,
    records: SyncPushRequest["records"],
  ): Promise<SyncPushResponse> {
    return this.post<SyncPushResponse>("/cloud/v1/sync/push", {
      workspace_id: workspaceId,
      records,
    });
  }

  /** Pull records since a given ISO timestamp. */
  async syncPull(workspaceId: string, since: string): Promise<SyncPullResponse> {
    return this.post<SyncPullResponse>("/cloud/v1/sync/pull", {
      workspace_id: workspaceId,
      since,
    });
  }

  // ── Workspace registration ────────────────────────────────────────

  /** Register a new workspace (enrollment with signed proof). */
  async registerWorkspace(envelope: RegisterEnvelope): Promise<RegisterResponse> {
    return this.post<RegisterResponse>("/cloud/v1/workspaces/register", envelope);
  }

  // ── Service accounts ──────────────────────────────────────────────

  /** List service accounts for a workspace. */
  async listServiceAccounts(workspaceId: string): Promise<ServiceAccount[]> {
    return this.get<ServiceAccount[]>(
      `/api/v1/workspaces/${workspaceId}/service-accounts`,
    );
  }

  /** Create a service account. Returns the plaintext token once. */
  async createServiceAccount(
    workspaceId: string,
    params: CreateServiceAccountParams,
  ): Promise<CreateServiceAccountResponse> {
    return this.post<CreateServiceAccountResponse>(
      `/api/v1/workspaces/${workspaceId}/service-accounts`,
      params,
    );
  }

  // ── Webhooks ──────────────────────────────────────────────────────

  /** List webhooks for a workspace. */
  async listWebhooks(workspaceId: string): Promise<Webhook[]> {
    return this.get<Webhook[]>(
      `/api/v1/workspaces/${workspaceId}/webhooks`,
    );
  }

  /** Create a webhook. */
  async createWebhook(
    workspaceId: string,
    params: CreateWebhookParams,
  ): Promise<Webhook> {
    return this.post<Webhook>(
      `/api/v1/workspaces/${workspaceId}/webhooks`,
      params,
    );
  }

  // ── Tool policy ───────────────────────────────────────────────────

  /** Get the current tool policy for a workspace. */
  async getToolPolicy(workspaceId: string): Promise<ToolPolicy> {
    return this.get<ToolPolicy>(
      `/api/v1/workspaces/${workspaceId}/tool-policy`,
    );
  }

  /** Set the tool policy for a workspace. */
  async setToolPolicy(
    workspaceId: string,
    params: SetToolPolicyParams,
  ): Promise<ToolPolicy> {
    return this.put<ToolPolicy>(
      `/api/v1/workspaces/${workspaceId}/tool-policy`,
      params,
    );
  }

  // ── Policy sets ───────────────────────────────────────────────────

  /** List policy sets for a workspace. */
  async listPolicySets(workspaceId: string): Promise<PolicySet[]> {
    return this.get<PolicySet[]>(
      `/api/v1/workspaces/${workspaceId}/policy-sets`,
    );
  }

  /** Create a policy set. */
  async createPolicySet(
    workspaceId: string,
    params: CreatePolicySetParams,
  ): Promise<PolicySet> {
    return this.post<PolicySet>(
      `/api/v1/workspaces/${workspaceId}/policy-sets`,
      params,
    );
  }

  /** Apply a policy set to a workspace. */
  async applyPolicySet(
    workspaceId: string,
    policySetId: string,
  ): Promise<{ status: string }> {
    return this.post<{ status: string }>(
      `/api/v1/workspaces/${workspaceId}/policy-sets/${policySetId}/apply`,
      {},
    );
  }

  // ── Telemetry ─────────────────────────────────────────────────────

  /** Ingest telemetry events. */
  async ingestTelemetry(payload: TelemetryPayload): Promise<void> {
    await this.post("/cloud/v1/telemetry", payload);
  }

  // ── Runtime callbacks ─────────────────────────────────────────────

  /** Post a runtime callback event. */
  async postRuntimeCallback(payload: RuntimeCallbackPayload): Promise<void> {
    await this.post("/cloud/v1/runtime/callbacks", payload);
  }

  // ── Internal transport ────────────────────────────────────────────

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    attempt = 0,
  ): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.token}`,
      };

      const res = await fetch(`${this.baseUrl}${path}`, {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });

      if (!res.ok) {
        const text = await res.text();

        // Retry on 429 or 5xx (up to maxRetries)
        if ((res.status === 429 || res.status >= 500) && attempt < this.maxRetries) {
          const retryHeader = res.headers.get("retry-after");
          const retryAfter = retryHeader ? parseInt(retryHeader, 10) : 1;
          await sleep(Math.min(retryAfter, 10) * 1000);
          return this.request<T>(method, path, body, attempt + 1);
        }

        const retryHeader = res.headers.get("retry-after");
        const retryAfter = retryHeader ? parseInt(retryHeader, 10) : null;
        throw new ControlKeelError(res.status, text, retryAfter);
      }

      // Some endpoints return 204 No Content
      if (res.status === 204 || res.headers.get("content-length") === "0") {
        return undefined as T;
      }

      return (await res.json()) as T;
    } finally {
      clearTimeout(timer);
    }
  }

  private post<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>("POST", path, body);
  }

  private get<T>(path: string): Promise<T> {
    return this.request<T>("GET", path);
  }

  private put<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>("PUT", path, body);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
