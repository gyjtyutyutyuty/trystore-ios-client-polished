#!/usr/bin/env node
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const sourceDir = resolve(process.argv[2] ?? 'ThreeOneOSFive/Patches');
const assetCatalog = resolve(process.argv[3] ?? 'ThreeOneOSFive/Assets.xcassets');
const encodedKey = process.env.PATCH_BUNDLE_KEY_BASE64 ?? process.env.PATCH_BUNDLE_ENCRYPTION_KEY ?? '';
const key = Buffer.from(encodedKey, 'base64');
if (key.length !== 32 || key.toString('base64') !== encodedKey) {
  throw new Error('Set PATCH_BUNDLE_KEY_BASE64 (or PATCH_BUNDLE_ENCRYPTION_KEY) to a base64-encoded 32-byte AES key.');
}

function decrypt(combined, decryptionKey) {
  if (combined.length < 28) throw new Error('AES-GCM Data Set is shorter than nonce and authentication tag.');
  const nonce = combined.subarray(0, 12);
  const ciphertext = combined.subarray(12, -16);
  const tag = combined.subarray(-16);
  const decipher = createDecipheriv('aes-256-gcm', decryptionKey, nonce);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

// Keep asset catalog folder/file names recognizable in the repository.
const assetNames = {
  'HEAD.3105': 'HEAD',
  'NECK.3105': 'NECK',
  'HSPESSCOSO.3105': 'HS_PESSCOSO',
  'HS SLA PECHO.3105': 'HS_SLA_PECHO',
  'HOLOGRAMAARMAS.3105': 'HOLOGRAMA_ARMAS',
  'HOLOGRAMAPERSONAJE.3105': 'HOLOGRAMA_PERSONAJE',
  'HOLOGRAMAEXCLUSIVO(2).3105': 'HOLOGRAMA_EXCLUSIVO_VERDE',
  'HOLOGRAMAEXCLUSIVO(3).3105': 'HOLOGRAMA_EXCLUSIVO_ROSADO',
};

const files = (await readdir(sourceDir, { withFileTypes: true }))
  .filter(entry => entry.isFile() && entry.name.endsWith('.3105'))
  .map(entry => entry.name)
  .sort();
if (files.length !== Object.keys(assetNames).length
    || files.some(name => !(name in assetNames))) {
  throw new Error(`Expected exactly ${Object.keys(assetNames).length} known .3105 resources in ${sourceDir}`);
}

for (const filename of files) {
  const assetName = assetNames[filename];
  const data = await readFile(join(sourceDir, filename));
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([cipher.update(data), cipher.final()]);
  const combined = Buffer.concat([nonce, ciphertext, cipher.getAuthTag()]);
  const dataset = join(assetCatalog, `${assetName}.dataset`);
  await mkdir(dataset, { recursive: true });
  const payloadPath = join(dataset, `${assetName}.bin`);
  await writeFile(payloadPath, combined);
  await writeFile(join(dataset, 'Contents.json'), `${JSON.stringify({
    data: [{ filename: `${assetName}.bin`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
  }, null, 2)}\n`);

  // Read back the exact generated file and authenticate/decrypt it with the same
  // runtime key. A modified, truncated, or wrong-key bundle must fail the build.
  const written = await readFile(payloadPath);
  const roundTrip = decrypt(written, key);
  if (!roundTrip.equals(data)) {
    throw new Error(`AES-GCM round-trip did not reproduce the source package: ${filename}`);
  }

  // Exercise the authentication boundary on every generated Data Set. Flip a
  // key bit to guarantee a distinct wrong key and require GCM authentication to fail.
  const wrongKey = Buffer.from(key);
  wrongKey[0] ^= 1;
  let rejectedWrongKey = false;
  try {
    decrypt(written, wrongKey);
  } catch {
    rejectedWrongKey = true;
  }
  if (!rejectedWrongKey) {
    throw new Error(`AES-GCM accepted a wrong key for ${filename}`);
  }
}

console.log(`Encrypted ${files.length} patch files into named .bin Data Sets in ${assetCatalog}.`);
console.log('The AES key is not written to the asset catalog or the iOS project.');
