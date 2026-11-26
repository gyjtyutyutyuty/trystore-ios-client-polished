// Server-side session registry.
//
// A signed cookie proves the token came from PANEL_TOKEN_KEY, but a signature
// cannot be withdrawn. Before this table, "Cerrar sesión" only deleted the
// cookie in that browser: a copied token kept working until it expired. Every
// session is now recorded in D1 under the SHA-256 of the token, so logging out
// kills that exact session on every isolate, and the owner can end every app
// session at once.
//
// Only the hash is stored: a dump of the table hands nobody a usable cookie.
//
// Without env.DB (unit tests, a local run with no D1) the registry lives in the
// isolate. With D1, a database error propagates and the Worker fails closed
// instead of trusting a token it cannot revoke.

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS panel_sessions (
    id TEXT PRIMARY KEY,
    subject TEXT NOT NULL,
    role TEXT NOT NULL,
    issued_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER,
    created_at INTEGER NOT NULL
  )`,
  "CREATE INDEX IF NOT EXISTS panel_sessions_role ON panel_sessions(role, revoked_at)",
  "CREATE INDEX IF NOT EXISTS panel_sessions_expires ON panel_sessions(expires_at)",
];

// Expired rows are dead weight but useful evidence for a week; after that the
// prune deletes them so the table does not grow forever.
const KEEP_EXPIRED_SECONDS = 7 * 24 * 60 * 60;

function isActive(row, { role, subject, nowSeconds }) {
  return Boolean(
    row &&
      !row.revoked_at &&
      Number(row.expires_at) > nowSeconds &&
      row.role === role &&
      row.subject === subject,
  );
}

export function memorySessionStore() {
  const sessions = new Map();
  return {
    kind: "memory",
    async register({ id, subject, role, issuedAt, expiresAt, nowSeconds }) {
      if (sessions.has(id)) return;
      sessions.set(id, {
        id,
        subject,
        role,
        issued_at: issuedAt,
        expires_at: expiresAt,
        revoked_at: null,
        created_at: nowSeconds,
      });
    },
    async isActive({ id, role, subject, nowSeconds }) {
      return isActive(sessions.get(id), { role, subject, nowSeconds });
    },
    async revoke({ id, nowSeconds }) {
      const row = sessions.get(id);
      if (!row || row.revoked_at) return 0;
      row.revoked_at = nowSeconds;
      return 1;
    },
    async revokeRole({ role, nowSeconds }) {
      let count = 0;
      for (const row of sessions.values()) {
        if (row.role === role && !row.revoked_at && row.expires_at > nowSeconds) {
          row.revoked_at = nowSeconds;
          count += 1;
        }
      }
      return count;
    },
    async countRole({ role, nowSeconds }) {
      let total = 0;
      for (const row of sessions.values()) {
        if (row.role === role && !row.revoked_at && row.expires_at > nowSeconds) total += 1;
      }
      return total;
    },
  };
}

export function d1SessionStore(db) {
  let schema = null;
  let pruned = false;

  // The DDL is idempotent and runs once per isolate; a failure clears the
  // promise so the next request can retry instead of failing forever.
  async function ready() {
    if (!schema) {
      schema = (async () => {
        for (const statement of SCHEMA) await db.prepare(statement).run();
      })().catch((error) => {
        schema = null;
        throw error;
      });
    }
    await schema;
    if (!pruned) {
      pruned = true;
      try {
        const cutoff = Math.floor(Date.now() / 1000) - KEEP_EXPIRED_SECONDS;
        await db.prepare("DELETE FROM panel_sessions WHERE expires_at < ?1").bind(cutoff).run();
      } catch {
        // Housekeeping is best effort: a failed prune must not fail a login.
        pruned = false;
      }
    }
  }

  return {
    kind: "d1",
    async register({ id, subject, role, issuedAt, expiresAt, nowSeconds }) {
      await ready();
      // DO NOTHING, never REPLACE: redeeming the same token after logout must
      // find the row revoked, not revive it.
      await db
        .prepare(
          "INSERT INTO panel_sessions (id, subject, role, issued_at, expires_at, revoked_at, created_at) " +
            "VALUES (?1, ?2, ?3, ?4, ?5, NULL, ?6) ON CONFLICT(id) DO NOTHING",
        )
        .bind(id, subject, role, issuedAt, expiresAt, nowSeconds)
        .run();
    },
    async isActive({ id, role, subject, nowSeconds }) {
      await ready();
      const row = await db
        .prepare("SELECT subject, role, expires_at, revoked_at FROM panel_sessions WHERE id=?1")
        .bind(id)
        .first();
      return isActive(row, { role, subject, nowSeconds });
    },
    async revoke({ id, nowSeconds }) {
      await ready();
      const result = await db
        .prepare("UPDATE panel_sessions SET revoked_at=?1 WHERE id=?2 AND revoked_at IS NULL")
        .bind(nowSeconds, id)
        .run();
      return Number(result?.meta?.changes || 0);
    },
    async revokeRole({ role, nowSeconds }) {
      await ready();
      const result = await db
        .prepare(
          "UPDATE panel_sessions SET revoked_at=?1 WHERE role=?2 AND revoked_at IS NULL AND expires_at>?1",
        )
        .bind(nowSeconds, role)
        .run();
      return Number(result?.meta?.changes || 0);
    },
    async countRole({ role, nowSeconds }) {
      await ready();
      const row = await db
        .prepare(
          "SELECT COUNT(*) AS total FROM panel_sessions WHERE role=?1 AND revoked_at IS NULL AND expires_at>?2",
        )
        .bind(role, nowSeconds)
        .first();
      return Number(row?.total || 0);
    },
  };
}

let warnedNoDb = false;
const storesByEnv = new WeakMap();

/// One registry per environment: the D1 handle and its schema check are
/// memoised, and a test environment never inherits another's sessions.
export function sessionStore(env) {
  let store = storesByEnv.get(env);
  if (!store) {
    if (env?.DB) {
      store = d1SessionStore(env.DB);
    } else {
      if (!warnedNoDb) {
        warnedNoDb = true;
        console.warn("ffhub: no D1 binding, panel sessions live in one isolate");
      }
      store = memorySessionStore();
    }
    storesByEnv.set(env, store);
  }
  return store;
}
