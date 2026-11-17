-- App Attest registrations are bound to a license and claimed device.
-- Challenge values are kept only as SHA-256 hashes and expire quickly.
CREATE TABLE IF NOT EXISTS app_attest_keys (
  key_id TEXT PRIMARY KEY,
  license_key_id INTEGER NOT NULL REFERENCES global_keys(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  public_key_pem TEXT NOT NULL,
  sign_count INTEGER NOT NULL DEFAULT 0 CHECK (sign_count >= 0),
  environment TEXT NOT NULL CHECK (environment IN ('production', 'development')),
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  UNIQUE (license_key_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_app_attest_keys_license_device
  ON app_attest_keys(license_key_id, device_id);

CREATE TABLE IF NOT EXISTS app_attest_challenges (
  challenge_id TEXT PRIMARY KEY,
  challenge_hash TEXT NOT NULL,
  license_key_id INTEGER NOT NULL REFERENCES global_keys(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  key_id TEXT,
  purpose TEXT NOT NULL CHECK (purpose IN ('attestation', 'bundle-key')),
  issued_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_app_attest_challenges_expiry
  ON app_attest_challenges(expires_at);
CREATE INDEX IF NOT EXISTS idx_app_attest_challenges_license_device
  ON app_attest_challenges(license_key_id, device_id, purpose, consumed_at);
