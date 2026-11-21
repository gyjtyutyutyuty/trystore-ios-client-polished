-- Device-bound key release.
--
-- The first time a licence asks for a challenge, `public_key` is still NULL.
-- The P-256 public half arrives with the signed bundle-key request and is
-- stored there; later releases must sign a fresh challenge with the matching
-- private key, so a copied device UUID does not look like the same phone.
CREATE TABLE IF NOT EXISTS feed_device_keys (
  subject TEXT PRIMARY KEY,
  public_key TEXT,
  challenge TEXT,
  challenge_expires_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_feed_device_keys_expiry
  ON feed_device_keys(challenge_expires_at);
