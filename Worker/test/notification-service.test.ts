import { describe, expect, it } from "vitest";
import type { DrawInfo } from "../src/models/draw";
import type {
  JackpotNotification,
  NotificationSender,
  NotificationSendResult,
  NotificationStore,
  NotificationSubscription,
} from "../src/models/notification";
import { NotificationService } from "../src/services/notification-service";

const DRAW: DrawInfo = {
  id: "2026-076",
  drawNumber: "26/076",
  drawDate: "2026-07-16T21:30:00+08:00",
  salesCloseAt: "2026-07-16T21:15:00+08:00",
  estimatedFirstPrizeFund: 30_000_000,
  jackpot: 18_000_000,
  status: "StartSell",
  mainNumbers: [],
  specialNumber: null,
  updatedAt: "2026-07-15T12:00:00.000Z",
  sourceURL: "https://bet.hkjc.com/ch/marksix",
};

const SUBSCRIPTIONS: NotificationSubscription[] = [
  makeSubscription("00000000-0000-4000-8000-000000000001", 16_000_000),
  makeSubscription("00000000-0000-4000-8000-000000000002", 30_000_000),
];

class RecordingNotificationStore implements NotificationStore {
  readonly reservations = new Set<string>();
  readonly sent: string[] = [];
  savedSubscription: NotificationSubscription | null = null;

  /** Records registration writes for contract completeness. */
  async saveSubscription(subscription: NotificationSubscription): Promise<void> {
    this.savedSubscription = subscription;
  }

  /** Applies the same threshold rule used by the D1 query. */
  async findEligibleSubscriptions(_drawId: string, fund: number): Promise<NotificationSubscription[]> {
    return SUBSCRIPTIONS.filter((subscription) => subscription.threshold <= fund);
  }

  /** Claims each installation only once. */
  async reserveDelivery(drawId: string, installationId: string): Promise<boolean> {
    const key = `${drawId}:${installationId}`;
    if (this.reservations.has(key)) {
      return false;
    }
    this.reservations.add(key);
    return true;
  }

  /** Records successful deliveries. */
  async markDeliverySent(_drawId: string, installationId: string): Promise<void> {
    this.sent.push(installationId);
  }

  /** This sender fixture does not produce failed deliveries. */
  async markDeliveryFailed(): Promise<void> {}

  /** This sender fixture does not invalidate tokens. */
  async disableSubscription(): Promise<void> {}
}

class RecordingSender implements NotificationSender {
  readonly recipients: string[] = [];

  /** Records each recipient and reports an accepted APNs request. */
  async send(
    subscription: NotificationSubscription,
    _notification: JackpotNotification,
  ): Promise<NotificationSendResult> {
    this.recipients.push(subscription.installationId);
    return { success: true, shouldDisableToken: false };
  }
}

describe("NotificationService", () => {
  it("does not notify when the draw is not today in Hong Kong", async () => {
    const sender = new RecordingSender();
    const service = new NotificationService(new RecordingNotificationStore(), sender);

    const result = await service.notifyEligibleUsers(DRAW, new Date("2026-07-15T01:15:00Z"));

    expect(result.outcome).toBe("not_draw_day");
    expect(sender.recipients).toEqual([]);
  });

  it("notifies thresholds equal to or below the estimated fund", async () => {
    const store = new RecordingNotificationStore();
    const sender = new RecordingSender();
    const service = new NotificationService(store, sender);

    const result = await service.notifyEligibleUsers(DRAW, new Date("2026-07-16T01:15:00Z"));

    expect(result).toEqual({
      outcome: "completed",
      eligibleCount: 2,
      sentCount: 2,
      failedCount: 0,
    });
    expect(sender.recipients).toHaveLength(2);
  });

  it("does not send the same draw to the same installation twice", async () => {
    const store = new RecordingNotificationStore();
    const sender = new RecordingSender();
    const service = new NotificationService(store, sender);
    const now = new Date("2026-07-16T01:15:00Z");

    await service.notifyEligibleUsers(DRAW, now);
    await service.notifyEligibleUsers(DRAW, now);

    expect(sender.recipients).toHaveLength(2);
  });
});

/** Creates a valid APNs fixture with a controlled threshold. */
function makeSubscription(installationId: string, threshold: number): NotificationSubscription {
  return {
    installationId,
    deviceToken: "a".repeat(64),
    threshold,
    enabled: true,
    apnsEnvironment: "sandbox",
    updatedAt: "2026-07-15T12:00:00.000Z",
  };
}
