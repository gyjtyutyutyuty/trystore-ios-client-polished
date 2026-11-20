-- Which bundle-key version the feed serves, per project. Kept in D1 so that
-- retiring a leaked key is a data change (`/rotate` in the admin bot) instead of
-- a deploy, and so a device never receives a key that cannot open its package.
CREATE TABLE IF NOT EXISTS feed_key_state (
  project     TEXT    PRIMARY KEY,
  key_version TEXT    NOT NULL,
  rotated_at  INTEGER NOT NULL
);
