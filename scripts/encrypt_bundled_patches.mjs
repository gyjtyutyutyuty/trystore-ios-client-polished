#!/usr/bin/env node
import { createCipheriv, randomBytes } from 'node:crypto';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const sourceDir = resolve(process.argv[2] ?? 'ThreeOneOSFive/Patches');
const assetCatalog = resolve(process.argv[3] ?? 'ThreeOneOSFive/Assets.xcassets');
const key = Buffer.from(process.env.PATCH_BUNDLE_KEY_BASE64 ?? '', 'base64');
if (key.length !== 32) {
  throw new Error('Set PATCH_BUNDLE_KEY_BASE64 to a base64-encoded 32-byte AES key.');
}

// Keep asset catalog folder/file names recognizable in the repository.
const assetNames = {
  'HEAD.TRYSTORE': 'HEAD',
  'NECK.TRYSTORE': 'NECK',
  'HSPESSCOSO.TRYSTORE': 'HS_PESSCOSO',
  'HS SLA PECHO.TRYSTORE': 'HS_SLA_PECHO',
  'EXCLUSIVO AZUL.TRYSTORE': 'EXCLUSIVO_AZUL',
  'TryStore.TRYSTORE': 'TRYSTORE_BALAS_MAGICAS',
  'HOLOGRAMAEXCLUSIVO(4).TRYSTORE': 'HOLOGRAMA_EXCLUSIVO_VERDE',
  'HOLOGRAMAEXCLUSIVO(5).TRYSTORE': 'HOLOGRAMA_EXCLUSIVO_ROSADO',
  'Cuello y Drag.TRYSTORE': 'CUELLO_Y_DRAG',
  'Pecho3105.TRYSTORE': 'PECHO3105',
  'CUELLO3105.TRYSTORE': 'CUELLO3105',
};

const files = (await readdir(sourceDir, { withFileTypes: true }))
  .filter(entry => entry.isFile() && entry.name.endsWith('.TRYSTORE'))
  .map(entry => entry.name)
  .sort();
if (files.length !== Object.keys(assetNames).length
    || files.some(name => !(name in assetNames))) {
  throw new Error(`Expected exactly ${Object.keys(assetNames).length} known .TRYSTORE resources in ${sourceDir}`);
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
  await writeFile(join(dataset, `${assetName}.bin`), combined);
  await writeFile(join(dataset, 'Contents.json'), `${JSON.stringify({
    data: [{ filename: `${assetName}.bin`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
  }, null, 2)}\n`);
}

console.log(`Encrypted ${files.length} patch files into named .bin Data Sets in ${assetCatalog}.`);
console.log('The AES key is not written to the asset catalog or the iOS project.');
