// Counters that survive a single isolate.
//
// The old limit lived in a Map, so a request that landed on a different isolate
// started from zero: it was a speed bump against a loop, not a quota. These
// counters sit in D1, which every isolate shares, so /api/jobs can be capped
// for real. When the binding is missing or the database errors, the limiter
// degrades to the in-memory store instead of letting requests through
// unlimited — a broken quota must not become no quota.

const SCHEMA = `CREATE TABLE IF NOT EXISTS request_limits (
  bucket TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  hits INTEGER NOT NULL,
  PRIMARY KEY (bucket, window_start)
)`;

const MAX_MEMORY_KEYS = 10_000;

export function windowStart(nowMs, windowSeconds) {
  const seconds = Math.max(1, Math.floor(windowSeconds));
  return Math.floor(nowMs / 1000 / seconds) * seconds;
}

export function memoryStore() {
  const counters = new Map();
  return {
    kind: "memory",
    async hit(bucket, start) {
      if (counters.size > MAX_MEMORY_KEYS) counters.clear();
      const key = `${bucket}:${start}`;
      const next = (counters.get(key) || 0) + 1;
      counters.set(key, next);
      return next;
    },
  };
}

export function d1Store(db) {
  let schema = null;
  return {
    kind: "d1",
    async hit(bucket, start) {
      // One attempt per isolate unless it fails; the DDL is idempotent.
      if (!schema) {
        schema = db.prepare(SCHEMA).run().catch((error) => {
          schema = null;
          throw error;
        });
      }
      await schema;
      const row = await db
        .prepare(
          "INSERT INTO request_limits (bucket, window_start, hits) VALUES (?1, ?2, 1) " +
            "ON CONFLICT(bucket, window_start) DO UPDATE SET hits = hits + 1 RETURNING hits",
        )
        .bind(bucket, start)
        .first();
      return Number(row?.hits ?? 1);
    },
  };
}

/// Returns {ok, count, limit, retryAfter}. `retryAfter` is seconds until the
/// window rolls over, which is what a 429 should tell the caller.
export async function consume(store, { bucket, limit, windowSeconds, nowMs = Date.now() }) {
  const seconds = Math.max(1, Math.floor(windowSeconds));
  const start = windowStart(nowMs, seconds);
  const count = await store.hit(bucket, start);
  const resetAt = start + seconds;
  return {
    ok: count <= limit,
    count,
    limit,
    retryAfter: Math.max(1, resetAt - Math.floor(nowMs / 1000)),
    resetAt,
  };
}

/// Prefers D1, falls back to memory. `onFallback` lets the Worker log the fact
/// once instead of silently pretending the quota held.
export function limiter({ db, fallback, onFallback }) {
  const shared = db ? d1Store(db) : null;
  let warned = false;
  return {
    async consume(options) {
      if (shared) {
        try {
          return await consume(shared, options);
        } catch {
          if (!warned && typeof onFallback === "function") {
            warned = true;
            onFallback();
          }
        }
      }
      return consume(fallback, options);
    },
  };
}
