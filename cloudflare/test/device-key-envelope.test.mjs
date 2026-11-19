import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";
import worker from "../patch-feed-worker.js";

if (!globalThis.crypto) Object.defineProperty(globalThis, "crypto", { value: webcrypto });

const b64 = (value) => Buffer.from(value).toString("base64");
const deviceID = "7d6a2980-7df2-4d20-a5a3-e51a6dd3d60f";
const licenseKey = "TEST-LICENSE-KEY-01";
const appBundleKey = Buffer.from(Array.from({ length: 32 }, (_, index) => (index * 7 + 13) & 0xff));

function bindings() {
  return {
    APP_BUNDLE_KEY: appBundleKey.toString("base64"),
    RESELLER: {
      fetch: async () => new Response(JSON.stringify({
        valid: true,
        outcome: "active",
      }), { status: 200, headers: { "content-type": "application/json" } }),
    },
  };
}

function request(method, body) {
  return new Request("https://trystore-patch-feed.example/api/patches/trystore/bundle-key", {
    method,
    headers: {
      authorization: `Bearer ${licenseKey}`,
      "x-trystore-device-id": deviceID,
      ...(body ? { "content-type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

test("signed-session gate rejects a missing session header", async () => {
  const env = bindings();
  env.REQUIRE_SIGNED_SESSION = "1";
  const response = await worker.fetch(request("POST", {
    publicKey: b64(new Uint8Array(65)),
  }), env);
  assert.equal(response.status, 401);
});

test("bundle key is returned only as an envelope decryptable by the requesting P-256 private key", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  );
  const publicKey = await crypto.subtle.exportKey("raw", pair.publicKey);
  const response = await worker.fetch(request("POST", { publicKey: b64(publicKey) }), bindings());
  assert.equal(response.status, 200);
  const envelope = await response.json();
  assert.equal(envelope.valid, true);
  assert.equal(envelope.scheme, "p256-hkdf-sha256-aesgcm-v2");
  assert.equal(envelope.keyVersion, 2);
  assert.equal(Object.hasOwn(envelope, "key"), false);

  const ephemeralPublicKey = await crypto.subtle.importKey(
    "raw",
    Buffer.from(envelope.ephemeralPublicKey, "base64"),
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [],
  );
  const sharedBits = await crypto.subtle.deriveBits(
    { name: "ECDH", public: ephemeralPublicKey },
    pair.privateKey,
    256,
  );
  const deviceInfo = new TextEncoder().encode(
    `trystore-patch-feed|bundle-key|v2|trystore|${deviceID.toLowerCase()}`,
  );
  const hkdfKey = await crypto.subtle.importKey("raw", sharedBits, "HKDF", false, ["deriveKey"]);
  const wrappingKey = await crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: Buffer.from(envelope.salt, "base64"),
      info: deviceInfo,
    },
    hkdfKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["decrypt"],
  );
  const clearKey = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: Buffer.from(envelope.nonce, "base64"),
      additionalData: deviceInfo,
      tagLength: 128,
    },
    wrappingKey,
    Buffer.from(envelope.ciphertext, "base64"),
  );
  assert.deepEqual(Buffer.from(clearKey), appBundleKey);

  const wrongDeviceInfo = new TextEncoder().encode(
    `trystore-patch-feed|bundle-key|v2|trystore|${deviceID.replace(/.$/, "0").toLowerCase()}`,
  );
  const wrongDeviceKey = await crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: Buffer.from(envelope.salt, "base64"),
      info: wrongDeviceInfo,
    },
    hkdfKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["decrypt"],
  );
  await assert.rejects(() => crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: Buffer.from(envelope.nonce, "base64"),
      additionalData: wrongDeviceInfo,
      tagLength: 128,
    },
    wrongDeviceKey,
    Buffer.from(envelope.ciphertext, "base64"),
  ));
});

test("legacy plaintext bundle-key GET is rejected", async () => {
  const response = await worker.fetch(request("GET"), bindings());
  assert.equal(response.status, 405);
  assert.deepEqual(await response.json(), { error: "device_key_exchange_required" });
});
