-- Align a deployment created before the App Attest merge with the current
-- license-worker schema. Fresh installs already get these columns from
-- 0001_license_devices.sql and 0002_api_rate_limits.sql; skip this file there.
--
-- Apply once, against the legacy schema:
--   wrangler d1 execute jvztxnx-global-control --remote \
--     --file migrations/0004_align_device_rate_schema.sql -c wrangler.license.toml

ALTER TABLE license_devices RENAME COLUMN first_seen TO first_seen_at;
ALTER TABLE license_devices RENAME COLUMN last_seen TO last_seen_at;
ALTER TABLE license_devices ADD COLUMN revoked_at INTEGER;
ALTER TABLE api_rate_limits RENAME COLUMN count TO hits;
