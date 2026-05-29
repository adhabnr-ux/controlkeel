/**
 * ControlKeel SDK error class.
 *
 * Thrown when the API returns a non-2xx response. Includes the HTTP
 * status, response body, and (for 429 responses) the Retry-After value
 * from P3.5 rate limiting.
 */
export class ControlKeelError extends Error {
  readonly status: number;
  readonly body: string;
  readonly retryAfter: number | null;

  constructor(status: number, body: string, retryAfter?: number | null) {
    const retryMsg = retryAfter ? ` (retry after ${retryAfter}s)` : "";
    super(`ControlKeel API error ${status}${retryMsg}: ${body.slice(0, 200)}`);
    this.name = "ControlKeelError";
    this.status = status;
    this.body = body;
    this.retryAfter = retryAfter ?? null;
  }
}
