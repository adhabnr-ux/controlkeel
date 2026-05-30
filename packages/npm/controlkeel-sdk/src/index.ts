/**
 * ControlKeel Cloud SDK
 *
 * Typed access to the ControlKeel /cloud/v1 governance API.
 *
 * @example
 * ```ts
 * import { ControlKeelClient } from "@aryaminus/controlkeel-sdk";
 *
 * const ck = new ControlKeelClient({
 *   baseUrl: "https://controlkeel.com",
 *   token: process.env.CK_WORKSPACE_KEY!,
 * });
 *
 * const { accepted } = await ck.syncPush("ws-123", [{ type: "finding", id: "f1" }]);
 * ```
 */

export { ControlKeelClient } from "./client.js";
export { ControlKeelError } from "./error.js";
export type {
  ControlKeelClientOptions,
  SyncRecord,
  SyncPushRequest,
  SyncPushResponse,
  SyncPullRequest,
  SyncPullResponse,
  RegisterEnvelope,
  RegisterResponse,
  ServiceAccount,
  CreateServiceAccountParams,
  CreateServiceAccountResponse,
  Webhook,
  CreateWebhookParams,
  ToolPolicy,
  SetToolPolicyParams,
  PolicySet,
  CreatePolicySetParams,
  TelemetryPayload,
  RuntimeCallbackPayload,
  ErrorResponse,
} from "./types.js";
