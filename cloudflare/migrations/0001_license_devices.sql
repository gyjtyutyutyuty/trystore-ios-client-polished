-- License devices and rate limiting for the Global Key Control worker.
-- Own tables: nothing here reads or writes another project's schema.
-- Apply with:
--   wrangler d1 execute jvztxnx-global-control --remote \
--     --file migrations/0001_license_devices.sql -c wrangler.license.toml

CREATE TABLE IF NOT EXISTS license_devices (
  key_id     INTEGER NOT NULL,
  device_id  TEXT    NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  PRIMARY KEY (key_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_license_devices_device
  ON license_devices (device_id);

CREATE TABLE IF NOT EXISTS api_rate_limits (
  bucket       TEXT    NOT NULL,
  subject      TEXT    NOT NULL,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL,
  PRIMARY KEY (bucket, subject, window_start)
);

CREATE INDEX IF NOT EXISTS idx_api_rate_limits_window
  ON api_rate_limits (window_start);
