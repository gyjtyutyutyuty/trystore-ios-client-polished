-- Signals used to detect one licence being shared across devices.
-- IPs are stored as salted hashes, never raw.

CREATE TABLE IF NOT EXISTS license_signals (
  key_id       INTEGER NOT NULL,
  ip_bucket    TEXT    NOT NULL,
  window_start INTEGER NOT NULL,
  last_seen    INTEGER NOT NULL,
  PRIMARY KEY (key_id, ip_bucket, window_start)
);

CREATE INDEX IF NOT EXISTS idx_license_signals_window
  ON license_signals (key_id, window_start);
