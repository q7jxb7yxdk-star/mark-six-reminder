import { describe, expect, it } from "vitest";
import { routeRequest } from "../src/api/router";
import type { DrawInfo, DrawSnapshot, DrawStore } from "../src/models/draw";
import type { NotificationStore, NotificationSubscription } from "../src/models/notification";

const DRAW: DrawInfo = {
  id: "202675N",
  drawNumber: "26/075",
  drawDate: "2026-07-14T21:30:00+08:00",
  salesCloseAt: "2026-07-14T21:15:00+08:00",
  estimatedFirstPrizeFund: 20_000_000,
  jackpot: 12_000_000,
  status: "Result",
  mainNumbers: [3, 8, 17, 24, 36, 45],
  specialNumber: 9,
  updatedAt: "2026-07-14T14:15:00.000Z",
  sourceURL: "https://bet.hkjc.com/ch/marksix",
};

class StubDrawStore implements DrawStore {
  /** Returns the fixture as the current draw. */
  async getCurrent(): Promise<DrawInfo> {
    return DRAW;
  }

  /** Returns the fixture only for its official identifier. */
  async getById(id: string): Promise<DrawInfo | null> {
    return id === DRAW.id ? DRAW : null;
  }

  /** Accepts snapshots without external persistence. */
  async saveSnapshot(_snapshot: DrawSnapshot): Promise<void> {}
}

class StubNotificationStore implements NotificationStore {
  savedSubscription: NotificationSubscription | null = null;

  /** Retains the latest subscription so request normalization can be asserted. */
  async saveSubscription(subscription: NotificationSubscription): Promise<void> {
    this.savedSubscription = subscription;
  }

  /** Returns no eligible subscriptions. */
  async findEligibleSubscriptions(): Promise<NotificationSubscription[]> {
    return [];
  }

  /** Declines all delivery reservations. */
  async reserveDelivery(): Promise<boolean> {
    return false;
  }

  /** Accepts successful delivery updates. */
  async markDeliverySent(): Promise<void> {}

  /** Accepts failed delivery updates. */
  async markDeliveryFailed(): Promise<void> {}

  /** Accepts subscription disable requests. */
  async disableSubscription(): Promise<void> {}
}

describe("draw result API", () => {
  it("returns one persisted draw by official identifier", async () => {
    const response = await routeRequest(
      new Request(`https://example.com/v1/draws/${DRAW.id}`),
      new StubDrawStore(),
      new StubNotificationStore(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ data: DRAW });
  });

  it("returns a stable not-found response for an unknown identifier", async () => {
    const response = await routeRequest(
      new Request("https://example.com/v1/draws/unknown"),
      new StubDrawStore(),
      new StubNotificationStore(),
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({
      error: { code: "DRAW_NOT_FOUND", message: "Draw data was not found" },
    });
  });
});

describe("notification subscription API", () => {
  it("accepts a variable-length hexadecimal Simulator APNs token", async () => {
    const notificationStore = new StubNotificationStore();
    const deviceToken = "aB".repeat(80);
    const response = await routeRequest(
      new Request("https://example.com/v1/notification-subscriptions", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          installationId: "550e8400-e29b-41d4-a716-446655440000",
          deviceToken,
          threshold: 25_000_000,
          enabled: true,
          apnsEnvironment: "sandbox",
        }),
      }),
      new StubDrawStore(),
      notificationStore,
    );

    expect(response.status).toBe(200);
    expect(notificationStore.savedSubscription).toMatchObject({
      deviceToken: deviceToken.toLowerCase(),
      threshold: 25_000_000,
      enabled: true,
      apnsEnvironment: "sandbox",
    });
  });

  it("rejects a token that is not complete hexadecimal bytes", async () => {
    const notificationStore = new StubNotificationStore();
    const request = new Request("https://example.com/v1/notification-subscriptions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        installationId: "550e8400-e29b-41d4-a716-446655440000",
        deviceToken: "a".repeat(65),
        threshold: 13_000_000,
        enabled: true,
        apnsEnvironment: "sandbox",
      }),
    });

    await expect(
      routeRequest(request, new StubDrawStore(), notificationStore),
    ).rejects.toMatchObject({
      code: "INVALID_SUBSCRIPTION",
      status: 400,
    });
    expect(notificationStore.savedSubscription).toBeNull();
  });
});
