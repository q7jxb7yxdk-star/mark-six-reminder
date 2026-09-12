import { beforeAll, describe, expect, it, vi } from "vitest";
import type { DrawInfo } from "../src/models/draw";
import type { APNsEnvironment, NotificationSubscription } from "../src/models/notification";
import { APNsClient, type APNsConfigurations } from "../src/services/apns-client";

const DRAW: DrawInfo = {
  id: "2026-099",
  drawNumber: "26/099",
  drawDate: "2026-09-12T21:30:00+08:00",
  salesCloseAt: "2026-09-12T21:15:00+08:00",
  estimatedFirstPrizeFund: 8_000_000,
  jackpot: null,
  status: "StartSell",
  mainNumbers: [],
  specialNumber: null,
  updatedAt: "2026-09-12T01:00:00.000Z",
  sourceURL: "https://bet.hkjc.com/ch/marksix",
};

let privateKey: string;

beforeAll(async () => {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  if (!("privateKey" in keyPair)) {
    throw new Error("Expected an ECDSA key pair");
  }
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);
  if (!(pkcs8 instanceof ArrayBuffer)) {
    throw new Error("Expected a PKCS#8 key buffer");
  }
  privateKey = pemPrivateKey(pkcs8);
});

describe("APNsClient", () => {
  it("uses an isolated endpoint and signing key for each APNs environment", async () => {
    const requests: Array<{ url: string; keyId: string }> = [];
    const fetcher = vi.fn<typeof fetch>(async (input, init) => {
      const headers = new Headers(init?.headers);
      requests.push({
        url: String(input),
        keyId: providerKeyId(headers.get("authorization")),
      });
      return new Response(null, { status: 200 });
    });
    const configurations: APNsConfigurations = {
      sandbox: configuration("SANDBOX01"),
      production: configuration("PRODUCT01"),
    };
    const client = new APNsClient(configurations, fetcher);

    await client.send(subscription("sandbox"), { draw: DRAW, estimatedFund: 8_000_000 });
    await client.send(subscription("production"), { draw: DRAW, estimatedFund: 8_000_000 });

    expect(requests).toEqual([
      {
        url: `https://api.sandbox.push.apple.com/3/device/${"a".repeat(64)}`,
        keyId: "SANDBOX01",
      },
      {
        url: `https://api.push.apple.com/3/device/${"a".repeat(64)}`,
        keyId: "PRODUCT01",
      },
    ]);
  });
});

function configuration(keyId: string) {
  return {
    keyId,
    teamId: "TEAMID1234",
    privateKey,
    topic: "com.sunny.mark-six-reminder",
  };
}

function subscription(apnsEnvironment: APNsEnvironment): NotificationSubscription {
  return {
    installationId: crypto.randomUUID(),
    deviceToken: "a".repeat(64),
    threshold: 8_000_000,
    enabled: true,
    apnsEnvironment,
    updatedAt: "2026-09-12T01:00:00.000Z",
  };
}

function providerKeyId(authorization: string | null): string {
  if (!authorization?.startsWith("bearer ")) {
    throw new Error("Missing APNs provider token");
  }

  const encodedHeader = authorization.slice("bearer ".length).split(".")[0];
  if (!encodedHeader) {
    throw new Error("APNs provider token does not contain a header");
  }
  const header = JSON.parse(Buffer.from(encodedHeader, "base64url").toString("utf8")) as { kid?: unknown };
  if (typeof header.kid !== "string") {
    throw new Error("APNs provider token does not contain a key ID");
  }
  return header.kid;
}

function pemPrivateKey(pkcs8: ArrayBuffer): string {
  const base64 = Buffer.from(pkcs8).toString("base64");
  const lines = base64.match(/.{1,64}/g)?.join("\n") ?? base64;
  return `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----`;
}
