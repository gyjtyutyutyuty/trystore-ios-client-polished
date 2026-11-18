-- Feed-local state. Kept out of KV because the KV free tier allows only
-- 1,000 writes per day and the per-request rate counter burned through it.
--
-- feed_blobs lets a repaired package be served even when the KV write quota is
-- exhausted. The manifest route overlays the hash and size from this table.

CREATE TABLE IF NOT EXISTS feed_rate_limits (
  bucket       TEXT    NOT NULL,
  subject      TEXT    NOT NULL,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL,
  PRIMARY KEY (bucket, subject, window_start)
);

CREATE TABLE IF NOT EXISTS feed_auth_cache (
  subject    TEXT    PRIMARY KEY,
  expires_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS feed_blobs (
  project    TEXT    NOT NULL,
  name       TEXT    NOT NULL,
  bytes      BLOB    NOT NULL,
  sha256     TEXT    NOT NULL,
  size       INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (project, name)
);
