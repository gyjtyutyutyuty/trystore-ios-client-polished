-- 3105 project + Supabase-adapter support tables.
-- Run against the jvztxnx-global-control D1 database.

INSERT INTO projects (name, slug, key_prefix, status, created_at)
SELECT '3105', '3105', '3105', 'active', CAST(strftime('%s','now') AS INTEGER)
WHERE NOT EXISTS (SELECT 1 FROM projects WHERE slug = '3105');

-- key_value holds the peppered reference written by the adapter, never the
-- licence itself; see 3105-security-scrub.sql.
CREATE TABLE IF NOT EXISTS access_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key_value TEXT NOT NULL,
  device_id TEXT,
  action TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_access_logs_key ON access_logs(key_value, created_at);

CREATE TABLE IF NOT EXISTS app_config (
  id INTEGER PRIMARY KEY,
  maintenance_mode INTEGER NOT NULL DEFAULT 0,
  maintenance_message TEXT NOT NULL DEFAULT '',
  app_title TEXT,
  app_subtitle TEXT,
  online_text TEXT,
  footer_text TEXT,
  updated_at INTEGER NOT NULL
);

INSERT OR IGNORE INTO app_config (id, maintenance_mode, maintenance_message, updated_at)
VALUES (1, 0, '', CAST(strftime('%s','now') AS INTEGER));

CREATE INDEX IF NOT EXISTS idx_global_key_devices_target
  ON global_key_devices(key_id, target);
