CREATE TABLE IF NOT EXISTS notification_subscriptions (
  installation_id TEXT PRIMARY KEY,
  device_token TEXT NOT NULL,
  threshold INTEGER NOT NULL CHECK (threshold >= 0),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  apns_environment TEXT NOT NULL CHECK (apns_environment IN ('sandbox', 'production')),
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS notification_subscriptions_by_eligibility
ON notification_subscriptions(enabled, threshold);

CREATE TABLE IF NOT EXISTS notification_deliveries (
  draw_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'failed')),
  attempted_at TEXT NOT NULL,
  sent_at TEXT,
  error_code TEXT,
  PRIMARY KEY (draw_id, installation_id)
);

CREATE INDEX IF NOT EXISTS notification_deliveries_by_status
ON notification_deliveries(status, attempted_at);
