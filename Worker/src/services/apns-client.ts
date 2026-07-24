import type {
  JackpotNotification,
  NotificationSender,
  NotificationSendResult,
  NotificationSubscription,
} from "../models/notification";

/** Secret and non-secret values required to authenticate with APNs. */
export interface APNsConfiguration {
  keyId: string;
  teamId: string;
  privateKey: string;
  topic: string;
}

interface APNsErrorPayload {
  reason?: string;
}

const PERMANENT_TOKEN_ERRORS = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered",
]);

/** Sends token-authenticated HTTP/2 requests to Apple's Push Notification service. */
export class APNsClient implements NotificationSender {
  private providerToken: string | null = null;

  /** Creates a sender from secrets loaded at Worker execution time. */
  constructor(private readonly configuration: APNsConfiguration) {}

  /** Sends one visible jackpot notification and normalizes the APNs result. */
  async send(
    subscription: NotificationSubscription,
    notification: JackpotNotification,
  ): Promise<NotificationSendResult> {
    const providerToken = await this.getProviderToken();
    const host = subscription.apnsEnvironment === "sandbox"
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";
    const response = await fetch(`${host}/3/device/${subscription.deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${providerToken}`,
        "apns-collapse-id": notification.draw.id.slice(0, 64),
        "apns-priority": "10",
        "apns-push-type": "alert",
        "apns-topic": this.configuration.topic,
        "content-type": "application/json",
      },
      body: JSON.stringify(makePayload(notification)),
    });

    if (response.ok) {
      return { success: true, shouldDisableToken: false };
    }

    const error = await parseAPNsError(response);
    return {
      success: false,
      errorCode: error,
      shouldDisableToken: PERMANENT_TOKEN_ERRORS.has(error),
    };
  }

  /** Reuses one short-lived provider JWT within the current scheduled execution. */
  private async getProviderToken(): Promise<string> {
    if (this.providerToken) {
      return this.providerToken;
    }

    const issuedAt = Math.floor(Date.now() / 1_000);
    const header = base64URL(JSON.stringify({ alg: "ES256", kid: this.configuration.keyId }));
    const claims = base64URL(JSON.stringify({ iss: this.configuration.teamId, iat: issuedAt }));
    const unsignedToken = `${header}.${claims}`;
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      decodePrivateKey(this.configuration.privateKey),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      privateKey,
      new TextEncoder().encode(unsignedToken),
    );

    this.providerToken = `${unsignedToken}.${base64URL(signature)}`;
    return this.providerToken;
  }
}

/** Builds the small visible notification payload consumed by the iOS app. */
function makePayload(notification: JackpotNotification): object {
  const amount = new Intl.NumberFormat("zh-HK", {
    style: "currency",
    currency: "HKD",
    maximumFractionDigits: 0,
  }).format(notification.estimatedFund);

  return {
    aps: {
      alert: {
        title: "今晚六合彩攪珠",
        body: `第 ${notification.draw.drawNumber} 期估計頭獎基金 ${amount}`,
      },
      sound: "default",
    },
    drawId: notification.draw.id,
  };
}

/** Reads only APNs' documented, bounded error shape and returns a safe code. */
async function parseAPNsError(response: Response): Promise<string> {
  try {
    const payload = await response.json<APNsErrorPayload>();
    return payload.reason ?? `HTTP_${response.status}`;
  } catch {
    return `HTTP_${response.status}`;
  }
}

/** Converts a PEM-encoded PKCS#8 key into bytes accepted by Web Crypto. */
function decodePrivateKey(privateKey: string): ArrayBuffer {
  const base64 = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
}

/** Produces unpadded Base64URL for JWT components. */
function base64URL(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
