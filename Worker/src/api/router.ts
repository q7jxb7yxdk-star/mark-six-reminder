import type { DrawStore } from "../models/draw";
import type {
  APNsEnvironment,
  NotificationStore,
  NotificationSubscription,
} from "../models/notification";

const JSON_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "cache-control": "public, max-age=60",
  "content-type": "application/json; charset=utf-8",
};

/** Routes the small public HTTP API without introducing a framework dependency. */
export async function routeRequest(
  request: Request,
  drawStore: DrawStore,
  notificationStore: NotificationStore,
): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: JSON_HEADERS });
  }

  if (request.method === "GET" && url.pathname === "/health") {
    return jsonResponse({ status: "ok" });
  }

  if (request.method === "GET" && url.pathname === "/v1/draws/current") {
    const draw = await drawStore.getCurrent();
    if (!draw) {
      return jsonResponse(
        { error: { code: "DRAW_NOT_READY", message: "Draw data is not available yet" } },
        503,
      );
    }

    return jsonResponse({ data: draw });
  }

  if (request.method === "GET") {
    const drawId = parseDrawIdPath(url.pathname);
    if (drawId) {
      const draw = await drawStore.getById(drawId);
      if (!draw) {
        return jsonResponse(
          { error: { code: "DRAW_NOT_FOUND", message: "Draw data was not found" } },
          404,
        );
      }
      return jsonResponse({ data: draw });
    }
  }

  if (request.method === "POST" && url.pathname === "/v1/notification-subscriptions") {
    const subscription = await parseSubscription(request);
    await notificationStore.saveSubscription(subscription);
    return jsonResponse({ data: { registered: true } });
  }

  return jsonResponse({ error: { code: "NOT_FOUND", message: "Route not found" } }, 404);
}

/** Extracts a bounded official draw identifier from the result lookup route. */
function parseDrawIdPath(pathname: string): string | null {
  const match = /^\/v1\/draws\/([A-Za-z0-9_-]{1,80})$/.exec(pathname);
  return match?.[1] ?? null;
}

/** Validates the small registration document before it reaches D1. */
async function parseSubscription(request: Request): Promise<NotificationSubscription> {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > 8_192) {
    throw new APIRequestError("REQUEST_TOO_LARGE", "Registration request is too large", 413);
  }

  let value: unknown;
  try {
    const body = await readLimitedBody(request, 8_192);
    value = JSON.parse(body) as unknown;
  } catch (error) {
    if (error instanceof APIRequestError) {
      throw error;
    }
    throw new APIRequestError("INVALID_JSON", "Request body must be valid JSON", 400);
  }

  if (!isRecord(value)) {
    throw new APIRequestError("INVALID_SUBSCRIPTION", "Notification settings are invalid", 400);
  }

  const installationId = value.installationId;
  const deviceToken = value.deviceToken;
  const threshold = value.threshold;
  const enabled = value.enabled;
  const apnsEnvironment = value.apnsEnvironment;
  if (
    typeof installationId !== "string" || !isUUID(installationId) ||
    !isDeviceToken(deviceToken) ||
    typeof threshold !== "number" || !Number.isSafeInteger(threshold) || threshold < 0 || threshold > 1_000_000_000 ||
    typeof enabled !== "boolean" ||
    !isAPNsEnvironment(apnsEnvironment)
  ) {
    throw new APIRequestError("INVALID_SUBSCRIPTION", "Notification settings are invalid", 400);
  }

  return {
    installationId,
    deviceToken: deviceToken.toLowerCase(),
    threshold,
    enabled,
    apnsEnvironment,
    updatedAt: new Date().toISOString(),
  };
}

/** Reads a request stream while enforcing a strict decoded byte limit. */
async function readLimitedBody(request: Request, maximumBytes: number): Promise<string> {
  if (!request.body) {
    return "";
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      byteCount += value.byteLength;
      if (byteCount > maximumBytes) {
        throw new APIRequestError("REQUEST_TOO_LARGE", "Registration request is too large", 413);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(byteCount);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(body);
}

/** An expected client error with a safe public response. */
export class APIRequestError extends Error {
  /** Creates a typed API request error. */
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "APIRequestError";
  }
}

/** Narrows JSON objects without accepting arrays or null. */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Accepts canonical UUID text generated by the app installation. */
function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

/** Accepts bounded, byte-aligned hexadecimal APNs tokens from devices and Simulator. */
function isDeviceToken(value: unknown): value is string {
  return typeof value === "string" &&
    value.length >= 64 &&
    value.length <= 512 &&
    value.length % 2 === 0 &&
    /^[a-fA-F0-9]+$/.test(value);
}

/** Narrows the only two APNs gateway choices accepted by the backend. */
function isAPNsEnvironment(value: unknown): value is APNsEnvironment {
  return value === "sandbox" || value === "production";
}

/** Creates consistent JSON responses for success and error payloads. */
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}
