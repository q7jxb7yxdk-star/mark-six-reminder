import type { DrawInfo } from "../models/draw";
import type { NotificationSender, NotificationStore } from "../models/notification";
import { isHongKongDrawDay } from "../utils/hong-kong-date";

/** A compact structured result suitable for Worker logs and unit tests. */
export interface NotificationRunSummary {
  outcome: "not_draw_day" | "fund_unavailable" | "no_eligible_users" | "apns_not_configured" | "completed";
  eligibleCount: number;
  sentCount: number;
  failedCount: number;
}

/** Applies draw-day, user-threshold and once-per-draw rules before contacting APNs. */
export class NotificationService {
  /** Creates the service with durable storage and an optional configured sender. */
  constructor(
    private readonly store: NotificationStore,
    private readonly sender: NotificationSender | null,
  ) {}

  /** Evaluates all eligible installations and sends at most one alert per draw. */
  async notifyEligibleUsers(draw: DrawInfo, now = new Date()): Promise<NotificationRunSummary> {
    if (!isHongKongDrawDay(draw.drawDate, now)) {
      return summary("not_draw_day");
    }

    const estimatedFund = draw.estimatedFirstPrizeFund;
    if (estimatedFund === null) {
      return summary("fund_unavailable");
    }

    const subscriptions = await this.store.findEligibleSubscriptions(draw.id, estimatedFund);
    if (subscriptions.length === 0) {
      return summary("no_eligible_users");
    }

    if (!this.sender) {
      return { ...summary("apns_not_configured"), eligibleCount: subscriptions.length };
    }

    let sentCount = 0;
    let failedCount = 0;
    for (const subscription of subscriptions) {
      const attemptedAt = new Date().toISOString();
      const reserved = await this.store.reserveDelivery(
        draw.id,
        subscription.installationId,
        attemptedAt,
      );
      if (!reserved) {
        continue;
      }

      try {
        const result = await this.sender.send(subscription, { draw, estimatedFund });
        if (result.success) {
          await this.store.markDeliverySent(draw.id, subscription.installationId, new Date().toISOString());
          sentCount += 1;
          continue;
        }

        const errorCode = result.errorCode ?? "UNKNOWN_APNS_ERROR";
        await this.store.markDeliveryFailed(draw.id, subscription.installationId, errorCode);
        if (result.shouldDisableToken) {
          await this.store.disableSubscription(subscription.installationId, new Date().toISOString());
        }
        failedCount += 1;
      } catch (error) {
        const errorCode = error instanceof Error ? error.name : "UnexpectedError";
        await this.store.markDeliveryFailed(draw.id, subscription.installationId, errorCode);
        failedCount += 1;
      }
    }

    return {
      outcome: "completed",
      eligibleCount: subscriptions.length,
      sentCount,
      failedCount,
    };
  }
}

/** Creates the zero-count result used by early exits. */
function summary(outcome: NotificationRunSummary["outcome"]): NotificationRunSummary {
  return { outcome, eligibleCount: 0, sentCount: 0, failedCount: 0 };
}
