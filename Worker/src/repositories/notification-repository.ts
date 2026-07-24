import type { NotificationStore, NotificationSubscription } from "../models/notification";

interface NotificationSubscriptionRow {
  installation_id: string;
  device_token: string;
  threshold: number;
  enabled: number;
  apns_environment: "sandbox" | "production";
  updated_at: string;
}

/** Stores device preferences and per-draw delivery claims in D1. */
export class NotificationRepository implements NotificationStore {
  /** Creates a repository backed by the configured D1 binding. */
  constructor(private readonly database: D1Database) {}

  /** Upserts the latest settings for one app installation. */
  async saveSubscription(subscription: NotificationSubscription): Promise<void> {
    await this.database
      .prepare(
        `INSERT INTO notification_subscriptions (
          installation_id, device_token, threshold, enabled, apns_environment, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(installation_id) DO UPDATE SET
          device_token = excluded.device_token,
          threshold = excluded.threshold,
          enabled = excluded.enabled,
          apns_environment = excluded.apns_environment,
          updated_at = excluded.updated_at`,
      )
      .bind(
        subscription.installationId,
        subscription.deviceToken,
        subscription.threshold,
        subscription.enabled ? 1 : 0,
        subscription.apnsEnvironment,
        subscription.updatedAt,
      )
      .run();
  }

  /** Selects enabled subscriptions which meet the fund and have no delivery claim. */
  async findEligibleSubscriptions(
    drawId: string,
    estimatedFund: number,
  ): Promise<NotificationSubscription[]> {
    const result = await this.database
      .prepare(
        `SELECT subscription.*
         FROM notification_subscriptions AS subscription
         LEFT JOIN notification_deliveries AS delivery
           ON delivery.draw_id = ?
          AND delivery.installation_id = subscription.installation_id
         WHERE subscription.enabled = 1
           AND subscription.threshold <= ?
           AND delivery.installation_id IS NULL
         ORDER BY subscription.installation_id`,
      )
      .bind(drawId, estimatedFund)
      .all<NotificationSubscriptionRow>();

    return result.results.map(mapSubscriptionRow);
  }

  /** Inserts a unique pending record and returns whether this execution owns it. */
  async reserveDelivery(drawId: string, installationId: string, attemptedAt: string): Promise<boolean> {
    const result = await this.database
      .prepare(
        `INSERT INTO notification_deliveries (
          draw_id, installation_id, status, attempted_at
        ) VALUES (?, ?, 'pending', ?)
        ON CONFLICT(draw_id, installation_id) DO NOTHING`,
      )
      .bind(drawId, installationId, attemptedAt)
      .run();

    return result.meta.changes === 1;
  }

  /** Marks a reserved delivery as accepted by APNs. */
  async markDeliverySent(drawId: string, installationId: string, sentAt: string): Promise<void> {
    await this.database
      .prepare(
        `UPDATE notification_deliveries
         SET status = 'sent', sent_at = ?, error_code = NULL
         WHERE draw_id = ? AND installation_id = ?`,
      )
      .bind(sentAt, drawId, installationId)
      .run();
  }

  /** Marks a reserved delivery as failed without exposing APNs response bodies. */
  async markDeliveryFailed(drawId: string, installationId: string, errorCode: string): Promise<void> {
    await this.database
      .prepare(
        `UPDATE notification_deliveries
         SET status = 'failed', error_code = ?
         WHERE draw_id = ? AND installation_id = ?`,
      )
      .bind(errorCode, drawId, installationId)
      .run();
  }

  /** Stops future sends to a token APNs has identified as permanently invalid. */
  async disableSubscription(installationId: string, updatedAt: string): Promise<void> {
    await this.database
      .prepare(
        `UPDATE notification_subscriptions
         SET enabled = 0, updated_at = ?
         WHERE installation_id = ?`,
      )
      .bind(updatedAt, installationId)
      .run();
  }
}

/** Converts a D1 row into the domain model used by notification services. */
function mapSubscriptionRow(row: NotificationSubscriptionRow): NotificationSubscription {
  return {
    installationId: row.installation_id,
    deviceToken: row.device_token,
    threshold: row.threshold,
    enabled: row.enabled === 1,
    apnsEnvironment: row.apns_environment,
    updatedAt: row.updated_at,
  };
}
