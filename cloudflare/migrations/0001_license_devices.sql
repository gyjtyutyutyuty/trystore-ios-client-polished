-- Bind local license activations to a device without storing the raw license key.
CREATE TABLE IF NOT EXISTS license_devices (
  key_id INTEGER NOT NULL REFERENCES global_keys(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  first_seen_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  revoked_at INTEGER,
  PRIMARY KEY (key_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_license_devices_key_active
  ON license_devices(key_id, revoked_at);
