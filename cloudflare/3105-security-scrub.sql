-- Removes the plaintext licence keys that the 3105 adapter used to write into
-- access_logs. New rows carry a peppered reference (`k1:...`) instead; old rows
-- are overwritten so a D1 read can no longer hand out working credentials.
--
-- Run once, after ACCESS_LOG_PEPPER is set on the 3105api Worker:
--   npx wrangler d1 execute DB --remote -c wrangler.3105.toml \
--       --file 3105-security-scrub.sql --yes

UPDATE access_logs
SET key_value = 'purged'
WHERE key_value <> ''
  AND key_value NOT LIKE 'k1:%';

CREATE INDEX IF NOT EXISTS idx_access_logs_created
  ON access_logs(created_at);

-- Keep the radio quiet: the adapter holds no other licence material, and this
-- confirms the scrub in one query.
SELECT
  SUM(CASE WHEN key_value <> '' AND key_value NOT LIKE 'k1:%' THEN 1 ELSE 0 END)
    AS plaintext_rows,
  COUNT(*) AS total_rows
FROM access_logs;
