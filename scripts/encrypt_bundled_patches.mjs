#!/usr/bin/env node
import { createCipheriv, randomBytes } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';

const sourceDir = resolve(process.argv[2] ?? 'ThreeOneOSFive/Patches');
const outputDir = resolve(process.argv[3] ?? 'ThreeOneOSFive/Patches/Encrypted');
const encodedKey = process.env.PATCH_BUNDLE_KEY_BASE64 ?? '';
const key = Buffer.from(encodedKey, 'base64');
if (key.length !== 32) {
  throw new Error('Set PATCH_BUNDLE_KEY_BASE64 to a base64-encoded 32-byte AES key.');
}
await mkdir(outputDir, { recursive: true });
const files = (await readdir(sourceDir, { withFileTypes: true }))
  .filter(entry => entry.isFile() && entry.name.endsWith('.3105'));
if (files.length === 0) throw new Error(`No .3105 resources found in ${sourceDir}`);
for (const entry of files) {
  const plain = await readFile(join(sourceDir, entry.name));
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([cipher.update(plain), cipher.final()]);
  const combined = Buffer.concat([nonce, ciphertext, cipher.getAuthTag()]);
  const output = join(outputDir, `${basename(entry.name)}.enc`);
  await writeFile(output, combined, { mode: 0o644 });
  console.log(`${entry.name} -> ${output} (${combined.length} bytes)`);
}
