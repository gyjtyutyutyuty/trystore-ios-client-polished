-- Device binding and edge rate limiting for the global licence worker.
-- Apply with: wrangler d1 execute <db> --file migrations/0001_license_devices.sql

CREATE TABLE IF NOT EXISTS global_key_devices (
  key_id     INTEGER NOT NULL,
  device_id  TEXT    NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  PRIMARY KEY (key_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_global_key_devices_device
  ON global_key_devices (device_id);

CREATE TABLE IF NOT EXISTS api_rate_limits (
  bucket       TEXT    NOT NULL,
  subject      TEXT    NOT NULL,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL,
  PRIMARY KEY (bucket, subject, window_start)
);

CREATE INDEX IF NOT EXISTS idx_api_rate_limits_window
  ON api_rate_limits (window_start);
