import type { DrawInfo } from "./draw";

/** The APNs gateway associated with an app installation's provisioning profile. */
export type APNsEnvironment = "sandbox" | "production";

/** A validated notification preference registered by one app installation. */
export interface NotificationSubscription {
  installationId: string;
  deviceToken: string;
  threshold: number;
  enabled: boolean;
  apnsEnvironment: APNsEnvironment;
  updatedAt: string;
}

/** Persistence operations required by notification registration and delivery. */
export interface NotificationStore {
  /** Creates or replaces one installation's current notification preference. */
  saveSubscription(subscription: NotificationSubscription): Promise<void>;

  /** Finds enabled installations whose threshold is met and which have not been attempted. */
  findEligibleSubscriptions(drawId: string, estimatedFund: number): Promise<NotificationSubscription[]>;

  /** Atomically reserves one delivery so the same draw is not sent twice. */
  reserveDelivery(drawId: string, installationId: string, attemptedAt: string): Promise<boolean>;

  /** Records a successful APNs response. */
  markDeliverySent(drawId: string, installationId: string, sentAt: string): Promise<void>;

  /** Records a failed APNs response for later diagnosis. */
  markDeliveryFailed(drawId: string, installationId: string, errorCode: string): Promise<void>;

  /** Disables an installation whose APNs token is permanently invalid. */
  disableSubscription(installationId: string, updatedAt: string): Promise<void>;
}

/** The APNs payload data needed to send one jackpot alert. */
export interface JackpotNotification {
  draw: DrawInfo;
  estimatedFund: number;
}

/** Normalized APNs delivery result used by the notification service. */
export interface NotificationSendResult {
  success: boolean;
  errorCode?: string;
  shouldDisableToken: boolean;
}

/** Transport contract that keeps APNs implementation details outside business logic. */
export interface NotificationSender {
  /** Sends one jackpot alert to a registered installation. */
  send(
    subscription: NotificationSubscription,
    notification: JackpotNotification,
  ): Promise<NotificationSendResult>;
}
