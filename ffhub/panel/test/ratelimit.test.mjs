// Run with: node --test panel/test/ratelimit.test.mjs

import assert from "node:assert/strict";
import { test } from "node:test";

import { consume, d1Store, limiter, memoryStore, windowStart } from "../lib/ratelimit.js";

const NOW = 1_700_000_000_000;

test("windows are fixed and aligned", () => {
  assert.equal(windowStart(0, 60), 0);
  assert.equal(windowStart(61_000, 60), 60);
  assert.equal(windowStart(119_999, 60), 60);
  assert.equal(windowStart(120_000, 60), 120);
  // A nonsense window still produces a usable bucket.
  assert.equal(windowStart(1_000, 0), 1);
});

test("the counter trips exactly at the limit", async () => {
  const store = memoryStore();
  const options = { bucket: "jobs", limit: 2, windowSeconds: 60, nowMs: NOW };

  const first = await consume(store, options);
  const second = await consume(store, options);
  const third = await consume(store, options);

  assert.equal(first.ok, true);
  assert.equal(first.count, 1);
  assert.equal(second.ok, true);
  assert.equal(third.ok, false);
  assert.equal(third.limit, 2);
  assert.equal(third.retryAfter, 40);
});

test("a new window starts from zero", async () => {
  const store = memoryStore();
  const options = { bucket: "jobs", limit: 1, windowSeconds: 60 };

  assert.equal((await consume(store, { ...options, nowMs: NOW })).ok, true);
  assert.equal((await consume(store, { ...options, nowMs: NOW + 1000 })).ok, false);
  assert.equal((await consume(store, { ...options, nowMs: NOW + 60_000 })).ok, true);
});

test("retry-after is the time to the next window, never zero", async () => {
  const store = memoryStore();
  const result = await consume(store, { bucket: "b", limit: 1, windowSeconds: 60, nowMs: NOW + 59_999 });

  // Whatever the alignment, the caller is told to wait inside this window.
  assert.ok(result.retryAfter >= 1 && result.retryAfter <= 60, `retry-after ${result.retryAfter}`);
});

test("the D1 store counts through its upsert", async () => {
  const calls = [];
  const rows = new Map();
  const db = {
    prepare(sql) {
      calls.push(sql);
      return {
        bind(bucket, start) {
          return {
            async first() {
              const key = `${bucket}:${start}`;
              const next = (rows.get(key) || 0) + 1;
              rows.set(key, next);
              return { hits: next };
            },
            async run() {
              return { meta: { changes: 0 } };
            },
          };
        },
        async run() {
          return { meta: { changes: 0 } };
        },
      };
    },
  };

  const store = d1Store(db);
  assert.equal(await store.hit("jobs", 60), 1);
  assert.equal(await store.hit("jobs", 60), 2);
  // The schema is created once per store, not per hit.
  assert.equal(calls.filter((sql) => sql.includes("CREATE TABLE")).length, 1);
  assert.ok(calls.some((sql) => sql.includes("ON CONFLICT(bucket, window_start)")));
});

test("a broken database falls back to memory instead of letting everything through", async () => {
  const warnings = [];
  const store = limiter({
    db: {
      prepare() {
        throw new Error("D1 is down");
      },
    },
    fallback: memoryStore(),
    onFallback: () => warnings.push("fallback"),
  });

  const first = await store.consume({ bucket: "jobs", limit: 1, windowSeconds: 60, nowMs: NOW });
  const second = await store.consume({ bucket: "jobs", limit: 1, windowSeconds: 60, nowMs: NOW });

  assert.equal(first.ok, true);
  assert.equal(second.ok, false);
  assert.deepEqual(warnings, ["fallback"]);
});

test("with no database at all the limiter still counts", async () => {
  const store = limiter({ fallback: memoryStore() });
  const options = { bucket: "b", limit: 1, windowSeconds: 60, nowMs: NOW };

  assert.equal((await store.consume(options)).ok, true);
  assert.equal((await store.consume(options)).ok, false);
});
