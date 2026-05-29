/**
 * TypeScript type definitions for the ControlKeel /cloud/v1 API.
 *
 * These types mirror the JSON shapes accepted and returned by the
 * ControlKeel cloud API endpoints. They are versioned alongside the
 * SDK package version.
 */

// ── Sync ──────────────────────────────────────────────────────────

/** A single sync record (finding, proof, memory, etc.) pushed to cloud. */
export interface SyncRecord {
  [key: string]: unknown;
  /** The schema/type of this record (e.g. "finding", "proof_bundle"). */
  type?: string;
  /** Unique id for deduplication. */
  id?: string;
}

export interface SyncPushRequest {
  workspace_id: string;
  records: SyncRecord[];
}

export interface SyncPushResponse {
  accepted: number;
  rejected: number;
  errors?: Array<{ index: number; reason: string }>;
}

export interface SyncPullRequest {
  workspace_id: string;
  since: string;
}

export interface SyncPullResponse {
  records: SyncRecord[];
  has_more: boolean;
}

// ── Workspace registration ─────────────────────────────────────────

export interface RegisterEnvelope {
  /** Ed25519 public key (base64). */
  public_key: string;
  /** Signed challenge (base64). */
  signature: string;
  /** Workspace name hint. */
  name?: string;
  /** Slug hint. */
  slug?: string;
}

export interface RegisterResponse {
  workspace_id: string;
  workspace_key: string;
  slug: string;
}

// ── Service accounts ───────────────────────────────────────────────

export interface ServiceAccount {
  id: number;
  name: string;
  scopes: Record<string, string[]>;
  status: string;
  last_used_at: string | null;
  inserted_at: string;
}

export interface CreateServiceAccountParams {
  name: string;
  scopes?: string[] | Record<string, string[]>;
}

export interface CreateServiceAccountResponse {
  service_account: ServiceAccount;
  token: string;
}

// ── Webhooks ───────────────────────────────────────────────────────

export interface Webhook {
  id: number;
  name: string;
  url: string;
  subscribed_events: Record<string, string[]>;
  status: string;
  inserted_at: string;
}

export interface CreateWebhookParams {
  name: string;
  url: string;
  subscribed_events?: string[];
}

// ── Tool policy ────────────────────────────────────────────────────

export interface ToolPolicy {
  workspace_id: number;
  mode: "inherit" | "allowlist" | "denylist";
  tools: string[];
}

export interface SetToolPolicyParams {
  mode: string;
  tools: string[];
}

// ── Policy sets ────────────────────────────────────────────────────

export interface PolicySet {
  id: number;
  name: string;
  description: string;
  status: string;
  rules: unknown[];
  inserted_at: string;
}

export interface CreatePolicySetParams {
  name: string;
  description?: string;
  rules?: unknown[];
}

// ── Telemetry ──────────────────────────────────────────────────────

export interface TelemetryPayload {
  workspace_id: string;
  events: Array<{
    event_type: string;
    timestamp: string;
    payload: Record<string, unknown>;
  }>;
}

// ── Runtime callbacks ──────────────────────────────────────────────

export interface RuntimeCallbackPayload {
  workspace_id: string;
  session_id?: string;
  task_id?: string;
  event_type: string;
  data: Record<string, unknown>;
}

// ── Generic error response ─────────────────────────────────────────

export interface ErrorResponse {
  error: string;
  message?: string;
  retry_after?: number;
}

// ── Client options ─────────────────────────────────────────────────

export interface ControlKeelClientOptions {
  /** Base URL of the ControlKeel instance (e.g. "https://controlkeel.com"). */
  baseUrl: string;
  /** Bearer token: workspace key or service account token. */
  token: string;
  /** Max number of automatic retries on 429 / 5xx. Default: 2. */
  maxRetries?: number;
  /** Request timeout in milliseconds. Default: 30000. */
  timeoutMs?: number;
}
